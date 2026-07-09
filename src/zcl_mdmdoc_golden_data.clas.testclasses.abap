" Golden parity: every case in ZCL_MDMDOC_GOLDEN_DATA (generated from the shared
" tools/golden/golden_cases.json) must reproduce the SAME fields + crosscheck
" notes the Python deterministic engine produces — behavioural Python<->ABAP
" parity that a marker grep cannot give. doc_type is supplied per case (ABAP has
" no type_hint port); candidates come from the ported ZCL_MDMDOC_REGEX.
CLASS ltcl_golden DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    METHODS all_cases FOR TESTING.
    METHODS note_present
      IMPORTING it_notes     TYPE string_table
                iv_sub       TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.
ENDCLASS.


CLASS ltcl_golden IMPLEMENTATION.

  METHOD note_present.
    LOOP AT it_notes INTO DATA(lv_n).
      IF lv_n CS iv_sub.
        rv_ok = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD all_cases.
    LOOP AT zcl_mdmdoc_golden_data=>gt_cases INTO DATA(ls_case).
      DATA(lt_cand) = zcl_mdmdoc_regex=>extract_candidates( ls_case-raw_text ).
      " llm_fields simulate model output on BOTH sides (Python injected_llm seam)
      DATA(ls_ext) = zcl_mdmdoc_extract=>build(
        iv_doc_class  = ls_case-doc_class
        iv_doc_type   = ls_case-doc_type
        it_llm_fields = ls_case-llm_fields
        it_candidates = lt_cand
        iv_llm_used   = boolc( lines( ls_case-llm_fields ) > 0 )
        iv_raw_text   = ls_case-raw_text
        iv_filename   = ls_case-filename ).

      LOOP AT ls_case-exp_fields INTO DATA(ls_f).
        cl_abap_unit_assert=>assert_equals(
          act = zcl_mdmdoc_norm=>field_value( it_fields = ls_ext-fields
                                              iv_name = ls_f-name )
          exp = ls_f-value
          msg = |golden { ls_case-id }: field { ls_f-name }| ).
      ENDLOOP.

      LOOP AT ls_case-exp_notes INTO DATA(lv_sub).
        cl_abap_unit_assert=>assert_true(
          act = note_present( it_notes = ls_ext-crosscheck iv_sub = lv_sub )
          msg = |golden { ls_case-id }: missing note '{ lv_sub }'| ).
      ENDLOOP.

      " v2: VERDICT parity — the same rules engine + precedence fold must yield
      " the same rule findings and final verdict as the Python side
      IF ls_case-exp_verdict IS NOT INITIAL OR lines( ls_case-exp_findings ) > 0.
        DATA(lt_findings) = NEW zcl_mdmdoc_rules( )->run( is_ext = ls_ext ).
        LOOP AT ls_case-exp_findings INTO DATA(lv_rid).
          DATA lv_fired TYPE abap_bool.
          CLEAR lv_fired.
          LOOP AT lt_findings INTO DATA(ls_find).
            IF ls_find-rule_id = lv_rid.
              lv_fired = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.
          cl_abap_unit_assert=>assert_true(
            act = lv_fired
            msg = |golden { ls_case-id }: expected finding { lv_rid } did not fire| ).
        ENDLOOP.
        IF ls_case-exp_verdict IS NOT INITIAL.
          cl_abap_unit_assert=>assert_equals(
            act = zcl_mdmdoc_verdict=>decide( lt_findings )
            exp = ls_case-exp_verdict
            msg = |golden { ls_case-id }: verdict| ).
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
