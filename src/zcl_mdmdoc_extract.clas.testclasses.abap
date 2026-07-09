CLASS ltcl_extract DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    " a valid mod-97 IBAN used across tests (DE89 3704 0044 0532 0130 00)
    CONSTANTS c_iban TYPE string VALUE `DE89370400440532013000`.

    METHODS fld
      IMPORTING iv_name         TYPE string
                iv_value        TYPE string
      RETURNING VALUE(rs_field) TYPE zif_mdmdoc_types=>ty_field.

    METHODS field_of
      IMPORTING is_ext          TYPE zif_mdmdoc_types=>ty_extraction
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS has_note
      IMPORTING is_ext         TYPE zif_mdmdoc_types=>ty_extraction
                iv_sub         TYPE string
      RETURNING VALUE(rv_yes)  TYPE abap_bool.

    METHODS any_note_contains
      IMPORTING is_ext        TYPE zif_mdmdoc_types=>ty_extraction
                iv_sub        TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    " bank overlay
    METHODS iban_fill            FOR TESTING.
    METHODS iban_confirm         FOR TESTING.
    METHODS account_confirm      FOR TESTING.
    METHODS account_zero_pad     FOR TESTING.
    METHODS iban_mismatch_wins   FOR TESTING.
    METHODS notes_are_masked     FOR TESTING.

    " w9 overlay
    METHODS ein_settles_tin      FOR TESTING.
    METHODS tin_mismatch_hard_note FOR TESTING.
    METHODS boxed_tin_fill       FOR TESTING.

    " normalization
    METHODS country_to_iso2      FOR TESTING.
    METHODS flags_normalized     FOR TESTING.

    " secrets + passthrough
    METHODS secrets_registered   FOR TESTING.
    METHODS doctype_override     FOR TESTING.

    " audit guards (Python stage_b ports — PARITY.md GUARDS)
    METHODS guard_numeric_iban_moved  FOR TESTING.
    METHODS guard_iban_repair         FOR TESTING.
    METHODS guard_abi_cab_note        FOR TESTING.
    METHODS guard_docusign_signed     FOR TESTING.
    METHODS guard_stmt_period         FOR TESTING.
    METHODS guard_regulator_noise     FOR TESTING.
    METHODS guard_jp_postal_rescue    FOR TESTING.
ENDCLASS.


