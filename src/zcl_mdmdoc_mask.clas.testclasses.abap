CLASS ltcl_mask DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA gv_ell TYPE string.   " U+2026 ellipsis, built at runtime

    METHODS setup.

    " mask() shapes from the privacy.py docstrings
    METHODS mask_ssn        FOR TESTING.
    METHODS mask_ein        FOR TESTING.
    METHODS mask_tin_ssn    FOR TESTING.
    METHODS mask_tin_ein    FOR TESTING.
    METHODS mask_tin_bare   FOR TESTING.
    METHODS mask_iban       FOR TESTING.
    METHODS mask_account    FOR TESTING.
    METHODS mask_routing    FOR TESTING.
    METHODS mask_short      FOR TESTING.
    METHODS mask_empty      FOR TESTING.
    METHODS mask_unknown    FOR TESTING.

    " display_value policy matrix
    METHODS display_tin_full   FOR TESTING.
    METHODS display_bank_masked FOR TESTING.
    METHODS display_bank_full  FOR TESTING.
    METHODS display_empty      FOR TESTING.

    " kind_for_field
    METHODS kind_mapping       FOR TESTING.

    " scrub_text
    METHODS scrub_ssn_ein      FOR TESTING.
    METHODS scrub_iban         FOR TESTING.

    " assert_no_leak
    METHODS leak_pattern_hit   FOR TESTING.
    METHODS leak_clean_miss    FOR TESTING.
    METHODS leak_known_secret  FOR TESTING.
    METHODS leak_norm_secret   FOR TESTING.
    METHODS leak_tin_only      FOR TESTING.
ENDCLASS.


