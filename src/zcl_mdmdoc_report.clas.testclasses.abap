*"* use this source file for your ABAP unit test classes
CLASS ltcl_report DEFINITION DEFERRED.
CLASS zcl_mdmdoc_report DEFINITION LOCAL FRIENDS ltcl_report.

CLASS ltcl_report DEFINITION FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS build_bank_fields
      IMPORTING iv_iban        TYPE string DEFAULT 'DE44500105175407324931'
      RETURNING VALUE(rs_ext)  TYPE zif_mdmdoc_types=>ty_extraction.
    METHODS masks_iban_in_list   FOR TESTING.
    METHODS groups_findings      FOR TESTING.
    METHODS w9_sap_hints         FOR TESTING.
    METHODS json_is_valid        FOR TESTING.
    METHODS json_no_full_tin     FOR TESTING.
    METHODS sap_block_rendered   FOR TESTING.
    METHODS sap_compare_in_json  FOR TESTING.
ENDCLASS.

CLASS ltcl_report IMPLEMENTATION.

  METHOD build_bank_fields.
    rs_ext-doc_class = 'bank'.
    rs_ext-doc_type  = 'bank_letter'.
    INSERT VALUE #( name = 'account_holder' value = 'CAMPOVERDE SRL' ) INTO TABLE rs_ext-fields.
    INSERT VALUE #( name = 'bank_name'      value = 'BANCA X' )        INTO TABLE rs_ext-fields.
    INSERT VALUE #( name = 'bank_country'   value = 'IT' )             INTO TABLE rs_ext-fields.
    INSERT VALUE #( name = 'iban'           value = iv_iban )          INTO TABLE rs_ext-fields.
    INSERT VALUE #( name = 'signed'         value = 'false' )          INTO TABLE rs_ext-fields.
    APPEND iv_iban TO rs_ext-secrets.
  ENDMETHOD.

  METHOD masks_iban_in_list.
    DATA(ls_ext) = build_bank_fields( ).
    DATA(lt_find) = VALUE zif_mdmdoc_types=>tt_findings(
      ( rule_id = 'BNK-021' severity = 'WARNING' verdict_effect = 'WARNING' message = 'unsigned' ) ).
    DATA(lt) = zcl_mdmdoc_report=>build_list(
      is_ext = ls_ext it_findings = lt_find iv_verdict = 'WARNING' iv_lang = 'EN' iv_policy = 'masked' ).
    DATA(lv_all) = concat_lines_of( table = lt sep = |#| ).
    " full IBAN must NOT appear; masked form must
    cl_abap_unit_assert=>assert_false( boolc( lv_all CS 'DE44500105175407324931' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_all CS 'DE**' ) ).
    " country + length annotation present
    cl_abap_unit_assert=>assert_true( boolc( lv_all CS 'country DE' ) ).
  ENDMETHOD.

  METHOD groups_findings.
    DATA(ls_ext) = build_bank_fields( ).
    DATA(lt_find) = VALUE zif_mdmdoc_types=>tt_findings(
      ( rule_id = 'BNK-001' severity = 'CRITICAL' verdict_effect = 'REJECT'  message = 'invoice never' )
      ( rule_id = 'BNK-021' severity = 'WARNING'  verdict_effect = 'WARNING' message = 'unsigned letter' ) ).
    DATA(lt) = zcl_mdmdoc_report=>build_list(
      is_ext = ls_ext it_findings = lt_find iv_verdict = 'REJECT' iv_lang = 'EN' iv_policy = 'masked' ).
    DATA(lv_all) = concat_lines_of( table = lt sep = |#| ).
    cl_abap_unit_assert=>assert_true( boolc( lv_all CS '[BNK-001] invoice never' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_all CS '[BNK-021] unsigned letter' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_all CS 'Critical issues (1)' ) ).
  ENDMETHOD.

  METHOD w9_sap_hints.
    DATA ls_ext TYPE zif_mdmdoc_types=>ty_extraction.
    ls_ext-doc_class = 'w9'.
    ls_ext-doc_type  = 'w9'.
    INSERT VALUE #( name = 'line1_name' value = 'EIT 2.0 LLC' ) INTO TABLE ls_ext-fields.
    INSERT VALUE #( name = 'tin_type'   value = 'EIN' )         INTO TABLE ls_ext-fields.
    INSERT VALUE #( name = 'tin_raw'    value = '123456789' )   INTO TABLE ls_ext-fields.
    INSERT VALUE #( name = 'signed'     value = 'true' )        INTO TABLE ls_ext-fields.
    DATA(lt) = zcl_mdmdoc_report=>build_list(
      is_ext = ls_ext it_findings = VALUE #( ) iv_verdict = 'ACCEPT' iv_lang = 'EN' iv_policy = 'masked' ).
    DATA(lv_all) = concat_lines_of( table = lt sep = |#| ).
    cl_abap_unit_assert=>assert_true( boolc( lv_all CS 'SAP Name 1' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_all CS 'Tax Number 2' ) ).
    " full TIN never printed
    cl_abap_unit_assert=>assert_false( boolc( lv_all CS '123456789' ) ).
  ENDMETHOD.

  METHOD json_is_valid.
    DATA(ls_ext) = build_bank_fields( ).
    DATA(lv_json) = zcl_mdmdoc_report=>build_json(
      is_ext = ls_ext it_findings = VALUE #( ) iv_verdict = 'WARNING'
      iv_doc_path = '/tmp/x.pdf' iv_run_id = 'abcdef0123456789' iv_lang = 'EN' iv_policy = 'masked' ).
    " round-trips through /ui2/cl_json => structurally valid JSON
    DATA lr_data TYPE REF TO data.
    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = lr_data ).
      CATCH cx_root.
        cl_abap_unit_assert=>fail( 'build_json produced invalid JSON' ).
    ENDTRY.
    cl_abap_unit_assert=>assert_true( boolc( lv_json CS '"schema": "mdmdoc.v1"' ) ).
  ENDMETHOD.

  METHOD json_no_full_tin.
    DATA ls_ext TYPE zif_mdmdoc_types=>ty_extraction.
    ls_ext-doc_class = 'w9'.
    ls_ext-doc_type  = 'w9'.
    INSERT VALUE #( name = 'tin_type' value = 'EIN' )       INTO TABLE ls_ext-fields.
    INSERT VALUE #( name = 'tin_raw'  value = '987654321' ) INTO TABLE ls_ext-fields.
    APPEND '987654321' TO ls_ext-secrets.
    DATA(lv_json) = zcl_mdmdoc_report=>build_json(
      is_ext = ls_ext it_findings = VALUE #( ) iv_verdict = 'ACCEPT'
      iv_doc_path = '/tmp/w9.pdf' iv_run_id = 'ffee00112233aabb' iv_lang = 'EN' iv_policy = 'full' ).
    cl_abap_unit_assert=>assert_false( boolc( lv_json CS '987654321' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_json CS '"tin":' ) ).
  ENDMETHOD.

  METHOD sap_block_rendered.
    DATA(ls_ext) = build_bank_fields( ).
    DATA(lt_cmp) = VALUE zif_mdmdoc_types=>tt_compare_row(
      ( field = 'IBAN' doc = 'DE**…4931' sap = 'DE**…4999' status = 'MISMATCH' note = 'differs from position 21' ) ).
    DATA(lt) = zcl_mdmdoc_report=>build_list(
      is_ext = ls_ext it_findings = VALUE #( ) iv_verdict = 'NEED_MANUAL_REVIEW'
      iv_lang = 'EN' iv_policy = 'masked' it_compare = lt_cmp ).
    DATA(lv_all) = concat_lines_of( table = lt sep = |#| ).
    cl_abap_unit_assert=>assert_true( boolc( lv_all CS 'SAP COMPARISON' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_all CS 'MISMATCH' ) ).
    " empty compare -> no block
    DATA(lt2) = zcl_mdmdoc_report=>build_list(
      is_ext = ls_ext it_findings = VALUE #( ) iv_verdict = 'ACCEPT' iv_lang = 'EN' iv_policy = 'masked' ).
    cl_abap_unit_assert=>assert_false( boolc( concat_lines_of( table = lt2 sep = |#| ) CS 'SAP COMPARISON' ) ).
  ENDMETHOD.

  METHOD sap_compare_in_json.
    DATA(ls_ext) = build_bank_fields( ).
    DATA(lt_cmp) = VALUE zif_mdmdoc_types=>tt_compare_row(
      ( field = 'IBAN' doc = 'DE**…4931' sap = 'DE**…4999' status = 'MISMATCH' note = 'differs from position 21' ) ).
    DATA(lv_json) = zcl_mdmdoc_report=>build_json(
      is_ext = ls_ext it_findings = VALUE #( ) iv_verdict = 'NEED_MANUAL_REVIEW'
      iv_doc_path = '/tmp/x.pdf' iv_run_id = 'abcdef0123456789' iv_lang = 'EN'
      iv_policy = 'masked' it_compare = lt_cmp ).
    cl_abap_unit_assert=>assert_true( boolc( lv_json CS '"sap_compare":' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_json CS '"status": "MISMATCH"' ) ).
    " still valid JSON
    DATA lr_data TYPE REF TO data.
    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = lr_data ).
      CATCH cx_root.
        cl_abap_unit_assert=>fail( 'sap_compare broke JSON' ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
