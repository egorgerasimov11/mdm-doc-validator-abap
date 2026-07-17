CLASS zcl_mdmdoc_norm DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS norm_id
      IMPORTING iv_value     TYPE string
      RETURNING VALUE(rv_id) TYPE string.

    CLASS-METHODS digits_only
      IMPORTING iv_value         TYPE string
      RETURNING VALUE(rv_digits) TYPE string.

    CLASS-METHODS norm_flag
      IMPORTING iv_value       TYPE string
      RETURNING VALUE(rv_bool) TYPE abap_bool.

    CLASS-METHODS to_iso2
      IMPORTING iv_country     TYPE string
      RETURNING VALUE(rv_iso2) TYPE string.

    CLASS-METHODS iban_mod97_ok
      IMPORTING iv_iban      TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    CLASS-METHODS norm_classification
      IMPORTING iv_text         TYPE string
      RETURNING VALUE(rv_class) TYPE string.

    CLASS-METHODS looks_like_business
      IMPORTING iv_name       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    CLASS-METHODS looks_like_person
      IMPORTING iv_name       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    CLASS-METHODS parse_date
      IMPORTING iv_text TYPE string
      EXPORTING ev_date TYPE d
                ev_ok   TYPE abap_bool.

    CLASS-METHODS translate_fullwidth
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS field_value
      IMPORTING it_fields       TYPE zif_mdmdoc_types=>tt_fields
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS field_is_true
      IMPORTING it_fields      TYPE zif_mdmdoc_types=>tt_fields
                iv_name        TYPE string
      RETURNING VALUE(rv_bool) TYPE abap_bool.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_map,
             key TYPE string,
             val TYPE string,
           END OF ty_map,
           tt_map TYPE STANDARD TABLE OF ty_map WITH EMPTY KEY.

    TYPES: BEGIN OF ty_month,
             name TYPE string,   " english lower-case month name
             num  TYPE i,
           END OF ty_month,
           tt_month TYPE STANDARD TABLE OF ty_month WITH EMPTY KEY.

    CLASS-DATA gt_name_iso  TYPE tt_map.
    CLASS-DATA gt_iso3_iso2 TYPE tt_map.
    CLASS-DATA gt_iso2_set  TYPE string_table.
    CLASS-DATA gt_months    TYPE tt_month.
    CLASS-DATA gt_es_de     TYPE tt_map.   " foreign month -> english lower name

    CLASS-METHODS class_constructor.

    CLASS-METHODS is_alpha
      IMPORTING iv_char       TYPE csequence
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    CLASS-METHODS is_digit
      IMPORTING iv_char       TYPE csequence
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    CLASS-METHODS try_numeric_date
      IMPORTING iv_text TYPE string
      EXPORTING ev_date TYPE d
                ev_ok   TYPE abap_bool.

    CLASS-METHODS try_textual_date
      IMPORTING iv_text TYPE string
      EXPORTING ev_date TYPE d
                ev_ok   TYPE abap_bool.

    CLASS-METHODS make_date
      IMPORTING iv_year TYPE i
                iv_mon  TYPE i
                iv_day  TYPE i
      EXPORTING ev_date TYPE d
                ev_ok   TYPE abap_bool.
ENDCLASS.


