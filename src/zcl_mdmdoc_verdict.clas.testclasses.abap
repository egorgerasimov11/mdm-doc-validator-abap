CLASS ltcl_verdict DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    METHODS finding
      IMPORTING iv_effect        TYPE string
      RETURNING VALUE(rs_finding) TYPE zif_mdmdoc_types=>ty_finding.

    " decide() precedence matrix
    METHODS decide_empty            FOR TESTING.
    METHODS decide_only_effectless  FOR TESTING.
    METHODS decide_only_warning     FOR TESTING.
    METHODS decide_warning_wins     FOR TESTING.
    METHODS decide_review_over_warn FOR TESTING.
    METHODS decide_reject_over_all  FOR TESTING.
    METHODS decide_review_only      FOR TESTING.
    METHODS decide_ignores_blank    FOR TESTING.
    METHODS decide_ignores_unknown  FOR TESTING.

    " next_step() lookup
    METHODS next_step_bank_en       FOR TESTING.
    METHODS next_step_w9_en         FOR TESTING.
    METHODS next_step_bank_ru       FOR TESTING.
    METHODS next_step_w9_ru         FOR TESTING.
    METHODS next_step_unknown_class FOR TESTING.
    METHODS next_step_unknown_verd  FOR TESTING.

    " message_type() mapping
    METHODS msgty_accept            FOR TESTING.
    METHODS msgty_warning           FOR TESTING.
    METHODS msgty_review            FOR TESTING.
    METHODS msgty_reject            FOR TESTING.
ENDCLASS.


