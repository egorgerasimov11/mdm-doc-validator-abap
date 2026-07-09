" GENERATED from tools/golden/golden_cases.json by tools/golden/gen_abap_golden.py
" *** DO NOT EDIT BY HAND — edit the JSON corpus and re-run the generator ***
" GOLDEN-HASH 8a74945f3e2d6b66
" GEN-HASH 332a326a58f70960
CLASS zcl_mdmdoc_golden_data DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_exp_field,
             name  TYPE string,
             value TYPE string,
           END OF ty_exp_field,
           tt_exp_fields TYPE STANDARD TABLE OF ty_exp_field WITH DEFAULT KEY.
    TYPES: BEGIN OF ty_case,
             id           TYPE string,
             doc_class    TYPE string,
             doc_type     TYPE string,
             filename     TYPE string,
             raw_text     TYPE string,
             llm_fields   TYPE tt_exp_fields,
             exp_fields   TYPE tt_exp_fields,
             exp_notes    TYPE string_table,
             exp_verdict  TYPE string,
             exp_findings TYPE string_table,
           END OF ty_case,
           tt_cases TYPE STANDARD TABLE OF ty_case WITH DEFAULT KEY.

    CLASS-DATA gt_cases TYPE tt_cases READ-ONLY.
    CLASS-METHODS class_constructor.

    " corpus hash of the JSON this was generated from (check_parity freshness)
    CONSTANTS c_golden_hash TYPE string VALUE `8a74945f3e2d6b66`.
ENDCLASS.


CLASS zcl_mdmdoc_golden_data IMPLEMENTATION.

  METHOD class_constructor.
    APPEND VALUE #(
      id = `it-iban-checksum-valid`
      doc_class = `bank`
      doc_type = `other`
      filename = `it_bank_letter.pdf`
      raw_text = `Certificazione bancaria. Intestatario: Rossi SRL. Banca: Intesa Sanpaolo. IBAN: IT60 X054 ` &&
          `2811 1010 0000 0123 456. Firmato.`
      exp_notes = VALUE #(
        ( `iban checksum (ISO 13616 mod-97): valid` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `docusign-esignature`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `signed_letter.pdf`
      raw_text = `Bank letter for Globex GmbH. IBAN DE89 3704 0044 0532 0130 00 BIC COBADEFFXXX. DocuSign En` &&
          `velope ID: 5F2A-9911. Signed 2024-05-03 | 10:22 PDT.`
      exp_fields = VALUE #(
        ( name = `signed` value = `true` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `statement-period-as-date`
      doc_class = `bank`
      doc_type = `bank_statement`
      filename = `statement.pdf`
      raw_text = `Bank statement for account holder Meridian Ltd. IBAN GB29 NWBK 6016 1331 9268 19. Statemen` &&
          `t period 1 Jan 2025 to 31 Mar 2025.`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `Meridian Ltd` )
        ( name = `bank_name` value = `NatWest Bank` )
      )
      exp_notes = VALUE #(
        ( `document date = statement period` )
      )
      exp_verdict = `ACCEPT`
      exp_findings = VALUE #(
        ( `BNK-006` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `jp-domestic-form`
      doc_class = `bank`
      doc_type = `other`
      filename = `jp_form.pdf`
      raw_text = `銀行口座認証 〒813-0044 福岡市 口座番号 1234567 三井住友銀行 普通`
      exp_fields = VALUE #(
        ( name = `bank_country` value = `JP` )
      )
      exp_notes = VALUE #(
        ( `bank country inferred: JP` )
        ( `口座番号` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `invoice-classified`
      doc_class = `bank`
      doc_type = `invoice`
      filename = `invoice.pdf`
      raw_text = `INVOICE Invoice Number INV-2044 Invoice date 2025-01-10 Total due 1200.00 EUR remit to IBA` &&
          `N DE89370400440532013000`
      exp_verdict = `REJECT`
      exp_findings = VALUE #(
        ( `BNK-001` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `w9-form-classified`
      doc_class = `w9`
      doc_type = `w9`
      filename = `w9_form.pdf`
      raw_text = `Form W-9 Request for Taxpayer Identification Number and Certification. 1 Name China Med De` &&
          `vice LLC. 3 LLC. Employer identification number 45-3859289`
      exp_notes = VALUE #(
        ( `tin=filled-from-OCR(XX-XXX9289)` )
      )
      exp_verdict = `NEED_MANUAL_REVIEW`
      exp_findings = VALUE #(
        ( `W9-001` )
        ( `W9-003` )
        ( `W9-020` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `unsigned-bank-letter`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `unsigned_letter.pdf`
      raw_text = `Bank confirmation letter. We confirm that Vela s.r.o. holds account IBAN CZ65 0800 0000 19` &&
          `20 0014 5399 with our bank.`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `Vela s.r.o.` )
        ( name = `bank_name` value = `Ceska sporitelna` )
        ( name = `signed` value = `false` )
      )
      exp_verdict = `WARNING`
      exp_findings = VALUE #(
        ( `BNK-021` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `iban-invalid-checksum`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `letter_bad_iban.pdf`
      raw_text = `Bank confirmation letter. Account holder Norwind ApS. Bank: Danske Bank. Kindly note the a` &&
          `ccount details below. Signed by officer.`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `Norwind ApS` )
        ( name = `bank_name` value = `Danske Bank` )
        ( name = `iban` value = `DE44500105175407324930` )
        ( name = `signed` value = `true` )
      )
      exp_notes = VALUE #(
        ( `iban checksum (ISO 13616 mod-97): INVALID` )
      )
      exp_verdict = `NEED_MANUAL_REVIEW`
      exp_findings = VALUE #(
        ( `BNK-011` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `iban-model-vs-ocr-mismatch`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `letter_mismatch.pdf`
      raw_text = `Bank confirmation letter for Helios OU. IBAN: DE44 5001 0517 5407 3249 31. Signed.`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `Helios OU` )
        ( name = `bank_name` value = `Deutsche Bank` )
        ( name = `iban` value = `DE89370400440532013000` )
        ( name = `signed` value = `true` )
      )
      exp_fields = VALUE #(
        ( name = `iban` value = `DE**…3000` )
      )
      exp_notes = VALUE #(
        ( `iban=MISMATCH(model=DE**…3000 vs ocr=DE**…4931)` )
      )
      exp_verdict = `ACCEPT`
    ) TO gt_cases.
    APPEND VALUE #(
      id = `missing-holder-nmr`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `no_holder.pdf`
      raw_text = `Bank confirmation letter. IBAN FR14 2004 1010 0505 0001 3M02 606. BIC PSSTFRPP. Signed by officer.`
      llm_fields = VALUE #(
        ( name = `bank_name` value = `La Banque Postale` )
        ( name = `signed` value = `true` )
      )
      exp_verdict = `NEED_MANUAL_REVIEW`
      exp_findings = VALUE #(
        ( `BNK-023` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `date-older-2y`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `old_letter.pdf`
      raw_text = `Bank confirmation letter dated 15 Jan 2019. Account of Kestrel BV, IBAN NL91 ABNA 0417 164` &&
          `3 00. Signed by officer.`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `Kestrel BV` )
        ( name = `bank_name` value = `ABN AMRO` )
        ( name = `doc_date` value = `15 Jan 2019` )
        ( name = `signed` value = `true` )
      )
      exp_verdict = `ACCEPT`
      exp_findings = VALUE #(
        ( `BNK-020` )
      )
    ) TO gt_cases.
  ENDMETHOD.

ENDCLASS.
