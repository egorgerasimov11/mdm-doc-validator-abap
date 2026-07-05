# ZMDMDOC — class contract (fixed public APIs)

Every class implements EXACTLY these public signatures — consumers are written against them.
Private helpers are free. All classes: `PUBLIC FINAL CREATE PUBLIC` unless stated otherwise.
Shared types/constants: `ZIF_MDMDOC_TYPES` (see src/zif_mdmdoc_types.intf.abap).

Conventions:
- Booleans inside `tt_fields` are strings `'true'` / `'false'` (LLM JSON parity).
- Doc classes: `'bank'` / `'w9'`. Verdicts/severities: see interface constants.
- Rule messages keep `{value}`, `{value_masked}`, `{detail}` placeholders — the rules engine
  substitutes them (masked via ZCL_MDMDOC_MASK when the field is sensitive).
- Target release **7.50**: NO PCRE (`FIND PCRE`, `cl_abap_regex` pcre param forbidden).
  Classic regex only: `(?i)` → `IGNORING CASE`/`ignore_case = abap_true`; `\b` → `\<` `\>`;
  no `(?s)`/`(?m)` — flatten newlines to spaces or use a SPLIT line table instead.
- abapGit artifacts per class: `zcl_x.clas.abap`, `zcl_x.clas.testclasses.abap`,
  `zcl_x.clas.xml` (VSEOCLASS with `<WITH_UNIT_TESTS>X</WITH_UNIT_TESTS>`).
- Verify: `npx --yes @abaplint/cli 2>&1 | grep -i <your-file-basename>` must be empty
  (enabled rules: parser_error, check_syntax, unknown_types, check_ddic, implement_methods,
  method_implemented_twice, superclass_final, unreachable_code, line_length 140).
- Unit tests: `RISK LEVEL HARMLESS DURATION SHORT`, no network/filesystem/GUI.

## ZCL_MDMDOC_NORM (all CLASS-METHODS; port of fields.py normalizers + predicates.py parse_date)

```abap
norm_id            IMPORTING iv_value TYPE string RETURNING VALUE(rv_id) TYPE string.
  " strip all whitespace + '-', uppercase (fields._norm_id)
digits_only        IMPORTING iv_value TYPE string RETURNING VALUE(rv_digits) TYPE string.
norm_flag          IMPORTING iv_value TYPE string RETURNING VALUE(rv_bool) TYPE abap_bool.
  " 'true','yes','1','x' (any case) -> abap_true
to_iso2            IMPORTING iv_country TYPE string RETURNING VALUE(rv_iso2) TYPE string.
  " full name ('Germany'->'DE'), ISO3 ('DEU'->'DE'), passthrough ISO2; port fields.to_iso2
iban_mod97_ok      IMPORTING iv_iban TYPE string RETURNING VALUE(rv_ok) TYPE abap_bool.
  " ISO 13616; shape ^[A-Z]{2}\d{2}[A-Z0-9]{8,30}$ else false
norm_classification IMPORTING iv_text TYPE string RETURNING VALUE(rv_class) TYPE string.
  " -> individual_sole_prop|llc|partnership|corporation|trust_estate|other|'' (fields.norm_classification)
looks_like_business IMPORTING iv_name TYPE string RETURNING VALUE(rv_yes) TYPE abap_bool.
looks_like_person   IMPORTING iv_name TYPE string RETURNING VALUE(rv_yes) TYPE abap_bool.
parse_date         IMPORTING iv_text TYPE string
                   EXPORTING ev_date TYPE d ev_ok TYPE abap_bool.
  " multi-format incl. 'Month DD, YYYY', 'DD Month YYYY', ES/DE months, 2-digit years,
  " fallback: bare 4-digit year -> July 1 (predicates.parse_date)
translate_fullwidth IMPORTING iv_text TYPE string RETURNING VALUE(rv_text) TYPE string.
  " U+FF10..FF19 digits + FF21..FF3A/FF41..FF5A letters -> ASCII
field_value        IMPORTING it_fields TYPE zif_mdmdoc_types=>tt_fields iv_name TYPE string
                   RETURNING VALUE(rv_value) TYPE string.  " '' when absent
field_is_true      IMPORTING it_fields TYPE zif_mdmdoc_types=>tt_fields iv_name TYPE string
                   RETURNING VALUE(rv_bool) TYPE abap_bool.
```