CLASS ltcl_verdict IMPLEMENTATION.

  METHOD finding.
    rs_finding-rule_id        = `T`.
    rs_finding-severity       = zif_mdmdoc_types=>c_severity-warning.
    rs_finding-verdict_effect = iv_effect.
    rs_finding-message        = `t`.
  ENDMETHOD.

  METHOD decide_empty.
    DATA lt TYPE zif_mdmdoc_types=>tt_findings.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>decide( lt )
      exp = zif_mdmdoc_types=>c_verdict-accept
      msg = `empty findings -> ACCEPT` ).
  ENDMETHOD.

  METHOD decide_only_effectless.
    DATA lt TYPE zif_mdmdoc_types=>tt_findings.
    APPEND finding( `` ) TO lt.
    APPEND finding( `` ) TO lt.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>decide( lt )
      exp = zif_mdmdoc_types=>c_verdict-accept
      msg = `effect-less findings ignored -> ACCEPT` ).
  ENDMETHOD.

  METHOD decide_only_warning.
    DATA lt TYPE zif_mdmdoc_types=>tt_findings.
    APPEND finding( zif_mdmdoc_types=>c_verdict-warning ) TO lt.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>decide( lt )
      exp = zif_mdmdoc_types=>c_verdict-warning
      msg = `single WARNING effect -> WARNING` ).
  ENDMETHOD.

  METHOD decide_warning_wins.
    " Mix of WARNING + effect-less; WARNING is highest present.
    DATA lt TYPE zif_mdmdoc_types=>tt_findings.
    APPEND finding( `` ) TO lt.
    APPEND finding( zif_mdmdoc_types=>c_verdict-warning ) TO lt.
    APPEND finding( `` ) TO lt.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>decide( lt )
      exp = zif_mdmdoc_types=>c_verdict-warning ).
  ENDMETHOD.

  METHOD decide_review_over_warn.
    DATA lt TYPE zif_mdmdoc_types=>tt_findings.
    APPEND finding( zif_mdmdoc_types=>c_verdict-warning ) TO lt.
    APPEND finding( zif_mdmdoc_types=>c_verdict-review ) TO lt.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>decide( lt )
      exp = zif_mdmdoc_types=>c_verdict-review
      msg = `REVIEW outranks WARNING` ).
  ENDMETHOD.

  METHOD decide_reject_over_all.
    DATA lt TYPE zif_mdmdoc_types=>tt_findings.
    APPEND finding( zif_mdmdoc_types=>c_verdict-warning ) TO lt.
    APPEND finding( zif_mdmdoc_types=>c_verdict-reject ) TO lt.
    APPEND finding( zif_mdmdoc_types=>c_verdict-review ) TO lt.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>decide( lt )
      exp = zif_mdmdoc_types=>c_verdict-reject
      msg = `REJECT outranks everything` ).
  ENDMETHOD.

  METHOD decide_review_only.
    DATA lt TYPE zif_mdmdoc_types=>tt_findings.
    APPEND finding( zif_mdmdoc_types=>c_verdict-review ) TO lt.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>decide( lt )
      exp = zif_mdmdoc_types=>c_verdict-review ).
  ENDMETHOD.

  METHOD decide_ignores_blank.
    " Blank effects amid a real REJECT must not change outcome.
    DATA lt TYPE zif_mdmdoc_types=>tt_findings.
    APPEND finding( `` ) TO lt.
    APPEND finding( zif_mdmdoc_types=>c_verdict-reject ) TO lt.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>decide( lt )
      exp = zif_mdmdoc_types=>c_verdict-reject ).
  ENDMETHOD.

  METHOD decide_ignores_unknown.
    " ACCEPT is not a driver in Python precedence (sliced [:-1]); unknown effects ignored.
    DATA lt TYPE zif_mdmdoc_types=>tt_findings.
    APPEND finding( zif_mdmdoc_types=>c_verdict-accept ) TO lt.
    APPEND finding( `SOMETHING_ELSE` ) TO lt.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>decide( lt )
      exp = zif_mdmdoc_types=>c_verdict-accept
      msg = `ACCEPT/unknown effects are not drivers -> ACCEPT` ).
  ENDMETHOD.

  METHOD next_step_bank_en.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank
              iv_verdict   = zif_mdmdoc_types=>c_verdict-accept )
      exp = `use as banking support — compare against SAP/the request form before entry` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank
              iv_verdict   = zif_mdmdoc_types=>c_verdict-reject )
      exp = `kick back — request a bank letter / bank statement / supplier letterhead` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank
              iv_verdict   = zif_mdmdoc_types=>c_verdict-review )
      exp = `hold — resolve the flagged items manually before use` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank
              iv_verdict   = zif_mdmdoc_types=>c_verdict-warning )
      exp = `usable with caution — note the warnings for the Data Owner` ).
  ENDMETHOD.

  METHOD next_step_w9_en.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9
              iv_verdict   = zif_mdmdoc_types=>c_verdict-accept )
      exp = `use for SAP entry (Line 1 -> Name 1, Line 2 -> Name 2, TIN per type)` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9
              iv_verdict   = zif_mdmdoc_types=>c_verdict-reject )
      exp = `kick back — request a corrected W-9` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9
              iv_verdict   = zif_mdmdoc_types=>c_verdict-review )
      exp = `hold — clarify with requestor or request an updated form` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9
              iv_verdict   = zif_mdmdoc_types=>c_verdict-warning )
      exp = `usable with caution — note the warnings` ).
  ENDMETHOD.

  METHOD next_step_bank_ru.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank
              iv_verdict   = zif_mdmdoc_types=>c_verdict-accept
              iv_lang      = 'RU' )
      exp = `использовать как банковское подтверждение — сверьте с SAP/формой запроса перед вводом` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank
              iv_verdict   = zif_mdmdoc_types=>c_verdict-reject
              iv_lang      = 'RU' )
      exp = `вернуть — запросите банковское письмо / выписку / письмо на бланке поставщика` ).
  ENDMETHOD.

  METHOD next_step_w9_ru.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9
              iv_verdict   = zif_mdmdoc_types=>c_verdict-accept
              iv_lang      = 'RU' )
      exp = `использовать для ввода в SAP (Line 1 -> Name 1, Line 2 -> Name 2, TIN по типу)` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9
              iv_verdict   = zif_mdmdoc_types=>c_verdict-review
              iv_lang      = 'RU' )
      exp = `отложить — уточните у запросившего или запросите обновлённую форму` ).
  ENDMETHOD.

  METHOD next_step_unknown_class.
    " Python: unknown doc_class falls back to the bank texts.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = `something`
              iv_verdict   = zif_mdmdoc_types=>c_verdict-accept )
      exp = `use as banking support — compare against SAP/the request form before entry`
      msg = `unknown doc_class -> bank fallback` ).
  ENDMETHOD.

  METHOD next_step_unknown_verd.
    " Python: unknown verdict -> ''.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank
              iv_verdict   = `FOO` )
      exp = ``
      msg = `unknown verdict -> empty string` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>next_step(
              iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9
              iv_verdict   = `FOO`
              iv_lang      = 'RU' )
      exp = `` ).
  ENDMETHOD.

  METHOD msgty_accept.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>message_type( zif_mdmdoc_types=>c_verdict-accept )
      exp = 'S' ).
  ENDMETHOD.

  METHOD msgty_warning.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>message_type( zif_mdmdoc_types=>c_verdict-warning )
      exp = 'W' ).
  ENDMETHOD.

  METHOD msgty_review.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>message_type( zif_mdmdoc_types=>c_verdict-review )
      exp = 'W' ).
  ENDMETHOD.

  METHOD msgty_reject.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_verdict=>message_type( zif_mdmdoc_types=>c_verdict-reject )
      exp = 'E' ).
  ENDMETHOD.

ENDCLASS.
