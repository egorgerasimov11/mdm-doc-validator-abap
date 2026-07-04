CLASS zcl_mdmdoc_rules DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  " Port of rules/engine.py (run_rules + _eval_when + message formatting) and
  " rules/predicates.py (every predicate + REGISTRY + helpers).
  " Rules come either from a zmdmdoc.rules.v1 JSON string (constructor arg) or,
  " on empty/failed parse, from the generated ZCL_MDMDOC_RULES_DATA tables.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_rules_json TYPE string OPTIONAL.

    METHODS run
      IMPORTING is_ext             TYPE zif_mdmdoc_types=>ty_extraction
                iv_lang            TYPE string DEFAULT 'EN'
      RETURNING VALUE(rt_findings) TYPE zif_mdmdoc_types=>tt_findings.

  PRIVATE SECTION.
    " Parsed / fallback rule sets and the IBAN-length table.
    DATA gt_rules_bank TYPE zif_mdmdoc_types=>tt_rules.
    DATA gt_rules_w9   TYPE zif_mdmdoc_types=>tt_rules.
    DATA gt_iban_len   TYPE zif_mdmdoc_types=>tt_iban_len.
    " Remembered engine-severity finding to emit on every run (JSON parse failure).
    DATA gv_engine_error TYPE abap_bool.
    DATA gv_engine_msg   TYPE string.

    " JSON deserialization shape (zmdmdoc.rules.v1).
    TYPES: BEGIN OF ty_json_root,
             schema      TYPE string,
             rules_bank  TYPE zif_mdmdoc_types=>tt_rules,
             rules_w9    TYPE zif_mdmdoc_types=>tt_rules,
             iban_length TYPE STANDARD TABLE OF zif_mdmdoc_types=>ty_iban_len WITH EMPTY KEY,
           END OF ty_json_root.

    METHODS load_from_json
      IMPORTING iv_json      TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    METHODS load_from_data.

    " --- engine ---------------------------------------------------------
    METHODS eval_when
      IMPORTING is_rule       TYPE zif_mdmdoc_types=>ty_rule
                is_ext        TYPE zif_mdmdoc_types=>ty_extraction
      EXPORTING ev_fired      TYPE abap_bool
                ev_detail     TYPE string
                ev_field      TYPE string
                ev_unknown    TYPE abap_bool.

    METHODS dispatch_check
      IMPORTING iv_check      TYPE string
                iv_value      TYPE string
                is_ext        TYPE zif_mdmdoc_types=>ty_extraction
                it_args       TYPE zif_mdmdoc_types=>tt_args
      EXPORTING ev_fired      TYPE abap_bool
                ev_detail     TYPE string
                ev_unknown    TYPE abap_bool.

    METHODS format_message
      IMPORTING iv_template TYPE string
                iv_value    TYPE string
                iv_masked   TYPE string
                iv_detail   TYPE string
                iv_has_kind TYPE abap_bool
      RETURNING VALUE(rv_msg) TYPE string.

    " --- helpers --------------------------------------------------------
    METHODS field_str
      IMPORTING it_fields       TYPE zif_mdmdoc_types=>tt_fields
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS arg_value
      IMPORTING it_args         TYPE zif_mdmdoc_types=>tt_args
                iv_name         TYPE string
                iv_default      TYPE string OPTIONAL
      RETURNING VALUE(rv_value) TYPE string.

    METHODS regex_matches_start
      IMPORTING iv_pattern    TYPE string
                iv_text       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    METHODS signed_narrow
      IMPORTING it_fields     TYPE zif_mdmdoc_types=>tt_fields
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    METHODS positive_evidence
      IMPORTING iv_ev         TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    " --- predicates (fired + detail) ------------------------------------
    METHODS p_field_empty
      IMPORTING iv_value  TYPE string
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_no_bank_ids
      IMPORTING is_ext    TYPE zif_mdmdoc_types=>ty_extraction
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_swift_valid
      IMPORTING iv_value  TYPE string
                is_ext    TYPE zif_mdmdoc_types=>ty_extraction
                it_args   TYPE zif_mdmdoc_types=>tt_args
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_iban_valid
      IMPORTING iv_value  TYPE string
                is_ext    TYPE zif_mdmdoc_types=>ty_extraction
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_ein_shape
      IMPORTING iv_value  TYPE string
                it_args   TYPE zif_mdmdoc_types=>tt_args
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_tin_type_vs_classification
      IMPORTING is_ext    TYPE zif_mdmdoc_types=>ty_extraction
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_individual_biz_ein
      IMPORTING is_ext    TYPE zif_mdmdoc_types=>ty_extraction
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_line_swap_suspect
      IMPORTING is_ext    TYPE zif_mdmdoc_types=>ty_extraction
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_date_older_than
      IMPORTING iv_value  TYPE string
                it_args   TYPE zif_mdmdoc_types=>tt_args
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_unsigned_no_evidence
      IMPORTING is_ext    TYPE zif_mdmdoc_types=>ty_extraction
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_unsigned_typed_block
      IMPORTING is_ext    TYPE zif_mdmdoc_types=>ty_extraction
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.
ENDCLASS.