## ZCL_MDMDOC_MASK (all CLASS-METHODS; port of privacy.py)

```abap
mask           IMPORTING iv_kind TYPE string iv_value TYPE string
               RETURNING VALUE(rv_masked) TYPE string.
  " ssn->XXX-XX-<l4>, ein->XX-XXX<l4>, tin(route by shape 3-2-4/2-7), iban->CC**…<l4>,
  " account_number/routing_aba->…<l4>, unknown->****-style (privacy.mask)
display_value  IMPORTING iv_kind TYPE string iv_value TYPE string
                         iv_policy TYPE string DEFAULT 'masked'
               RETURNING VALUE(rv_out) TYPE string.
  " TIN kinds (ssn/ein/tin) masked under EVERY policy; bank kinds full only when policy='full'
kind_for_field IMPORTING iv_field TYPE string RETURNING VALUE(rv_kind) TYPE string.
  " from zif_mdmdoc_types=>c_field_kind; '' = not sensitive
scrub_text     IMPORTING iv_text TYPE string RETURNING VALUE(rv_text) TYPE string.
  " mask SSN/EIN shapes + IBAN-looking tokens inside free text (privacy.scrub_text)
assert_no_leak IMPORTING iv_blob TYPE string it_secrets TYPE string_table
                         iv_policy TYPE string DEFAULT 'strict'
               EXPORTING et_hits TYPE string_table ev_clean TYPE abap_bool.
  " policy 'strict': TIN+banking patterns+known secrets; 'tin-only': TIN patterns+TIN secrets
```

## ZCL_MDMDOC_VERDICT (all CLASS-METHODS; port of verdict.py)

```abap
decide       IMPORTING it_findings TYPE zif_mdmdoc_types=>tt_findings
             RETURNING VALUE(rv_verdict) TYPE string.
next_step    IMPORTING iv_doc_class TYPE string iv_verdict TYPE string
                       iv_lang TYPE string DEFAULT 'EN'
             RETURNING VALUE(rv_text) TYPE string.  " RU adds translated texts
message_type IMPORTING iv_verdict TYPE string RETURNING VALUE(rv_msgty) TYPE c.
  " ACCEPT->'S', WARNING/NEED_MANUAL_REVIEW->'W', REJECT->'E'
```

## ZCL_MDMDOC_REGEX (CLASS-METHODS; port of ocr.py regex_fields + fields.find_boxed_tin/find_valid_ibans)

```abap
extract_candidates IMPORTING iv_text TYPE string
                   RETURNING VALUE(rt_candidates) TYPE zif_mdmdoc_types=>tt_fields.
  " names: iban, swift_bic, account_number, routing_aba, routing_aba_wires, ein, ssn,
  "        tin_boxed (9 digits), tin_boxed_type ('EIN'/'SSN')
  " label-anchored windows; run on newline-flattened buffer; boxed TIN via line table
```

## ZCL_MDMDOC_SNIFF (CLASS-METHODS; port of stage_a.sniff_doc_class + fields.type_hint)

```abap
sniff_doc_class IMPORTING iv_text TYPE string iv_filename TYPE string
                RETURNING VALUE(rv_class) TYPE string.   " 'bank' | 'w9'
type_hint       IMPORTING iv_text TYPE string iv_filename TYPE string
                          iv_doc_class TYPE string
                RETURNING VALUE(rv_type) TYPE string.
  " bank: invoice/email/bank_letter/bank_statement/ap_document/payment_instructions/...
  " w9: w9/w8/unknown
```

