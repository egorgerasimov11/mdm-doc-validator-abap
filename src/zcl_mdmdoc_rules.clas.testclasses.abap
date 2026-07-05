*"* use this source file for your ABAP unit test classes
CLASS ltcl_rules DEFINITION FOR TESTING RISK LEVEL HARMLESS DURATION SHORT FINAL.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcl_mdmdoc_rules.   " default (generated tables)

    METHODS setup.

    " -- helpers ------------------------------------------------------
    METHODS f
      IMPORTING iv_name         TYPE string
                iv_value        TYPE string
      RETURNING VALUE(rs_field) TYPE zif_mdmdoc_types=>ty_field.

    METHODS ext
      IMPORTING iv_class      TYPE string
                iv_type       TYPE string
                it_fields     TYPE zif_mdmdoc_types=>tt_fields
      RETURNING VALUE(rs_ext) TYPE zif_mdmdoc_types=>ty_extraction.

    METHODS has_rule
      IMPORTING it_findings   TYPE zif_mdmdoc_types=>tt_findings
                iv_id         TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    METHODS find_rule
      IMPORTING it_findings      TYPE zif_mdmdoc_types=>tt_findings
                iv_id            TYPE string
      RETURNING VALUE(rs_finding) TYPE zif_mdmdoc_types=>ty_finding.

    " -- when-ops -----------------------------------------------------
    METHODS when_always              FOR TESTING.
    METHODS when_field_missing       FOR TESTING.
    METHODS when_flag_true           FOR TESTING.
    METHODS when_flag_false          FOR TESTING.
    METHODS applies_to_filter        FOR TESTING.

    " -- predicates ---------------------------------------------------
    METHODS pred_field_empty         FOR TESTING.
    METHODS pred_swift_country_bad   FOR TESTING.
    METHODS pred_swift_ok            FOR TESTING.
    METHODS pred_iban_bad_length     FOR TESTING.
    METHODS pred_iban_checksum_fail  FOR TESTING.
    METHODS pred_iban_ok             FOR TESTING.
    METHODS pred_ein_shape           FOR TESTING.
    METHODS pred_tin_vs_class_llc    FOR TESTING.
    METHODS pred_individual_ein_biz  FOR TESTING.
    METHODS pred_individual_no_biz   FOR TESTING.
    METHODS pred_line_swap_empty     FOR TESTING.
    METHODS pred_date_older          FOR TESTING.
    METHODS pred_no_bank_ids         FOR TESTING.
    METHODS pred_unsigned_no_ev      FOR TESTING.
    METHODS pred_unsigned_typed      FOR TESTING.

    " -- message formatting -------------------------------------------
    METHODS msg_masked_iban          FOR TESTING.
    METHODS msg_ru_selection         FOR TESTING.

    " -- engine robustness / JSON -------------------------------------
    METHODS unknown_predicate        FOR TESTING.
    METHODS json_override_happy      FOR TESTING.
    METHODS json_broken_fallback     FOR TESTING.

    " -- rule admin: per-class swap + readable conditions -------------
    METHODS skill_swap_partial       FOR TESTING.
    METHODS describe_conditions      FOR TESTING.
    METHODS list_rules_counts        FOR TESTING.

ENDCLASS.


