INTERFACE zif_mdmdoc_types
  PUBLIC.

  " Shared types + constants for the mdmdoc ABAP clone.
  " Mirrors the Python originals: fields.py (BANK_KEYS/W9_KEYS), rules/engine.py
  " (Rule/Finding), verdict.py (precedence values), privacy.py (FIELD_KIND).

  TYPES: BEGIN OF ty_field,
           name  TYPE string,
           value TYPE string,          " booleans stored as 'true'/'false'
         END OF ty_field,
         tt_fields TYPE HASHED TABLE OF ty_field WITH UNIQUE KEY name.

  TYPES: BEGIN OF ty_finding,
           rule_id        TYPE string,
           severity       TYPE string,  " CRITICAL | WARNING | NOTE
           verdict_effect TYPE string,  " REJECT | NEED_MANUAL_REVIEW | WARNING | ''
           message        TYPE string,
           detail         TYPE string,
           field          TYPE string,
         END OF ty_finding,
         tt_findings TYPE STANDARD TABLE OF ty_finding WITH EMPTY KEY.

  TYPES: BEGIN OF ty_arg,
           name  TYPE string,
           value TYPE string,          " lists flattened as comma-separated: '8,11'
         END OF ty_arg,
         tt_args TYPE STANDARD TABLE OF ty_arg WITH EMPTY KEY.

  TYPES: BEGIN OF ty_rule,
           id             TYPE string,
           name           TYPE string,
           applies_to     TYPE string_table,  " empty = applies to all doc types
           when_op        TYPE string,  " always|field_missing|flag_true|flag_false|equals|in|regex_mismatch|check
           when_field     TYPE string,
           when_value     TYPE string,  " equals-value / regex pattern
           when_values    TYPE string_table,  " for 'in'
           check_name     TYPE string,  " predicate name for 'check'
           check_args     TYPE tt_args,
           severity       TYPE string,
           verdict_effect TYPE string,
           message        TYPE string,  " keeps {value} {value_masked} {detail} placeholders
           message_ru     TYPE string,
         END OF ty_rule,
         tt_rules TYPE STANDARD TABLE OF ty_rule WITH EMPTY KEY.

  TYPES: BEGIN OF ty_iban_len,
           country TYPE c LENGTH 2,
           len     TYPE i,
         END OF ty_iban_len,
         tt_iban_len TYPE SORTED TABLE OF ty_iban_len WITH UNIQUE KEY country.

  TYPES: BEGIN OF ty_extraction,
           doc_class  TYPE string,            " bank | w9
           doc_type   TYPE string,
           fields     TYPE tt_fields,
           crosscheck TYPE string_table,
           warnings   TYPE string_table,
           model_id   TYPE string,
           llm_used   TYPE abap_bool,
           secrets    TYPE string_table,      " full sensitive values, in-memory only
         END OF ty_extraction.

  CONSTANTS: BEGIN OF c_verdict,
               accept  TYPE string VALUE 'ACCEPT',
               reject  TYPE string VALUE 'REJECT',
               review  TYPE string VALUE 'NEED_MANUAL_REVIEW',
               warning TYPE string VALUE 'WARNING',
             END OF c_verdict.

  CONSTANTS: BEGIN OF c_severity,
               critical TYPE string VALUE 'CRITICAL',
               warning  TYPE string VALUE 'WARNING',
               note     TYPE string VALUE 'NOTE',
             END OF c_severity.

  CONSTANTS: BEGIN OF c_doc_class,
               bank TYPE string VALUE 'bank',
               w9   TYPE string VALUE 'w9',
             END OF c_doc_class.

  " Masking kinds (privacy.py SENSITIVE_KINDS); TIN kinds are masked under EVERY policy
  CONSTANTS: BEGIN OF c_kind,
               ssn     TYPE string VALUE 'ssn',
               ein     TYPE string VALUE 'ein',
               tin     TYPE string VALUE 'tin',
               iban    TYPE string VALUE 'iban',
               account TYPE string VALUE 'account_number',
               routing TYPE string VALUE 'routing_aba',
             END OF c_kind.

  CONSTANTS: BEGIN OF c_policy,
               masked TYPE string VALUE 'masked',
               full   TYPE string VALUE 'full',
             END OF c_policy.

  " Field catalogs (fields.py BANK_KEYS / W9_KEYS) — split on ',' at runtime
  CONSTANTS c_bank_keys TYPE string VALUE
    `account_holder,account_type,bank_name,bank_country,bank_address,iban,swift_bic,` &
    `account_number,routing_aba,routing_aba_wires,branch_code,currency,doc_date,signed,` &
    `signature_evidence,partial_capture`.
  CONSTANTS c_w9_keys TYPE string VALUE
    `line1_name,line2_business_name,line3_classification,tin_type,tin_raw,address_street,` &
    `address_city_state_zip,signed,sign_date`.

  " privacy.py FIELD_KIND: extraction field name -> masking kind ('field:kind' pairs)
  CONSTANTS c_field_kind TYPE string VALUE
    `iban:iban,account_number:account_number,routing_aba:routing_aba,` &
    `routing_aba_wires:routing_aba,tin_raw:tin,tin_boxed:tin,ein:ein,ssn:ssn`.

  " ---- SAP Change Request comparison (sap_compare.py) ---------------------
  " SAP-side field set read from a change request / master record.
  TYPES: BEGIN OF ty_sap_field,
           name  TYPE string,
           value TYPE string,
         END OF ty_sap_field,
         tt_sap_fields TYPE HASHED TABLE OF ty_sap_field WITH UNIQUE KEY name.

  " One rendered comparison row (report.py sap_block).
  TYPES: BEGIN OF ty_compare_row,
           field  TYPE string,
           doc    TYPE string,   " document-side value (masked per policy)
           sap    TYPE string,   " SAP-side value (masked per policy)
           status TYPE string,   " match | MISMATCH | only-one-side | sap-only
           note   TYPE string,
         END OF ty_compare_row,
         tt_compare_row TYPE STANDARD TABLE OF ty_compare_row WITH EMPTY KEY.

  " SAP_KEYS (sap_compare.py) — the SAP-side field names, split on ',' at runtime.
  CONSTANTS c_sap_keys TYPE string VALUE
    `bank_details_id,bank_account,account_holder,iban,account_name,control_key,` &
    `reference_details,bank_country,bank_key,bank_name,street,city,bank_branch,swift_bic`.

  CONSTANTS: BEGIN OF c_cmp_status,
               match     TYPE string VALUE 'match',
               mismatch  TYPE string VALUE 'MISMATCH',
               one_side  TYPE string VALUE 'only-one-side',
               sap_only  TYPE string VALUE 'sap-only',
             END OF c_cmp_status.

ENDINTERFACE.