## ZCL_MDMDOC_PDF (CLASS-METHODS)

```abap
extract_text IMPORTING iv_pdf TYPE xstring
             EXPORTING ev_text TYPE string ev_pages TYPE i
                       ev_encrypted TYPE abap_bool et_warnings TYPE string_table.
```

## ZCL_MDMDOC_FILE

```abap
TYPES: BEGIN OF ty_doc,
         path    TYPE string,
         name    TYPE string,   " basename
         ext     TYPE string,   " lowercase, no dot
         content TYPE xstring,
         sha16   TYPE string,   " first 16 hex chars of SHA-256, lowercase
         source  TYPE string,   " 'pc' | 'server'
       END OF ty_doc.
CLASS-METHODS:
  read         IMPORTING iv_path TYPE string iv_from_server TYPE abap_bool
               EXPORTING es_doc TYPE ty_doc ev_error TYPE string,
  classify_ext IMPORTING iv_ext TYPE string RETURNING VALUE(rv_kind) TYPE string,
    " 'pdf'|'image'|'email'|'zip'|'editable'|'msg'|'other'
  unwrap       EXPORTING et_notes TYPE string_table ev_error TYPE string
               CHANGING cs_doc TYPE ty_doc,
    " zip via cl_abap_zip (best inner candidate), eml multipart+base64; depth<=2
  save_text    IMPORTING iv_path TYPE string iv_text TYPE string
                         iv_to_server TYPE abap_bool
               EXPORTING ev_error TYPE string.
```

## ZCL_MDMDOC_LLM (instance; CREATE PUBLIC, constructor-injected config)

```abap
METHODS:
  constructor      IMPORTING iv_url TYPE string iv_model_text TYPE string
                             iv_model_vision TYPE string iv_timeout TYPE i DEFAULT 120,
  probe            RETURNING VALUE(rv_up) TYPE abap_bool,       " GET /api/tags, 5s
  extract_fields   IMPORTING iv_doc_class TYPE string iv_text TYPE string
                             it_candidates TYPE zif_mdmdoc_types=>tt_fields
                   EXPORTING et_fields TYPE zif_mdmdoc_types=>tt_fields
                             ev_doc_type TYPE string ev_ok TYPE abap_bool ev_error TYPE string,
  transcribe_image IMPORTING iv_image TYPE xstring iv_mime TYPE string
                   EXPORTING ev_text TYPE string ev_ok TYPE abap_bool ev_error TYPE string.
```
HTTP isolated in ONE private non-final-testable method
`http_post( iv_path TYPE string iv_body TYPE string ) EXPORTING ev_body TYPE string ev_ok TYPE abap_bool ev_error TYPE string`
so tests can inject canned responses (make the class non-FINAL, method PROTECTED, tests subclass it).

## ZCL_MDMDOC_EXTRACT (CLASS-METHODS; port of fields.crosscheck_ids + apply_normalizers)

```abap
build IMPORTING iv_doc_class TYPE string iv_doc_type TYPE string
                it_llm_fields TYPE zif_mdmdoc_types=>tt_fields
                it_candidates TYPE zif_mdmdoc_types=>tt_fields
                iv_llm_used TYPE abap_bool
      RETURNING VALUE(rs_ext) TYPE zif_mdmdoc_types=>ty_extraction.
  " candidate overlay RULES: regex fills blank field ('filled-from-regex(<masked>)'),
  " norm_id-equal -> 'confirmed', zero-padded account variant -> 'confirmed (zero-padded variant)',
  " else regex WINS + 'MISMATCH(model=<masked> vs regex=<masked>)' crosscheck note.
  " ein candidate -> tin_raw + tin_type='EIN'; tin_boxed -> tin_raw + tin_type from tin_boxed_type.
  " bank_country -> to_iso2; line3_classification kept raw (predicates normalize on read).
  " secrets[] = full values of sensitive fields present. All notes use masked values ONLY.
```

## ZCL_MDMDOC_RULES (instance)