CLASS ltcl_rules IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW zcl_mdmdoc_rules( ).
  ENDMETHOD.


  METHOD f.
    rs_field-name  = iv_name.
    rs_field-value = iv_value.
  ENDMETHOD.


  METHOD ext.
    rs_ext-doc_class = iv_class.
    rs_ext-doc_type  = iv_type.
    rs_ext-fields    = it_fields.
  ENDMETHOD.


  METHOD has_rule.
    READ TABLE it_findings TRANSPORTING NO FIELDS WITH KEY rule_id = iv_id.
    rv_yes = boolc( sy-subrc = 0 ).
  ENDMETHOD.


  METHOD find_rule.
    READ TABLE it_findings INTO rs_finding WITH KEY rule_id = iv_id.
  ENDMETHOD.


  " ===================================================================
  "  WHEN-OPS
  " ===================================================================

  METHOD when_always.
    " BNK-001 fires on doc_type=invoice (applies_to=[invoice], when=always).
    DATA(ls_ext) = ext( iv_class = `bank` iv_type = `invoice`
                        it_fields = VALUE #( ) ).
    DATA(lt) = mo_cut->run( ls_ext ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `BNK-001` )
      msg = 'always: invoice must trigger BNK-001' ).
    " and BNK-002 (email-only) must NOT fire here
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt iv_id = `BNK-002` )
      msg = 'email rule must not fire on invoice' ).
  ENDMETHOD.


  METHOD when_field_missing.
    " W9-001 line1_missing fires when line1_name absent/empty.
    DATA(lt_miss) = mo_cut->run(
      ext( iv_class = `w9` iv_type = `w9` it_fields = VALUE #( ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt_miss iv_id = `W9-001` )
      msg = 'missing line1_name must fire W9-001' ).

    " present line1 -> W9-001 does not fire
    DATA(lt_ok) = mo_cut->run(
      ext( iv_class = `w9` iv_type = `w9`
           it_fields = VALUE #( ( f( iv_name = `line1_name` iv_value = `Jane Miller` ) )
                                ( f( iv_name = `tin_raw` iv_value = `12-3456789` ) )
                                ( f( iv_name = `line3_classification` iv_value = `corporation` ) ) ) ) ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt_ok iv_id = `W9-001` )
      msg = 'present line1_name must not fire W9-001' ).
  ENDMETHOD.


  METHOD when_flag_true.
    " BNK-022 partial_screenshot: flag_true partial_capture, doc_type bank_screenshot.
    DATA(lt_fire) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_screenshot`
           it_fields = VALUE #( ( f( iv_name = `partial_capture` iv_value = `true` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Big Bank` ) )
                                ( f( iv_name = `iban` iv_value = `DE89370400440532013000` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt_fire iv_id = `BNK-022` )
      msg = 'flag_true partial_capture must fire BNK-022' ).

    DATA(lt_no) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_screenshot`
           it_fields = VALUE #( ( f( iv_name = `partial_capture` iv_value = `false` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Big Bank` ) )
                                ( f( iv_name = `iban` iv_value = `DE89370400440532013000` ) ) ) ) ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt_no iv_id = `BNK-022` )
      msg = 'flag_true false must not fire BNK-022' ).
  ENDMETHOD.


  METHOD when_flag_false.
    " W9-020 unsigned: flag_false signed. Fires when signed not true.
    DATA(lt_unsigned) = mo_cut->run(
      ext( iv_class = `w9` iv_type = `w9`
           it_fields = VALUE #( ( f( iv_name = `line1_name` iv_value = `Jane Miller` ) )
                                ( f( iv_name = `tin_raw` iv_value = `12-3456789` ) )
                                ( f( iv_name = `line3_classification` iv_value = `corporation` ) )
                                ( f( iv_name = `signed` iv_value = `false` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt_unsigned iv_id = `W9-020` )
      msg = 'flag_false: unsigned W-9 must fire W9-020' ).

    DATA(lt_signed) = mo_cut->run(
      ext( iv_class = `w9` iv_type = `w9`
           it_fields = VALUE #( ( f( iv_name = `line1_name` iv_value = `Jane Miller` ) )
                                ( f( iv_name = `tin_raw` iv_value = `12-3456789` ) )
                                ( f( iv_name = `line3_classification` iv_value = `corporation` ) )
                                ( f( iv_name = `signed` iv_value = `true` ) ) ) ) ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt_signed iv_id = `W9-020` )
      msg = 'flag_false: signed W-9 must not fire W9-020' ).
  ENDMETHOD.


  METHOD applies_to_filter.
    " BNK-021 (bank_letter only) must not fire on an 'invoice' doc_type;
    " and a global rule (BNK-010, applies_to empty) is eligible everywhere.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `voided_check`
           it_fields = VALUE #( ( f( iv_name = `signed` iv_value = `false` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Big Bank` ) )
                                ( f( iv_name = `iban` iv_value = `DE89370400440532013000` ) ) ) ) ).
    " BNK-021 is bank_letter-scoped -> must NOT appear for voided_check
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt iv_id = `BNK-021` )
      msg = 'applies_to: bank_letter rule must skip voided_check' ).
  ENDMETHOD.


  " ===================================================================
  "  PREDICATES
  " ===================================================================

  METHOD pred_field_empty.
    " BNK-006 field_empty(swift_bic) on a bank_statement -> fires when empty.
    DATA(lt_empty) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_statement`
           it_fields = VALUE #( ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt_empty iv_id = `BNK-006` )
      msg = 'field_empty: absent swift_bic fires BNK-006' ).

    DATA(lt_present) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_statement`
           it_fields = VALUE #( ( f( iv_name = `swift_bic` iv_value = `DEUTDEFF` ) ) ) ) ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt_present iv_id = `BNK-006` )
      msg = 'field_empty: present swift_bic does not fire BNK-006' ).
  ENDMETHOD.


  METHOD pred_swift_country_bad.
    " BNK-010 swift_valid: country mismatch (GB in BIC vs Germany).
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_letter`
           it_fields = VALUE #( ( f( iv_name = `swift_bic` iv_value = `DEUTGB2LXXX` ) )
                                ( f( iv_name = `bank_country` iv_value = `Germany` ) )
                                ( f( iv_name = `signed` iv_value = `true` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Deutsche` ) )
                                ( f( iv_name = `iban` iv_value = `DE89370400440532013000` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `BNK-010` )
      msg = 'swift country mismatch must fire BNK-010' ).
    DATA(ls) = find_rule( it_findings = lt iv_id = `BNK-010` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = ls-detail exp = '*differs from bank country*'
      msg = 'BNK-010 detail should mention country mismatch' ).
  ENDMETHOD.


  METHOD pred_swift_ok.
    " Matching country -> no BNK-010.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_letter`
           it_fields = VALUE #( ( f( iv_name = `swift_bic` iv_value = `DEUTDEFFXXX` ) )
                                ( f( iv_name = `bank_country` iv_value = `Germany` ) )
                                ( f( iv_name = `signed` iv_value = `true` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Deutsche` ) )
                                ( f( iv_name = `iban` iv_value = `DE89370400440532013000` ) ) ) ) ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt iv_id = `BNK-010` )
      msg = 'valid matching SWIFT must not fire BNK-010' ).
  ENDMETHOD.


  METHOD pred_iban_bad_length.
    " BNK-011 iban_valid: DE IBAN of wrong length.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_letter`
           it_fields = VALUE #( ( f( iv_name = `iban` iv_value = `DE893704004405` ) )
                                ( f( iv_name = `signed` iv_value = `true` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Deutsche` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `BNK-011` )
      msg = 'wrong-length DE IBAN must fire BNK-011' ).
    DATA(ls) = find_rule( it_findings = lt iv_id = `BNK-011` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = ls-detail exp = '*differs from expected 22 for DE*'
      msg = 'BNK-011 detail should mention expected length 22' ).
  ENDMETHOD.


  METHOD pred_iban_checksum_fail.
    " BNK-011 iban_valid: right length/prefix but bad mod-97.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_letter`
           it_fields = VALUE #( ( f( iv_name = `iban` iv_value = `DE89310400440532013000` ) )
                                ( f( iv_name = `bank_country` iv_value = `Germany` ) )
                                ( f( iv_name = `signed` iv_value = `true` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Deutsche` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `BNK-011` )
      msg = 'checksum-fail IBAN must fire BNK-011' ).
    DATA(ls) = find_rule( it_findings = lt iv_id = `BNK-011` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = ls-detail exp = '*checksum failed*'
      msg = 'BNK-011 detail should mention checksum failure' ).
  ENDMETHOD.


  METHOD pred_iban_ok.
    " Valid DE IBAN, matching country -> no BNK-011.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_letter`
           it_fields = VALUE #( ( f( iv_name = `iban` iv_value = `DE89370400440532013000` ) )
                                ( f( iv_name = `bank_country` iv_value = `Germany` ) )
                                ( f( iv_name = `signed` iv_value = `true` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Deutsche` ) ) ) ) ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt iv_id = `BNK-011` )
      msg = 'valid IBAN must not fire BNK-011' ).
  ENDMETHOD.


  METHOD pred_ein_shape.
    " W9-010 ein_shape: 8-digit TIN fires (must be 9).
    DATA(lt_bad) = mo_cut->run(
      ext( iv_class = `w9` iv_type = `w9`
           it_fields = VALUE #( ( f( iv_name = `line1_name` iv_value = `Jane Miller` ) )
                                ( f( iv_name = `tin_raw` iv_value = `12-345678` ) )
                                ( f( iv_name = `line3_classification` iv_value = `corporation` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt_bad iv_id = `W9-010` )
      msg = '8-digit TIN must fire W9-010' ).

    DATA(lt_ok) = mo_cut->run(
      ext( iv_class = `w9` iv_type = `w9`
           it_fields = VALUE #( ( f( iv_name = `line1_name` iv_value = `Jane Miller` ) )
                                ( f( iv_name = `tin_raw` iv_value = `12-3456789` ) )
                                ( f( iv_name = `line3_classification` iv_value = `corporation` ) ) ) ) ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt_ok iv_id = `W9-010` )
      msg = '9-digit TIN must not fire W9-010' ).
  ENDMETHOD.


  METHOD pred_tin_vs_class_llc.
    " W9-011 tin_type_vs_classification: LLC + SSN fires.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `w9` iv_type = `w9`
           it_fields = VALUE #( ( f( iv_name = `line1_name` iv_value = `Widgets LLC` ) )
                                ( f( iv_name = `tin_raw` iv_value = `123-45-6789` ) )
                                ( f( iv_name = `tin_type` iv_value = `SSN` ) )
                                ( f( iv_name = `line3_classification` iv_value = `LLC` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `W9-011` )
      msg = 'LLC classification with SSN must fire W9-011' ).
    DATA(ls) = find_rule( it_findings = lt iv_id = `W9-011` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = ls-detail exp = '*llc classification with an SSN*'
      msg = 'W9-011 detail should mention llc + SSN' ).
  ENDMETHOD.


  METHOD pred_individual_ein_biz.
    " W9-012 individual_with_business_name_and_ein: Individual + LLC name + EIN.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `w9` iv_type = `w9`
           it_fields = VALUE #( ( f( iv_name = `line1_name` iv_value = `Acme Holdings LLC` ) )
                                ( f( iv_name = `tin_raw` iv_value = `12-3456789` ) )
                                ( f( iv_name = `tin_type` iv_value = `EIN` ) )
                                ( f( iv_name = `line3_classification` iv_value = `Individual/sole proprietor` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `W9-012` )
      msg = 'Individual + business name + EIN must fire W9-012' ).
  ENDMETHOD.


  METHOD pred_individual_no_biz.
    " No business name -> W9-012 must NOT fire (but tin_vs_class may fire for
    " individual+EIN+no biz name -> W9-011).
    DATA(lt) = mo_cut->run(
      ext( iv_class = `w9` iv_type = `w9`
           it_fields = VALUE #( ( f( iv_name = `line1_name` iv_value = `Jane Miller` ) )
                                ( f( iv_name = `tin_raw` iv_value = `12-3456789` ) )
                                ( f( iv_name = `tin_type` iv_value = `EIN` ) )
                                ( f( iv_name = `line3_classification` iv_value = `Individual/sole proprietor` ) ) ) ) ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt iv_id = `W9-012` )
      msg = 'Individual + EIN but plain person name must not fire W9-012' ).
    " tin_type_vs_classification: individual_sole_prop + EIN + no biz name -> fires
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `W9-011` )
      msg = 'Individual + EIN + no biz name should fire W9-011' ).
  ENDMETHOD.


  METHOD pred_line_swap_empty.
    " W9-013 line_swap_suspect: line1 empty, line2 present.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `w9` iv_type = `w9`
           it_fields = VALUE #( ( f( iv_name = `line2_business_name` iv_value = `Acme LLC` ) )
                                ( f( iv_name = `tin_raw` iv_value = `12-3456789` ) )
                                ( f( iv_name = `line3_classification` iv_value = `corporation` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `W9-013` )
      msg = 'empty line1 + present line2 must fire W9-013' ).
    DATA(ls) = find_rule( it_findings = lt iv_id = `W9-013` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = ls-detail exp = '*Line 1 empty*'
      msg = 'W9-013 detail should mention Line 1 empty' ).
  ENDMETHOD.


  METHOD pred_date_older.
    " BNK-020 date_older_than years=2: doc dated ~3 years ago fires.
    DATA lv_year TYPE i.
    lv_year = sy-datum+0(4) - 3.
    DATA(lv_date) = |{ lv_year }-06-15|.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_letter`
           it_fields = VALUE #( ( f( iv_name = `doc_date` iv_value = lv_date ) )
                                ( f( iv_name = `signed` iv_value = `true` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Big Bank` ) )
                                ( f( iv_name = `iban` iv_value = `DE89370400440532013000` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `BNK-020` )
      msg = 'document ~3 years old must fire BNK-020 (years=2)' ).
  ENDMETHOD.


  METHOD pred_no_bank_ids.
    " BNK-024 no_bank_ids: no iban/account/routing anywhere.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `other`
           it_fields = VALUE #( ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Big Bank` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `BNK-024` )
      msg = 'missing all bank ids must fire BNK-024' ).

    DATA(lt_ok) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `other`
           it_fields = VALUE #( ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Big Bank` ) )
                                ( f( iv_name = `account_number` iv_value = `12345678` ) ) ) ) ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt_ok iv_id = `BNK-024` )
      msg = 'account present must not fire BNK-024' ).
  ENDMETHOD.


  METHOD pred_unsigned_no_ev.
    " BNK-021 unsigned_no_evidence: unsigned + absence-statement evidence fires.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_letter`
           it_fields = VALUE #( ( f( iv_name = `signed` iv_value = `false` ) )
                                ( f( iv_name = `signature_evidence` iv_value = `No signature or stamp is present` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Big Bank` ) )
                                ( f( iv_name = `iban` iv_value = `DE89370400440532013000` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `BNK-021` )
      msg = 'unsigned + absence-statement must fire BNK-021' ).
    " BNK-026 (typed officer block) must NOT fire on an absence statement
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt iv_id = `BNK-026` )
      msg = 'absence statement is not compensating evidence, no BNK-026' ).
  ENDMETHOD.


  METHOD pred_unsigned_typed.
    " BNK-026 unsigned_typed_block: unsigned + officer-block evidence -> fires,
    " and BNK-021 (no evidence) must NOT fire.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_letter`
           it_fields = VALUE #( ( f( iv_name = `signed` iv_value = `false` ) )
                                ( f( iv_name = `signature_evidence` iv_value = `Typed officer block with name and title` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Big Bank` ) )
                                ( f( iv_name = `iban` iv_value = `DE89370400440532013000` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `BNK-026` )
      msg = 'compensating officer block must fire BNK-026' ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt iv_id = `BNK-021` )
      msg = 'with compensating evidence BNK-021 must not fire' ).
  ENDMETHOD.


  " ===================================================================
  "  MESSAGE FORMATTING
  " ===================================================================

  METHOD msg_masked_iban.
    " BNK-011 message 'IBAN {value_masked}: {detail}.' — placeholder must be a
    " masked IBAN (DE**...), never the full number.
    DATA(lt) = mo_cut->run(
      ext( iv_class = `bank` iv_type = `bank_letter`
           it_fields = VALUE #( ( f( iv_name = `iban` iv_value = `DE89310400440532013000` ) )
                                ( f( iv_name = `bank_country` iv_value = `Germany` ) )
                                ( f( iv_name = `signed` iv_value = `true` ) )
                                ( f( iv_name = `account_holder` iv_value = `Acme` ) )
                                ( f( iv_name = `bank_name` iv_value = `Deutsche` ) ) ) ) ).
    DATA(ls) = find_rule( it_findings = lt iv_id = `BNK-011` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = ls-message exp = 'IBAN DE*'
      msg = 'BNK-011 message must start with masked IBAN prefix' ).
    " full number must be gone
    cl_abap_unit_assert=>assert_equals(
      act = boolc( ls-message CS `DE89310400440532013000` )
      exp = abap_false
      msg = 'full IBAN must not appear in the message' ).
  ENDMETHOD.


  METHOD msg_ru_selection.
    " BNK-001 has message_ru; lang='RU' must select it.
    DATA(ls_ext) = ext( iv_class = `bank` iv_type = `invoice` it_fields = VALUE #( ) ).
    DATA(lt_ru) = mo_cut->run( is_ext = ls_ext iv_lang = `RU` ).
    DATA(ls_ru) = find_rule( it_findings = lt_ru iv_id = `BNK-001` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = ls_ru-message exp = '*Инвойс*'
      msg = 'RU: BNK-001 must use the Russian message' ).

    DATA(lt_en) = mo_cut->run( is_ext = ls_ext iv_lang = `EN` ).
    DATA(ls_en) = find_rule( it_findings = lt_en iv_id = `BNK-001` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = ls_en-message exp = '*Invoice used*'
      msg = 'EN: BNK-001 must use the English message' ).
  ENDMETHOD.


  " ===================================================================
  "  ENGINE ROBUSTNESS / JSON
  " ===================================================================

  METHOD unknown_predicate.
    " A rules JSON that references an unknown check -> ENGINE WARNING finding.
    DATA(lv_json) =
      `{"schema":"zmdmdoc.rules.v1",` &&
      `"rules_bank":[{"id":"X-999","name":"bad","applies_to":[],` &&
      `"severity":"CRITICAL","verdict_effect":"REJECT","message":"m","message_ru":"",` &&
      `"when_op":"check","when_field":"iban","when_value":"","when_values":[],` &&
      `"check_name":"does_not_exist","check_args":[]}],` &&
      `"rules_w9":[],"iban_length":[]}`.
    DATA(lo) = NEW zcl_mdmdoc_rules( lv_json ).
    DATA(lt) = lo->run(
      ext( iv_class = `bank` iv_type = `bank_letter`
           it_fields = VALUE #( ( f( iv_name = `iban` iv_value = `DE89370400440532013000` ) ) ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `ENGINE` )
      msg = 'unknown predicate must yield an ENGINE finding' ).
    DATA(ls) = find_rule( it_findings = lt iv_id = `ENGINE` ).
    cl_abap_unit_assert=>assert_equals(
      act = ls-severity exp = zif_mdmdoc_types=>c_severity-warning
      msg = 'unknown-predicate ENGINE finding must be WARNING' ).
  ENDMETHOD.


  METHOD json_override_happy.
    " A minimal valid JSON with one simple always-rule -> that rule fires,
    " and the generated BNK-001 is NOT present (override replaced the set).
    DATA(lv_json) =
      `{"schema":"zmdmdoc.rules.v1",` &&
      `"rules_bank":[{"id":"J-001","name":"custom","applies_to":[],` &&
      `"severity":"WARNING","verdict_effect":"WARNING","message":"custom fired","message_ru":"",` &&
      `"when_op":"always","when_field":"","when_value":"","when_values":[],` &&
      `"check_name":"","check_args":[]}],` &&
      `"rules_w9":[],"iban_length":[]}`.
    DATA(lo) = NEW zcl_mdmdoc_rules( lv_json ).
    DATA(lt) = lo->run(
      ext( iv_class = `bank` iv_type = `invoice` it_fields = VALUE #( ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `J-001` )
      msg = 'JSON override rule J-001 must fire' ).
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt iv_id = `BNK-001` )
      msg = 'generated rules must be replaced by the JSON override' ).
    " no engine-error finding on a clean parse
    cl_abap_unit_assert=>assert_false(
      act = has_rule( it_findings = lt iv_id = `ENGINE` )
      msg = 'clean JSON parse must not emit an ENGINE error' ).
  ENDMETHOD.


  METHOD json_broken_fallback.
    " Broken JSON -> fall back to generated tables + remember an ENGINE error
    " emitted on every run.
    DATA(lo) = NEW zcl_mdmdoc_rules( `{not valid json at all` ).
    DATA(lt) = lo->run(
      ext( iv_class = `bank` iv_type = `invoice` it_fields = VALUE #( ) ) ).
    " generated BNK-001 still present (fallback worked)
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `BNK-001` )
      msg = 'broken JSON must fall back to generated rules' ).
    " and an ENGINE (NOTE) finding is emitted
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt iv_id = `ENGINE` )
      msg = 'broken JSON must remember an ENGINE error finding' ).
    DATA(ls) = find_rule( it_findings = lt iv_id = `ENGINE` ).
    cl_abap_unit_assert=>assert_equals(
      act = ls-severity exp = zif_mdmdoc_types=>c_severity-note
      msg = 'JSON-fallback ENGINE finding must be NOTE severity' ).
  ENDMETHOD.

  METHOD skill_swap_partial.
    " Override carries ONLY rules_w9 -> the W-9 "skill" is swapped, but the
    " banking skill keeps its generated defaults (partial per-class override).
    DATA(lv_json) =
      `{"schema":"zmdmdoc.rules.v1",` &&
      `"rules_bank":[],"iban_length":[],` &&
      `"rules_w9":[{"id":"ZZ-009","name":"custom_w9","applies_to":["w9"],` &&
      `"severity":"WARNING","verdict_effect":"WARNING","message":"custom w9 skill",` &&
      `"message_ru":"","when_op":"always","when_field":"","when_value":"",` &&
      `"when_values":[],"check_name":"","check_args":[]}]}`.
    DATA(lo) = NEW zcl_mdmdoc_rules( lv_json ).
    " W-9 side: the swapped custom rule fires, the default W9-001 does not
    DATA(lt_w9) = lo->run( ext( iv_class = `w9` iv_type = `w9` it_fields = VALUE #( ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt_w9 iv_id = `ZZ-009` )
      msg = 'swapped W-9 skill must fire' ).
    " banking side: generated BNK-001 STILL fires (banking not touched)
    DATA(lt_bk) = lo->run( ext( iv_class = `bank` iv_type = `invoice` it_fields = VALUE #( ) ) ).
    cl_abap_unit_assert=>assert_true(
      act = has_rule( it_findings = lt_bk iv_id = `BNK-001` )
      msg = 'banking defaults must be preserved when only rules_w9 is overridden' ).
  ENDMETHOD.

  METHOD describe_conditions.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_rules=>describe_when( VALUE #( when_op = `always` ) ) exp = 'always' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_rules=>describe_when( VALUE #( when_op = `field_missing` when_field = `iban` ) )
      exp = 'iban is empty' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_rules=>describe_when( VALUE #( when_op = `flag_false` when_field = `signed` ) )
      exp = 'signed = false' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_rules=>describe_when( VALUE #( when_op = `equals` when_field = `doc_type` when_value = `invoice` ) )
      exp = 'doc_type = "invoice"' ).
    DATA(lv_in) = zcl_mdmdoc_rules=>describe_when(
      VALUE #( when_op = `in` when_field = `status` when_values = VALUE #( ( `a` ) ( `b` ) ) ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_in CS 'status in' AND lv_in CS 'a' AND lv_in CS 'b' ) ).
    DATA(lv_chk) = zcl_mdmdoc_rules=>describe_when(
      VALUE #( when_op = `check` check_name = `iban_valid` when_field = `iban` ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_chk CS 'check iban_valid' AND lv_chk CS 'iban' ) ).
  ENDMETHOD.

  METHOD list_rules_counts.
    cl_abap_unit_assert=>assert_equals(
      act = lines( zcl_mdmdoc_rules=>list_rules( `bank` ) ) exp = 15 ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( zcl_mdmdoc_rules=>list_rules( `w9` ) ) exp = 10 ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( zcl_mdmdoc_rules=>list_rules( ) ) exp = 25 ).
  ENDMETHOD.

ENDCLASS.
