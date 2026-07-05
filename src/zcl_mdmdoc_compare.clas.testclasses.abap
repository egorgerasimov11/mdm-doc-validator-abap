*"* use this source file for your ABAP unit test classes
CLASS ltcl_compare DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS ext
      IMPORTING it_pairs      TYPE string_table
      RETURNING VALUE(rs_ext) TYPE zif_mdmdoc_types=>ty_extraction.
    METHODS saptab
      IMPORTING it_pairs      TYPE string_table
      RETURNING VALUE(rt_sap) TYPE zif_mdmdoc_types=>tt_sap_fields.
    METHODS has_finding
      IMPORTING it_find      TYPE zif_mdmdoc_types=>tt_findings
                iv_id        TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS row_status
      IMPORTING it_rows        TYPE zif_mdmdoc_types=>tt_compare_row
                iv_field       TYPE string
      RETURNING VALUE(rv_stat) TYPE string.

    METHODS iban_match       FOR TESTING.
    METHODS iban_mismatch    FOR TESTING.
    METHODS iban_one_side    FOR TESTING.
    METHODS account_zeros    FOR TESTING.
    METHODS account_in_iban  FOR TESTING.
    METHODS account_mismatch FOR TESTING.
    METHODS swift_xxx        FOR TESTING.
    METHODS swift_mismatch   FOR TESTING.
    METHODS country_mismatch FOR TESTING.
    METHODS bankkey_confirm  FOR TESTING.
    METHODS bankkey_unconf   FOR TESTING.
    METHODS name_substring   FOR TESTING.
    METHODS holder_mismatch  FOR TESTING.
    METHODS no_full_iban     FOR TESTING.
ENDCLASS.