```abap
METHODS:
  constructor IMPORTING iv_rules_json TYPE string OPTIONAL,
    " '' -> generated ZCL_MDMDOC_RULES_DATA tables; else parse zmdmdoc.rules.v1 JSON
    " via /ui2/cl_json; on parse failure: fall back to generated + remember an engine_error
  run IMPORTING is_ext TYPE zif_mdmdoc_types=>ty_extraction
                iv_lang TYPE string DEFAULT 'EN'
      RETURNING VALUE(rt_findings) TYPE zif_mdmdoc_types=>tt_findings.
```
Engine: applies_to filter (empty=all); when-ops always|field_missing|flag_true|flag_false|
equals|in|regex_mismatch|check; predicates (private methods, dispatched by check_name):
field_empty, swift_valid, iban_valid, ein_shape, tin_type_vs_classification,
individual_with_business_name_and_ein, line_swap_suspect, date_older_than,
no_bank_ids, unsigned_no_evidence, unsigned_typed_block.
Unknown predicate/op -> finding rule_id='ENGINE', severity=WARNING, no dump.
Message placeholders: {value} raw-or-masked-if-sensitive, {value_masked} always masked,
{detail} predicate detail. iv_lang='RU' prefers message_ru when non-empty.

## ZCL_MDMDOC_REPORT (CLASS-METHODS)

```abap
build_list IMPORTING is_ext TYPE zif_mdmdoc_types=>ty_extraction
                     it_findings TYPE zif_mdmdoc_types=>tt_findings
                     iv_verdict TYPE string iv_lang TYPE string
                     iv_policy TYPE string
           RETURNING VALUE(rt_lines) TYPE string_table.
build_json IMPORTING is_ext TYPE zif_mdmdoc_types=>ty_extraction
                     it_findings TYPE zif_mdmdoc_types=>tt_findings
                     iv_verdict TYPE string iv_doc_path TYPE string
                     iv_run_id TYPE string iv_lang TYPE string
                     iv_policy TYPE string
           RETURNING VALUE(rv_json) TYPE string.   " schema 'mdmdoc.v1' subset
```

## Pipeline findings emitted by the program (reserved rule ids)

- `EXT-001` unreadable (no text layer) — severity WARNING, effect NEED_MANUAL_REVIEW
- `EXT-002` image without LLM/vision — WARNING, NEED_MANUAL_REVIEW
- `EXT-003` encrypted PDF — WARNING, NEED_MANUAL_REVIEW
- `EXT-004` partial PDF decode — WARNING, no effect
- `EXT-005` .msg unsupported — WARNING, NEED_MANUAL_REVIEW
- `LLM-001` LLM enabled but unreachable/failed — WARNING, NEED_MANUAL_REVIEW
- `LLM-002` LLM disabled by user (regex-only) — NOTE, no effect

## clas.xml template

```xml
<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0" serializer="LCL_OBJECT_CLAS" serializer_version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
   <VSEOCLASS>
    <CLSNAME>ZCL_MDMDOC_X</CLSNAME>
    <LANGU>E</LANGU>
    <DESCRIPT>mdmdoc: ...</DESCRIPT>
    <STATE>1</STATE>
    <CLSCCINCL>X</CLSCCINCL>
    <FIXPT>X</FIXPT>
    <UNICODE>X</UNICODE>
    <WITH_UNIT_TESTS>X</WITH_UNIT_TESTS>
   </VSEOCLASS>
  </asx:values>
 </asx:abap>
</abapGit>
```

## SAP Change Request comparison (feature 2)

Source-independent comparator + pluggable reader. Only the two MDG classes touch
the MDG framework (excluded from abaplint, `verify-on-system`); everything else is
pure ABAP and unit-tested.

### ZCL_MDMDOC_COMPARE (CLASS-METHODS; port of sap_compare.py)

