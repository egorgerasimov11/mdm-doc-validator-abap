CLASS ltcl_sniff DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    CONSTANTS c_bank TYPE string VALUE 'bank'.
    CONSTANTS c_w9   TYPE string VALUE 'w9'.
    CONSTANTS lf     TYPE c LENGTH 1 VALUE cl_abap_char_utilities=>newline.

    " sniff_doc_class
    METHODS sniff_filename_w9        FOR TESTING.
    METHODS sniff_filename_w8ben     FOR TESTING.
    METHODS sniff_filename_variants  FOR TESTING.
    METHODS sniff_text_w9            FOR TESTING.
    METHODS sniff_bank_default       FOR TESTING.
    METHODS sniff_bank_keyword_text  FOR TESTING.

    " type_hint — w9 branch
    METHODS hint_w9_form_text        FOR TESTING.
    METHODS hint_w8_text             FOR TESTING.
    METHODS hint_w9_unknown          FOR TESTING.

    " type_hint — bank branch
    METHODS hint_editable            FOR TESTING.
    METHODS hint_email_ext           FOR TESTING.
    METHODS hint_printed_email       FOR TESTING.
    METHODS hint_invoice_header      FOR TESTING.
    METHODS hint_invoice_filename    FOR TESTING.
    METHODS hint_remit_not_invoice   FOR TESTING.
    METHODS hint_bank_letter_beats   FOR TESTING.
    METHODS hint_bank_statement      FOR TESTING.
    METHODS hint_bank_letter         FOR TESTING.
    METHODS hint_payment_instr       FOR TESTING.
    METHODS hint_ap_document         FOR TESTING.
    METHODS hint_voided_check        FOR TESTING.
    METHODS hint_other               FOR TESTING.
ENDCLASS.


