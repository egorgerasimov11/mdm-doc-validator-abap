CLASS zcl_mdmdoc_extract DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Port of fields.crosscheck_ids + the field normalization applied in stage_b.
    " Builds a ty_extraction from the LLM-read fields and the regex candidates,
    " overlaying deterministic (regex) IDs on top of the model reads.
    CLASS-METHODS build
      IMPORTING iv_doc_class    TYPE string
                iv_doc_type     TYPE string
                it_llm_fields   TYPE zif_mdmdoc_types=>tt_fields
                it_candidates   TYPE zif_mdmdoc_types=>tt_fields
                iv_llm_used     TYPE abap_bool
      RETURNING VALUE(rs_ext)   TYPE zif_mdmdoc_types=>ty_extraction.

  PRIVATE SECTION.
    " ID_FIELDS (fields.py) — bank IDs cross-checked against regex candidates
    CONSTANTS c_id_fields TYPE string VALUE
      `iban,swift_bic,account_number,routing_aba,routing_aba_wires`.

    " sensitive field names whose full values are registered as secrets
    CONSTANTS c_secret_bank TYPE string VALUE
      `iban,account_number,routing_aba,routing_aba_wires`.
    CONSTANTS c_secret_w9 TYPE string VALUE `tin_raw`.

    " upsert (or clear) a field value in the field table
    CLASS-METHODS set_field
      IMPORTING iv_name   TYPE string
                iv_value  TYPE string
      CHANGING  ct_fields TYPE zif_mdmdoc_types=>tt_fields.

    " strip leading '0' characters (python str.lstrip("0"))
    CLASS-METHODS lstrip_zeros
      IMPORTING iv_value      TYPE string
      RETURNING VALUE(rv_out) TYPE string.

    " masked display for a field, using its kind (bank kinds honour policy 'masked')
    CLASS-METHODS masked
      IMPORTING iv_field       TYPE string
                iv_value       TYPE string
      RETURNING VALUE(rv_out)  TYPE string.

    CLASS-METHODS crosscheck_bank
      IMPORTING it_candidates TYPE zif_mdmdoc_types=>tt_fields
      CHANGING  cs_ext        TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS crosscheck_w9
      IMPORTING it_candidates TYPE zif_mdmdoc_types=>tt_fields
      CHANGING  cs_ext        TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS normalize_fields
      CHANGING cs_ext TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS register_secrets
      CHANGING cs_ext TYPE zif_mdmdoc_types=>ty_extraction.
ENDCLASS.