CLASS ltcl_extract IMPLEMENTATION.

  METHOD fld.
    rs_field-name  = iv_name.
    rs_field-value = iv_value.
  ENDMETHOD.

  METHOD field_of.
    READ TABLE is_ext-fields ASSIGNING FIELD-SYMBOL(<f>) WITH KEY name = iv_name.
    IF sy-subrc = 0.
      rv_value = <f>-value.
    ENDIF.
  ENDMETHOD.

  METHOD has_note.
    " exact note membership
    LOOP AT is_ext-crosscheck INTO DATA(lv_n).
      IF lv_n = iv_sub.
        rv_yes = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD any_note_contains.
    LOOP AT is_ext-crosscheck INTO DATA(lv_n).
      IF lv_n CS iv_sub.
        rv_yes = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD iban_fill.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    INSERT fld( iv_name = `iban` iv_value = `` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `iban` iv_value = c_iban ) INTO TABLE lt_cand.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `iban` ) exp = c_iban
      msg = `blank iban filled from regex` ).
    cl_abap_unit_assert=>assert_true(
      act = any_note_contains( is_ext = ls iv_sub = `iban=filled-from-OCR(` )
      msg = `fill note present` ).
  ENDMETHOD.

  METHOD iban_confirm.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " model reads the same IBAN, spaced/lower-case -> norm_id equal
    INSERT fld( iv_name = `iban` iv_value = `de89 3704 0044 0532 0130 00` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `iban` iv_value = c_iban ) INTO TABLE lt_cand.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    cl_abap_unit_assert=>assert_true(
      act = has_note( is_ext = ls iv_sub = `iban=confirmed` )
      msg = `iban confirmed note` ).
  ENDMETHOD.

  METHOD account_confirm.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    INSERT fld( iv_name = `account_number` iv_value = `12345678` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `account_number` iv_value = `12345678` ) INTO TABLE lt_cand.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    cl_abap_unit_assert=>assert_true(
      act = has_note( is_ext = ls iv_sub = `account_number=confirmed` )
      msg = `account confirmed note` ).
  ENDMETHOD.

  METHOD account_zero_pad.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " printed '12345678' vs zero-padded regex read '0000012345678'
    INSERT fld( iv_name = `account_number` iv_value = `12345678` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `account_number` iv_value = `0000012345678` ) INTO TABLE lt_cand.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    cl_abap_unit_assert=>assert_true(
      act = has_note( is_ext = ls iv_sub = `account_number=confirmed (zero-padded variant)` )
      msg = `zero-padded variant confirmed` ).
  ENDMETHOD.

  METHOD iban_mismatch_wins.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " model read a DIFFERENT (garbled) IBAN; regex candidate disagrees.
    " Python semantics (golden-aligned): the model value is KEPT, the
    " disagreement is a MISMATCH note + warning — uncertainty is metadata.
    INSERT fld( iv_name = `iban` iv_value = `DE00000000000000000000` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `iban` iv_value = c_iban ) INTO TABLE lt_cand.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    " model value KEPT (mirror of fields.crosscheck_ids)
    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `iban` ) exp = `DE00000000000000000000`
      msg = `model value kept on mismatch (Python semantics)` ).
    cl_abap_unit_assert=>assert_true(
      act = any_note_contains( is_ext = ls iv_sub = `iban=MISMATCH(model=` )
      msg = `mismatch note present` ).
    cl_abap_unit_assert=>assert_true(
      act = any_note_contains( is_ext = ls iv_sub = ` vs ocr=` )
      msg = `mismatch note names the ocr side` ).
    " a warning line was emitted
    cl_abap_unit_assert=>assert_true(
      act = boolc( lines( ls-warnings ) > 0 )
      msg = `mismatch warning emitted` ).
  ENDMETHOD.

  METHOD notes_are_masked.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    INSERT fld( iv_name = `iban` iv_value = `` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `iban` iv_value = c_iban ) INTO TABLE lt_cand.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    " no note may carry the full IBAN
    LOOP AT ls-crosscheck INTO DATA(lv_n).
      cl_abap_unit_assert=>assert_false(
        act = boolc( lv_n CS c_iban )
        msg = `full IBAN must never appear in a note` ).
    ENDLOOP.
  ENDMETHOD.

  METHOD ein_settles_tin.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " model read the digits but guessed SSN; EIN detector settles it
    INSERT fld( iv_name = `tin_raw`  iv_value = `12-3456789` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `tin_type` iv_value = `SSN` )        INTO TABLE lt_llm.
    INSERT fld( iv_name = `ein` iv_value = `12-3456789` )      INTO TABLE lt_cand.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `w9` iv_doc_type = `w9`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `tin_type` ) exp = `EIN`
      msg = `EIN detector settles tin_type` ).
    cl_abap_unit_assert=>assert_true(
      act = has_note( is_ext = ls iv_sub = `tin_type=EIN (settled by the EIN detector)` )
      msg = `settle note present` ).
  ENDMETHOD.

  METHOD tin_mismatch_hard_note.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " model TIN disagrees with the anchored EIN detector (audit-wave C5):
    " a hard-masked MISMATCH note; tin_type must NOT be settled.
    INSERT fld( iv_name = `tin_raw`  iv_value = `12-3456789` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `tin_type` iv_value = `SSN` )        INTO TABLE lt_llm.
    INSERT fld( iv_name = `ein` iv_value = `98-7654321` )      INTO TABLE lt_cand.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `w9` iv_doc_type = `w9`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT ls-crosscheck INTO DATA(lv_note).
      IF lv_note CP `tin_raw=MISMATCH*`.
        lv_found = abap_true.
      ENDIF.
      " hard-masked: neither full TIN appears in any crosscheck note
      cl_abap_unit_assert=>assert_false(
        act = boolc( lv_note CS `123456789` OR lv_note CS `987654321` )
        msg = `TIN digits must be masked in notes` ).
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = `contested TIN must leave a MISMATCH note` ).
    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `tin_type` ) exp = `SSN`
      msg = `a contested read settles nothing` ).
  ENDMETHOD.

  METHOD boxed_tin_fill.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " model missed the TIN entirely; boxed digits fill it, box label = EIN
    INSERT fld( iv_name = `tin_raw` iv_value = `` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `tin_boxed`      iv_value = `123456789` ) INTO TABLE lt_cand.
    INSERT fld( iv_name = `tin_boxed_type` iv_value = `EIN` )       INTO TABLE lt_cand.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `w9` iv_doc_type = `w9`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `tin_raw` ) exp = `123456789`
      msg = `tin filled from boxed digits` ).
    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `tin_type` ) exp = `EIN`
      msg = `boxed label settles tin_type` ).
    cl_abap_unit_assert=>assert_true(
      act = any_note_contains( is_ext = ls iv_sub = `tin=filled-from-boxed-digits(` )
      msg = `boxed-fill note present` ).
  ENDMETHOD.

  METHOD country_to_iso2.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    INSERT fld( iv_name = `bank_country` iv_value = ` Germany ` ) INTO TABLE lt_llm.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `bank_country` ) exp = `DE`
      msg = `bank_country -> ISO2 (trimmed)` ).
  ENDMETHOD.

  METHOD flags_normalized.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    INSERT fld( iv_name = `signed`          iv_value = `Yes` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `partial_capture` iv_value = `no` )  INTO TABLE lt_llm.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `signed` ) exp = `true`
      msg = `signed 'Yes' -> 'true'` ).
    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `partial_capture` ) exp = `false`
      msg = `partial_capture 'no' -> 'false'` ).
  ENDMETHOD.

  METHOD secrets_registered.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    INSERT fld( iv_name = `iban` iv_value = c_iban ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `account_number` iv_value = `12345678` ) INTO TABLE lt_llm.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    " full sensitive values registered
    READ TABLE ls-secrets TRANSPORTING NO FIELDS WITH KEY table_line = c_iban.
    cl_abap_unit_assert=>assert_subrc( act = sy-subrc msg = `iban secret registered` ).
    READ TABLE ls-secrets TRANSPORTING NO FIELDS WITH KEY table_line = `12345678`.
    cl_abap_unit_assert=>assert_subrc( act = sy-subrc msg = `account secret registered` ).
  ENDMETHOD.

  METHOD doctype_override.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " LLM proposes a doc_type + _model; explicit iv_doc_type must win
    INSERT fld( iv_name = `doc_type` iv_value = `invoice` )   INTO TABLE lt_llm.
    INSERT fld( iv_name = `_model`   iv_value = `qwen3:4b` )  INTO TABLE lt_llm.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true ).

    cl_abap_unit_assert=>assert_equals(
      act = ls-doc_type exp = `bank_letter` msg = `iv_doc_type overrides LLM doc_type` ).
    cl_abap_unit_assert=>assert_equals(
      act = ls-model_id exp = `qwen3:4b` msg = `model_id from _model entry` ).
    " meta entries must not leak into the field table
    READ TABLE ls-fields TRANSPORTING NO FIELDS WITH KEY name = `_model`.
    cl_abap_unit_assert=>assert_subrc( act = sy-subrc exp = 4 msg = `_model not a field` ).
    READ TABLE ls-fields TRANSPORTING NO FIELDS WITH KEY name = `doc_type`.
    cl_abap_unit_assert=>assert_subrc( act = sy-subrc exp = 4 msg = `doc_type not a field` ).
  ENDMETHOD.


  METHOD guard_numeric_iban_moved.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " US doc: a plain account number printed under an 'IBAN account no.' label
    INSERT fld( iv_name = `iban` iv_value = `4428793322` ) INTO TABLE lt_llm.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true
      iv_raw_text = `Account details for wires` ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `iban` ) exp = ``
      msg = `numeric iban field must be cleared` ).
    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `account_number` ) exp = `4428793322`
      msg = `numeric value relocated to account_number` ).
    cl_abap_unit_assert=>assert_true(
      act = any_note_contains( is_ext = ls iv_sub = `moved to account number` )
      msg = `relocation note present` ).
  ENDMETHOD.


  METHOD guard_iban_repair.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " model garbled the last digit; the DOCUMENT text holds the valid print
    INSERT fld( iv_name = `iban` iv_value = `DE89370400440532013001` ) INTO TABLE lt_llm.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true
      iv_raw_text = `IBAN: DE89 3704 0044 0532 0130 00, BIC: COBADEFF` ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `iban` ) exp = c_iban
      msg = `iban repaired from the raw text` ).
    cl_abap_unit_assert=>assert_true(
      act = has_note( is_ext = ls
                      iv_sub = `iban repaired from the document text (model read failed the mod-97 checksum)` )
      msg = `repair note present` ).
    cl_abap_unit_assert=>assert_true(
      act = has_note( is_ext = ls iv_sub = `iban checksum (ISO 13616 mod-97): valid` )
      msg = `checksum stated out loud` ).
  ENDMETHOD.


  METHOD guard_abi_cab_note.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " Italian letter: ABI landed in the ABA field; IT IBAN carries ABI/CAB
    INSERT fld( iv_name = `iban` iv_value = `IT60X0542811101000000123456` ) INTO TABLE lt_llm.
    INSERT fld( iv_name = `routing_aba` iv_value = `05428` ) INTO TABLE lt_llm.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true
      iv_raw_text = `` ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `routing_aba` ) exp = ``
      msg = `non-ABA code removed from the routing field` ).
    cl_abap_unit_assert=>assert_true(
      act = has_note( is_ext = ls
                      iv_sub = `domestic bank codes 05428 (ABI/CAB, not ABA): match the IBAN structure` )
      msg = `ABI/CAB structure note present` ).
    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `branch_code` ) exp = `11101`
      msg = `CAB doubles as branch_code` ).
  ENDMETHOD.


  METHOD guard_docusign_signed.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true
      iv_raw_text = `DocuSign Envelope ID: 5F2A. Signed 2024-05-03 | 10:22 PDT` ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `signed` ) exp = `true`
      msg = `e-signature envelope counts as signed` ).
    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `doc_date` ) exp = `2024-05-03`
      msg = `signing timestamp becomes doc_date` ).
    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `signature_evidence` )
      exp = `electronically signed (DocuSign/e-signature envelope present)`
      msg = `evidence text set` ).
  ENDMETHOD.


  METHOD guard_stmt_period.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_statement`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true
      iv_raw_text = `Statement period 1 Jan 2025 to 31 Mar 2025` ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `doc_date` ) exp = `1 Jan 2025 to 31 Mar 2025`
      msg = `statement period rescued as doc_date` ).
    cl_abap_unit_assert=>assert_true(
      act = has_note( is_ext = ls iv_sub = `document date = statement period` )
      msg = `period note present` ).
  ENDMETHOD.


  METHOD guard_regulator_noise.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    INSERT fld( iv_name = `bank_name`
                iv_value = `VIGILADO Superintendencia Financiera de Colombia` ) INTO TABLE lt_llm.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true
      iv_raw_text = `` ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `bank_name` ) exp = ``
      msg = `regulator watermark dropped from bank_name` ).
    cl_abap_unit_assert=>assert_true(
      act = boolc( lines( ls-warnings ) > 0 )
      msg = `watermark warning emitted` ).
  ENDMETHOD.


  METHOD guard_jp_postal_rescue.
    DATA lt_llm  TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    " model read the postal code as the account; the labeled field is right
    INSERT fld( iv_name = `account_number` iv_value = `8130044` ) INTO TABLE lt_llm.

    DATA(ls) = zcl_mdmdoc_extract=>build(
      iv_doc_class = `bank` iv_doc_type = `bank_letter`
      it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = abap_true
      iv_raw_text = `〒813-0044 福岡市東区 口座番号 1234567` ).

    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `account_number` ) exp = `1234567`
      msg = `postal code dropped, labeled account rescued` ).
    cl_abap_unit_assert=>assert_equals(
      act = field_of( is_ext = ls iv_name = `bank_country` ) exp = `JP`
      msg = `JP inferred from domestic form markers` ).
    cl_abap_unit_assert=>assert_true(
      act = boolc( lines( ls-warnings ) > 0 )
      msg = `postal-code warning emitted` ).
  ENDMETHOD.

ENDCLASS.
