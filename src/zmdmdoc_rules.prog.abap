*&---------------------------------------------------------------------*
*& Report ZMDMDOC_RULES
*&---------------------------------------------------------------------*
*& View the active validation rules in a readable form, and export them to an
*& editable JSON file. The exported JSON matches the schema the ZMDMDOC report
*& loads via its "rules override" parameter (p_rules) — so you can: export ->
*& edit the file -> feed it back with p_rules, without regenerating or
*& transporting the rule class.
*&
*& Rules live in three layers (see docs/INTEGRATION.md §8):
*&   rules/*.yaml (source) -> ZCL_MDMDOC_RULES_DATA (generated, runs in SAP)
*&   -> optional rules.json runtime override (p_rules).
*&---------------------------------------------------------------------*
REPORT zmdmdoc_rules.

PARAMETERS: p_lang TYPE c LENGTH 2 DEFAULT 'EN'.
SELECTION-SCREEN BEGIN OF LINE.
  PARAMETERS: rb_all RADIOBUTTON GROUP cls DEFAULT 'X'.   " all
  PARAMETERS: rb_bnk RADIOBUTTON GROUP cls.               " banking only
  PARAMETERS: rb_w9  RADIOBUTTON GROUP cls.               " w9 only
SELECTION-SCREEN END OF LINE.
PARAMETERS: p_exp  AS CHECKBOX DEFAULT ' '.               " export JSON
PARAMETERS: p_file TYPE string LOWER CASE.
PARAMETERS: rb_pc  RADIOBUTTON GROUP tgt DEFAULT 'X'.
PARAMETERS: rb_srv RADIOBUTTON GROUP tgt.

START-OF-SELECTION.
  DATA(lv_lang) = CONV string( to_upper( p_lang ) ).
  DATA(lv_class) = COND string( WHEN rb_bnk = abap_true THEN zif_mdmdoc_types=>c_doc_class-bank
                                WHEN rb_w9 = abap_true  THEN zif_mdmdoc_types=>c_doc_class-w9
                                ELSE `` ).
  DATA(lt_rules) = zcl_mdmdoc_rules=>list_rules( lv_class ).

  WRITE: / |mdmdoc validation rules ({ lines( lt_rules ) })|. ULINE.
  LOOP AT lt_rules ASSIGNING FIELD-SYMBOL(<r>).
    CASE <r>-severity.
      WHEN zif_mdmdoc_types=>c_severity-critical. FORMAT COLOR COL_NEGATIVE.
      WHEN zif_mdmdoc_types=>c_severity-warning.  FORMAT COLOR COL_TOTAL.
      WHEN OTHERS.                                 FORMAT COLOR COL_NORMAL.
    ENDCASE.
    DATA(lv_eff) = COND string( WHEN <r>-verdict_effect IS NOT INITIAL THEN <r>-verdict_effect ELSE `(no verdict effect)` ).
    DATA(lv_appl) = COND string( WHEN <r>-applies_to IS NOT INITIAL
                                 THEN concat_lines_of( table = <r>-applies_to sep = |, | ) ELSE `all types` ).
    WRITE: / |[{ <r>-id }]|, <r>-severity, |-> { lv_eff }|.
    FORMAT COLOR OFF.
    WRITE: /  |    applies to: { lv_appl }|.
    WRITE: /  |    when      : { zcl_mdmdoc_rules=>describe_when( <r> ) }|.
    DATA(lv_msg) = COND string( WHEN lv_lang = 'RU' AND <r>-message_ru IS NOT INITIAL THEN <r>-message_ru ELSE <r>-message ).
    WRITE: /  |    message   : { lv_msg }|.
    SKIP.
  ENDLOOP.

  IF p_exp = abap_true AND p_file IS NOT INITIAL.
    " export in the zmdmdoc.rules.v1 shape (re-loadable via ZMDMDOC p_rules)
    TYPES: BEGIN OF ty_exp,
             schema      TYPE string,
             rules_bank  TYPE zif_mdmdoc_types=>tt_rules,
             rules_w9    TYPE zif_mdmdoc_types=>tt_rules,
             iban_length TYPE zif_mdmdoc_types=>tt_iban_len,
           END OF ty_exp.
    " Export the whole set, or just one class as a swappable "skill" pack
    " (rb_bnk -> banking pack, rb_w9 -> W-9 pack). Partial packs are re-loadable
    " via ZMDMDOC p_rules and override only their own class.
    DATA ls_exp TYPE ty_exp.
    ls_exp-schema = 'zmdmdoc.rules.v1'.
    IF lv_class <> zif_mdmdoc_types=>c_doc_class-w9.       " all or banking
      ls_exp-rules_bank  = zcl_mdmdoc_rules_data=>gt_rules_bank.
      ls_exp-iban_length = zcl_mdmdoc_rules_data=>gt_iban_len.
    ENDIF.
    IF lv_class <> zif_mdmdoc_types=>c_doc_class-bank.     " all or w9
      ls_exp-rules_w9 = zcl_mdmdoc_rules_data=>gt_rules_w9.
    ENDIF.
    DATA(lv_json) = /ui2/cl_json=>serialize( data = ls_exp ).

    DATA lv_err TYPE string.
    zcl_mdmdoc_file=>save_text(
      EXPORTING iv_path = p_file iv_text = lv_json iv_to_server = boolc( rb_srv = abap_true )
      IMPORTING ev_error = lv_err ).
    ULINE.
    IF lv_err IS INITIAL.
      WRITE: / |Rules exported to { p_file } — edit it and feed back via ZMDMDOC p_rules.|.
    ELSE.
      WRITE: / |Export failed: { lv_err }|.
    ENDIF.
  ENDIF.
