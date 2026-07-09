" GENERATED from rules/banking.yaml + rules/w9.yaml by tools/gen_rules_abap.py
" *** DO NOT EDIT BY HAND — edit the YAML and re-run the generator ***
CLASS zcl_mdmdoc_rules_data DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-DATA gt_rules_bank TYPE zif_mdmdoc_types=>tt_rules READ-ONLY.
    CLASS-DATA gt_rules_w9 TYPE zif_mdmdoc_types=>tt_rules READ-ONLY.
    CLASS-DATA gt_iban_len TYPE zif_mdmdoc_types=>tt_iban_len READ-ONLY.
    CLASS-DATA gt_doc_types_bank TYPE string_table READ-ONLY.
    CLASS-DATA gt_doc_types_w9 TYPE string_table READ-ONLY.
    CLASS-METHODS class_constructor.
  PRIVATE SECTION.
    CLASS-METHODS build_bank.
    CLASS-METHODS build_w9.
    CLASS-METHODS build_tables.
ENDCLASS.


CLASS zcl_mdmdoc_rules_data IMPLEMENTATION.

  METHOD class_constructor.
    build_bank( ).
    build_w9( ).
    build_tables( ).
  ENDMETHOD.

  METHOD build_bank.
    APPEND VALUE #(
        id = `BNK-001`
        name = `invoice_never_bank_proof`
        applies_to = VALUE #(
          ( `invoice` ) )
        when_op = `always`
        severity = `CRITICAL`
        verdict_effect = `REJECT`
        message = `Invoice used as banking support — an invoice (incl. pro forma) is never acceptable, even w` &&
        `hen it shows remittance/bank details. Request a bank letter, bank statement or supplier le` &&
        `tterhead.`
        message_ru = `Инвойс как банковское подтверждение не принимается (даже с реквизитами). Запросить bank le` &&
        `tter / statement / supplier letterhead.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-002`
        name = `email_as_proof`
        applies_to = VALUE #(
          ( `email` ) )
        when_op = `always`
        severity = `CRITICAL`
        verdict_effect = `REJECT`
        message = `Plain email is not normal bank support — exception-only with explicit Finance/Accounting a` &&
        `pproval evidence.`
        message_ru = `Обычное письмо — не банковское подтверждение; только как исключение с явным одобрением Fin` &&
        `ance/Accounting.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-003`
        name = `editable_source`
        applies_to = VALUE #(
          ( `editable_source` ) )
        when_op = `always`
        severity = `CRITICAL`
        verdict_effect = `REJECT`
        message = `Editable file (.docx/.xlsx/.txt/.rtf) is not acceptable as bank proof. Request a PDF/scan ` &&
        `on letterhead.`
        message_ru = `Редактируемый файл (.docx/.xlsx/.txt/.rtf) не принимается как банковское подтверждение. За` &&
        `просить PDF/скан.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-005`
        name = `ap_form_self_certified`
        applies_to = VALUE #(
          ( `ap_document` ) )
        when_op = `always`
        severity = `NOTE`
        message = `Self-certified AP/HCP bank-information form (not bank-issued). Acceptable per the HCP/AP p` &&
        `olicy for this request type; verify every detail against SAP and the request context.`
        message_ru = `Самозаполненная AP/HCP форма банковских данных (не выпущена банком). Приемлемо по политике` &&
        ` HCP/AP для этого типа запроса; каждую деталь сверить с SAP и контекстом запроса.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-006`
        name = `statement_swift_not_shown`
        applies_to = VALUE #(
          ( `bank_statement` ) )
        when_op = `check`
        when_field = `swift_bic`
        check_name = `field_empty`
        severity = `NOTE`
        message = `Bank statement shows no SWIFT/BIC — normal for statements; take SWIFT from the SAP/request` &&
        `-form comparison, not from this document.`
        message_ru = `В выписке нет SWIFT/BIC — для выписок это норма; SWIFT берётся из сверки с SAP/формой запр` &&
        `оса, не из этого документа.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-004`
        name = `payment_instructions_context`
        applies_to = VALUE #(
          ( `payment_instructions` ) )
        when_op = `always`
        severity = `WARNING`
        verdict_effect = `WARNING`
        message = `Supplier payment instructions — NOT an invoice. Acceptable only as an official, non-editab` &&
        `le supplier document (letterhead) whose details match SAP; otherwise request a bank letter` &&
        ` or bank statement. Mind payment-method limits printed on it (e.g. 'ACH only — not for wir` &&
        `e transfers'). Any kickback reason is 'no official supplier support', never 'invoice'.`
        message_ru = `Платёжные инструкции поставщика — это НЕ инвойс. Принимается только как официальный нереда` &&
        `ктируемый документ поставщика (letterhead) с реквизитами, совпадающими с SAP; иначе запрос` &&
        `ить bank letter / bank statement. Учитывай ограничения способа платежа (например, «ACH onl` &&
        `y — не для wire»). Причина kickback — «нет официального подтверждения поставщика», не «инв` &&
        `ойс».`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-010`
        name = `swift_shape`
        when_op = `check`
        when_field = `swift_bic`
        check_name = `swift_valid`
        check_args = VALUE #(
          ( name = `lengths` value = `8,11` ) )
        severity = `CRITICAL`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `SWIFT/BIC {value} fails shape/country check: {detail}.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-011`
        name = `iban_country_length`
        when_op = `check`
        when_field = `iban`
        check_name = `iban_valid`
        check_args = VALUE #(
          ( name = `table` value = `iban_length` ) )
        severity = `CRITICAL`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `IBAN {value_masked}: {detail}.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-020`
        name = `doc_older_than_2y`
        when_op = `check`
        when_field = `doc_date`
        check_name = `date_older_than`
        check_args = VALUE #(
          ( name = `years` value = `2` ) )
        severity = `NOTE`
        message = `Document is older than 2 years ({detail}) — confirm the details are still current.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-021`
        name = `missing_signature_bank_letter`
        applies_to = VALUE #(
          ( `bank_letter` ) )
        when_op = `check`
        when_field = `signed`
        check_name = `unsigned_no_evidence`
        severity = `WARNING`
        verdict_effect = `WARNING`
        message = `Bank letter appears unsigned/unstamped (no officer block either).`
        message_ru = `Банковское письмо без подписи/печати (и без блока офицера).`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-026`
        name = `typed_officer_block_instead_of_signature`
        applies_to = VALUE #(
          ( `bank_letter` ) )
        when_op = `check`
        when_field = `signed`
        check_name = `unsigned_typed_block`
        severity = `NOTE`
        message = `No wet signature/stamp; compensating evidence present ({detail}) — normal for system-issue` &&
        `d bank letters; note for the Data Owner.`
        message_ru = `Живой подписи/печати нет; есть компенсирующее свидетельство ({detail}) — норма для системн` &&
        `о выпускаемых банковских писем; заметка для Data Owner.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-022`
        name = `partial_screenshot`
        applies_to = VALUE #(
          ( `bank_screenshot` ) )
        when_op = `flag_true`
        when_field = `partial_capture`
        severity = `WARNING`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `Screenshot appears cropped/partial — key fields may be cut off.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-023`
        name = `missing_account_holder`
        applies_to = VALUE #(
          ( `bank_letter` )
          ( `bank_statement` )
          ( `supplier_letterhead` )
          ( `bank_screenshot` )
          ( `voided_check` )
          ( `ap_document` )
          ( `payment_instructions` )
          ( `other` ) )
        when_op = `field_missing`
        when_field = `account_holder`
        severity = `WARNING`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `No account holder / beneficiary name readable on the document.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-024`
        name = `no_banking_identity`
        applies_to = VALUE #(
          ( `bank_letter` )
          ( `bank_statement` )
          ( `supplier_letterhead` )
          ( `bank_screenshot` )
          ( `voided_check` )
          ( `ap_document` )
          ( `payment_instructions` )
          ( `other` ) )
        when_op = `check`
        check_name = `no_bank_ids`
        severity = `WARNING`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `Document shows no bank account identifiers (no IBAN, account number or routing) — cannot s` &&
        `erve as banking evidence as-is.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-025`
        name = `missing_bank_name`
        applies_to = VALUE #(
          ( `bank_letter` )
          ( `bank_statement` )
          ( `bank_screenshot` )
          ( `voided_check` ) )
        when_op = `field_missing`
        when_field = `bank_name`
        severity = `WARNING`
        verdict_effect = `WARNING`
        message = `Bank name not readable on the document.`
      ) TO gt_rules_bank.
    APPEND VALUE #(
        id = `BNK-030`
        name = `unrecognized_document_type`
        applies_to = VALUE #(
          ( `other` ) )
        when_op = `always`
        severity = `WARNING`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `Document type could not be established — an unrecognized document is never auto-accepted; ` &&
        `review manually.`
        message_ru = `Тип документа не установлен — неопознанный документ не принимается автоматически; проверьт` &&
        `е вручную.`
      ) TO gt_rules_bank.
  ENDMETHOD.

  METHOD build_w9.
    APPEND VALUE #(
        id = `W9-030`
        name = `w8_detected`
        applies_to = VALUE #(
          ( `w8` ) )
        when_op = `always`
        severity = `WARNING`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `This is a W-8 (foreign status), not a W-9 — apply W-8 treatment; do not map to Tax Number ` &&
        `1/2 as a W-9.`
        message_ru = `Это W-8 (иностранный статус), не W-9 — другой процесс обработки.`
      ) TO gt_rules_w9.
    APPEND VALUE #(
        id = `W9-031`
        name = `unknown_tax_doc`
        applies_to = VALUE #(
          ( `unknown` )
          ( `other_tax` ) )
        when_op = `always`
        severity = `WARNING`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `Not recognized as a W-9 — confirm the document type before using it as US tax evidence.`
      ) TO gt_rules_w9.
    APPEND VALUE #(
        id = `W9-001`
        name = `line1_missing`
        applies_to = VALUE #(
          ( `w9` ) )
        when_op = `field_missing`
        when_field = `line1_name`
        severity = `CRITICAL`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `W-9 Line 1 (taxpayer legal name) is missing/unreadable — Line 1 must feed SAP Name 1.`
      ) TO gt_rules_w9.
    APPEND VALUE #(
        id = `W9-002`
        name = `tin_unreadable`
        applies_to = VALUE #(
          ( `w9` ) )
        when_op = `field_missing`
        when_field = `tin_raw`
        severity = `WARNING`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `TIN not readable on the form — cannot verify SSN/EIN mapping.`
      ) TO gt_rules_w9.
    APPEND VALUE #(
        id = `W9-003`
        name = `classification_missing`
        applies_to = VALUE #(
          ( `w9` ) )
        when_op = `field_missing`
        when_field = `line3_classification`
        severity = `WARNING`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `Federal tax classification (Line 3) unclear — Recipient Type cannot be verified.`
      ) TO gt_rules_w9.
    APPEND VALUE #(
        id = `W9-010`
        name = `ein_9_digits`
        applies_to = VALUE #(
          ( `w9` ) )
        when_op = `check`
        when_field = `tin_raw`
        check_name = `ein_shape`
        check_args = VALUE #(
          ( name = `digits` value = `9` ) )
        severity = `CRITICAL`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `TIN {value} has the wrong digit count: {detail} (EIN/SSN must be 9 digits).`
      ) TO gt_rules_w9.
    APPEND VALUE #(
        id = `W9-011`
        name = `tin_type_vs_classification`
        applies_to = VALUE #(
          ( `w9` ) )
        when_op = `check`
        when_field = `tin_raw`
        check_name = `tin_type_vs_classification`
        severity = `CRITICAL`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `TIN type conflicts with the tax classification: {detail}. Individual/Sole proprietor norma` &&
        `lly uses SSN (Tax Number 1); businesses use EIN (Tax Number 2).`
      ) TO gt_rules_w9.
    APPEND VALUE #(
        id = `W9-012`
        name = `individual_llc_ein_mix`
        applies_to = VALUE #(
          ( `w9` ) )
        when_op = `check`
        check_name = `individual_with_business_name_and_ein`
        severity = `CRITICAL`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `Internal inconsistency: {detail}. Request clarification or an updated W-9 (rule DR-2026062` &&
        `4-131532).`
      ) TO gt_rules_w9.
    APPEND VALUE #(
        id = `W9-013`
        name = `line_swap_suspect`
        applies_to = VALUE #(
          ( `w9` ) )
        when_op = `check`
        check_name = `line_swap_suspect`
        severity = `WARNING`
        verdict_effect = `NEED_MANUAL_REVIEW`
        message = `Line 1 / Line 2 look swapped or collapsed: {detail}. Never swap or merge W-9 name lines (L` &&
        `ine 1 -> Name 1, Line 2 -> Name 2).`
      ) TO gt_rules_w9.
    APPEND VALUE #(
        id = `W9-020`
        name = `unsigned`
        applies_to = VALUE #(
          ( `w9` ) )
        when_op = `flag_false`
        when_field = `signed`
        severity = `WARNING`
        verdict_effect = `WARNING`
        message = `W-9 appears unsigned — note for review (blocking only if packet rules say so).`
      ) TO gt_rules_w9.
  ENDMETHOD.

  METHOD build_tables.
    gt_doc_types_bank = VALUE #(
      ( `bank_letter` )
      ( `bank_statement` )
      ( `supplier_letterhead` )
      ( `bank_screenshot` )
      ( `voided_check` )
      ( `ap_document` )
      ( `payment_instructions` )
      ( `invoice` )
      ( `email` )
      ( `editable_source` )
      ( `other` ) ).
    gt_doc_types_w9 = VALUE #(
      ( `w9` )
      ( `w8` )
      ( `other_tax` )
      ( `unknown` ) ).
    gt_iban_len = VALUE #(
      ( country = 'AD' len = 24 )
      ( country = 'AE' len = 23 )
      ( country = 'AT' len = 20 )
      ( country = 'BE' len = 16 )
      ( country = 'BG' len = 22 )
      ( country = 'BH' len = 22 )
      ( country = 'BR' len = 29 )
      ( country = 'CH' len = 21 )
      ( country = 'CY' len = 28 )
      ( country = 'CZ' len = 24 )
      ( country = 'DE' len = 22 )
      ( country = 'DK' len = 18 )
      ( country = 'EE' len = 20 )
      ( country = 'EG' len = 29 )
      ( country = 'ES' len = 24 )
      ( country = 'FI' len = 18 )
      ( country = 'FR' len = 27 )
      ( country = 'GB' len = 22 )
      ( country = 'GR' len = 27 )
      ( country = 'HR' len = 21 )
      ( country = 'HU' len = 28 )
      ( country = 'IE' len = 22 )
      ( country = 'IL' len = 23 )
      ( country = 'IQ' len = 23 )
      ( country = 'IS' len = 26 )
      ( country = 'IT' len = 27 )
      ( country = 'JO' len = 30 )
      ( country = 'KW' len = 30 )
      ( country = 'LB' len = 28 )
      ( country = 'LI' len = 21 )
      ( country = 'LT' len = 20 )
      ( country = 'LU' len = 20 )
      ( country = 'LV' len = 21 )
      ( country = 'MC' len = 27 )
      ( country = 'MT' len = 31 )
      ( country = 'MX' len = 18 )
      ( country = 'NL' len = 18 )
      ( country = 'NO' len = 15 )
      ( country = 'PK' len = 24 )
      ( country = 'PL' len = 28 )
      ( country = 'PT' len = 25 )
      ( country = 'QA' len = 29 )
      ( country = 'RO' len = 24 )
      ( country = 'SA' len = 24 )
      ( country = 'SE' len = 24 )
      ( country = 'SG' len = 19 )
      ( country = 'SI' len = 19 )
      ( country = 'SK' len = 24 )
      ( country = 'TN' len = 24 )
      ( country = 'TR' len = 26 )
    ).
  ENDMETHOD.

ENDCLASS.
