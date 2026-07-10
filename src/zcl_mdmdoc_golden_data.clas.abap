" GENERATED from tools/golden/golden_cases.json by tools/golden/gen_abap_golden.py
" *** DO NOT EDIT BY HAND — edit the JSON corpus and re-run the generator ***
" GOLDEN-HASH 0f1dbbd08066e066
" GEN-HASH caa4175f8b059eb4
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
    CONSTANTS c_golden_hash TYPE string VALUE `0f1dbbd08066e066`.
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
      exp_verdict = `REJECT`
      exp_findings = VALUE #(
        ( `BNK-006` )
        ( `BNK-047` )
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
        ( name = `swift_bic` value = `DEUTDEFF` )
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
      id = `bank-no-swift-warning`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `no_swift.pdf`
      raw_text = `Bank confirmation letter. Account of Falcon OU held at Deutsche Bank, IBAN DE89 3704 0044 ` &&
          `0532 0130 00. Signed by officer.`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `Falcon OU` )
        ( name = `bank_name` value = `Deutsche Bank` )
        ( name = `iban` value = `DE89370400440532013000` )
        ( name = `signed` value = `true` )
      )
      exp_verdict = `WARNING`
      exp_findings = VALUE #(
        ( `BNK-048` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `missing-holder-nmr`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `no_holder.pdf`
      raw_text = `Bank confirmation letter. IBAN FR14 2004 1010 0505 0001 3M02 606. BIC PSSTFRPP. Signed by ` &&
          `officer.`
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
        ( name = `swift_bic` value = `ABNANL2A` )
        ( name = `signed` value = `true` )
      )
      exp_verdict = `ACCEPT`
      exp_findings = VALUE #(
        ( `BNK-020` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `zh-mobile-not-account`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `cn_notice.pdf`
      raw_text = `会议通知 开户银行: 中国工商银行北京分行 收款账号: 6222 0202 0000 1234 567 户名: 某某协会 联系人: 王伟 电话: 13712346060`
      llm_fields = VALUE #(
        ( name = `account_number` value = `13712346060` )
        ( name = `account_holder` value = `某某协会` )
        ( name = `bank_name` value = `中国工商银行` )
        ( name = `signed` value = `true` )
      )
      exp_notes = VALUE #(
        ( `account number taken from the labeled 账号/账户 field` )
        ( `bank country inferred: CN` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `zh-labeled-account-rescue`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `cn_sheet.pdf`
      raw_text = `供应商银行信息 开户银行: 某某银行 银行账号: 1100 2233 4455 66 户名: 假冒贸易有限公司`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `假冒贸易有限公司` )
        ( name = `bank_name` value = `某某银行` )
        ( name = `signed` value = `true` )
      )
      exp_notes = VALUE #(
        ( `account_number=filled-from-OCR` )
        ( `bank country inferred: CN` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `role-signatory-not-holder`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `mercury_letter.pdf`
      raw_text = `Bank confirmation letter. This letter is to verify that Jamcorder LLC is a customer of Mer` &&
          `cury Bank.` &&
          cl_abap_char_utilities=>newline &&
          `Account number: 202412345678` &&
          cl_abap_char_utilities=>newline &&
          `Account signatory` &&
          cl_abap_char_utilities=>newline &&
          `Charles A. Fakeperson` &&
          cl_abap_char_utilities=>newline &&
          `Signed by officer.`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `Charles A. Fakeperson` )
        ( name = `bank_name` value = `Mercury Bank` )
        ( name = `signed` value = `true` )
      )
      exp_fields = VALUE #(
        ( name = `account_holder` value = `Jamcorder LLC` )
        ( name = `account_signatory` value = `Charles A. Fakeperson` )
      )
      exp_notes = VALUE #(
        ( `account holder grounded from the document's relationship sentence` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `officer-block-bnk026`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `officer_letter.pdf`
      raw_text = `Bank confirmation letter. This letter is to confirm the account details below. IBAN DE89 3` &&
          `704 0044 0532 0130 00 held by Vela GmbH.` &&
          cl_abap_char_utilities=>newline &&
          `Sincerely,` &&
          cl_abap_char_utilities=>newline &&
          `Jordan Q. Sample` &&
          cl_abap_char_utilities=>newline &&
          `Vice President` &&
          cl_abap_char_utilities=>newline &&
          `Tel: +1 212 555 0000` &&
          cl_abap_char_utilities=>newline &&
          `Fakebank AG`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `Vela GmbH` )
        ( name = `bank_name` value = `Fakebank AG` )
        ( name = `bank_country` value = `Germany` )
        ( name = `signed` value = `false` )
      )
      exp_findings = VALUE #(
        ( `BNK-026` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `w9-esignature-accepted`
      doc_class = `w9`
      doc_type = `w9`
      filename = `motion_w9.pdf`
      raw_text = `Form W-9 Request for Taxpayer Identification Number and Certification. 1 Name Motion Fake ` &&
          `Industries LLC. 3 LLC. Employer identification number 00-1234567. Will Fakename. Digitally` &&
          ` signed by Will Fakename. Date 2026.01.27.`
      llm_fields = VALUE #(
        ( name = `line1_name` value = `Motion Fake Industries LLC` )
        ( name = `line3_classification` value = `LLC` )
        ( name = `signed` value = `false` )
      )
      exp_fields = VALUE #(
        ( name = `signed` value = `true` )
        ( name = `signature_kind` value = `electronic` )
        ( name = `sign_date` value = `2026.01.27` )
      )
      exp_notes = VALUE #(
        ( `tin=filled-from-OCR` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `w8-own-schema`
      doc_class = `w9`
      doc_type = `w8`
      filename = `w8ben_e_form.pdf`
      raw_text = `Form W-8BEN-E Certificate of Status of Beneficial Owner for United States Tax Withholding ` &&
          `and Reporting (Entities). Part I Identification of Beneficial Owner. Chapter 4 Status: Act` &&
          `ive NFFE. Part XXX Certification.`
      llm_fields = VALUE #(
        ( name = `legal_name` value = `Nord Fake GmbH` )
        ( name = `country_incorporation` value = `Germany` )
        ( name = `chapter4_status` value = `Active NFFE` )
        ( name = `signed` value = `false` )
      )
      exp_fields = VALUE #(
        ( name = `legal_name` value = `Nord Fake GmbH` )
      )
      exp_verdict = `NEED_MANUAL_REVIEW`
      exp_findings = VALUE #(
        ( `W9-030` )
        ( `W8-001` )
        ( `W8-003` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `cn-letter-cnaps`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `cn_bank_letter.pdf`
      raw_text = `银行账户信息` &&
          cl_abap_char_utilities=>newline &&
          `公司名称: 假冒服务有限公司` &&
          cl_abap_char_utilities=>newline &&
          `开户行:中国某某银行股份有限公司北京支行` &&
          cl_abap_char_utilities=>newline &&
          `账号: 35310188000049999` &&
          cl_abap_char_utilities=>newline &&
          `我公司银行信息如下(收付款账户):` &&
          cl_abap_char_utilities=>newline &&
          `开户银行名称:中国某某银行股份有限公司北京支行` &&
          cl_abap_char_utilities=>newline &&
          `账号: 35310188000049999` &&
          cl_abap_char_utilities=>newline &&
          `联行号: 303100000999`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `假冒服务有限公司` )
        ( name = `bank_name` value = `中国某某银行股份有限公司北京支行` )
        ( name = `signed` value = `true` )
      )
      exp_fields = VALUE #(
        ( name = `national_clearing` value = `…0999` )
        ( name = `account_number` value = `…9999` )
      )
      exp_notes = VALUE #(
        ( `national clearing code (CNAPS)` )
        ( `bank country inferred: CN` )
      )
    ) TO gt_cases.
    APPEND VALUE #(
      id = `bank-address-grounding`
      doc_class = `bank`
      doc_type = `bank_letter`
      filename = `remit_form.pdf`
      raw_text = `Bank confirmation letter.` &&
          cl_abap_char_utilities=>newline &&
          `REMIT PAYMENT INFORMATION` &&
          cl_abap_char_utilities=>newline &&
          `Name on Account AcmeCo LLC` &&
          cl_abap_char_utilities=>newline &&
          `Bank Name First Example Bank` &&
          cl_abap_char_utilities=>newline &&
          `Bank Address 100 N. Example St..` &&
          cl_abap_char_utilities=>newline &&
          `City, State, Zip Code Springfield, CA. 00000` &&
          cl_abap_char_utilities=>newline &&
          `Account Number 001200000000` &&
          cl_abap_char_utilities=>newline &&
          `Routing for ACH 121000358` &&
          cl_abap_char_utilities=>newline &&
          `This letter is to confirm the account details below for AcmeCo LLC.` &&
          cl_abap_char_utilities=>newline &&
          `Sincerely,` &&
          cl_abap_char_utilities=>newline &&
          `Jordan Q. Sample` &&
          cl_abap_char_utilities=>newline &&
          `Vice President` &&
          cl_abap_char_utilities=>newline &&
          `First Example Bank`
      llm_fields = VALUE #(
        ( name = `account_holder` value = `AcmeCo LLC` )
        ( name = `bank_name` value = `First Example Bank` )
        ( name = `bank_country` value = `US` )
        ( name = `account_number` value = `001200000000` )
        ( name = `routing_aba` value = `121000358` )
        ( name = `signed` value = `false` )
      )
      exp_fields = VALUE #(
        ( name = `bank_address` value = `100 N. Example St, Springfield, CA. 00000` )
      )
    ) TO gt_cases.
  ENDMETHOD.

ENDCLASS.