```abap
compare IMPORTING is_ext TYPE ty_extraction it_sap TYPE tt_sap_fields iv_policy TYPE string DEFAULT 'masked'
        EXPORTING et_findings TYPE tt_findings et_rows TYPE tt_compare_row.
  " SAP-001 IBAN mismatch (char-by-char, first-diff pos, CRITICAL/REVIEW)
  " SAP-002 IBAN only-one-side (WARNING); SAP-003 account (0-pad + in-IBAN tolerance, CRITICAL)
  " SAP-004 SWIFT (±XXX, CRITICAL); SAP-005 country to_iso2 (CRITICAL)
  " SAP-006 bank_key unconfirmed-by-document (WARNING); SAP-007 bank name substring (WARNING)
  " SAP-008 account holder substring (CRITICAL); SAP-000 all-match (NOTE)
  " both sides masked via zcl_mdmdoc_mask; full sensitive values never leave.
```

### ZIF_MDMDOC_SAP_READER (adapter)

```abap
read_cr_fields      IMPORTING iv_cr EXPORTING et_sap TYPE tt_sap_fields ev_found ev_error.
read_cr_attachments IMPORTING iv_cr EXPORTING et_docs TYPE tt_attachment ev_error.
```

- `ZCL_MDMDOC_SAP_MANUAL` — implements it from a direct table or flat JSON `{sap_field:value}`
  (test double / no-SAP fallback).
- `ZCL_MDMDOC_MDG_READER` — implements it over MDG: `constructor( io_model TYPE REF TO
  if_usmd_model_ext, iv_crequest )`; `read_cr_fields` via `io_model->read_entity_data_all`
  (entities BP_CENTRL/ADDRESS/BP_BANKDT/BP_IBAN/BP_TAXNUM → SAP_KEYS), attachments via GOS.
  **verify-on-system.**

### ZCL_MDG_BP_FIELD_DERR_VAL (BAdI USMD_RULE_SERVICE)

`IF_EX_USMD_RULE_SERVICE~CHECK_ENTITY` (anchor guard on BP_BANKDT) → read attachment + CR fields →
deterministic pipeline (LLM off) → `ZCL_MDMDOC_COMPARE` → findings emitted as CR messages
(WARNING; REJECT→E). **verify-on-system.** Deploy: see docs/INTEGRATION.md chapter 10.

### ZCL_MDMDOC_REPORT (extended)

`build_list` / `build_json` gained optional `it_compare TYPE tt_compare_row` → renders a
`SAP COMPARISON` block and a `sap_compare` JSON array (empty → omitted, backward compatible).

## Deployment: pre-flight + adaptable mapping (feature 3)

### ZCL_MDMDOC_SELFTEST (pure, unit-tested)

```abap
run_core         RETURNING VALUE(rt_checks) TYPE tt_check.   " all non-MDG checks
check_class      IMPORTING iv_name RETURNING ty_check.       " RTTI existence
check_json / check_mask / check_pdf / check_comparator RETURNING ty_check.
```
`ty_check` = { name, status (PASS|FAIL|SKIP), detail } in ZIF_MDMDOC_TYPES.

### ZMDMDOC_DOCTOR (report, verify-on-system)

Runs `run_core` + MDG availability + optional live CR read (p_cr) → colored PASS/FAIL list.

### ZCL_MDMDOC_MDG_MAP (verify-on-system)

```abap
get_map  IMPORTING iv_model TYPE usmd_model RETURNING VALUE(rt_map) TYPE tt_map.
defaults RETURNING VALUE(rt_map) TYPE tt_map.
```
`tt_map` = { sap_key, entity, field }. Defaults overlaid by optional table ZMDMDOC_MAP
(dynamic SELECT — activates even without the table). ZCL_MDMDOC_MDG_READER is table-driven
off this map (no hard-coded entity/field names).

### ZMDMDOC_MDG_DISCOVER (report, verify-on-system)

Reads the live MDG model (entities+fields via RTTI), matches field names to synonyms, proposes
the SAP_KEY→entity.field mapping, lists gaps, optional save to ZMDMDOC_MAP.