CLASS ltcl_mask IMPLEMENTATION.

  METHOD setup.
    gv_ell = cl_abap_conv_in_ce=>uccp( uccp = '2026' ).
  ENDMETHOD.

  METHOD mask_ssn.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'ssn' iv_value = '123-45-6789' )
      exp = 'XXX-XX-6789' ).
  ENDMETHOD.

  METHOD mask_ein.
    " EIN: XX-XXX + last4 (privacy.py: "XX-XXX" + d[-4:])
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'ein' iv_value = '12-3456789' )
      exp = 'XX-XXX6789' ).
  ENDMETHOD.

  METHOD mask_tin_ssn.
    " tin routed to SSN style by 3-2-4 shape
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'tin' iv_value = '123-45-6789' )
      exp = 'XXX-XX-6789' ).
  ENDMETHOD.

  METHOD mask_tin_ein.
    " tin routed to EIN style by 2-7 shape
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'tin' iv_value = '12-3456789' )
      exp = 'XX-XXX6789' ).
  ENDMETHOD.

  METHOD mask_tin_bare.
    " tin with no recognizable hyphen shape: stars + last4
    " 9 bare digits -> 5 stars + last4
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'tin' iv_value = '123456789' )
      exp = '*****6789' ).
  ENDMETHOD.

  METHOD mask_iban.
    " DE44500105175407324931 -> DE**…4931
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'iban' iv_value = 'DE44500105175407324931' )
      exp = |DE**{ gv_ell }4931| ).
  ENDMETHOD.

  METHOD mask_account.
    " 0560016869996971 -> …6971
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'account_number' iv_value = '0560016869996971' )
      exp = |{ gv_ell }6971| ).
  ENDMETHOD.

  METHOD mask_routing.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'routing_aba' iv_value = '021000021' )
      exp = |{ gv_ell }0021| ).
  ENDMETHOD.

  METHOD mask_short.
    " account with <4 digits -> ellipsis + all digits
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'account_number' iv_value = '12' )
      exp = |{ gv_ell }12| ).
    " ssn with <4 digits
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'ssn' iv_value = '12' )
      exp = 'XXX-XX-????' ).
  ENDMETHOD.

  METHOD mask_empty.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'ssn' iv_value = '   ' )
      exp = '' ).
  ENDMETHOD.

  METHOD mask_unknown.
    " unknown kind, >=5 digits -> stars + last4
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'mystery' iv_value = '9988776655' )
      exp = '******6655' ).
    " unknown kind, <5 digits -> ****
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>mask( iv_kind = 'mystery' iv_value = '123' )
      exp = '****' ).
  ENDMETHOD.

  METHOD display_tin_full.
    " TIN kinds are masked even under policy='full'
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>display_value(
              iv_kind = 'ssn' iv_value = '123-45-6789' iv_policy = 'full' )
      exp = 'XXX-XX-6789' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>display_value(
              iv_kind = 'tin' iv_value = '12-3456789' iv_policy = 'full' )
      exp = 'XX-XXX6789' ).
  ENDMETHOD.

  METHOD display_bank_masked.
    " bank kind under default masked policy -> masked
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>display_value(
              iv_kind = 'iban' iv_value = 'DE44500105175407324931' )
      exp = |DE**{ gv_ell }4931| ).
  ENDMETHOD.

  METHOD display_bank_full.
    " bank kind under policy='full' -> raw (trimmed) value
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>display_value(
              iv_kind = 'iban' iv_value = ' DE44500105175407324931 ' iv_policy = 'full' )
      exp = 'DE44500105175407324931' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>display_value(
              iv_kind = 'account_number' iv_value = '0560016869996971' iv_policy = 'full' )
      exp = '0560016869996971' ).
  ENDMETHOD.

  METHOD display_empty.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>display_value( iv_kind = 'iban' iv_value = '' )
      exp = '' ).
  ENDMETHOD.

  METHOD kind_mapping.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>kind_for_field( 'iban' ) exp = 'iban' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>kind_for_field( 'routing_aba_wires' ) exp = 'routing_aba' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>kind_for_field( 'tin_raw' ) exp = 'tin' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>kind_for_field( 'tin_boxed' ) exp = 'tin' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>kind_for_field( 'ein' ) exp = 'ein' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>kind_for_field( 'ssn' ) exp = 'ssn' ).
    " not sensitive -> ''
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_mask=>kind_for_field( 'bank_name' ) exp = '' ).
  ENDMETHOD.

  METHOD scrub_ssn_ein.
    DATA lv_in  TYPE string.
    DATA lv_out TYPE string.
    lv_in  = 'SSN 123-45-6789 and EIN 12-3456789 here'.
    lv_out = zcl_mdmdoc_mask=>scrub_text( lv_in ).
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_out exp = '*XXX-XX-6789*' ).
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_out exp = '*XX-XXX6789*' ).
    " raw values must be gone
    cl_abap_unit_assert=>assert_equals(
      act = boolc( lv_out CS '123-45-6789' ) exp = abap_false ).
    cl_abap_unit_assert=>assert_equals(
      act = boolc( lv_out CS '12-3456789' ) exp = abap_false ).
  ENDMETHOD.

  METHOD scrub_iban.
    DATA lv_out TYPE string.
    lv_out = zcl_mdmdoc_mask=>scrub_text( 'Pay to DE44500105175407324931 today' ).
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_out exp = |*DE**{ gv_ell }4931*| ).
    cl_abap_unit_assert=>assert_equals(
      act = boolc( lv_out CS 'DE44500105175407324931' ) exp = abap_false ).
  ENDMETHOD.

  METHOD leak_pattern_hit.
    DATA lt_hits  TYPE string_table.
    DATA lv_clean TYPE abap_bool.
    DATA lt_sec   TYPE string_table.
    " unmasked SSN in output -> strict catches it via pattern pass
    zcl_mdmdoc_mask=>assert_no_leak(
      EXPORTING iv_blob = 'oops 123-45-6789 leaked' it_secrets = lt_sec
      IMPORTING et_hits = lt_hits ev_clean = lv_clean ).
    cl_abap_unit_assert=>assert_equals( act = lv_clean exp = abap_false ).
    cl_abap_unit_assert=>assert_not_initial( act = lt_hits ).
  ENDMETHOD.

  METHOD leak_clean_miss.
    DATA lt_hits  TYPE string_table.
    DATA lv_clean TYPE abap_bool.
    DATA lt_sec   TYPE string_table.
    " already masked -> no pattern, no secret -> clean
    zcl_mdmdoc_mask=>assert_no_leak(
      EXPORTING iv_blob = 'safe: XXX-XX-6789 and DE**...4931' it_secrets = lt_sec
      IMPORTING et_hits = lt_hits ev_clean = lv_clean ).
    cl_abap_unit_assert=>assert_equals( act = lv_clean exp = abap_true ).
    cl_abap_unit_assert=>assert_initial( act = lt_hits ).
  ENDMETHOD.

  METHOD leak_known_secret.
    DATA lt_hits  TYPE string_table.
    DATA lv_clean TYPE abap_bool.
    DATA lt_sec   TYPE string_table.
    APPEND 'DE44500105175407324931' TO lt_sec.
    " exact secret appears verbatim -> known-secret pass fires
    zcl_mdmdoc_mask=>assert_no_leak(
      EXPORTING iv_blob = 'ref DE44500105175407324931 end' it_secrets = lt_sec
      IMPORTING et_hits = lt_hits ev_clean = lv_clean ).
    cl_abap_unit_assert=>assert_equals( act = lv_clean exp = abap_false ).
  ENDMETHOD.

  METHOD leak_norm_secret.
    DATA lt_hits  TYPE string_table.
    DATA lv_clean TYPE abap_bool.
    DATA lt_sec   TYPE string_table.
    APPEND '021000021' TO lt_sec.
    " secret appears spaced/grouped -> digit-normalized secret pass catches it
    zcl_mdmdoc_mask=>assert_no_leak(
      EXPORTING iv_blob = 'aba 0210 0002 1 shown' it_secrets = lt_sec
      IMPORTING et_hits = lt_hits ev_clean = lv_clean ).
    cl_abap_unit_assert=>assert_equals( act = lv_clean exp = abap_false ).
  ENDMETHOD.

  METHOD leak_tin_only.
    DATA lt_hits  TYPE string_table.
    DATA lv_clean TYPE abap_bool.
    DATA lt_sec   TYPE string_table.
    " a bare 9-digit routing number: under tin-only it is ALLOWED (no bank patterns,
    " no bare \d{9} TIN pattern), so no hit.
    zcl_mdmdoc_mask=>assert_no_leak(
      EXPORTING iv_blob = 'routing 021000021 visible' it_secrets = lt_sec
                iv_policy = 'tin-only'
      IMPORTING et_hits = lt_hits ev_clean = lv_clean ).
    cl_abap_unit_assert=>assert_equals( act = lv_clean exp = abap_true ).
    " but the SAME blob under strict trips the long-digit banking pattern... 9 digits
    " is below \d{11,18}; still, tin-only leaves it clean which is the point.
    " And a real TIN shape is still blocked under tin-only:
    CLEAR lt_hits.
    zcl_mdmdoc_mask=>assert_no_leak(
      EXPORTING iv_blob = 'ssn 123-45-6789' it_secrets = lt_sec
                iv_policy = 'tin-only'
      IMPORTING et_hits = lt_hits ev_clean = lv_clean ).
    cl_abap_unit_assert=>assert_equals( act = lv_clean exp = abap_false ).
  ENDMETHOD.

ENDCLASS.