CLASS zcl_mdmdoc_extract IMPLEMENTATION.

  METHOD build.
    " doc_class passthrough
    rs_ext-doc_class = iv_doc_class.

    " doc_type: explicit iv_doc_type wins over the LLM value; fall back to
    " the LLM field '_model'/'doc_type'? — the task fixes iv_doc_type as the
    " override, else the LLM-provided doc_type field if present.
    IF iv_doc_type IS NOT INITIAL.
      rs_ext-doc_type = iv_doc_type.
    ELSE.
      rs_ext-doc_type = zcl_mdmdoc_norm=>field_value(
        it_fields = it_llm_fields iv_name = `doc_type` ).
    ENDIF.

    " llm_used passthrough; model_id from '_model' candidate/field entry
    rs_ext-llm_used = iv_llm_used.
    rs_ext-model_id = zcl_mdmdoc_norm=>field_value(
      it_fields = it_llm_fields iv_name = `_model` ).

    " start from the LLM fields (minus the meta '_model'/'doc_type' entries)
    rs_ext-fields = it_llm_fields.
    DELETE rs_ext-fields WHERE name = `_model`.
    DELETE rs_ext-fields WHERE name = `doc_type`.

    " deterministic ID overlay, scoped by doc class
    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank.
      crosscheck_bank( EXPORTING it_candidates = it_candidates
                       CHANGING  cs_ext = rs_ext ).
    ELSEIF iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9.
      crosscheck_w9( EXPORTING it_candidates = it_candidates
                     CHANGING  cs_ext = rs_ext ).
    ENDIF.

    " field normalization (bank_country -> ISO2, flags -> 'true'/'false', trim)
    normalize_fields( CHANGING cs_ext = rs_ext ).

    " secrets = full values of every sensitive field present
    register_secrets( CHANGING cs_ext = rs_ext ).
  ENDMETHOD.


  METHOD set_field.
    READ TABLE ct_fields ASSIGNING FIELD-SYMBOL(<f>) WITH KEY name = iv_name.
    IF sy-subrc = 0.
      <f>-value = iv_value.
    ELSE.
      INSERT VALUE #( name = iv_name value = iv_value ) INTO TABLE ct_fields.
    ENDIF.
  ENDMETHOD.


  METHOD lstrip_zeros.
    rv_out = iv_value.
    WHILE strlen( rv_out ) > 0 AND rv_out(1) = `0`.
      rv_out = rv_out+1.
    ENDWHILE.
  ENDMETHOD.


  METHOD masked.
    DATA(lv_kind) = zcl_mdmdoc_mask=>kind_for_field( iv_field ).
    " policy 'masked': bank kinds masked, TIN kinds masked regardless
    rv_out = zcl_mdmdoc_mask=>display_value(
      iv_kind  = lv_kind
      iv_value = iv_value
      iv_policy = zif_mdmdoc_types=>c_policy-masked ).
  ENDMETHOD.


  METHOD crosscheck_bank.
    DATA lt_ids TYPE string_table.
    SPLIT c_id_fields AT `,` INTO TABLE lt_ids.

    LOOP AT lt_ids INTO DATA(lv_k).
      " regex candidate value for this ID field
      DATA(lv_dv) = zcl_mdmdoc_norm=>field_value(
        it_fields = it_candidates iv_name = lv_k ).
      IF lv_dv IS INITIAL.
        CONTINUE.
      ENDIF.

      " model-read value (already in cs_ext-fields)
      DATA(lv_mv) = zcl_mdmdoc_norm=>field_value(
        it_fields = cs_ext-fields iv_name = lv_k ).

      DATA(lv_note) = ``.
      IF lv_mv IS INITIAL.
        " blank model field + candidate -> fill from regex
        set_field( EXPORTING iv_name = lv_k iv_value = lv_dv
                   CHANGING  ct_fields = cs_ext-fields ).
        lv_note = |{ lv_k }=filled-from-regex({ masked( iv_field = lv_k iv_value = lv_dv ) })|.
        APPEND lv_note TO cs_ext-crosscheck.

      ELSEIF zcl_mdmdoc_norm=>norm_id( lv_mv ) = zcl_mdmdoc_norm=>norm_id( lv_dv ).
        " both present and norm_id-equal -> confirmed
        lv_note = |{ lv_k }=confirmed|.
        APPEND lv_note TO cs_ext-crosscheck.

      ELSEIF lv_k = `account_number`
             AND lstrip_zeros( zcl_mdmdoc_norm=>norm_id( lv_mv ) ) IS NOT INITIAL
             AND lstrip_zeros( zcl_mdmdoc_norm=>norm_id( lv_mv ) )
                 = lstrip_zeros( zcl_mdmdoc_norm=>norm_id( lv_dv ) ).
        " printed account vs zero-padded variant — same account
        lv_note = |{ lv_k }=confirmed (zero-padded variant)|.
        APPEND lv_note TO cs_ext-crosscheck.

      ELSE.
        " different -> candidate (regex) WINS + mismatch note + warning line
        DATA(lv_masked_m) = masked( iv_field = lv_k iv_value = lv_mv ).
        DATA(lv_masked_d) = masked( iv_field = lv_k iv_value = lv_dv ).
        set_field( EXPORTING iv_name = lv_k iv_value = lv_dv
                   CHANGING  ct_fields = cs_ext-fields ).
        lv_note = |{ lv_k }=MISMATCH(model={ lv_masked_m } vs regex={ lv_masked_d })|.
        APPEND lv_note TO cs_ext-crosscheck.
        APPEND |{ lv_k }: regex overrode model read ({ lv_note })| TO cs_ext-warnings.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD crosscheck_w9.
    " EIN candidate settles the TIN (deterministic, label/format anchored)
    DATA(lv_ein) = zcl_mdmdoc_norm=>field_value(
      it_fields = it_candidates iv_name = `ein` ).
    IF lv_ein IS NOT INITIAL.
      DATA(lv_tin) = zcl_mdmdoc_norm=>field_value(
        it_fields = cs_ext-fields iv_name = `tin_raw` ).
      IF lv_tin IS INITIAL.
        set_field( EXPORTING iv_name = `tin_raw` iv_value = lv_ein
                   CHANGING  ct_fields = cs_ext-fields ).
        APPEND |tin=filled-from-regex({ zcl_mdmdoc_mask=>mask( iv_kind = zif_mdmdoc_types=>c_kind-ein iv_value = lv_ein ) })|
               TO cs_ext-crosscheck.
        lv_tin = lv_ein.
      ENDIF.
      IF zcl_mdmdoc_norm=>norm_id( lv_tin ) = zcl_mdmdoc_norm=>norm_id( lv_ein ).
        DATA(lv_tt) = to_upper( zcl_mdmdoc_norm=>field_value(
          it_fields = cs_ext-fields iv_name = `tin_type` ) ).
        IF lv_tt <> `EIN`.
          APPEND `tin_type=EIN (settled by the EIN detector)` TO cs_ext-crosscheck.
        ENDIF.
        set_field( EXPORTING iv_name = `tin_type` iv_value = `EIN`
                   CHANGING  ct_fields = cs_ext-fields ).
      ENDIF.
    ENDIF.

    " W-9 digit boxes (one digit per line in the text layer)
    DATA(lv_boxed) = zcl_mdmdoc_norm=>field_value(
      it_fields = it_candidates iv_name = `tin_boxed` ).
    IF lv_boxed IS NOT INITIAL.
      DATA(lv_tin2) = zcl_mdmdoc_norm=>field_value(
        it_fields = cs_ext-fields iv_name = `tin_raw` ).
      IF lv_tin2 IS INITIAL.
        set_field( EXPORTING iv_name = `tin_raw` iv_value = lv_boxed
                   CHANGING  ct_fields = cs_ext-fields ).
        APPEND |tin=filled-from-boxed-digits({ zcl_mdmdoc_mask=>mask( iv_kind = zif_mdmdoc_types=>c_kind-tin iv_value = lv_boxed ) })|
               TO cs_ext-crosscheck.
        lv_tin2 = lv_boxed.
      ENDIF.
      DATA(lv_boxed_type) = zcl_mdmdoc_norm=>field_value(
        it_fields = it_candidates iv_name = `tin_boxed_type` ).
      IF lv_boxed_type IS NOT INITIAL
         AND zcl_mdmdoc_norm=>norm_id( lv_tin2 ) = zcl_mdmdoc_norm=>norm_id( lv_boxed ).
        DATA(lv_tt2) = to_upper( zcl_mdmdoc_norm=>field_value(
          it_fields = cs_ext-fields iv_name = `tin_type` ) ).
        IF lv_tt2 <> to_upper( lv_boxed_type ).
          APPEND |tin_type={ lv_boxed_type } (settled by the { lv_boxed_type } box label)|
                 TO cs_ext-crosscheck.
        ENDIF.
        set_field( EXPORTING iv_name = `tin_type` iv_value = lv_boxed_type
                   CHANGING  ct_fields = cs_ext-fields ).
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD normalize_fields.
    " trim all values; bank_country -> ISO2; signed/partial_capture -> 'true'/'false'
    LOOP AT cs_ext-fields ASSIGNING FIELD-SYMBOL(<f>).
      " Python .strip() — leading/trailing ASCII whitespace only
      DATA(lv_v) = <f>-value.
      SHIFT lv_v LEFT  DELETING LEADING ` `.
      SHIFT lv_v RIGHT DELETING TRAILING ` `.
      SHIFT lv_v LEFT  DELETING LEADING ` `.
      <f>-value = lv_v.
    ENDLOOP.

    " bank_country -> ISO2 (only when it resolves; keep raw otherwise)
    READ TABLE cs_ext-fields ASSIGNING <f> WITH KEY name = `bank_country`.
    IF sy-subrc = 0 AND <f>-value IS NOT INITIAL.
      DATA(lv_iso2) = zcl_mdmdoc_norm=>to_iso2( <f>-value ).
      IF lv_iso2 IS NOT INITIAL.
        <f>-value = lv_iso2.
      ENDIF.
    ENDIF.

    " signed / partial_capture -> canonical 'true'/'false' strings
    READ TABLE cs_ext-fields ASSIGNING <f> WITH KEY name = `signed`.
    IF sy-subrc = 0.
      <f>-value = COND string(
        WHEN zcl_mdmdoc_norm=>norm_flag( <f>-value ) = abap_true THEN `true` ELSE `false` ).
    ENDIF.
    READ TABLE cs_ext-fields ASSIGNING <f> WITH KEY name = `partial_capture`.
    IF sy-subrc = 0.
      <f>-value = COND string(
        WHEN zcl_mdmdoc_norm=>norm_flag( <f>-value ) = abap_true THEN `true` ELSE `false` ).
    ENDIF.
  ENDMETHOD.


  METHOD register_secrets.
    DATA lt_keys TYPE string_table.
    IF cs_ext-doc_class = zif_mdmdoc_types=>c_doc_class-bank.
      SPLIT c_secret_bank AT `,` INTO TABLE lt_keys.
    ELSE.
      SPLIT c_secret_w9 AT `,` INTO TABLE lt_keys.
    ENDIF.

    LOOP AT lt_keys INTO DATA(lv_key).
      DATA(lv_val) = zcl_mdmdoc_norm=>field_value(
        it_fields = cs_ext-fields iv_name = lv_key ).
      IF lv_val IS NOT INITIAL.
        APPEND lv_val TO cs_ext-secrets.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
