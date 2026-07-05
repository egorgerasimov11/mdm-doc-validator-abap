*&---------------------------------------------------------------------*
*& Report ZMDMDOC_DOCTOR
*&---------------------------------------------------------------------*
*& Deployment pre-flight: small, independent checks you run BEFORE enabling
*& the MDG BAdI globally — "can it load, can it read data". Each check is
*& isolated so a red line tells you exactly what to fix.
*&
*& The core (non-MDG) checks are the unit-tested ZCL_MDMDOC_SELFTEST. The MDG
*& checks below touch the MDG framework and are *** VERIFY ON SYSTEM *** — this
*& program is excluded from abaplint. Give a change-request number to also test
*& live CR field + attachment reading.
*&---------------------------------------------------------------------*
REPORT zmdmdoc_doctor.

PARAMETERS: p_model TYPE usmd_model DEFAULT 'BP'.
PARAMETERS: p_cr    TYPE usmd_crequest.     " optional: test reading this CR

START-OF-SELECTION.
  DATA lt TYPE zif_mdmdoc_types=>tt_check.

  " 1) core checks (unit-tested, no SAP MDG needed)
  lt = zcl_mdmdoc_selftest=>run_core( ).

  " 2) MDG framework availability
  APPEND zcl_mdmdoc_selftest=>check_class( 'IF_USMD_MODEL_EXT' ) TO lt.
  APPEND zcl_mdmdoc_selftest=>check_class( 'ZCL_MDMDOC_MDG_READER' ) TO lt.
  APPEND zcl_mdmdoc_selftest=>check_class( 'ZCL_MDG_BP_FIELD_DERR_VAL' ) TO lt.
  APPEND zcl_mdmdoc_selftest=>check_class( 'CL_GOS_API' ) TO lt.

  " 3) message class ZMDMDOC / 001 present
  DATA lv_msg TYPE string.
  SELECT SINGLE text FROM t100 INTO @lv_msg
    WHERE sprsl = @sy-langu AND arbgb = 'ZMDMDOC' AND msgnr = '001'.
  APPEND VALUE #( name = 'message class ZMDMDOC / 001'
                  status = COND #( WHEN sy-subrc = 0 THEN zif_mdmdoc_types=>c_check-pass ELSE zif_mdmdoc_types=>c_check-fail )
                  detail = COND #( WHEN sy-subrc = 0 THEN 'defined' ELSE 'create in SE91 (001 = &1&2&3&4)' ) ) TO lt.

  " 4) live MDG read for a given CR (optional)
  IF p_cr IS NOT INITIAL.
    TRY.
        " *** VERIFY ON SYSTEM ***: how you obtain an if_usmd_model_ext instance
        " standalone may differ; inside the BAdI it is passed as io_model.
        DATA(lo_model) = cl_usmd_model_ext=>get_instance( i_usmd_model = p_model ).
        DATA(lo_reader) = NEW zcl_mdmdoc_mdg_reader(
          io_model = lo_model iv_crequest = p_cr iv_model = p_model ).

        lo_reader->zif_mdmdoc_sap_reader~read_cr_fields(
          EXPORTING iv_cr = |{ p_cr }|
          IMPORTING et_sap = DATA(lt_sap) ev_found = DATA(lv_found) ev_error = DATA(lv_err) ).
        APPEND VALUE #( name = |read CR fields ({ p_cr })|
                        status = COND #( WHEN lv_found = abap_true THEN zif_mdmdoc_types=>c_check-pass ELSE zif_mdmdoc_types=>c_check-fail )
                        detail = COND #( WHEN lv_found = abap_true THEN |{ lines( lt_sap ) } field(s) read| ELSE |nothing read { lv_err }| ) ) TO lt.

        lo_reader->zif_mdmdoc_sap_reader~read_cr_attachments(
          EXPORTING iv_cr = |{ p_cr }|
          IMPORTING et_docs = DATA(lt_docs) ev_error = DATA(lv_aerr) ).
        APPEND VALUE #( name = |read CR attachments ({ p_cr })|
                        status = COND #( WHEN lt_docs IS NOT INITIAL THEN zif_mdmdoc_types=>c_check-pass
                                         WHEN lv_aerr IS NOT INITIAL THEN zif_mdmdoc_types=>c_check-fail
                                         ELSE zif_mdmdoc_types=>c_check-skip )
                        detail = COND #( WHEN lt_docs IS NOT INITIAL THEN |{ lines( lt_docs ) } attachment(s)|
                                         WHEN lv_aerr IS NOT INITIAL THEN lv_aerr ELSE 'no attachments on this CR' ) ) TO lt.
      CATCH cx_root INTO DATA(lx).
        APPEND VALUE #( name = |MDG model instance ({ p_model })|
                        status = zif_mdmdoc_types=>c_check-fail detail = lx->get_text( ) ) TO lt.
    ENDTRY.
  ELSE.
    APPEND VALUE #( name = 'live CR read'
                    status = zif_mdmdoc_types=>c_check-skip detail = 'enter a change request number to test' ) TO lt.
  ENDIF.

  " ---- output ----
  DATA lv_fail TYPE i.
  DATA lv_pass TYPE i.
  WRITE: / 'mdmdoc deployment pre-flight', AT 60 'model', p_model.
  ULINE.
  LOOP AT lt ASSIGNING FIELD-SYMBOL(<c>).
    CASE <c>-status.
      WHEN zif_mdmdoc_types=>c_check-pass. FORMAT COLOR COL_POSITIVE. lv_pass = lv_pass + 1.
      WHEN zif_mdmdoc_types=>c_check-fail. FORMAT COLOR COL_NEGATIVE. lv_fail = lv_fail + 1.
      WHEN OTHERS.                          FORMAT COLOR COL_TOTAL.
    ENDCASE.
    WRITE: / <c>-status, AT 8 <c>-name.
    FORMAT COLOR OFF.
    IF <c>-detail IS NOT INITIAL.
      WRITE: AT 55 <c>-detail.
    ENDIF.
  ENDLOOP.
  ULINE.
  WRITE: / |{ lv_pass } passed, { lv_fail } failed|.
  IF lv_fail = 0.
    WRITE: / 'All checks passed — safe to enable the BAdI (verify the MDG mapping first).'.
  ELSE.
    WRITE: / 'Fix the red checks before enabling the BAdI globally.'.
  ENDIF.