CLASS zcl_mdmdoc_norm IMPLEMENTATION.

  METHOD class_constructor.
    " COUNTRY_NAME_TO_ISO (lower-case keys)
    gt_name_iso = VALUE #(
      ( key = `brazil` val = `BR` ) ( key = `brasil` val = `BR` )
      ( key = `chile` val = `CL` ) ( key = `colombia` val = `CO` )
      ( key = `canada` val = `CA` )
      ( key = `united states` val = `US` ) ( key = `usa` val = `US` )
      ( key = `united states of america` val = `US` ) ( key = `u.s.` val = `US` )
      ( key = `germany` val = `DE` ) ( key = `deutschland` val = `DE` )
      ( key = `italy` val = `IT` ) ( key = `italia` val = `IT` )
      ( key = `france` val = `FR` )
      ( key = `netherlands` val = `NL` ) ( key = `nederland` val = `NL` )
      ( key = `the netherlands` val = `NL` ) ( key = `holland` val = `NL` )
      ( key = `switzerland` val = `CH` ) ( key = `schweiz` val = `CH` )
      ( key = `suisse` val = `CH` ) ( key = `japan` val = `JP` )
      ( key = `korea` val = `KR` )
      ( key = `south korea` val = `KR` ) ( key = `republic of korea` val = `KR` )
      ( key = `china` val = `CN` ) ( key = `spain` val = `ES` )
      ( key = `españa` val = `ES` )
      ( key = `united kingdom` val = `GB` ) ( key = `uk` val = `GB` )
      ( key = `great britain` val = `GB` ) ( key = `austria` val = `AT` )
      ( key = `poland` val = `PL` )
      ( key = `belgium` val = `BE` ) ( key = `finland` val = `FI` )
      ( key = `norway` val = `NO` ) ( key = `sweden` val = `SE` )
      ( key = `ireland` val = `IE` )
      ( key = `portugal` val = `PT` ) ( key = `denmark` val = `DK` )
      ( key = `singapore` val = `SG` ) ( key = `hong kong` val = `HK` )
      ( key = `malaysia` val = `MY` )
      ( key = `united arab emirates` val = `AE` ) ( key = `uae` val = `AE` )
      ( key = `mexico` val = `MX` ) ( key = `argentina` val = `AR` )
      ( key = `india` val = `IN` ) ).

    " ISO2_SET = distinct values of the map
    LOOP AT gt_name_iso ASSIGNING FIELD-SYMBOL(<m>).
      READ TABLE gt_iso2_set TRANSPORTING NO FIELDS WITH KEY table_line = <m>-val.
      IF sy-subrc <> 0.
        APPEND <m>-val TO gt_iso2_set.
      ENDIF.
    ENDLOOP.

    gt_iso3_iso2 = VALUE #(
      ( key = `COL` val = `CO` ) ( key = `USA` val = `US` )
      ( key = `DEU` val = `DE` ) ( key = `CHN` val = `CN` )
      ( key = `GBR` val = `GB` ) ( key = `ESP` val = `ES` )
      ( key = `MEX` val = `MX` ) ( key = `BRA` val = `BR` )
      ( key = `CHL` val = `CL` ) ( key = `CAN` val = `CA` )
      ( key = `FRA` val = `FR` ) ( key = `ITA` val = `IT` )
      ( key = `NLD` val = `NL` ) ( key = `CHE` val = `CH` )
      ( key = `JPN` val = `JP` ) ( key = `KOR` val = `KR` )
      ( key = `SGP` val = `SG` ) ( key = `ARE` val = `AE` )
      ( key = `AUT` val = `AT` ) ( key = `PRT` val = `PT` ) ).

    " [CONST:months_abbrev_set]
    gt_months = VALUE #(
      ( name = `january` num = 1 ) ( name = `february` num = 2 )
      ( name = `march` num = 3 ) ( name = `april` num = 4 )
      ( name = `may` num = 5 ) ( name = `june` num = 6 )
      ( name = `july` num = 7 ) ( name = `august` num = 8 )
      ( name = `september` num = 9 ) ( name = `october` num = 10 )
      ( name = `november` num = 11 ) ( name = `december` num = 12 )
      " abbreviated (%b) forms
      ( name = `jan` num = 1 ) ( name = `feb` num = 2 )
      ( name = `mar` num = 3 ) ( name = `apr` num = 4 )
      ( name = `jun` num = 6 ) ( name = `jul` num = 7 )
      ( name = `aug` num = 8 ) ( name = `sep` num = 9 )
      ( name = `oct` num = 10 ) ( name = `nov` num = 11 )
      ( name = `dec` num = 12 ) ).

    " ES/DE month -> english lower month name (predicates._MONTHS)
    " [CONST:months_es_de_map]
    gt_es_de = VALUE #(
      ( key = `enero` val = `january` ) ( key = `febrero` val = `february` )
      ( key = `marzo` val = `march` ) ( key = `abril` val = `april` )
      ( key = `mayo` val = `may` ) ( key = `junio` val = `june` )
      ( key = `julio` val = `july` ) ( key = `agosto` val = `august` )
      ( key = `septiembre` val = `september` ) ( key = `octubre` val = `october` )
      ( key = `noviembre` val = `november` ) ( key = `diciembre` val = `december` )
      ( key = `januar` val = `january` ) ( key = `februar` val = `february` )
      ( key = `märz` val = `march` )
      ( key = `mai` val = `may` ) ( key = `juni` val = `june` )
      ( key = `juli` val = `july` ) ( key = `oktober` val = `october` )
      ( key = `dezember` val = `december` ) ).
  ENDMETHOD.


  METHOD is_alpha.
    rv_yes = boolc( iv_char CA 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz' ).
  ENDMETHOD.


  METHOD is_digit.
    rv_yes = boolc( iv_char CA '0123456789' ).
  ENDMETHOD.


  METHOD norm_id.
    " fields._norm_id: strip [\s\-.] then upper-case
    rv_id = iv_value.
    REPLACE ALL OCCURRENCES OF REGEX `[[:space:]\-.]` IN rv_id WITH ``.
    TRANSLATE rv_id TO UPPER CASE.
  ENDMETHOD.


  METHOD digits_only.
    DATA lv_len TYPE i.
    DATA lv_off TYPE i.
    rv_digits = ``.
    lv_len = strlen( iv_value ).
    WHILE lv_off < lv_len.
      DATA(lv_ch) = iv_value+lv_off(1).
      IF lv_ch CA '0123456789'.
        rv_digits = rv_digits && lv_ch.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD norm_flag.
    " 'true','yes','1','x' (any case) -> abap_true
    DATA(lv) = to_lower( condense( iv_value ) ).
    rv_bool = boolc( lv = `true` OR lv = `yes` OR lv = `1` OR lv = `x` ).
  ENDMETHOD.


  METHOD to_iso2.
    DATA lv_v   TYPE string.
    DATA lv_low TYPE string.
    DATA lv_up  TYPE string.

    lv_v = iv_country.
    CONDENSE lv_v.                 " python .strip()
    IF lv_v IS INITIAL.
      rv_iso2 = ``.
      RETURN.
    ENDIF.

    lv_low = to_lower( lv_v ).
    READ TABLE gt_name_iso ASSIGNING FIELD-SYMBOL(<m>) WITH KEY key = lv_low.
    IF sy-subrc = 0.
      rv_iso2 = <m>-val.
      RETURN.
    ENDIF.

    lv_up = to_upper( lv_v ).

    " len == 2 and in ISO2_SET
    IF strlen( lv_up ) = 2.
      READ TABLE gt_iso2_set TRANSPORTING NO FIELDS WITH KEY table_line = lv_up.
      IF sy-subrc = 0.
        rv_iso2 = lv_up.
        RETURN.
      ENDIF.
    ENDIF.

    " ISO3 -> ISO2
    READ TABLE gt_iso3_iso2 ASSIGNING <m> WITH KEY key = lv_up.
    IF sy-subrc = 0.
      rv_iso2 = <m>-val.
      RETURN.
    ENDIF.

    " len > 2 and first two in ISO2_SET and 3rd char not alpha
    IF strlen( lv_up ) > 2.
      DATA(lv_prefix) = lv_up(2).
      DATA(lv_third) = lv_up+2(1).
      READ TABLE gt_iso2_set TRANSPORTING NO FIELDS WITH KEY table_line = lv_prefix.
      IF sy-subrc = 0 AND is_alpha( lv_third ) = abap_false.
        rv_iso2 = lv_prefix.
        RETURN.
      ENDIF.
    ENDIF.

    rv_iso2 = ``.
  ENDMETHOD.


  METHOD iban_mod97_ok.
    " ISO 13616. Strip whitespace only, upper-case.
    DATA lv_s TYPE string.
    lv_s = iv_iban.
    REPLACE ALL OCCURRENCES OF REGEX `[[:space:]]` IN lv_s WITH ``.
    TRANSLATE lv_s TO UPPER CASE.

    " shape ^[A-Z]{2}\d{2}[A-Z0-9]{8,30}$
    IF NOT cl_abap_matcher=>matches(
             pattern = `[A-Z][A-Z]\d\d[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]{0,22}`
             text    = lv_s ).
      rv_ok = abap_false.
      RETURN.
    ENDIF.

    " re-arranged: move first 4 chars to end
    DATA(lv_len) = strlen( lv_s ).
    DATA(lv_rot) = lv_s+4 && lv_s(4).

    " streaming mod-97: for each char, expand letters A=10..Z=35 to their
    " digits, feeding one decimal digit at a time into carry = (carry*10+d) MOD 97
    DATA lv_carry TYPE i VALUE 0.
    DATA lv_off   TYPE i VALUE 0.
    lv_len = strlen( lv_rot ).
    WHILE lv_off < lv_len.
      DATA(lv_ch) = lv_rot+lv_off(1).
      DATA lv_val TYPE i.
      IF lv_ch CA '0123456789'.
        lv_val = lv_ch.
        lv_carry = ( lv_carry * 10 + lv_val ) MOD 97.
      ELSE.
        " letter: value 10..35 -> two decimal digits
        DATA lv_pos TYPE i.
        FIND FIRST OCCURRENCE OF lv_ch IN 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' MATCH OFFSET lv_pos.
        lv_val = lv_pos + 10.
        lv_carry = ( lv_carry * 10 + ( lv_val DIV 10 ) ) MOD 97.
        lv_carry = ( lv_carry * 10 + ( lv_val MOD 10 ) ) MOD 97.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.

    rv_ok = boolc( lv_carry = 1 ).
  ENDMETHOD.


  METHOD norm_classification.
    DATA(lv) = to_lower( iv_text ).
    DATA(lv_strip) = lv.
    CONDENSE lv_strip.

    IF lv CS `individual` OR lv CS `sole`.
      rv_class = `individual_sole_prop`.
    ELSEIF lv CS `llc` OR lv CS `limited liability`.
      rv_class = `llc`.
    ELSEIF lv CS `partnership`.
      rv_class = `partnership`.
    ELSEIF lv CS `corporation` OR lv_strip = `c corp` OR lv_strip = `s corp`.
      rv_class = `corporation`.
    ELSEIF lv CS `trust` OR lv CS `estate`.
      rv_class = `trust_estate`.
    ELSEIF lv_strip IS NOT INITIAL.
      rv_class = `other`.
    ELSE.
      rv_class = ``.
    ENDIF.
  ENDMETHOD.


  METHOD looks_like_business.
    " _BUSINESS_SUFFIX_RE, case-insensitive, whole-word.
    " (?i)\b(llc|l\.l\.c|inc|incorporated|corp|corporation|ltd|limited|gmbh|
    "        s\.?a\.?s?|pllc|llp|company|co\.)\b
    DATA(lv_pat) = `\<(llc|l\.l\.c|inc|incorporated|corp|corporation|ltd|limited|gmbh|`
                && `s\.?a\.?s?|pllc|llp|company|co\.)\>`.
    rv_yes = boolc( cl_abap_matcher=>contains(
                      pattern     = lv_pat
                      text        = iv_name
                      ignore_case = abap_true ) ).
  ENDMETHOD.


  METHOD looks_like_person.
    " predicates._looks_like_person
    DATA(lv_n) = iv_name.
    CONDENSE lv_n.                              " .strip() (also collapses inner runs; fine for shape)
    IF lv_n IS INITIAL.
      rv_yes = abap_false.
      RETURN.
    ENDIF.

    " any digit -> not a person
    DATA lv_off TYPE i.
    DATA(lv_len) = strlen( lv_n ).
    WHILE lv_off < lv_len.
      IF is_digit( substring( val = lv_n off = lv_off len = 1 ) ) = abap_true.
        rv_yes = abap_false.
        RETURN.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.

    " stop-words: " of ", " the ", " and ", " & ", " for "
    DATA(lv_low) = | { to_lower( lv_n ) } |.    " space-padded, python f" {n.lower()} "
    IF lv_low CS ` of ` OR lv_low CS ` the ` OR lv_low CS ` and `
       OR lv_low CS ` & ` OR lv_low CS ` for `.
      rv_yes = abap_false.
      RETURN.
    ENDIF.

    " business suffix guard
    IF looks_like_business( lv_n ) = abap_true.
      rv_yes = abap_false.
      RETURN.
    ENDIF.

    " _PERSON_NAME_RE: ^[A-Z][a-z]+(?:\s+[A-Z]\.?)?(?:\s+[A-Z][a-z]+){1,2}$
    DATA(lv_pat) = `[A-Z][a-z]+(\s+[A-Z]\.?)?(\s+[A-Z][a-z]+){1,2}`.
    rv_yes = boolc( cl_abap_matcher=>matches( pattern = lv_pat text = lv_n ) ).
  ENDMETHOD.


  METHOD parse_date.
    CLEAR ev_date.
    ev_ok = abap_false.

    DATA(lv_v) = iv_text.
    CONDENSE lv_v.                               " .strip()
    IF lv_v IS INITIAL.
      RETURN.
    ENDIF.

    " ES/DE month substitution (whole-word), then drop stand-alone 'de'
    DATA(lv_low) = to_lower( lv_v ).
    LOOP AT gt_es_de ASSIGNING FIELD-SYMBOL(<mm>).
      IF cl_abap_matcher=>contains(
           pattern     = |\\<{ <mm>-key }\\>|
           text        = lv_low
           ignore_case = abap_true ).
        " replace foreign month with english (case-insensitive, whole word)
        REPLACE ALL OCCURRENCES OF REGEX |\\<{ <mm>-key }\\>| IN lv_v
                WITH <mm>-val IGNORING CASE.
        " drop 'de' whole-word (\bde\b, case-insensitive)
        REPLACE ALL OCCURRENCES OF REGEX `\<de\>` IN lv_v WITH ` ` IGNORING CASE.
        CONDENSE lv_v.
        EXIT.
      ENDIF.
    ENDLOOP.

    " numeric formats first (matches python _DATE_FORMATS order well enough:
    " numeric formats are mutually exclusive by shape; textual handled separately)
    try_numeric_date( EXPORTING iv_text = lv_v IMPORTING ev_date = ev_date ev_ok = ev_ok ).
    IF ev_ok = abap_true.
      RETURN.
    ENDIF.

    try_textual_date( EXPORTING iv_text = lv_v IMPORTING ev_date = ev_date ev_ok = ev_ok ).
    IF ev_ok = abap_true.
      RETURN.
    ENDIF.

    " year-only fallback: first 20xx -> July 1
    DATA lv_yoff TYPE i.
    DATA lv_ylen TYPE i.
    FIND FIRST OCCURRENCE OF REGEX `20\d\d` IN lv_v MATCH OFFSET lv_yoff MATCH LENGTH lv_ylen.
    IF sy-subrc = 0.
      DATA(lv_ystr) = lv_v+lv_yoff(4).
      make_date( EXPORTING iv_year = CONV i( lv_ystr ) iv_mon = 7 iv_day = 1
                 IMPORTING ev_date = ev_date ev_ok = ev_ok ).
    ENDIF.
  ENDMETHOD.


  METHOD try_numeric_date.
    " Handles: %d.%m.%Y %d/%m/%Y %m/%d/%Y %Y-%m-%d %d-%m-%Y %m/%d/%y %d.%m.%y
    " Python tries the list in order and returns the FIRST that parses.
    CLEAR ev_date.
    ev_ok = abap_false.

    DATA lt_parts TYPE string_table.
    DATA lv_sep   TYPE c LENGTH 1.

    " %Y-%m-%d  (ISO, dash, 4-digit year first)
    IF cl_abap_matcher=>matches( pattern = `\d\d\d\d-\d{1,2}-\d{1,2}` text = iv_text ).
      SPLIT iv_text AT '-' INTO TABLE lt_parts.
      make_date( EXPORTING iv_year = CONV i( lt_parts[ 1 ] )
                           iv_mon  = CONV i( lt_parts[ 2 ] )
                           iv_day  = CONV i( lt_parts[ 3 ] )
                 IMPORTING ev_date = ev_date ev_ok = ev_ok ).
      RETURN.
    ENDIF.

    " dotted: %d.%m.%Y then %d.%m.%y
    IF iv_text CS '.'.
      SPLIT iv_text AT '.' INTO TABLE lt_parts.
      IF lines( lt_parts ) = 3.
        DATA(lv_y) = lt_parts[ 3 ].
        IF strlen( lv_y ) = 4 AND cl_abap_matcher=>matches( pattern = `\d\d\d\d` text = lv_y ).
          make_date( EXPORTING iv_year = CONV i( lv_y )
                               iv_mon  = CONV i( lt_parts[ 2 ] )
                               iv_day  = CONV i( lt_parts[ 1 ] )
                     IMPORTING ev_date = ev_date ev_ok = ev_ok ).
          RETURN.
        ELSEIF strlen( lv_y ) = 2 AND cl_abap_matcher=>matches( pattern = `\d\d` text = lv_y ).
          make_date( EXPORTING iv_year = 2000 + CONV i( lv_y )
                               iv_mon  = CONV i( lt_parts[ 2 ] )
                               iv_day  = CONV i( lt_parts[ 1 ] )
                     IMPORTING ev_date = ev_date ev_ok = ev_ok ).
          RETURN.
        ENDIF.
      ENDIF.
      RETURN.
    ENDIF.

    " slash: %d/%m/%Y, %m/%d/%Y, %m/%d/%y (python order: dmy-Y, mdy-Y, mdy-y).
    " Try %d/%m/%Y first, then %m/%d/%Y, then %m/%d/%y.
    IF iv_text CS '/'.
      SPLIT iv_text AT '/' INTO TABLE lt_parts.
      IF lines( lt_parts ) = 3.
        DATA(lv_a) = lt_parts[ 1 ].
        DATA(lv_b) = lt_parts[ 2 ].
        DATA(lv_c) = lt_parts[ 3 ].
        IF strlen( lv_c ) = 4 AND cl_abap_matcher=>matches( pattern = `\d\d\d\d` text = lv_c ).
          " %d/%m/%Y
          make_date( EXPORTING iv_year = CONV i( lv_c ) iv_mon = CONV i( lv_b ) iv_day = CONV i( lv_a )
                     IMPORTING ev_date = ev_date ev_ok = ev_ok ).
          IF ev_ok = abap_true.
            RETURN.
          ENDIF.
          " %m/%d/%Y
          make_date( EXPORTING iv_year = CONV i( lv_c ) iv_mon = CONV i( lv_a ) iv_day = CONV i( lv_b )
                     IMPORTING ev_date = ev_date ev_ok = ev_ok ).
          RETURN.
        ELSEIF strlen( lv_c ) = 2 AND cl_abap_matcher=>matches( pattern = `\d\d` text = lv_c ).
          " %m/%d/%y
          make_date( EXPORTING iv_year = 2000 + CONV i( lv_c ) iv_mon = CONV i( lv_a ) iv_day = CONV i( lv_b )
                     IMPORTING ev_date = ev_date ev_ok = ev_ok ).
          RETURN.
        ENDIF.
      ENDIF.
      RETURN.
    ENDIF.

    " dash (non-ISO): %d-%m-%Y
    IF iv_text CS '-'.
      SPLIT iv_text AT '-' INTO TABLE lt_parts.
      IF lines( lt_parts ) = 3.
        DATA(lv_yy) = lt_parts[ 3 ].
        IF strlen( lv_yy ) = 4 AND cl_abap_matcher=>matches( pattern = `\d\d\d\d` text = lv_yy ).
          make_date( EXPORTING iv_year = CONV i( lv_yy )
                               iv_mon  = CONV i( lt_parts[ 2 ] )
                               iv_day  = CONV i( lt_parts[ 1 ] )
                     IMPORTING ev_date = ev_date ev_ok = ev_ok ).
        ENDIF.
      ENDIF.
      RETURN.
    ENDIF.
  ENDMETHOD.


  METHOD try_textual_date.
    " Handles: %B %d, %Y | %d %B %Y | %b %d, %Y
    " Month name (full or abbreviated) already normalised to english by parse_date.
    CLEAR ev_date.
    ev_ok = abap_false.

    " normalise: drop commas, collapse spaces
    DATA(lv) = iv_text.
    REPLACE ALL OCCURRENCES OF ',' IN lv WITH ` `.
    CONDENSE lv.
    IF lv IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_tok TYPE string_table.
    SPLIT lv AT ` ` INTO TABLE lt_tok.
    DELETE lt_tok WHERE table_line IS INITIAL.
    IF lines( lt_tok ) <> 3.
      RETURN.
    ENDIF.

    DATA lv_mon  TYPE i.
    DATA lv_day  TYPE i.
    DATA lv_year TYPE i.
    DATA lv_have_mon TYPE abap_bool VALUE abap_false.

    " Pattern A: <MonthName> <day> <year>   (%B/%b %d, %Y)
    DATA(lv_t1) = to_lower( lt_tok[ 1 ] ).
    READ TABLE gt_months ASSIGNING FIELD-SYMBOL(<mo>) WITH KEY name = lv_t1.
    IF sy-subrc = 0
       AND cl_abap_matcher=>matches( pattern = `\d{1,2}` text = lt_tok[ 2 ] )
       AND cl_abap_matcher=>matches( pattern = `\d\d\d\d` text = lt_tok[ 3 ] ).
      lv_mon  = <mo>-num.
      lv_day  = lt_tok[ 2 ].
      lv_year = lt_tok[ 3 ].
      lv_have_mon = abap_true.
    ELSE.
      " Pattern B: <day> <MonthName> <year>   (%d %B %Y)
      DATA(lv_t2) = to_lower( lt_tok[ 2 ] ).
      READ TABLE gt_months ASSIGNING <mo> WITH KEY name = lv_t2.
      IF sy-subrc = 0
         AND cl_abap_matcher=>matches( pattern = `\d{1,2}` text = lt_tok[ 1 ] )
         AND cl_abap_matcher=>matches( pattern = `\d\d\d\d` text = lt_tok[ 3 ] ).
        lv_mon  = <mo>-num.
        lv_day  = lt_tok[ 1 ].
        lv_year = lt_tok[ 3 ].
        lv_have_mon = abap_true.
      ENDIF.
    ENDIF.

    IF lv_have_mon = abap_false.
      RETURN.
    ENDIF.

    make_date( EXPORTING iv_year = lv_year iv_mon = lv_mon iv_day = lv_day
               IMPORTING ev_date = ev_date ev_ok = ev_ok ).
  ENDMETHOD.


  METHOD make_date.
    " Validate a calendar date (strptime rejects invalid dates -> ValueError).
    CLEAR ev_date.
    ev_ok = abap_false.

    IF iv_year < 1 OR iv_year > 9999 OR iv_mon < 1 OR iv_mon > 12 OR iv_day < 1 OR iv_day > 31.
      RETURN.
    ENDIF.

    DATA lv_maxday TYPE i.
    CASE iv_mon.
      WHEN 1 OR 3 OR 5 OR 7 OR 8 OR 10 OR 12.
        lv_maxday = 31.
      WHEN 4 OR 6 OR 9 OR 11.
        lv_maxday = 30.
      WHEN 2.
        DATA lv_leap TYPE abap_bool.
        IF ( iv_year MOD 4 = 0 AND iv_year MOD 100 <> 0 ) OR iv_year MOD 400 = 0.
          lv_leap = abap_true.
        ELSE.
          lv_leap = abap_false.
        ENDIF.
        lv_maxday = COND i( WHEN lv_leap = abap_true THEN 29 ELSE 28 ).
    ENDCASE.

    IF iv_day > lv_maxday.
      RETURN.
    ENDIF.

    DATA lv_y TYPE c LENGTH 4.
    DATA lv_m TYPE c LENGTH 2.
    DATA lv_d TYPE c LENGTH 2.
    lv_y = |{ iv_year WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
    lv_m = |{ iv_mon WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
    lv_d = |{ iv_day WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
    ev_date = lv_y && lv_m && lv_d.
    ev_ok = abap_true.
  ENDMETHOD.


  METHOD translate_fullwidth.
    " U+FF10..FF19 -> 0-9 ; U+FF21..FF3A -> A-Z ; U+FF41..FF5A -> a-z
    DATA lv_off TYPE i.
    DATA(lv_len) = strlen( iv_text ).
    rv_text = ``.

    " Reference ASCII strings, indexed by (codepoint - base)
    CONSTANTS lc_digits TYPE string VALUE `0123456789`.
    CONSTANTS lc_upper  TYPE string VALUE `ABCDEFGHIJKLMNOPQRSTUVWXYZ`.
    CONSTANTS lc_lower  TYPE string VALUE `abcdefghijklmnopqrstuvwxyz`.

    WHILE lv_off < lv_len.
      DATA(lv_ch) = iv_text+lv_off(1).
      DATA(lv_cp) = cl_abap_conv_in_ce=>uccpi( lv_ch ).   " code point as integer
      DATA lv_out TYPE string.
      IF lv_cp >= 65296 AND lv_cp <= 65305.          " FF10..FF19
        DATA(lv_idx) = lv_cp - 65296.
        lv_out = lc_digits+lv_idx(1).
      ELSEIF lv_cp >= 65313 AND lv_cp <= 65338.      " FF21..FF3A
        lv_idx = lv_cp - 65313.
        lv_out = lc_upper+lv_idx(1).
      ELSEIF lv_cp >= 65345 AND lv_cp <= 65370.      " FF41..FF5A
        lv_idx = lv_cp - 65345.
        lv_out = lc_lower+lv_idx(1).
      ELSE.
        lv_out = lv_ch.
      ENDIF.
      rv_text = rv_text && lv_out.
      lv_off = lv_off + 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD field_value.
    READ TABLE it_fields ASSIGNING FIELD-SYMBOL(<f>) WITH KEY name = iv_name.
    IF sy-subrc = 0.
      rv_value = <f>-value.
    ELSE.
      rv_value = ``.
    ENDIF.
  ENDMETHOD.


  METHOD field_is_true.
    rv_bool = norm_flag( field_value( it_fields = it_fields iv_name = iv_name ) ).
  ENDMETHOD.

ENDCLASS.
