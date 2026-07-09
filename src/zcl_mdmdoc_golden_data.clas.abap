" GENERATED from tools/golden/golden_cases.json by tools/golden/gen_abap_golden.py
" *** DO NOT EDIT BY HAND — edit the JSON corpus and re-run the generator ***
" GOLDEN-HASH 6e65a042b271a9ab
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
             id         TYPE string,
             doc_class  TYPE string,
             doc_type   TYPE string,
             filename   TYPE string,
             raw_text   TYPE string,
             exp_fields TYPE tt_exp_fields,
             exp_notes  TYPE string_table,
           END OF ty_case,
           tt_cases TYPE STANDARD TABLE OF ty_case WITH DEFAULT KEY.

    CLASS-DATA gt_cases TYPE tt_cases READ-ONLY.
    CLASS-METHODS class_constructor.

    " corpus hash of the JSON this was generated from (check_parity freshness)
    CONSTANTS c_golden_hash TYPE string VALUE `6e65a042b271a9ab`.
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
      exp_notes = VALUE #(
        ( `document date = statement period` )
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
    ) TO gt_cases.
    APPEND VALUE #(
      id = `w9-form-classified`
      doc_class = `w9`
      doc_type = `w9`
      filename = `w9_form.pdf`
      raw_text = `Form W-9 Request for Taxpayer Identification Number and Certification. 1 Name China Med De` &&
          `vice LLC. 3 LLC. Employer identification number 45-3859289`
    ) TO gt_cases.
  ENDMETHOD.

ENDCLASS.