CLASS ltcl_sniff IMPLEMENTATION.

  METHOD sniff_filename_w9.
    " filename regex wins even with empty text
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>sniff_doc_class(
              iv_text     = ``
              iv_filename = `Acme_W-9_2024.pdf` )
      exp = c_w9
      msg = `W-9 in filename -> w9` ).
  ENDMETHOD.

  METHOD sniff_filename_w8ben.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>sniff_doc_class(
              iv_text     = ``
              iv_filename = `vendor W8BEN form.pdf` )
      exp = c_w9
      msg = `W8BEN in filename -> w9` ).
  ENDMETHOD.

  METHOD sniff_filename_variants.
    " underscore / space / plain '9'
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>sniff_doc_class( iv_text = `` iv_filename = `w_9.pdf` )
      exp = c_w9 ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>sniff_doc_class( iv_text = `` iv_filename = `Form W 9.pdf` )
      exp = c_w9 ).
    " a filename that merely contains 'w' + digits without boundary -> not w9
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>sniff_doc_class( iv_text = `` iv_filename = `bw9x.pdf` )
      exp = c_bank
      msg = `no word boundary around w9 -> bank` ).
  ENDMETHOD.

  METHOD sniff_text_w9.
    " no filename hint, but text carries a W-9 sniff marker
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>sniff_doc_class(
              iv_text     = `Form W-9 Request for Taxpayer Identification Number and Certification`
              iv_filename = `scan001.pdf` )
      exp = c_w9
      msg = `W-9 marker in text -> w9` ).
  ENDMETHOD.

  METHOD sniff_bank_default.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>sniff_doc_class(
              iv_text     = `Hello world, nothing relevant here.`
              iv_filename = `document.pdf` )
      exp = c_bank
      msg = `nothing matches -> bank default` ).
  ENDMETHOD.

  METHOD sniff_bank_keyword_text.
    " bank IBAN/SWIFT text with a neutral filename stays bank
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>sniff_doc_class(
              iv_text     = `Beneficiary bank details: IBAN DE89..., SWIFT/BIC COBADEFF`
              iv_filename = `bank_confirmation.pdf` )
      exp = c_bank
      msg = `bank keywords -> bank` ).
  ENDMETHOD.

  METHOD hint_w9_form_text.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `Form W-9 (Rev. October 2018) Request for Taxpayer Identification`
              iv_filename  = `scan.pdf`
              iv_doc_class = c_w9 )
      exp = `w9`
      msg = `W-9 form text -> w9` ).
  ENDMETHOD.

  METHOD hint_w8_text.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `Form W-8BEN Certificate of Foreign Status of Beneficial Owner`
              iv_filename  = `scan.pdf`
              iv_doc_class = c_w9 )
      exp = `w8`
      msg = `W-8 text -> w8 hint` ).
  ENDMETHOD.

  METHOD hint_w9_unknown.
    " w9 doc_class but no W-9/W-8 markers -> '' (unknown)
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `Some unrelated tax paperwork`
              iv_filename  = `scan.pdf`
              iv_doc_class = c_w9 )
      exp = ``
      msg = `no tax-form markers -> empty hint` ).
  ENDMETHOD.

  METHOD hint_editable.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `whatever`
              iv_filename  = `vendor.xlsx`
              iv_doc_class = c_bank )
      exp = `editable_source`
      msg = `editable ext -> editable_source` ).
  ENDMETHOD.

  METHOD hint_email_ext.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `anything`
              iv_filename  = `message.eml`
              iv_doc_class = c_bank )
      exp = `email`
      msg = `email ext -> email` ).
  ENDMETHOD.

  METHOD hint_printed_email.
    " Outlook-style printed email headers -> email (>= 3 of from/sent/to/subject)
    DATA(lv_text) = `From: alice@corp.com` && lf
                 && `Sent: Monday, June 30, 2025 9:14 AM` && lf
                 && `To: bob@vendor.com` && lf
                 && `Subject: Bank details` && lf
                 && `Please find our IBAN below.`.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = lv_text
              iv_filename  = `thread.pdf`
              iv_doc_class = c_bank )
      exp = `email`
      msg = `printed email headers -> email` ).
  ENDMETHOD.

  METHOD hint_invoice_header.
    " a bare 'INVOICE' header line (own document) -> invoice
    DATA(lv_text) = `ACME LTD` && lf && `INVOICE` && lf
                 && `Invoice Number: 55231` && lf && `Amount Due: 1,200.00`.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = lv_text
              iv_filename  = `doc.pdf`
              iv_doc_class = c_bank )
      exp = `invoice`
      msg = `invoice header line -> invoice` ).
  ENDMETHOD.

  METHOD hint_invoice_filename.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `some banking-ish body without invoice marks`
              iv_filename  = `Invoice_998.pdf`
              iv_doc_class = c_bank )
      exp = `invoice`
      msg = `invoice in filename -> invoice` ).
  ENDMETHOD.

  METHOD hint_remit_not_invoice.
    " invoice marks ONLY appear on remittance-instruction lines -> excluded,
    " so no structural invoice evidence remains -> not classified as invoice.
    DATA(lv_text) = `Payment instructions for ACH payments only.` && lf
                 && `When making payment please include the invoice number and invoice date.` && lf
                 && `Remittance advice must be accompanied by the invoice number.`.
    " these invoice-mark lines are all in remit context, and there is no header,
    " so the type is NOT invoice; it becomes payment_instructions.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = lv_text
              iv_filename  = `remit.pdf`
              iv_doc_class = c_bank )
      exp = `payment_instructions`
      msg = `invoice marks only in remit context -> not invoice` ).
  ENDMETHOD.

  METHOD hint_bank_letter_beats.
    " document has invoice marks AND a bank-letter phrase: bank letter wins,
    " so structural invoice hint must NOT fire (page_marker_bank_letter true).
    DATA(lv_text) = `This letter is to confirm the account details below.` && lf
                 && `Invoice Number: 12` && lf && `Invoice Date: 2025-01-01` && lf
                 && `Account confirmation for our records.`.
    " not 'invoice' (bank_letter guard); has 'bank confirmation'? no. Falls to
    " bank_letter via 'account confirmation' keyword.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = lv_text
              iv_filename  = `letter.pdf`
              iv_doc_class = c_bank )
      exp = `bank_letter`
      msg = `bank-letter evidence blocks the invoice hint` ).
  ENDMETHOD.

  METHOD hint_bank_statement.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `Account Statement for the statement period 01-31 Jan 2025`
              iv_filename  = `stmt.pdf`
              iv_doc_class = c_bank )
      exp = `bank_statement`
      msg = `account statement -> bank_statement` ).
  ENDMETHOD.

  METHOD hint_bank_letter.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `We provide this bank confirmation of the beneficiary account.`
              iv_filename  = `conf.pdf`
              iv_doc_class = c_bank )
      exp = `bank_letter`
      msg = `bank confirmation -> bank_letter` ).
  ENDMETHOD.

  METHOD hint_payment_instr.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `Please use these banking details. For ACH payments use the routing below.`
              iv_filename  = `pay.pdf`
              iv_doc_class = c_bank )
      exp = `payment_instructions`
      msg = `ACH payment instructions -> payment_instructions` ).
  ENDMETHOD.

  METHOD hint_ap_document.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `Bank Account Information sheet, signed via DocuSign for our vendor.`
              iv_filename  = `apform.pdf`
              iv_doc_class = c_bank )
      exp = `ap_document`
      msg = `bank account info + docusign -> ap_document` ).
  ENDMETHOD.

  METHOD hint_voided_check.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `Attached is a voided check for account setup.`
              iv_filename  = `check.pdf`
              iv_doc_class = c_bank )
      exp = `voided_check`
      msg = `voided check -> voided_check` ).
  ENDMETHOD.

  METHOD hint_other.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_sniff=>type_hint(
              iv_text      = `A plain letter with no strong signals.`
              iv_filename  = `misc.pdf`
              iv_doc_class = c_bank )
      exp = ``
      msg = `no strong bank signal -> empty hint` ).
  ENDMETHOD.

ENDCLASS.
