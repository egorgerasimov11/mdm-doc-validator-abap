*"* use this source file for your ABAP unit test classes
CLASS ltcl_selftest DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS core_all_pass    FOR TESTING.
    METHODS missing_class    FOR TESTING.
ENDCLASS.

CLASS ltcl_selftest IMPLEMENTATION.

  METHOD core_all_pass.
    " the non-MDG checks that don't depend on optional components must pass
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_selftest=>check_mask( )-status exp = 'PASS' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_selftest=>check_pdf( )-status exp = 'PASS' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_selftest=>check_comparator( )-status exp = 'PASS' ).
    " own class must be found
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_selftest=>check_class( 'ZCL_MDMDOC_COMPARE' )-status exp = 'PASS' ).
  ENDMETHOD.

  METHOD missing_class.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_selftest=>check_class( 'ZCL_NOPE_DOES_NOT_EXIST_XYZ' )-status exp = 'FAIL' ).
  ENDMETHOD.

ENDCLASS.
