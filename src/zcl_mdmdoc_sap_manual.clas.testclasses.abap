*"* use this source file for your ABAP unit test classes
CLASS ltcl_manual DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS json_to_fields   FOR TESTING.
    METHODS direct_table     FOR TESTING.
    METHODS end_to_end_cmp   FOR TESTING.
ENDCLASS.

CLASS ltcl_manual IMPLEMENTATION.

  METHOD json_to_fields.
    DATA(lo) = NEW zcl_mdmdoc_sap_manual(
      iv_json = `{"iban":"DE44500105175407324931","bank_name":"DEUTSCHE BANK AG","control_key":""}` ).
    DATA lt_sap TYPE zif_mdmdoc_types=>tt_sap_fields.
    DATA lv_found TYPE abap_bool.
    lo->zif_mdmdoc_sap_reader~read_cr_fields(
      EXPORTING iv_cr = 'CR1' IMPORTING et_sap = lt_sap ev_found = lv_found ).
    cl_abap_unit_assert=>assert_true( lv_found ).
    READ TABLE lt_sap WITH KEY name = 'iban' INTO DATA(ls).
    cl_abap_unit_assert=>assert_equals( act = ls-value exp = 'DE44500105175407324931' ).
    " empty component must not create a row
    READ TABLE lt_sap WITH KEY name = 'control_key' TRANSPORTING NO FIELDS.
    cl_abap_unit_assert=>assert_subrc( exp = 4 act = sy-subrc ).
  ENDMETHOD.

  METHOD direct_table.
    DATA(lt_in) = VALUE zif_mdmdoc_types=>tt_sap_fields( ( name = 'swift_bic' value = 'DEUTDEFF' ) ).
    DATA(lo) = NEW zcl_mdmdoc_sap_manual( it_sap = lt_in ).
    lo->zif_mdmdoc_sap_reader~read_cr_fields(
      EXPORTING iv_cr = 'CR1' IMPORTING et_sap = DATA(lt_sap) ev_found = DATA(lv_found) ).
    cl_abap_unit_assert=>assert_true( lv_found ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_sap ) exp = 1 ).
  ENDMETHOD.

  METHOD end_to_end_cmp.
    " manual reader -> comparator, IBAN mismatch produces SAP-001
    DATA(lo) = NEW zcl_mdmdoc_sap_manual( iv_json = `{"iban":"DE44500105175407324999"}` ).
    lo->zif_mdmdoc_sap_reader~read_cr_fields(
      EXPORTING iv_cr = 'CR1' IMPORTING et_sap = DATA(lt_sap) ).
    DATA ls_ext TYPE zif_mdmdoc_types=>ty_extraction.
    ls_ext-doc_class = 'bank'.
    INSERT VALUE #( name = 'iban' value = 'DE44500105175407324931' ) INTO TABLE ls_ext-fields.
    zcl_mdmdoc_compare=>compare(
      EXPORTING is_ext = ls_ext it_sap = lt_sap
      IMPORTING et_findings = DATA(lt_find) ).
    DATA lv_hit TYPE abap_bool.
    LOOP AT lt_find TRANSPORTING NO FIELDS WHERE rule_id = 'SAP-001'.
      lv_hit = abap_true.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true( lv_hit ).
  ENDMETHOD.

ENDCLASS.
