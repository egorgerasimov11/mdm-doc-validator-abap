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

    " The active rule set (for viewing/exporting): generated defaults for the
    " doc class, or '' for both. Used by the ZMDMDOC_RULES viewer report.
    CLASS-METHODS list_rules
      IMPORTING iv_doc_class  TYPE string OPTIONAL
      RETURNING VALUE(rt)     TYPE zif_mdmdoc_types=>tt_rules.

    " Human-readable one-line description of a rule's WHEN condition.
    CLASS-METHODS describe_when
      IMPORTING is_rule       TYPE zif_mdmdoc_types=>ty_rule
      RETURNING VALUE(rv_txt) TYPE string.

    " PUBLIC since the S1 wave: zcl_mdmdoc_extract's officer-block/esign
    " guards must not overwrite ALREADY-positive evidence, and the 23-phrase
    " _EV_POSITIVE list must stay single-sourced (§8 constants parity).
    CLASS-METHODS positive_evidence
      IMPORTING iv_ev         TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

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

    METHODS p_w8_ch4_cert_missing
      IMPORTING is_ext    TYPE zif_mdmdoc_types=>ty_extraction
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    "--- US TIN structure (skill us-tax-number-validator; W9-040/041) ---------
    METHODS p_tin_structural
      IMPORTING iv_value  TYPE string
                is_ext    TYPE zif_mdmdoc_types=>ty_extraction
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_tin_placeholder
      IMPORTING iv_value  TYPE string
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS tin_ph_kind
      IMPORTING iv_d           TYPE string
      RETURNING VALUE(rv_kind) TYPE string.

    METHODS tin_ein_bad
      IMPORTING iv_d             TYPE string
      RETURNING VALUE(rv_detail) TYPE string.

    METHODS tin_ssn_bad
      IMPORTING iv_d             TYPE string
      RETURNING VALUE(rv_detail) TYPE string.

    METHODS tin_itin_bad
      IMPORTING iv_d             TYPE string
      RETURNING VALUE(rv_detail) TYPE string.

    "--- US routing / account arithmetic (skill sap-us-bank-validate) ---------
    METHODS p_routing_format
      IMPORTING iv_value  TYPE string
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_routing_checksum
      IMPORTING iv_value  TYPE string
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_routing_prefix
      IMPORTING iv_value  TYPE string
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    METHODS p_account_sig_digits
      IMPORTING iv_value  TYPE string
                it_args   TYPE zif_mdmdoc_types=>tt_args
      EXPORTING ev_fired  TYPE abap_bool
                ev_detail TYPE string.

    "helpers for the routing arithmetic (pure functions)
    METHODS routing_sum
      IMPORTING iv_d          TYPE string
      RETURNING VALUE(rv_sum) TYPE i.

    METHODS routing_prefix_ok
      IMPORTING iv_d         TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.
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

    " Per-class ("skill") partial override: start from the generated defaults,
    " then replace ONLY the sections the override file actually carries. So a
    " file with just rules_w9 swaps the W-9 skill and leaves banking untouched.
    load_from_data( ).
    IF ls_root-rules_bank IS NOT INITIAL.
      gt_rules_bank = ls_root-rules_bank.
    ENDIF.
    IF ls_root-rules_w9 IS NOT INITIAL.
      gt_rules_w9 = ls_root-rules_w9.
    ENDIF.
    IF ls_root-iban_length IS NOT INITIAL.
      CLEAR gt_iban_len.
      LOOP AT ls_root-iban_length ASSIGNING FIELD-SYMBOL(<il>).
        INSERT <il> INTO TABLE gt_iban_len.
      ENDLOOP.
    ENDIF.
    rv_ok = abap_true.
  ENDMETHOD.


  METHOD run.
    DATA lt_rules TYPE zif_mdmdoc_types=>tt_rules.
    DATA lv_lang  TYPE string.

    lv_lang = to_upper( iv_lang ).

    " Remembered JSON-parse-failure engine error surfaces on every run.
    " Fail closed: the operator's intended override did NOT run, so the
    " verdict cannot be trusted to ACCEPT (mirror of engine.py ENGINE-GUARD).
    IF gv_engine_error = abap_true.
      APPEND VALUE #( rule_id        = `ENGINE-GUARD`
                      severity       = zif_mdmdoc_types=>c_severity-warning
                      verdict_effect = zif_mdmdoc_types=>c_verdict-review
                      message  = gv_engine_msg ) TO rt_findings.
    ENDIF.

    IF is_ext-doc_class = zif_mdmdoc_types=>c_doc_class-w9.
      lt_rules = gt_rules_w9.
    ELSE.
      lt_rules = gt_rules_bank.
    ENDIF.

    DATA lv_country_skips TYPE i.
    DATA lv_country_ids   TYPE string.

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

      " country scope (F3, mirror of Python engine.run_rules): empty = all
      " countries; else fields-doc_country must be listed. An UNDETECTED
      " document country skips the rule and one COUNTRY-1 NOTE reports it
      " (operator decision: inform, never block).
      IF ls_rule-countries IS NOT INITIAL.
        DATA(lv_cc) = to_upper( condense( field_str(
                          it_fields = is_ext-fields
                          iv_name   = `doc_country` ) ) ).
        IF lv_cc IS INITIAL.
          lv_country_skips = lv_country_skips + 1.
          IF lv_country_ids IS INITIAL.
            lv_country_ids = lv_rid.
          ELSE.
            lv_country_ids = |{ lv_country_ids }, { lv_rid }|.
          ENDIF.
          CONTINUE.
        ENDIF.
        DATA(lv_cc_hit) = abap_false.
        LOOP AT ls_rule-countries INTO DATA(lv_ctry).
          IF to_upper( condense( lv_ctry ) ) = lv_cc.
            lv_cc_hit = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_cc_hit = abap_false.
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
            " Unknown predicate / when-op -> fail-closed ENGINE-GUARD (NMR):
            " the rule could not be evaluated, so it might have been a blocker.
            APPEND VALUE #( rule_id        = `ENGINE-GUARD`
                            severity       = zif_mdmdoc_types=>c_severity-warning
                            verdict_effect = zif_mdmdoc_types=>c_verdict-review
                            message  = |engine_error: rule { lv_rid } uses an unknown check/when-op - held for manual review| )
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
            IF lv_eff IS NOT INITIAL.
              " engine.py: an invalid effect must not silently drop what a
              " human approved - fail closed to manual review.
              DATA(lv_gmsg) = |engine_error: rule { lv_rid } declares | &&
                |invalid verdict_effect '{ lv_eff }' - held for manual review|.
              APPEND VALUE #( rule_id        = `ENGINE-GUARD`
                              severity       = zif_mdmdoc_types=>c_severity-warning
                              verdict_effect = zif_mdmdoc_types=>c_verdict-review
                              message        = lv_gmsg )
                     TO rt_findings.
            ENDIF.
            CLEAR lv_eff.
          ENDIF.

          APPEND VALUE #( rule_id        = lv_rid
                          severity       = lv_sev
                          verdict_effect = lv_eff
                          message        = lv_msg
                          detail         = lv_detail
                          field          = lv_field ) TO rt_findings.
        CATCH cx_root INTO DATA(lx).
          " engine.py: any per-rule failure -> fail-closed ENGINE-GUARD (NMR),
          " never crash. The errored rule might have been a REJECT.
          APPEND VALUE #( rule_id        = `ENGINE-GUARD`
                          severity       = zif_mdmdoc_types=>c_severity-warning
                          verdict_effect = zif_mdmdoc_types=>c_verdict-review
                          message  = |engine_error: rule { lv_rid } failed ({ lx->get_text( ) }) - fail-closed: held for manual review| )
                 TO rt_findings.
      ENDTRY.
    ENDLOOP.

    IF lv_country_skips > 0.
      APPEND VALUE #( rule_id        = `COUNTRY-1`
                      severity       = zif_mdmdoc_types=>c_severity-note
                      verdict_effect = ``
                      message        = |document country undetected - { lv_country_skips } | &&
                                       |country-scoped rule(s) not evaluated ({ lv_country_ids })| )
             TO rt_findings.
    ENDIF.
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
      WHEN `tin_structural`.
        p_tin_structural( EXPORTING iv_value = iv_value is_ext = is_ext
                          IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `tin_placeholder`.
        p_tin_placeholder( EXPORTING iv_value = iv_value
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
      WHEN `w8_ch4_cert_missing`.
        p_w8_ch4_cert_missing( EXPORTING is_ext = is_ext
                               IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `routing_format`.
        p_routing_format( EXPORTING iv_value = iv_value
                          IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `routing_checksum`.
        p_routing_checksum( EXPORTING iv_value = iv_value
                            IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `routing_prefix`.
        p_routing_prefix( EXPORTING iv_value = iv_value
                          IMPORTING ev_fired = ev_fired ev_detail = ev_detail ).
      WHEN `account_sig_digits`.
        p_account_sig_digits( EXPORTING iv_value = iv_value it_args = it_args
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
    " [CONST:ev_positive_phrases]
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
    " [CONST:no_bank_ids_keys]
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
    " [CONST:swift_lengths_default]
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

    " [CONST:bic_shape_regex]
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

    " [CONST:iban_shape_regex]
    " shape ^[A-Z]{2}\d{2}[A-Z0-9]+$
    IF regex_matches_start( iv_pattern = `^[A-Z]{2}\d{2}[A-Z0-9]+$`
                            iv_text = lv_iban ) = abap_false.
      " A purely numeric value is a plain account number — the US and other
      " non-IBAN countries have no IBAN, so a domestic/international account
      " number in this field is a NORMAL format, not a malformed IBAN.
      " (The extract guard already relocates it to account_number; this is defence.)
      IF lv_iban CO `0123456789`.
        ev_fired = abap_false.
        RETURN.
      ENDIF.
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
    " [CONST:ein_digits_default]
    DATA(lv_want)   = CONV i( arg_value( it_args = it_args iv_name = `digits` iv_default = `9` ) ).
    IF lv_digits <> lv_want.
      ev_fired  = abap_true.
      ev_detail = |{ lv_digits } digits, must be { lv_want }|.
    ELSE.
      ev_fired = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD tin_ph_kind.
    CLEAR rv_kind.
    IF strlen( iv_d ) <> 9.
      RETURN.
    ENDIF.
    DATA(lv_first) = iv_d(1).
    DATA(lv_same)  = abap_true.
    DATA(lv_i)     = 1.
    WHILE lv_i < 9.
      IF iv_d+lv_i(1) <> lv_first.
        lv_same = abap_false.
        EXIT.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.
    IF lv_same = abap_true.
      rv_kind = `repeated-single-digit placeholder`.
      RETURN.
    ENDIF.
    " [CONST:known_fake_tins] FMX never-issued + SSA advertising SSNs
    DATA(lt_fake) = VALUE string_table( ( `123456789` ) ( `987654321` ) ( `078051120` )
                                        ( `219099999` ) ( `987654320` ) ( `987654322` )
                                        ( `987654323` ) ( `987654324` ) ( `987654325` )
                                        ( `987654326` ) ( `987654327` ) ( `987654328` )
                                        ( `987654329` ) ).
    IF line_exists( lt_fake[ table_line = iv_d ] ).
      rv_kind = `known never-issued / reserved example TIN`.
    ENDIF.
  ENDMETHOD.


  METHOD tin_ein_bad.
    CLEAR rv_detail.
    " [CONST:ein_never_prefixes] IRS never-assigned EIN prefixes (17 of 100)
    DATA(lt_never) = VALUE string_table( ( `00` ) ( `07` ) ( `08` ) ( `09` ) ( `17` )
                                         ( `18` ) ( `19` ) ( `28` ) ( `29` ) ( `49` )
                                         ( `69` ) ( `70` ) ( `78` ) ( `79` ) ( `89` )
                                         ( `96` ) ( `97` ) ).
    IF line_exists( lt_never[ table_line = iv_d(2) ] ).
      rv_detail = `EIN prefix is not an IRS-assigned prefix`.
    ENDIF.
  ENDMETHOD.


  METHOD tin_ssn_bad.
    CLEAR rv_detail.
    DATA(lv_area)   = iv_d(3).
    DATA(lv_group)  = iv_d+3(2).
    DATA(lv_serial) = iv_d+5(4).
    DATA(lv_first)  = iv_d(1).
    " [CONST:ssn_area_invalid] SSA: areas 000/666/9xx never issued
    IF lv_area = `000` OR lv_area = `666` OR lv_first = `9`.
      rv_detail = `SSN area is a never-issued area`.
      RETURN.
    ENDIF.
    IF lv_group = `00`.
      rv_detail = `SSN group is invalid`.
      RETURN.
    ENDIF.
    IF lv_serial = `0000`.
      rv_detail = `SSN serial is invalid`.
    ENDIF.
  ENDMETHOD.


  METHOD tin_itin_bad.
    CLEAR rv_detail.
    DATA(lv_g) = CONV i( iv_d+3(2) ).
    " [CONST:itin_group_ranges] IRS Pub 4757: 50-65/70-88/90-92/94-99; 93 = ATIN
    IF ( lv_g >= 50 AND lv_g <= 65 ) OR ( lv_g >= 70 AND lv_g <= 88 )
       OR ( lv_g >= 90 AND lv_g <= 93 ) OR ( lv_g >= 94 AND lv_g <= 99 ).
      RETURN.
    ENDIF.
    rv_detail = `ITIN group is outside the IRS-assigned ranges`.
  ENDMETHOD.


  METHOD p_tin_placeholder.
    CLEAR: ev_fired, ev_detail.
    DATA(lv_d) = zcl_mdmdoc_norm=>digits_only( iv_value ).
    IF strlen( lv_d ) <> 9.
      RETURN.
    ENDIF.
    DATA(lv_kind) = tin_ph_kind( lv_d ).
    IF lv_kind IS NOT INITIAL.
      ev_fired  = abap_true.
      ev_detail = lv_kind.
    ENDIF.
  ENDMETHOD.


  METHOD p_tin_structural.
    " Printed hyphenation picks the type; bare 9 digits fall back to tin_type,
    " then to any-type-accepts. Disjoint with p_tin_placeholder by design.
    CLEAR: ev_fired, ev_detail.
    DATA(lv_v) = iv_value.
    CONDENSE lv_v.
    DATA(lv_d) = zcl_mdmdoc_norm=>digits_only( iv_value ).
    IF strlen( lv_d ) <> 9 OR tin_ph_kind( lv_d ) IS NOT INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_bad) = ``.
    " [CONST:tin_format_shapes]
    IF regex_matches_start( iv_pattern = `^\d\d[- ]\d{7}$` iv_text = lv_v ) = abap_true.
      lv_bad = tin_ein_bad( lv_d ).
    ELSEIF regex_matches_start( iv_pattern = `^\d{3}-\d\d-\d{4}$` iv_text = lv_v ) = abap_true.
      IF lv_d(1) = `9`.
        lv_bad = tin_itin_bad( lv_d ).
      ELSE.
        lv_bad = tin_ssn_bad( lv_d ).
      ENDIF.
    ELSE.
      DATA(lv_tt) = to_upper( field_str( it_fields = is_ext-fields iv_name = `tin_type` ) ).
      CONDENSE lv_tt.
      IF lv_tt = `EIN`.
        lv_bad = tin_ein_bad( lv_d ).
      ELSEIF lv_tt = `SSN`.
        IF lv_d(1) = `9`.
          lv_bad = tin_itin_bad( lv_d ).
        ELSE.
          lv_bad = tin_ssn_bad( lv_d ).
        ENDIF.
      ELSE.
        DATA(lv_ok) = abap_false.
        IF tin_ein_bad( lv_d ) IS INITIAL.
          lv_ok = abap_true.
        ELSEIF lv_d(1) <> `9` AND tin_ssn_bad( lv_d ) IS INITIAL.
          lv_ok = abap_true.
        ELSEIF lv_d(1) = `9` AND tin_itin_bad( lv_d ) IS INITIAL.
          lv_ok = abap_true.
        ENDIF.
        IF lv_ok = abap_false.
          lv_bad = `9 digits match no valid EIN/SSN/ITIN structure`.
        ENDIF.
      ENDIF.
    ENDIF.
    IF lv_bad IS NOT INITIAL.
      ev_fired  = abap_true.
      ev_detail = lv_bad.
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

    " [CONST:date_older_than_years_default]
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


  METHOD p_w8_ch4_cert_missing.
    " W-8BEN-E: Part I claims a chapter-4 (FATCA) status but no matching
    " certification Part is completed (mirrors predicates.w8_ch4_cert_missing)
    DATA(lv_status) = field_str( it_fields = is_ext-fields iv_name = `chapter4_status` ).
    DATA(lv_cert)   = field_str( it_fields = is_ext-fields iv_name = `chapter4_cert_section` ).
    IF lv_status IS INITIAL OR lv_cert IS NOT INITIAL.
      ev_fired = abap_false.
      RETURN.
    ENDIF.
    ev_fired  = abap_true.
    ev_detail = |chapter-4 status '{ lv_status }' is claimed but no certification part is completed|.
  ENDMETHOD.

  METHOD list_rules.
    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank.
      rt = zcl_mdmdoc_rules_data=>gt_rules_bank.
    ELSEIF iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9.
      rt = zcl_mdmdoc_rules_data=>gt_rules_w9.
    ELSE.
      rt = zcl_mdmdoc_rules_data=>gt_rules_bank.
      APPEND LINES OF zcl_mdmdoc_rules_data=>gt_rules_w9 TO rt.
    ENDIF.
  ENDMETHOD.

  METHOD describe_when.
    CASE is_rule-when_op.
      WHEN 'always'.
        rv_txt = 'always'.
      WHEN 'field_missing'.
        rv_txt = |{ is_rule-when_field } is empty|.
      WHEN 'flag_true'.
        rv_txt = |{ is_rule-when_field } = true|.
      WHEN 'flag_false'.
        rv_txt = |{ is_rule-when_field } = false|.
      WHEN 'equals'.
        rv_txt = |{ is_rule-when_field } = "{ is_rule-when_value }"|.
      WHEN 'in'.
        rv_txt = |{ is_rule-when_field } in ({ concat_lines_of( table = is_rule-when_values sep = |, | ) })|.
      WHEN 'regex_mismatch'.
        rv_txt = |{ is_rule-when_field } does not match /{ is_rule-when_value }/|.
      WHEN 'check'.
        DATA lv_args TYPE string.
        LOOP AT is_rule-check_args INTO DATA(ls_a).
          lv_args = COND #( WHEN lv_args IS INITIAL THEN |{ ls_a-name }={ ls_a-value }|
                            ELSE |{ lv_args }, { ls_a-name }={ ls_a-value }| ).
        ENDLOOP.
        rv_txt = |check { is_rule-check_name }( { is_rule-when_field }{ COND #( WHEN lv_args IS NOT INITIAL THEN |; { lv_args }| ) } )|.
      WHEN OTHERS.
        rv_txt = is_rule-when_op.
    ENDCASE.
  ENDMETHOD.


  "--- US routing / account arithmetic (mirrors predicates.py; see PARITY.md) --

  METHOD routing_sum.
    " ABA 3-7-1 weighted sum. iv_d must be 9 numeric digits.
    DATA lv_c TYPE c LENGTH 1.
    DATA lv_n TYPE i.
    DO 9 TIMES.
      DATA(lv_off) = sy-index - 1.
      lv_c = iv_d+lv_off(1).
      lv_n = lv_c.
      rv_sum = rv_sum + SWITCH i( lv_off MOD 3 WHEN 0 THEN 3 WHEN 1 THEN 7 ELSE 1 ) * lv_n.
    ENDDO.
  ENDMETHOD.


  METHOD routing_prefix_ok.
    " Federal Reserve routing symbol: 00, 01-12, 21-32, 61-72, 80. 62 IS valid.
    DATA lv_p TYPE i.
    lv_p = iv_d(2).
    rv_ok = xsdbool( ( lv_p >= 0 AND lv_p <= 12 ) OR ( lv_p >= 21 AND lv_p <= 32 )
                     OR ( lv_p >= 61 AND lv_p <= 72 ) OR lv_p = 80 ).
  ENDMETHOD.


  METHOD p_routing_format.
    DATA(lv_raw) = iv_value.
    CONDENSE lv_raw.
    ev_fired = abap_false.
    IF lv_raw IS INITIAL.
      RETURN.
    ENDIF.
    IF strlen( lv_raw ) = 9 AND lv_raw CO `0123456789`.
      RETURN.
    ENDIF.
    FIND REGEX `^[A-Za-z]{6}[A-Za-z0-9]{2}([A-Za-z0-9]{3})?$` IN lv_raw.
    IF sy-subrc = 0.
      ev_fired  = abap_true.
      ev_detail = `a SWIFT/BIC code, not a routing number — it belongs in the SWIFT field`.
      RETURN.
    ENDIF.
    DATA(lv_clean) = zcl_mdmdoc_norm=>digits_only( lv_raw ).
    IF strlen( lv_clean ) = 9 AND routing_sum( lv_clean ) MOD 10 = 0.
      ev_fired  = abap_true.
      ev_detail = |{ strlen( lv_raw ) } chars with stray punctuation — cleans to a |
               && |checksum-valid 9-digit number; re-enter digits only|.
      RETURN.
    ENDIF.
    ev_fired  = abap_true.
    ev_detail = |{ strlen( lv_raw ) } chars, must be exactly 9 numeric digits|.
  ENDMETHOD.


  METHOD p_routing_checksum.
    DATA(lv_raw) = iv_value.
    CONDENSE lv_raw.
    ev_fired = abap_false.
    IF NOT ( strlen( lv_raw ) = 9 AND lv_raw CO `0123456789` ).
      RETURN.   " format problems are routing_format's job
    ENDIF.
    DATA(lv_sum) = routing_sum( lv_raw ).
    IF lv_sum MOD 10 = 0.
      RETURN.
    ENDIF.
    ev_fired  = abap_true.
    ev_detail = |weighted sum { lv_sum }, { lv_sum } mod 10 = { lv_sum MOD 10 } ≠ 0 — |
             && |mathematically cannot be a real routing number|.
  ENDMETHOD.


  METHOD p_routing_prefix.
    DATA(lv_raw) = iv_value.
    CONDENSE lv_raw.
    ev_fired = abap_false.
    IF NOT ( strlen( lv_raw ) = 9 AND lv_raw CO `0123456789` )
       OR routing_sum( lv_raw ) MOD 10 <> 0.
      RETURN.   " format/checksum rules own those failures
    ENDIF.
    IF routing_prefix_ok( lv_raw ) = abap_true.
      RETURN.
    ENDIF.
    ev_fired  = abap_true.
    ev_detail = |first two digits { lv_raw(2) } are never assigned |
             && |(valid: 00, 01-12, 21-32, 61-72, 80)|.
  ENDMETHOD.


  METHOD p_account_sig_digits.
    DATA(lv_raw) = iv_value.
    CONDENSE lv_raw.
    ev_fired = abap_false.
    IF lv_raw IS INITIAL.
      RETURN.   " a missing account is a separate missing-field rule
    ENDIF.
    DATA(lv_min) = CONV i( arg_value( it_args = it_args iv_name = `min` iv_default = `4` ) ).
    DATA(lv_core) = lv_raw.
    SHIFT lv_core LEFT DELETING LEADING `0`.
    DATA(lv_sig) = strlen( lv_core ).
    IF lv_sig = 0.
      ev_fired  = abap_true.
      ev_detail = `account is all zeros`.
    ELSEIF lv_sig < lv_min.
      ev_fired  = abap_true.
      ev_detail = |only { lv_sig } significant digit(s) after removing zero |
               && |padding — a real US account has at least { lv_min }|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
