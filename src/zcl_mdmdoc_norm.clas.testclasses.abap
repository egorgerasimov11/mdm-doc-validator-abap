CLASS ltcl_norm DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS norm_id_basic       FOR TESTING.
    METHODS digits_only_basic   FOR TESTING.
    METHODS norm_flag_variants  FOR TESTING.
    METHODS to_iso2_cases       FOR TESTING.
    METHODS iban_mod97_vectors  FOR TESTING.
    METHODS classification_map  FOR TESTING.
    METHODS business_and_person FOR TESTING.
    METHODS parse_date_formats  FOR TESTING.
    METHODS parse_date_textual  FOR TESTING.
    METHODS parse_date_yearonly FOR TESTING.
    METHODS parse_date_invalid  FOR TESTING.
    METHODS fullwidth_map       FOR TESTING.
    METHODS field_helpers       FOR TESTING.

    METHODS date_str
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_iso)  TYPE string.
ENDCLASS.


CLASS ltcl_norm IMPLEMENTATION.

  METHOD date_str.
    DATA lv_d TYPE d.
    DATA lv_ok TYPE abap_bool.
    zcl_mdmdoc_norm=>parse_date( EXPORTING iv_text = iv_text
                                 IMPORTING ev_date = lv_d ev_ok = lv_ok ).
    IF lv_ok = abap_false.
      rv_iso = `FAIL`.
    ELSE.
      rv_iso = lv_d.   " YYYYMMDD
    ENDIF.
  ENDMETHOD.


  METHOD norm_id_basic.
    " strips whitespace, hyphen AND dot; upper-cases
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_id( ` de89 3704-0044.0532 ` )
      exp = `DE89370400440532` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_id( ` gb82 west-1234.5698 ` )
      exp = `GB82WEST12345698` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_id( `` )
      exp = `` ).
  ENDMETHOD.


  METHOD digits_only_basic.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>digits_only( `12-34 ab56` )
      exp = `123456` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>digits_only( `no digits` )
      exp = `` ).
  ENDMETHOD.


  METHOD norm_flag_variants.
    cl_abap_unit_assert=>assert_true( zcl_mdmdoc_norm=>norm_flag( `true` ) ).
    cl_abap_unit_assert=>assert_true( zcl_mdmdoc_norm=>norm_flag( `TRUE` ) ).
    cl_abap_unit_assert=>assert_true( zcl_mdmdoc_norm=>norm_flag( `Yes` ) ).
    cl_abap_unit_assert=>assert_true( zcl_mdmdoc_norm=>norm_flag( `1` ) ).
    cl_abap_unit_assert=>assert_true( zcl_mdmdoc_norm=>norm_flag( `X` ) ).
    cl_abap_unit_assert=>assert_false( zcl_mdmdoc_norm=>norm_flag( `false` ) ).
    cl_abap_unit_assert=>assert_false( zcl_mdmdoc_norm=>norm_flag( `no` ) ).
    cl_abap_unit_assert=>assert_false( zcl_mdmdoc_norm=>norm_flag( `` ) ).
  ENDMETHOD.


  METHOD to_iso2_cases.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>to_iso2( `Germany` ) exp = `DE` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>to_iso2( `DEU` ) exp = `DE` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>to_iso2( `US` ) exp = `US` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>to_iso2( `  united states of america ` ) exp = `US` ).
    " ISO2 passthrough only for known set
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>to_iso2( `ZZ` ) exp = `` ).
    " prefix rule: 'US-XX' -> 'US' (3rd char not alpha)
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>to_iso2( `US-CA` ) exp = `US` ).
    " unknown long -> ''
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>to_iso2( `USSR` ) exp = `` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>to_iso2( `` ) exp = `` ).
  ENDMETHOD.


  METHOD iban_mod97_vectors.
    " known-good vectors
    cl_abap_unit_assert=>assert_true(
      zcl_mdmdoc_norm=>iban_mod97_ok( `GB82WEST12345698765432` ) ).
    cl_abap_unit_assert=>assert_true(
      zcl_mdmdoc_norm=>iban_mod97_ok( `DE89370400440532013000` ) ).
    " spaces tolerated
    cl_abap_unit_assert=>assert_true(
      zcl_mdmdoc_norm=>iban_mod97_ok( `GB82 WEST 1234 5698 7654 32` ) ).
    " corrupt check digit fails
    cl_abap_unit_assert=>assert_false(
      zcl_mdmdoc_norm=>iban_mod97_ok( `GB83WEST12345698765432` ) ).
    " wrong shape fails
    cl_abap_unit_assert=>assert_false(
      zcl_mdmdoc_norm=>iban_mod97_ok( `1234` ) ).
    cl_abap_unit_assert=>assert_false(
      zcl_mdmdoc_norm=>iban_mod97_ok( `` ) ).
  ENDMETHOD.


  METHOD classification_map.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_classification( `Individual/sole proprietor` )
      exp = `individual_sole_prop` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_classification( `Limited Liability Company (LLC)` )
      exp = `llc` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_classification( `Partnership` )
      exp = `partnership` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_classification( `C Corporation` )
      exp = `corporation` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_classification( `S Corp` )
      exp = `corporation` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_classification( `Trust/estate` )
      exp = `trust_estate` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_classification( `something else` )
      exp = `other` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>norm_classification( `   ` )
      exp = `` ).
  ENDMETHOD.


  METHOD business_and_person.
    " business
    cl_abap_unit_assert=>assert_true(
      zcl_mdmdoc_norm=>looks_like_business( `Acme LLC` ) ).
    cl_abap_unit_assert=>assert_true(
      zcl_mdmdoc_norm=>looks_like_business( `Beispiel GmbH` ) ).
    cl_abap_unit_assert=>assert_true(
      zcl_mdmdoc_norm=>looks_like_business( `Widgets, Inc` ) ).
    cl_abap_unit_assert=>assert_false(
      zcl_mdmdoc_norm=>looks_like_business( `John Smith` ) ).

    " person
    cl_abap_unit_assert=>assert_true(
      zcl_mdmdoc_norm=>looks_like_person( `John Smith` ) ).
    cl_abap_unit_assert=>assert_true(
      zcl_mdmdoc_norm=>looks_like_person( `Mary J Watson` ) ).
    " trade name with stop-word -> not person
    cl_abap_unit_assert=>assert_false(
      zcl_mdmdoc_norm=>looks_like_person( `Culligan of Denver` ) ).
    " digits -> not person
    cl_abap_unit_assert=>assert_false(
      zcl_mdmdoc_norm=>looks_like_person( `Route 66 Diner` ) ).
    " business suffix -> not person
    cl_abap_unit_assert=>assert_false(
      zcl_mdmdoc_norm=>looks_like_person( `Smith LLC` ) ).
    cl_abap_unit_assert=>assert_false(
      zcl_mdmdoc_norm=>looks_like_person( `` ) ).
  ENDMETHOD.


  METHOD parse_date_formats.
    " %d.%m.%Y
    cl_abap_unit_assert=>assert_equals( act = date_str( `15.03.2024` ) exp = `20240315` ).
    " %Y-%m-%d
    cl_abap_unit_assert=>assert_equals( act = date_str( `2024-03-15` ) exp = `20240315` ).
    " %m/%d/%Y (12/31 unambiguously mdY since 31>12)
    cl_abap_unit_assert=>assert_equals( act = date_str( `12/31/2023` ) exp = `20231231` ).
    " %d/%m/%Y (25 can't be a month, so dmY)
    cl_abap_unit_assert=>assert_equals( act = date_str( `25/12/2023` ) exp = `20231225` ).
    " %d-%m-%Y
    cl_abap_unit_assert=>assert_equals( act = date_str( `07-06-2022` ) exp = `20220607` ).
    " %m/%d/%y (2-digit year)
    cl_abap_unit_assert=>assert_equals( act = date_str( `03/09/21` ) exp = `20210309` ).
    " %d.%m.%y (2-digit year)
    cl_abap_unit_assert=>assert_equals( act = date_str( `09.03.21` ) exp = `20210309` ).
  ENDMETHOD.


  METHOD parse_date_textual.
    " %B %d, %Y
    cl_abap_unit_assert=>assert_equals( act = date_str( `March 15, 2024` ) exp = `20240315` ).
    " %d %B %Y
    cl_abap_unit_assert=>assert_equals( act = date_str( `15 March 2024` ) exp = `20240315` ).
    " %b %d, %Y
    cl_abap_unit_assert=>assert_equals( act = date_str( `Mar 15, 2024` ) exp = `20240315` ).
    " ES month: enero
    cl_abap_unit_assert=>assert_equals( act = date_str( `15 de enero de 2024` ) exp = `20240115` ).
    " DE month: märz
    cl_abap_unit_assert=>assert_equals( act = date_str( `15 März 2024` ) exp = `20240315` ).
  ENDMETHOD.


  METHOD parse_date_yearonly.
    " bare 4-digit 20xx year -> July 1
    cl_abap_unit_assert=>assert_equals( act = date_str( `some text 2024 blah` ) exp = `20240701` ).
    cl_abap_unit_assert=>assert_equals( act = date_str( `2023` ) exp = `20230701` ).
  ENDMETHOD.


  METHOD parse_date_invalid.
    cl_abap_unit_assert=>assert_equals( act = date_str( `` ) exp = `FAIL` ).
    cl_abap_unit_assert=>assert_equals( act = date_str( `not a date` ) exp = `FAIL` ).
    " Feb 31 is not a valid strptime date, so every explicit format fails; the
    " year-only fallback then finds 2024 and yields July 1 (matches the Python original).
    cl_abap_unit_assert=>assert_equals( act = date_str( `31.02.2024` ) exp = `20240701` ).
  ENDMETHOD.


  METHOD fullwidth_map.
    " Fullwidth 'ＤＥ８９' -> 'DE89'
    DATA(lv_in) = |{ cl_abap_conv_in_ce=>uccp( 65316 ) }|   " FF24 D
               && |{ cl_abap_conv_in_ce=>uccp( 65317 ) }|   " FF25 E
               && |{ cl_abap_conv_in_ce=>uccp( 65304 ) }|   " FF18 8
               && |{ cl_abap_conv_in_ce=>uccp( 65305 ) }|.  " FF19 9
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>translate_fullwidth( lv_in )
      exp = `DE89` ).
    " lowercase fullwidth 'ａ' -> 'a', plain ASCII untouched
    DATA(lv_a) = |{ cl_abap_conv_in_ce=>uccp( 65345 ) }|.   " FF41 a
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>translate_fullwidth( |X{ lv_a }Z| )
      exp = `XaZ` ).
    " ascii passthrough
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>translate_fullwidth( `plain 123` )
      exp = `plain 123` ).
  ENDMETHOD.


  METHOD field_helpers.
    DATA lt_fields TYPE zif_mdmdoc_types=>tt_fields.
    INSERT VALUE #( name = `signed` value = `true` ) INTO TABLE lt_fields.
    INSERT VALUE #( name = `bank_country` value = `Germany` ) INTO TABLE lt_fields.

    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>field_value( it_fields = lt_fields iv_name = `bank_country` )
      exp = `Germany` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_norm=>field_value( it_fields = lt_fields iv_name = `absent` )
      exp = `` ).
    cl_abap_unit_assert=>assert_true(
      zcl_mdmdoc_norm=>field_is_true( it_fields = lt_fields iv_name = `signed` ) ).
    cl_abap_unit_assert=>assert_false(
      zcl_mdmdoc_norm=>field_is_true( it_fields = lt_fields iv_name = `absent` ) ).
  ENDMETHOD.

ENDCLASS.