CLASS zcl_mdmdoc_rules IMPLEMENTATION.

  METHOD constructor.
    IF iv_rules_json IS NOT INITIAL.
      IF load_from_json( iv_rules_json ) = abap_false.
        " parse failure: fall back to generated tables + remember an engine error.
        load_from_data( ).
        gv_engine_error = abap_true.
        gv_engine_msg   = `engine_error: rules JSON parse failed, using generated fallback rules`.
      ENDIF.
    ELSE.
      load_from_data( ).
    ENDIF.
  ENDMETHOD.


  METHOD load_from_data.
    gt_rules_bank = zcl_mdmdoc_rules_data=>gt_rules_bank.
    gt_rules_w9   = zcl_mdmdoc_rules_data=>gt_rules_w9.
    gt_iban_len   = zcl_mdmdoc_rules_data=>gt_iban_len.
  ENDMETHOD.


  METHOD load_from_json.
    DATA ls_root TYPE ty_json_root.
    TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING json = iv_json
          CHANGING  data = ls_root ).
      CATCH cx_root.
        rv_ok = abap_false.
        RETURN.
    ENDTRY.

    " A well-formed zmdmdoc.rules.v1 must carry at least one rule set.
    IF ls_root-rules_bank IS INITIAL AND ls_root-rules_w9 IS INITIAL.
      rv_ok = abap_false.
      RETURN.
    ENDIF.

    gt_rules_bank = ls_root-rules_bank.
    gt_rules_w9   = ls_root-rules_w9.
    CLEAR gt_iban_len.
    LOOP AT ls_root-iban_length ASSIGNING FIELD-SYMBOL(<il>).
      INSERT <il> INTO TABLE gt_iban_len.
    ENDLOOP.
    rv_ok = abap_true.
  ENDMETHOD.


  METHOD run.
    DATA lt_rules TYPE zif_mdmdoc_types=>tt_rules.
    DATA lv_lang  TYPE string.

    lv_lang = to_upper( iv_lang ).

    " Remembered JSON-parse-failure engine error surfaces on every run.
    IF gv_engine_error = abap_true.
      APPEND VALUE #( rule_id  = `ENGINE`
                      severity = zif_mdmdoc_types=>c_severity-note
                      message  = gv_engine_msg ) TO rt_findings.
    ENDIF.

    IF is_ext-doc_class = zif_mdmdoc_types=>c_doc_class-w9.
      lt_rules = gt_rules_w9.
    ELSE.
      lt_rules = gt_rules_bank.
    ENDIF.

    LOOP AT lt_rules ASSIGNING FIELD-SYMBOL(<rule>).
      DATA(ls_rule) = <rule>.
      DATA(lv_rid)  = ls_rule-id.
      IF lv_rid IS INITIAL.
        lv_rid = `?`.
      ENDIF.

      " applies_to filter: empty = all; else doc_type must be listed.
      IF ls_rule-applies_to IS NOT INITIAL.
        READ TABLE ls_rule-applies_to TRANSPORTING NO FIELDS
             WITH KEY table_line = is_ext-doc_type.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
      ENDIF.

      DATA lv_fired   TYPE abap_bool.
      DATA lv_detail  TYPE string.
      DATA lv_field   TYPE string.
      DATA lv_unknown TYPE abap_bool.
      CLEAR: lv_fired, lv_detail, lv_field, lv_unknown.

      TRY.
          eval_when(
            EXPORTING is_rule  = ls_rule
                      is_ext   = is_ext
            IMPORTING ev_fired    = lv_fired
                      ev_detail   = lv_detail
                      ev_field    = lv_field
                      ev_unknown  = lv_unknown ).

          IF lv_unknown = abap_true.
            " Unknown predicate / when-op -> ENGINE finding, WARNING, no dump.
            APPEND VALUE #( rule_id  = `ENGINE`
                            severity = zif_mdmdoc_types=>c_severity-warning
                            message  = |engine_error: rule { lv_rid } uses an unknown check/when-op| )
                   TO rt_findings.
            CONTINUE.
          ENDIF.

          IF lv_fired = abap_false.
            CONTINUE.
          ENDIF.

          " --- message formatting -------------------------------------
          DATA(lv_raw)  = field_str( it_fields = is_ext-fields iv_name = lv_field ).
          DATA(lv_kind) = zcl_mdmdoc_mask=>kind_for_field( lv_field ).
          DATA lv_masked TYPE string.
          IF lv_kind IS NOT INITIAL AND lv_raw IS NOT INITIAL.
            lv_masked = zcl_mdmdoc_mask=>display_value(
                          iv_kind  = lv_kind
                          iv_value = lv_raw
                          iv_policy = zif_mdmdoc_types=>c_policy-masked ).
          ELSE.
            lv_masked = lv_raw.
          ENDIF.

          DATA(lv_tmpl) = ls_rule-message.
          IF lv_lang = `RU` AND ls_rule-message_ru IS NOT INITIAL.
            lv_tmpl = ls_rule-message_ru.
          ENDIF.

          DATA(lv_msg) = format_message(
                           iv_template = lv_tmpl
                           iv_value    = lv_raw
                           iv_masked   = lv_masked
                           iv_detail   = lv_detail
                           iv_has_kind = boolc( lv_kind IS NOT INITIAL ) ).

          " severity / verdict validation (mirror engine.py fallbacks).
          DATA(lv_sev) = ls_rule-severity.
          IF lv_sev <> zif_mdmdoc_types=>c_severity-critical
             AND lv_sev <> zif_mdmdoc_types=>c_severity-warning
             AND lv_sev <> zif_mdmdoc_types=>c_severity-note.
            lv_sev = zif_mdmdoc_types=>c_severity-warning.
          ENDIF.

          DATA(lv_eff) = ls_rule-verdict_effect.
          IF lv_eff <> zif_mdmdoc_types=>c_verdict-reject
             AND lv_eff <> zif_mdmdoc_types=>c_verdict-review
             AND lv_eff <> zif_mdmdoc_types=>c_verdict-warning
             AND lv_eff <> zif_mdmdoc_types=>c_verdict-accept.
            CLEAR lv_eff.
          ENDIF.

          APPEND VALUE #( rule_id        = lv_rid
                          severity       = lv_sev
                          verdict_effect = lv_eff
                          message        = lv_msg
                          detail         = lv_detail
                          field          = lv_field ) TO rt_findings.
        CATCH cx_root INTO DATA(lx).
          " engine.py: any per-rule failure -> NOTE engine_error, never crash.
          APPEND VALUE #( rule_id  = lv_rid
                          severity = zif_mdmdoc_types=>c_severity-note
                          message  = |engine_error: rule { lv_rid } failed ({ lx->get_text( ) })| )
                 TO rt_findings.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.


  METHOD eval_when.
    CLEAR: ev_fired, ev_detail, ev_field, ev_unknown.
    DATA(lv_op) = is_rule-when_op.

    CASE lv_op.
      WHEN `always`.
        ev_fired = abap_true.

      WHEN `field_missing`.
        ev_field = is_rule-when_field.
        ev_fired = boolc( field_str( it_fields = is_ext-fields
                                     iv_name = is_rule-when_field ) IS INITIAL ).

      WHEN `flag_true`.
        ev_field = is_rule-when_field.
        ev_fired = zcl_mdmdoc_norm=>field_is_true( it_fields = is_ext-fields
                                                    iv_name = is_rule-when_field ).

      WHEN `flag_false`.
        ev_field = is_rule-when_field.
        ev_fired = boolc( zcl_mdmdoc_norm=>field_is_true(
                            it_fields = is_ext-fields
                            iv_name = is_rule-when_field ) = abap_false ).

      WHEN `equals`.
        ev_field = is_rule-when_field.
        ev_fired = boolc( to_lower( field_str( it_fields = is_ext-fields
                                               iv_name = is_rule-when_field ) )
                          = to_lower( is_rule-when_value ) ).

      WHEN `in`.
        ev_field = is_rule-when_field.
        DATA(lv_lc) = to_lower( field_str( it_fields = is_ext-fields
                                           iv_name = is_rule-when_field ) ).
        LOOP AT is_rule-when_values ASSIGNING FIELD-SYMBOL(<wv>).
          IF to_lower( <wv> ) = lv_lc.
            ev_fired = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.

      WHEN `regex_mismatch`.
        ev_field = is_rule-when_field.
        DATA(lv_v) = field_str( it_fields = is_ext-fields
                                iv_name = is_rule-when_field ).
        IF lv_v IS INITIAL.
          ev_fired = abap_false.
        ELSE.
          ev_fired = boolc( regex_matches_start( iv_pattern = is_rule-when_value
                                                 iv_text = lv_v ) = abap_false ).
        ENDIF.

      WHEN `check`.
        ev_field = is_rule-when_field.
        DATA(lv_val) = field_str( it_fields = is_ext-fields
                                  iv_name = is_rule-when_field ).
        dispatch_check(
          EXPORTING iv_check = is_rule-check_name
                    iv_value = lv_val
                    is_ext   = is_ext
                    it_args  = is_rule-check_args
          IMPORTING ev_fired   = ev_fired
                    ev_detail  = ev_detail
                    ev_unknown = ev_unknown ).

      WHEN OTHERS.
        ev_unknown = abap_true.
    ENDCASE.
  ENDMETHOD.


  METHOD dispatch_check.
    CLEAR: ev_fired, ev_detail, ev_unknown.

    CASE iv_check.
      WHEN `field_empty`.
        p_field_empty( EXPORTING iv_value = iv_value
                       IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `no_bank_ids`.
        p_no_bank_ids( EXPORTING is_ext = is_ext
                       IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `swift_valid`.
        p_swift_valid( EXPORTING iv_value = iv_value is_ext = is_ext it_args = it_args
                       IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `iban_valid`.
        p_iban_valid( EXPORTING iv_value = iv_value is_ext = is_ext
                      IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `ein_shape`.
        p_ein_shape( EXPORTING iv_value = iv_value it_args = it_args
                     IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `tin_type_vs_classification`.
        p_tin_type_vs_classification( EXPORTING is_ext = is_ext
                                      IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `individual_with_business_name_and_ein`.
        p_individual_biz_ein( EXPORTING is_ext = is_ext
                              IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `line_swap_suspect`.
        p_line_swap_suspect( EXPORTING is_ext = is_ext
                             IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `date_older_than`.
        p_date_older_than( EXPORTING iv_value = iv_value it_args = it_args
                           IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `unsigned_no_evidence`.
        p_unsigned_no_evidence( EXPORTING is_ext = is_ext
                                IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `unsigned_typed_block`.
        p_unsigned_typed_block( EXPORTING is_ext = is_ext
                                IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN OTHERS.
        ev_unknown = abap_true.
    ENDCASE.
  ENDMETHOD.


  METHOD format_message.
    " {value} -> masked when the field is sensitive, else raw; {value_masked}
    " always masked; {detail} predicate detail. Mirrors engine.py .format(...).
    DATA(lv_value_sub) = iv_value.
    IF iv_has_kind = abap_true.
      lv_value_sub = iv_masked.
    ENDIF.

    rv_msg = iv_template.
    REPLACE ALL OCCURRENCES OF `{value_masked}` IN rv_msg WITH iv_masked.
    REPLACE ALL OCCURRENCES OF `{value}`        IN rv_msg WITH lv_value_sub.
    REPLACE ALL OCCURRENCES OF `{detail}`       IN rv_msg WITH iv_detail.
  ENDMETHOD.


  METHOD field_str.
    " engine._field_str: value stripped (booleans returned as-is, but here all
    " values are strings incl. 'true'/'false').
    rv_value = zcl_mdmdoc_norm=>field_value( it_fields = it_fields iv_name = iv_name ).
    CONDENSE rv_value.
  ENDMETHOD.


  METHOD arg_value.
    READ TABLE it_args ASSIGNING FIELD-SYMBOL(<a>) WITH KEY name = iv_name.
    IF sy-subrc = 0.
      rv_value = <a>-value.
    ELSE.
      rv_value = iv_default.
    ENDIF.
  ENDMETHOD.


  METHOD regex_matches_start.
    " Emulate Python re.match: pattern must match starting at offset 0.
    DATA lv_off TYPE i.
    TRY.
        FIND REGEX iv_pattern IN iv_text MATCH OFFSET lv_off.
        IF sy-subrc = 0 AND lv_off = 0.
          rv_yes = abap_true.
        ELSE.
          rv_yes = abap_false.
        ENDIF.
      CATCH cx_sy_regex cx_sy_matcher.
        rv_yes = abap_false.
    ENDTRY.
  ENDMETHOD.


  METHOD signed_narrow.
    " predicates use a NARROW signed test: only 'true'/'yes' count (NOT '1'/'x'
    " and NOT the engine's 'signed' token). Replicated verbatim.
    DATA(lv) = to_lower( condense( zcl_mdmdoc_norm=>field_value(
                                     it_fields = it_fields iv_name = `signed` ) ) ).
    rv_yes = boolc( lv = `true` OR lv = `yes` ).
  ENDMETHOD.


  METHOD positive_evidence.
    " Port of predicates._positive_evidence / _EV_POSITIVE (VERBATIM phrase list).
    DATA(lv_t) = to_lower( condense( iv_ev ) ).
    IF lv_t IS INITIAL.
      rv_yes = abap_false.
      RETURN.
    ENDIF.
    DATA lt_ev TYPE string_table.
    lt_ev = VALUE #(
      ( `computer generated` ) ( `computer-generated` ) ( `system generated` )
      ( `system-generated` ) ( `electronically` ) ( `electronic confirmation` )
      ( `requires no signature` ) ( `no signature required` ) ( `verification code` )
      ( `typed officer` ) ( `officer block` ) ( `officer name` ) ( `contact block` )
      ( `digital signature` ) ( `digitally signed` ) ( `qr code` ) ( `printed signature` )
      ( `signature-like` ) ( `docusign` ) ( `e-signature` ) ( `electronic signature` )
      ( `title block` ) ( `name and title` ) ).
    LOOP AT lt_ev ASSIGNING FIELD-SYMBOL(<m>).
      IF lv_t CS <m>.
        rv_yes = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
    rv_yes = abap_false.
  ENDMETHOD.


  " ====================================================================
  "  PREDICATES
  " ====================================================================

  METHOD p_field_empty.
    " Python: fired when str(value or '').strip() is empty.
    DATA(lv) = iv_value.
    CONDENSE lv.
    IF lv IS INITIAL.
      ev_fired  = abap_true.
      ev_detail = `not shown in the document`.
    ELSE.
      ev_fired  = abap_false.
      ev_detail = ``.
    ENDIF.
  ENDMETHOD.


  METHOD p_no_bank_ids.
    DATA(lv_iban)    = field_str( it_fields = is_ext-fields iv_name = `iban` ).
    DATA(lv_acct)    = field_str( it_fields = is_ext-fields iv_name = `account_number` ).
    DATA(lv_routing) = field_str( it_fields = is_ext-fields iv_name = `routing_aba` ).
    IF lv_iban IS NOT INITIAL OR lv_acct IS NOT INITIAL OR lv_routing IS NOT INITIAL.
      ev_fired  = abap_false.
      ev_detail = ``.
    ELSE.
      ev_fired  = abap_true.
      ev_detail = `no IBAN, account number or routing/ABA found`.
    ENDIF.
  ENDMETHOD.


  METHOD p_swift_valid.
    DATA(lv_sw) = zcl_mdmdoc_norm=>norm_id( iv_value ).
    IF lv_sw IS INITIAL.
      ev_fired = abap_false.
      RETURN.
    ENDIF.

    " lengths arg (e.g. '8,11').
    DATA lt_len TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    DATA(lv_lengths) = arg_value( it_args = it_args iv_name = `lengths` iv_default = `8,11` ).
    SPLIT lv_lengths AT `,` INTO TABLE DATA(lt_tokens).
    LOOP AT lt_tokens ASSIGNING FIELD-SYMBOL(<t>).
      DATA(lv_tok) = condense( <t> ).
      IF lv_tok IS NOT INITIAL.
        APPEND CONV i( lv_tok ) TO lt_len.
      ENDIF.
    ENDLOOP.
    IF lt_len IS INITIAL.
      APPEND 8 TO lt_len.
      APPEND 11 TO lt_len.
    ENDIF.

    DATA(lv_swlen) = strlen( lv_sw ).
    READ TABLE lt_len TRANSPORTING NO FIELDS WITH KEY table_line = lv_swlen.
    IF sy-subrc <> 0.
      ev_fired  = abap_true.
      ev_detail = |length { lv_swlen }, must be one of { lv_lengths }|.
      RETURN.
    ENDIF.

    " BIC shape: ^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$
    IF regex_matches_start( iv_pattern = `^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$`
                            iv_text = lv_sw ) = abap_false.
      ev_fired  = abap_true.
      ev_detail = `not a valid BIC shape (6 letters + 2/5 alphanumerics)`.
      RETURN.
    ENDIF.

    DATA(lv_bc) = zcl_mdmdoc_norm=>to_iso2( field_str( it_fields = is_ext-fields
                                                       iv_name = `bank_country` ) ).
    DATA(lv_cc) = lv_sw+4(2).
    " cc.isalpha(): both chars alphabetic.
    DATA(lv_cc_alpha) = boolc( lv_cc CO `ABCDEFGHIJKLMNOPQRSTUVWXYZ` ).
    IF lv_bc IS NOT INITIAL AND lv_cc_alpha = abap_true AND lv_cc <> lv_bc.
      ev_fired  = abap_true.
      ev_detail = |SWIFT country ({ lv_cc }) differs from bank country ({ lv_bc })|.
      RETURN.
    ENDIF.

    ev_fired = abap_false.
  ENDMETHOD.


  METHOD p_iban_valid.
    DATA(lv_iban) = zcl_mdmdoc_norm=>norm_id( iv_value ).
    IF lv_iban IS INITIAL.
      ev_fired = abap_false.
      RETURN.
    ENDIF.

    " shape ^[A-Z]{2}\d{2}[A-Z0-9]+$
    IF regex_matches_start( iv_pattern = `^[A-Z]{2}\d{2}[A-Z0-9]+$`
                            iv_text = lv_iban ) = abap_false.
      ev_fired  = abap_true.
      ev_detail = `non-standard shape (may be a plain account number in the IBAN field)`.
      RETURN.
    ENDIF.

    DATA(lv_cc)  = lv_iban(2).
    DATA(lv_len) = strlen( lv_iban ).

    READ TABLE gt_iban_len ASSIGNING FIELD-SYMBOL(<il>) WITH KEY country = lv_cc.
    IF sy-subrc = 0 AND <il>-len > 0 AND lv_len <> <il>-len.
      ev_fired  = abap_true.
      ev_detail = |length { lv_len } differs from expected { <il>-len } for { lv_cc }|.
      RETURN.
    ENDIF.

    DATA(lv_bc) = zcl_mdmdoc_norm=>to_iso2( field_str( it_fields = is_ext-fields
                                                       iv_name = `bank_country` ) ).
    IF lv_bc IS NOT INITIAL AND lv_cc <> lv_bc.
      ev_fired  = abap_true.
      ev_detail = |IBAN prefix ({ lv_cc }) differs from bank country ({ lv_bc })|.
      RETURN.
    ENDIF.

    IF zcl_mdmdoc_norm=>iban_mod97_ok( lv_iban ) = abap_false.
      ev_fired  = abap_true.
      ev_detail = `checksum failed (ISO 13616 mod-97) — an OCR misread or a typo`.
      RETURN.
    ENDIF.

    ev_fired = abap_false.
  ENDMETHOD.


  METHOD p_ein_shape.
    DATA(lv_v) = iv_value.
    CONDENSE lv_v.
    IF lv_v IS INITIAL.
      ev_fired = abap_false.
      RETURN.
    ENDIF.
    DATA(lv_d)      = zcl_mdmdoc_norm=>digits_only( iv_value ).
    DATA(lv_digits) = strlen( lv_d ).
    DATA(lv_want)   = CONV i( arg_value( it_args = it_args iv_name = `digits` iv_default = `9` ) ).
    IF lv_digits <> lv_want.
      ev_fired  = abap_true.
      ev_detail = |{ lv_digits } digits, must be { lv_want }|.
    ELSE.
      ev_fired = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD p_tin_type_vs_classification.
    DATA(lv_cls) = zcl_mdmdoc_norm=>norm_classification(
                     field_str( it_fields = is_ext-fields iv_name = `line3_classification` ) ).
    DATA(lv_tt)  = to_upper( field_str( it_fields = is_ext-fields iv_name = `tin_type` ) ).
    IF lv_cls IS INITIAL OR lv_tt IS INITIAL.
      ev_fired = abap_false.
      RETURN.
    ENDIF.

    DATA(lv_biz) = field_str( it_fields = is_ext-fields iv_name = `line2_business_name` ).
    IF lv_cls = `individual_sole_prop` AND lv_tt = `EIN` AND lv_biz IS INITIAL.
      ev_fired  = abap_true.
      ev_detail = `Individual/Sole proprietor classification with EIN and no business name`.
      RETURN.
    ENDIF.

    IF ( lv_cls = `llc` OR lv_cls = `corporation` OR lv_cls = `partnership`
         OR lv_cls = `trust_estate` ) AND lv_tt = `SSN`.
      ev_fired  = abap_true.
      ev_detail = |{ lv_cls } classification with an SSN|.
      RETURN.
    ENDIF.

    ev_fired = abap_false.
  ENDMETHOD.


  METHOD p_individual_biz_ein.
    DATA(lv_cls) = zcl_mdmdoc_norm=>norm_classification(
                     field_str( it_fields = is_ext-fields iv_name = `line3_classification` ) ).
    DATA(lv_tt)  = to_upper( field_str( it_fields = is_ext-fields iv_name = `tin_type` ) ).
    DATA(lv_biz) = boolc(
      zcl_mdmdoc_norm=>looks_like_business(
        field_str( it_fields = is_ext-fields iv_name = `line1_name` ) ) = abap_true
      OR zcl_mdmdoc_norm=>looks_like_business(
        field_str( it_fields = is_ext-fields iv_name = `line2_business_name` ) ) = abap_true ).

    IF lv_cls = `individual_sole_prop` AND lv_tt = `EIN` AND lv_biz = abap_true.
      ev_fired  = abap_true.
      ev_detail = `Individual classification + business/LLC name + EIN together`.
    ELSE.
      ev_fired = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD p_line_swap_suspect.
    DATA(lv_l1) = field_str( it_fields = is_ext-fields iv_name = `line1_name` ).
    DATA(lv_l2) = field_str( it_fields = is_ext-fields iv_name = `line2_business_name` ).

    IF lv_l1 IS INITIAL AND lv_l2 IS NOT INITIAL.
      ev_fired  = abap_true.
      ev_detail = `Line 1 empty while Line 2 present — lines likely swapped/collapsed`.
      RETURN.
    ENDIF.

    DATA(lv_cls) = zcl_mdmdoc_norm=>norm_classification(
                     field_str( it_fields = is_ext-fields iv_name = `line3_classification` ) ).
    IF lv_cls = `individual_sole_prop`
       AND zcl_mdmdoc_norm=>looks_like_business( lv_l1 ) = abap_true
       AND zcl_mdmdoc_norm=>looks_like_person( lv_l2 ) = abap_true.
      ev_fired  = abap_true.
      ev_detail = `Line 1 looks like a business while Line 2 looks like a person (Individual classification)`.
      RETURN.
    ENDIF.

    ev_fired = abap_false.
  ENDMETHOD.


  METHOD p_date_older_than.
    DATA lv_date TYPE d.
    DATA lv_ok   TYPE abap_bool.
    zcl_mdmdoc_norm=>parse_date( EXPORTING iv_text = iv_value
                                 IMPORTING ev_date = lv_date ev_ok = lv_ok ).
    IF lv_ok = abap_false.
      ev_fired = abap_false.
      RETURN.
    ENDIF.

    DATA(lv_years) = CONV i( arg_value( it_args = it_args iv_name = `years` iv_default = `2` ) ).
    DATA(lv_age_days) = CONV i( sy-datum - lv_date ).   " datetime.now() - dt, in days
    IF lv_age_days > lv_years * 365.
      ev_fired  = abap_true.
      DATA(lv_iso) = |{ lv_date+0(4) }-{ lv_date+4(2) }-{ lv_date+6(2) }|.
      ev_detail = |document date { lv_iso } is ~{ lv_age_days DIV 365 } years old|.
    ELSE.
      ev_fired = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD p_unsigned_no_evidence.
    IF signed_narrow( is_ext-fields ) = abap_true.
      ev_fired = abap_false.
      RETURN.
    ENDIF.
    DATA(lv_ev) = field_str( it_fields = is_ext-fields iv_name = `signature_evidence` ).
    IF positive_evidence( lv_ev ) = abap_true.
      ev_fired = abap_false.
      RETURN.
    ENDIF.
    ev_fired = abap_true.
    IF lv_ev IS NOT INITIAL.
      ev_detail = |no signature, and the noted '{ lv_ev }' is a statement of absence, | &&
                  |not a compensating artifact|.
    ELSE.
      ev_detail = `no signature, stamp or officer block visible`.
    ENDIF.
  ENDMETHOD.


  METHOD p_unsigned_typed_block.
    DATA(lv_ev) = field_str( it_fields = is_ext-fields iv_name = `signature_evidence` ).
    IF signed_narrow( is_ext-fields ) = abap_false AND positive_evidence( lv_ev ) = abap_true.
      ev_fired  = abap_true.
      ev_detail = lv_ev.
    ELSE.
      ev_fired = abap_false.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