CLASS ltcl_compare IMPLEMENTATION.

  METHOD ext.
    " pairs are 'name=value' strings
    LOOP AT it_pairs INTO DATA(lv_p).
      SPLIT lv_p AT '=' INTO DATA(lv_n) DATA(lv_v).
      INSERT VALUE #( name = lv_n value = lv_v ) INTO TABLE rs_ext-fields.
    ENDLOOP.
    rs_ext-doc_class = 'bank'.
    rs_ext-doc_type  = 'bank_letter'.
  ENDMETHOD.

  METHOD saptab.
    LOOP AT it_pairs INTO DATA(lv_p).
      SPLIT lv_p AT '=' INTO DATA(lv_n) DATA(lv_v).
      INSERT VALUE #( name = lv_n value = lv_v ) INTO TABLE rt_sap.
    ENDLOOP.
  ENDMETHOD.

  METHOD has_finding.
    LOOP AT it_find TRANSPORTING NO FIELDS WHERE rule_id = iv_id.
      rv_ok = abap_true.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

  METHOD row_status.
    READ TABLE it_rows WITH KEY field = iv_field INTO DATA(ls).
    IF sy-subrc = 0.
      rv_stat = ls-status.
    ENDIF.
  ENDMETHOD.

  METHOD iban_match.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `iban=DE44500105175407324931` ) ) )
                it_sap = saptab( VALUE #( ( `iban=DE44 5001 0517 5407 3249 31` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'IBAN' ) exp = 'match' ).
    cl_abap_unit_assert=>assert_true( has_finding( it_find = lt_find iv_id = 'SAP-000' ) ).
    cl_abap_unit_assert=>assert_false( has_finding( it_find = lt_find iv_id = 'SAP-001' ) ).
  ENDMETHOD.

  METHOD iban_mismatch.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `iban=DE44500105175407324931` ) ) )
                it_sap = saptab( VALUE #( ( `iban=DE44500105175407324999` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'IBAN' ) exp = 'MISMATCH' ).
    cl_abap_unit_assert=>assert_true( has_finding( it_find = lt_find iv_id = 'SAP-001' ) ).
    cl_abap_unit_assert=>assert_false( has_finding( it_find = lt_find iv_id = 'SAP-000' ) ).
  ENDMETHOD.

  METHOD iban_one_side.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `iban=DE44500105175407324931` ) ) )
                it_sap = saptab( VALUE #( ( `bank_name=X` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'IBAN' ) exp = 'only-one-side' ).
    cl_abap_unit_assert=>assert_true( has_finding( it_find = lt_find iv_id = 'SAP-002' ) ).
  ENDMETHOD.

  METHOD account_zeros.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `account_number=123456789` ) ) )
                it_sap = saptab( VALUE #( ( `bank_account=000123456789` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'Bank Account' ) exp = 'match' ).
    cl_abap_unit_assert=>assert_false( has_finding( it_find = lt_find iv_id = 'SAP-003' ) ).
  ENDMETHOD.

  METHOD account_in_iban.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `account_number=5407324931` ) ) )
                it_sap = saptab( VALUE #( ( `bank_account=99999999` )
                                          ( `iban=DE44500105175407324931` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'Bank Account' ) exp = 'match' ).
    cl_abap_unit_assert=>assert_false( has_finding( it_find = lt_find iv_id = 'SAP-003' ) ).
  ENDMETHOD.

  METHOD account_mismatch.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `account_number=111122223333` ) ) )
                it_sap = saptab( VALUE #( ( `bank_account=444455556666` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'Bank Account' ) exp = 'MISMATCH' ).
    cl_abap_unit_assert=>assert_true( has_finding( it_find = lt_find iv_id = 'SAP-003' ) ).
  ENDMETHOD.

  METHOD swift_xxx.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `swift_bic=DEUTDEFF` ) ) )
                it_sap = saptab( VALUE #( ( `swift_bic=DEUTDEFFXXX` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'SWIFT/BIC' ) exp = 'match' ).
    cl_abap_unit_assert=>assert_false( has_finding( it_find = lt_find iv_id = 'SAP-004' ) ).
  ENDMETHOD.

  METHOD swift_mismatch.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `swift_bic=DEUTDEFF` ) ) )
                it_sap = saptab( VALUE #( ( `swift_bic=BNPAFRPP` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_find = lt_find iv_id = 'SAP-004' ) ).
  ENDMETHOD.

  METHOD country_mismatch.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `bank_country=Germany` ) ) )
                it_sap = saptab( VALUE #( ( `bank_country=FR` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'Bank Country' ) exp = 'MISMATCH' ).
    cl_abap_unit_assert=>assert_true( has_finding( it_find = lt_find iv_id = 'SAP-005' ) ).
  ENDMETHOD.

  METHOD bankkey_confirm.
    " bank key sits in the IBAN bank-code position -> confirmed, no finding
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `iban=DE44500105175407324931` ) ) )
                it_sap = saptab( VALUE #( ( `bank_key=50010517` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'Bank Key' ) exp = 'match' ).
    cl_abap_unit_assert=>assert_false( has_finding( it_find = lt_find iv_id = 'SAP-006' ) ).
  ENDMETHOD.

  METHOD bankkey_unconf.
    " routing present but different from SAP bank key -> unconfirmed warning
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `routing_aba=021000021` ) ) )
                it_sap = saptab( VALUE #( ( `bank_key=99998888` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'Bank Key' ) exp = 'MISMATCH' ).
    cl_abap_unit_assert=>assert_true( has_finding( it_find = lt_find iv_id = 'SAP-006' ) ).
  ENDMETHOD.

  METHOD name_substring.
    " document bank name contained in SAP name -> match
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `bank_name=Deutsche Bank` ) ) )
                it_sap = saptab( VALUE #( ( `bank_name=DEUTSCHE BANK AG` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'Bank Name' ) exp = 'match' ).
    cl_abap_unit_assert=>assert_false( has_finding( it_find = lt_find iv_id = 'SAP-007' ) ).
  ENDMETHOD.

  METHOD holder_mismatch.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `account_holder=ACME TRADING LLC` ) ) )
                it_sap = saptab( VALUE #( ( `account_name=GLOBEX CORPORATION` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    cl_abap_unit_assert=>assert_equals( act = row_status( it_rows = lt_rows iv_field = 'Account Holder' ) exp = 'MISMATCH' ).
    cl_abap_unit_assert=>assert_true( has_finding( it_find = lt_find iv_id = 'SAP-008' ) ).
  ENDMETHOD.

  METHOD no_full_iban.
    " a masked comparison must never surface the full IBAN in rows or messages
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ext( VALUE #( ( `iban=DE44500105175407324931` ) ) )
                it_sap = saptab( VALUE #( ( `iban=DE44500105175407324999` ) ) )
      IMPORTING et_findings = DATA(lt_find) et_rows = DATA(lt_rows) ).
    DATA(lv_all) = concat_lines_of( table = VALUE string_table(
      FOR r IN lt_rows ( |{ r-doc }#{ r-sap }#{ r-note }| ) ) sep = |#| ).
    LOOP AT lt_find INTO DATA(ls_f).
      lv_all = |{ lv_all }#{ ls_f-message }|.
    ENDLOOP.
    cl_abap_unit_assert=>assert_false( boolc( lv_all CS 'DE44500105175407324931' ) ).
    cl_abap_unit_assert=>assert_false( boolc( lv_all CS 'DE44500105175407324999' ) ).
  ENDMETHOD.

ENDCLASS.
