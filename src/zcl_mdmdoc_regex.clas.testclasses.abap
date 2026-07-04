CLASS ltcl_regex DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS iban_with_spaces    FOR TESTING.
    METHODS swift_near_label    FOR TESTING.
    METHODS swift_word_reject   FOR TESTING.
    METHODS routing_std_vs_wire FOR TESTING.
    METHODS ein_hyphenated      FOR TESTING.
    METHODS ein_spaced_label    FOR TESTING.
    METHODS ssn_masked          FOR TESTING.
    METHODS boxed_tin_ein       FOR TESTING.
    METHODS boxed_tin_ssn       FOR TESTING.
    METHODS account_label_en    FOR TESTING.
    METHODS account_label_es    FOR TESTING.
    METHODS account_fallback    FOR TESTING.
    METHODS fullwidth_ein       FOR TESTING.

    "! value of a candidate ('' when absent)
    METHODS cand
      IMPORTING it     TYPE zif_mdmdoc_types=>tt_fields
                iv     TYPE string
      RETURNING VALUE(rv) TYPE string.

    "! join lines with a real newline (SPLIT target of extract_candidates)
    METHODS ml
      IMPORTING it        TYPE string_table
      RETURNING VALUE(rv) TYPE string.

    "! build a string from a table of unicode code points
    METHODS cp
      IMPORTING it        TYPE string_table
      RETURNING VALUE(rv) TYPE string.
ENDCLASS.


CLASS ltcl_regex IMPLEMENTATION.

  METHOD cand.
    READ TABLE it ASSIGNING FIELD-SYMBOL(<f>) WITH KEY name = iv.
    IF sy-subrc = 0.
      rv = <f>-value.
    ELSE.
      rv = ``.
    ENDIF.
  ENDMETHOD.


  METHOD ml.
    DATA lv_first TYPE abap_bool VALUE abap_true.
    LOOP AT it ASSIGNING FIELD-SYMBOL(<l>).
      IF lv_first = abap_true.
        rv = <l>.
        lv_first = abap_false.
      ELSE.
        rv = rv && cl_abap_char_utilities=>newline && <l>.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD cp.
    LOOP AT it ASSIGNING FIELD-SYMBOL(<n>).
      rv = rv && cl_abap_conv_in_ce=>uccp( CONV i( <n> ) ).
    ENDLOOP.
  ENDMETHOD.


  METHOD iban_with_spaces.
    " grouped IBAN with spaces -> stripped + upper, kept (len within 15..34)
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      `Please remit to IBAN DE89 3704 0044 0532 0130 00 at the bank.` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `iban` ) exp = `DE89370400440532013000` ).
  ENDMETHOD.


  METHOD swift_near_label.
    " BIC near a SWIFT label is accepted even though it is otherwise word-like
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      `Beneficiary bank SWIFT: DEUTDEFF500 for wire transfers.` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `swift_bic` ) exp = `DEUTDEFF500` ).
  ENDMETHOD.


  METHOD swift_word_reject.
    " an 8-letter ALL-ALPHA word with no BIC/SWIFT label is NOT a BIC
    " (Python: findall branch requires at least one digit -> not c.isalpha()).
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      `The NOTABANK institution processes payments.` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `swift_bic` ) exp = `` ).
  ENDMETHOD.


  METHOD routing_std_vs_wire.
    " US letter with TWO ABA values: standard vs wires, routed by qualifier word
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      `Routing (ABA): 021000021 ; Wire routing number: 026009593` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `routing_aba` ) exp = `021000021` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `routing_aba_wires` ) exp = `026009593` ).
  ENDMETHOD.


  METHOD ein_hyphenated.
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      `Federal EIN 12-3456789 on file.` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `ein` ) exp = `12-3456789` ).
  ENDMETHOD.


  METHOD ein_spaced_label.
    " spaced digits near the EIN label (no contiguous dd-ddddddd) -> reassembled
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      `Employer Identification Number 8 1 - 0 8 2 6 7 3 4 (as printed)` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `ein` ) exp = `81-0826734` ).
  ENDMETHOD.


  METHOD ssn_masked.
    " SSN is stored MASKED, never in full
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      `SSN 123-45-6789 provided by the individual.` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `ssn` ) exp = `***-**-6789` ).
  ENDMETHOD.


  METHOD boxed_tin_ein.
    " W-9 digit boxes: one digit per line, a dash line between the EIN 2-7 groups.
    " Type settled by the preceding 'Employer identification' label -> EIN.
    DATA(lv_text) = ml( VALUE #(
      ( `Employer identification number` )
      ( `8` ) ( `1` ) ( `-` )
      ( `0` ) ( `8` ) ( `2` ) ( `6` ) ( `7` ) ( `3` ) ( `4` ) ) ).
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates( lv_text ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `tin_boxed` ) exp = `810826734` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `tin_boxed_type` ) exp = `EIN` ).
  ENDMETHOD.


  METHOD boxed_tin_ssn.
    " 9 single-digit lines under a 'Social security' label -> SSN boxed TIN
    DATA(lv_text) = ml( VALUE #(
      ( `Social security number` )
      ( `1` ) ( `2` ) ( `3` ) ( `4` ) ( `5` ) ( `6` ) ( `7` ) ( `8` ) ( `9` ) ) ).
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates( lv_text ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `tin_boxed` ) exp = `123456789` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `tin_boxed_type` ) exp = `SSN` ).
  ENDMETHOD.


  METHOD account_label_en.
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      `Bank of Example. Account No. 1234567890 Sort code 20-00-00` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `account_number` ) exp = `1234567890` ).
  ENDMETHOD.


  METHOD account_label_es.
    " Spanish label 'Cuenta'
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      `Banco Ejemplo. Cuenta: 000123456789 Titular: ACME` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `account_number` ) exp = `000123456789` ).
  ENDMETHOD.


  METHOD account_fallback.
    " no account label, but a long standalone 11..18 digit run -> account candidate
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      `Reference value 12345678901234 printed on the advice.` ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `account_number` ) exp = `12345678901234` ).
  ENDMETHOD.


  METHOD fullwidth_ein.
    " full-width digits normalise to ASCII first (translate_fullwidth), then the
    " EIN regex matches. '１２-３４５６７８９' -> '12-3456789'.
    DATA(lv_fw) = cp( VALUE #(
      ( `65297` ) ( `65298` ) ) )   " FF11 '1', FF12 '2'
      && `-`
      && cp( VALUE #(
      ( `65299` ) ( `65300` ) ( `65301` ) ( `65302` )
      ( `65303` ) ( `65304` ) ( `65305` ) ) ).   " FF13..FF19 '3'..'9'
    DATA(lt) = zcl_mdmdoc_regex=>extract_candidates(
      |Tax ID { lv_fw } certified.| ).
    cl_abap_unit_assert=>assert_equals(
      act = cand( it = lt iv = `ein` ) exp = `12-3456789` ).
  ENDMETHOD.

ENDCLASS.
