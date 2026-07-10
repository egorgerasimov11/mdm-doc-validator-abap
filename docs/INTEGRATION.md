# Integrating ZMDMDOC into SAP — step-by-step guide and dependencies

> Русская версия: [INTEGRATION.ru.md](INTEGRATION.ru.md)

This document describes how to install the ABAP clone of the validator (`ZMDMDOC`) into an SAP
system, which standard components it needs, how to configure the optional Ollama call,
and how to embed the program into background jobs / call it from other code.

Target environment: **on-premise SAP, ABAP ≥ 7.50** (ECC EhP8, S/4HANA any release, ABAP Platform).
Not for BTP ABAP Environment (Steampunk) — it has no direct access to the SAPGUI file system.

---

## 0. TL;DR — what you need

| What | Required? | Why |
|---|---|---|
| ABAP ≥ 7.50 | yes | classic regex, report syntax |
| [abapGit](https://abapgit.org) | yes | source import |
| Developer key / transport | yes (except `$TMP`) | creating Z-objects |
| Component **SAP_UI** (`/UI2/CL_JSON`) | almost always | LLM calls, JSON export, rules override |
| Role with S_GUI, S_DATASET, S_ICF | yes | file upload + outbound HTTP |
| [Ollama](https://ollama.com) + models | no (optional) | LLM field extraction, reading scans |
| Outbound HTTP allowed on the app server | Ollama only | calling `/api/chat` |

The core (PDF reading + regex extraction + rules + verdict) works **without** SAP_UI, without
Ollama and without outbound HTTP. Everything marked "optional" is needed only for LLM mode.

---

## 1. Standard ABAP dependencies (check availability BEFORE the import)

All of these are standard SAP classes; on 7.50+ they are practically always present. Check in
SE24 / SE80 if your system is stripped down:

| Class / object | Used in | Comment |
|---|---|---|
| `/UI2/CL_JSON` | `ZCL_MDMDOC_LLM`, `ZCL_MDMDOC_RULES`, `ZCL_MDMDOC_REPORT` | component **SAP_UI** (standard since NW 7.40 SP08). Without it LLM, JSON export and the JSON rules override are disabled — the core still works |
| `CL_ABAP_GZIP` | `ZCL_MDMDOC_PDF` | inflating FlateDecode PDF streams. **Check this first** (see §7) |
| `CL_ABAP_ZIP` | `ZCL_MDMDOC_FILE`, `ZCL_MDMDOC_PDF` | unpacking `.zip` containers, fallback inflation |
| `CL_ABAP_MESSAGE_DIGEST` | `ZCL_MDMDOC_FILE` | SHA-256 → document run id |
| `CL_HTTP_CLIENT` (`CREATE_BY_URL`) | `ZCL_MDMDOC_LLM` | Ollama calls `/api/tags`, `/api/chat` |
| `CL_HTTP_UTILITY` | `ZCL_MDMDOC_LLM`, `ZCL_MDMDOC_FILE` | base64 encode/decode (vision images, `.eml` attachments) |
| `CL_GUI_FRONTEND_SERVICES` | `ZMDMDOC`, `ZCL_MDMDOC_FILE` | picking/uploading a file from the PC, JSON download |
| `CL_ABAP_CONV_IN_CE` / `CL_ABAP_CODEPAGE` | `ZCL_MDMDOC_FILE`, `ZCL_MDMDOC_PDF` | xstring ↔ string (UTF-8 / Latin-1) |
| `CL_ABAP_REGEX` / `FIND REGEX` | `ZCL_MDMDOC_REGEX`, `ZCL_MDMDOC_RULES` | classic regex (**not PCRE** — 7.50 compatibility) |

There are no external Z-dependencies: the package is self-contained. The only internal
dependencies are the interface `ZIF_MDMDOC_TYPES` (part of the package) and the generated class
`ZCL_MDMDOC_RULES_DATA`.

> **One-shot check** (SE38 → create a throwaway report or use the console):
> make sure the classes `/UI2/CL_JSON`, `CL_ABAP_GZIP`, `CL_ABAP_ZIP` open in SE24.
> If `/UI2/CL_JSON` is missing — install the SAP_UI component, or use the system
> in deterministic mode (without LLM/JSON).

---

## 2. Import via abapGit

### 2.1. Prerequisites
1. Install abapGit (report `ZABAPGIT_STANDALONE` or the full version) — https://abapgit.org.
2. For online mode: configure SSL for github.com in **STRUST** (SSL client SSL Client (Standard))
   and enable the service in **SICF** if needed. Offline mode needs no SSL.
3. Create the target package:
   - SE80 → right-click → Create → Package → **`ZMDMDOC`** (or your Z-namespace);
   - Software Component `HOME` / `LOCAL`, assign a transport layer when moving between systems;
   - for local tests `$TMP` is acceptable (no transport).

### 2.2. Online import (if the repository is reachable over HTTPS)
1. abapGit → **New Online** → repository URL → Package `ZMDMDOC` → Branch `main`.
2. **Pull** → abapGit creates all package objects.
3. Activate everything: SE80 → package `ZMDMDOC` → Activate all (or Ctrl+F3 on the objects).

### 2.3. Offline import (ZIP)
1. Zip the repository contents (the `src/` folder is mandatory; `.abapgit.xml` in the root).
   Easiest: `git archive`, or download the ZIP from your git hosting.
2. abapGit → **New Offline** → Package `ZMDMDOC` → **Import ZIP** → pick the archive.
3. **Pull** → activate all objects.

### 2.4. What appears in the system
- Package `ZMDMDOC`.
- 5 programs: `ZMDMDOC` (executable report — the validator itself), `ZMDMDOC_RULES` (view/export
  the rules), `ZMDMDOC_SETUP` (all-in-one onboarding run, ch. 11), `ZMDMDOC_DOCTOR`
  (pre-flight tests, ch. 11), `ZMDMDOC_MDG_DISCOVER` (MDG mapping discovery, ch. 12).
- 2 interfaces: `ZIF_MDMDOC_TYPES`, `ZIF_MDMDOC_SAP_READER`.
- 20 classes:
  - 13 core validator classes: `ZCL_MDMDOC_FILE / _PDF / _SNIFF / _REGEX / _LLM / _EXTRACT /
    _RULES / _VERDICT / _MASK / _NORM / _REPORT / _COMPARE / _SAP_MANUAL`;
  - 2 generated: `ZCL_MDMDOC_RULES_DATA` (the rules from YAML), `ZCL_MDMDOC_GOLDEN_DATA`
    (golden corpus of test data);
  - 5 MDG-scenario classes: `ZCL_MDMDOC_MDG_READER`, `ZCL_MDMDOC_MDG_MAP`, `ZCL_MDMDOC_ONBOARD`,
    `ZCL_MDG_BP_FIELD_DERR_VAL`, `ZCL_MDMDOC_SELFTEST`.
- Message class (if added) `ZMDMDOC` for the verdict texts.

### 2.5. Post-import check

**Activation.** On a system with MDG all package objects activate. On a system **without MDG**
(plain ECC / S/4 without MDG) 7 objects reference USMD types and **will not activate**:
`ZCL_MDMDOC_MDG_READER`, `ZCL_MDMDOC_MDG_MAP`, `ZCL_MDMDOC_ONBOARD`,
`ZCL_MDG_BP_FIELD_DERR_VAL`, `ZMDMDOC_SETUP`, `ZMDMDOC_DOCTOR`, `ZMDMDOC_MDG_DISCOVER`.
This is expected: leave them inactive or delete them. The validator core (`ZMDMDOC` +
`ZMDMDOC_RULES` + the 13 core classes + the generated data classes + `ZCL_MDMDOC_SELFTEST`)
activates and works fully without them.

1. SE80 → package → select all classes → **Run → Unit Tests** (Ctrl+Shift+F10).
   All tests are `HARMLESS/SHORT`, no network or files — they must pass green.
2. SA38 → `ZMDMDOC` → the selection screen must open with no syntax errors.

---

## 3. Authorizations (role for the operator user)

Minimal set of authorization objects (PFCG role):

| Object | Values | Why |
|---|---|---|
| `S_TCODE` | `SA38` (or your own Z-transaction, see §4) | running the report |
| `S_GUI` | ACTVT `61` (Upload/Download) | reading a file from the PC, JSON download |
| `S_DATASET` | PROGRAM `ZMDMDOC*`, ACTVT `33`(read)/`34`(write), path filter | "application server" mode (`OPEN DATASET`) |
| `S_ICF` | ICF_FIELD `SERVICE`, value per your outbound-HTTP policy | Ollama calls (LLM mode only) |
| `S_DEVELOP` | dev system only | activation / unit tests |

If LLM is not used — `S_ICF` is not needed. If files come only from the PC — `S_DATASET` can be
withheld (the "application server" radio button simply won't work then — that is expected).

---

## 4. (Optional) Own transaction instead of SA38

So that operators do not need broad `SA38` access:
1. SE93 → create transaction **`ZMDMDOC`** → type "Program and selection screen (report transaction)"
   → Program `ZMDMDOC`.
2. In the role grant `S_TCODE` = `ZMDMDOC` instead of `SA38`.

---

## 5. (Optional) Configuring outbound HTTP to Ollama

Needed **only** if you enable LLM mode (model-based field extraction and reading scans).

### 5.1. Where Ollama must run
`CL_HTTP_CLIENT=>CREATE_BY_URL` opens the connection **from the SAP application server**, not from
the operator's PC. So the URL must be reachable from the application server itself:
- Ollama on the same host as the app server (e.g. a local ABAP Developer Trial in Docker):
  `http://localhost:11434`.
- Ollama on another host in the network: start it as `OLLAMA_HOST=0.0.0.0 ollama serve`,
  URL `http://<host-or-IP>:11434`.

### 5.2. Models
```bash
ollama pull qwen3:4b        # text model — extracts fields from document text
ollama pull qwen2.5vl:7b    # vision — transcribes scanned images (.png/.jpg)
```

### 5.3. HTTP vs HTTPS
- **Plain HTTP** (`http://…:11434`): no extra setup — this is an outbound call,
  **no SM59 destination and no SICF service are required**. Network reachability and `S_ICF` are enough.
- **HTTPS**: the endpoint's CA certificate must be added to **STRUST** → "SSL client SSL Client (Standard)"
  (or whichever PSE your profile uses), otherwise the TLS handshake fails.

### 5.4. Proxy
If outbound traffic goes through a corporate proxy — set it in the
`CREATE_BY_URL( proxy_host = … proxy_service = … )` call. In the current version the proxy
parameters are empty (direct connection). If a proxy is needed — this is the single place to
change in `ZCL_MDMDOC_LLM` (the client-creation method); deliberately kept narrow.

### 5.5. Availability check
On the selection screen tick the LLM checkbox and enter the URL. The program first performs
`GET /api/tags` (5 s timeout). If Ollama is unreachable — you get finding `LLM-001` and the program
continues in deterministic mode (regex-only). In other words, a wrong HTTP setup **does not break**
the run, it degrades to model-free mode.

---

## 6. Embedding into processes

### 6.1. Background job (SM36/SM37)
1. Create a variant of report `ZMDMDOC` (file — from the **application server**, since there is no
   PC session in background; "application server" radio + a path on the application server).
2. For background runs enable the "strict mode" checkbox: on a REJECT verdict the program issues
   `MESSAGE TYPE 'E'` → the job goes to status **Canceled** (the machine-readable analogue of the
   Python version's "exit code 1"). On ACCEPT/WARNING the job finishes successfully.
3. The job status in SM37 is the "return code" for your scheduler.

Mapping of the Python original's exit codes to SAP statuses:

| Python `mdmdoc` | ZMDMDOC (background, strict mode) |
|---|---|
| 0 ACCEPT | job Finished, MESSAGE S |
| 1 REJECT | job **Canceled** (MESSAGE E) |
| 2 REVIEW/WARNING | job Finished, MESSAGE "W" |
| 3 LLM unavailable | finding `LLM-001`, job Finished |
| 4 unreadable document | finding `EXT-001`/`EXT-002`, job Finished |

### 6.2. Calling from other ABAP code
```abap
SUBMIT zmdmdoc
  WITH p_file  = '/interface/in/vendor_bank_letter.pdf'
  WITH rb_srv  = abap_true       " file from the application server
  WITH rb_auto = abap_true       " document class auto-detection
  WITH cb_llm  = abap_false      " deterministic mode
  AND RETURN.

DATA lv_verdict TYPE string.
DATA lv_json    TYPE string.
IMPORT verdict = lv_verdict
       json    = lv_json
  FROM MEMORY ID 'ZMDMDOC_RESULT'.
" lv_verdict ∈ { ACCEPT | REJECT | WARNING | NEED_MANUAL_REVIEW }
" lv_json    = report in mdmdoc.v1 format (when cb_json = abap_true)
```

### 6.3. Calling the classes directly (no screen)
The pipeline logic lives in the classes; the report is only a thin wrapper. For fully programmatic
use (e.g. from a workflow or an RFC wrapper) call the classes directly in this order:
`ZCL_MDMDOC_FILE=>read` → `unwrap` → `ZCL_MDMDOC_PDF=>extract_text`
→ `ZCL_MDMDOC_SNIFF=>sniff_doc_class` → `ZCL_MDMDOC_REGEX=>extract_candidates`
→ (opt.) `ZCL_MDMDOC_LLM->extract_fields` → `ZCL_MDMDOC_EXTRACT=>build`
→ `NEW ZCL_MDMDOC_RULES( )->run` → `ZCL_MDMDOC_VERDICT=>decide`
→ `ZCL_MDMDOC_REPORT=>build_list / build_json`.
Exact signatures — see [docs/CONTRACT.md](CONTRACT.md).

### 6.4. RFC wrapper for external systems (if needed)
If the document arrives from an external system (e.g. from middleware together with the file
bytes), wrap the class calls in an RFC-enabled function module: input — the `XSTRING` file content
+ the file name, output — the verdict and the JSON. That is ~30 lines on top of the existing
classes; deliberately not part of the delivery (every landscape has its own integration contract),
but the architecture is ready for it: `ZCL_MDMDOC_FILE` can already take an `xstring` directly in
the `ty_doc` structure.

---

## 7. Verification order on the target system (risks)

Verify in this order — from the riskiest item to the standard ones:

1. **`CL_ABAP_GZIP=>DECOMPRESS_BINARY` with zlib streams (RFC 1950).**
   PDF uses FlateDecode = zlib, not gzip. `ZCL_MDMDOC_PDF` tries three inflation strategies
   (direct → strip the zlib header + synthetic gzip envelope → synthetic ZIP via
   `CL_ABAP_ZIP`). If all three fail on your kernel — only PDFs with uncompressed streams are
   readable; the workaround is in the README (re-export the PDF via "print to PDF"). Test on a
   real compressed PDF in dev.
2. **`/UI2/CL_JSON`** is present (SAP_UI component). Missing → LLM/JSON/override are disabled,
   the core works.
3. **`CL_ABAP_ZIP`** — behaviour on a CRC mismatch (for `.zip` containers and PDF strategy 3).
4. Everything else (`CL_ABAP_MESSAGE_DIGEST`, `CL_HTTP_CLIENT`, `CL_HTTP_UTILITY`,
   `CL_GUI_FRONTEND_SERVICES`) — standard since 7.40, low risk.

---

## 8. Updating the rules after installation

The full guide is in [docs/RULES.md](RULES.md) (view in SAP, change, delete, swap a "skill").
In short:

- **View in SAP:** report `ZMDMDOC_RULES` (list of all rules + JSON export).
- **Permanent change** (with transport): edit `rules/banking.yaml` / `rules/w9.yaml`,
  `python3 tools/gen_rules_abap.py`, abapGit Pull, activate, transport.
- **Governance-tier shipping profile:** the generator can filter by tier:
  `python3 tools/gen_rules_abap.py --tier-min corp` emits only `tier: corp` rules
  (dropping the experimental `BNK-002`, `BNK-030`). The **default** generation ships the full
  set, including those two experimental rules, — a deliberate operator decision.
  Rules without a tier tag always pass the filter.
- **Quick fix without transport**: `ZMDMDOC_RULES` → export → edit the file → the
  "rules override" parameter (`p_rules`) of report `ZMDMDOC` → loaded via `/UI2/CL_JSON`.
  Broken JSON → warning + fallback to the built-in rules.
- **Per-class "skill" swap:** each document type is a separate set. A file `rules/w9.rules.json`
  (only `rules_w9`) replaces **only** W-9, the banking module stays default (and vice versa) —
  the override is now partial. Handy when "one type misbehaves — swap only its pack".
  Export of a single class: `ZMDMDOC_RULES` with the `W-9 only` / `Banking only` radio.

---

## 9. Implementation checklist

- [ ] ABAP ≥ 7.50, abapGit installed.
- [ ] Package `ZMDMDOC` created, transport layer assigned (or `$TMP` for testing).
- [ ] `/UI2/CL_JSON`, `CL_ABAP_GZIP`, `CL_ABAP_ZIP` open in SE24.
- [ ] Import via abapGit → activation without errors (on a system without MDG the 7 MDG objects
      do not activate — that is expected, see §2.5).
- [ ] Package unit tests green (Ctrl+Shift+F10).
- [ ] `ZMDMDOC` starts from SA38, the screen opens.
- [ ] Operator role: `S_TCODE`, `S_GUI`, `S_DATASET` for server-side files, `S_ICF` for LLM.
- [ ] (LLM) Ollama reachable **from the application server**, models `qwen3:4b` + `qwen2.5vl:7b` pulled.
- [ ] (LLM+HTTPS) CA certificate in STRUST.
- [ ] Smoke test: run a real `bank_letter.pdf` → get a verdict; with LLM enabled —
      run a `.png` scan → check the transcription.
- [ ] (Background) variant with a server path + strict mode → check the status in SM37.

---

## 10. Embedding into SAP MDG (Change Request cross-check via BAdI)

A separate scenario: not a standalone report, but an **automatic check inside MDG**. The user
creates a customer/vendor in Fiori as a Change Request and attaches a document (bank letter / W-9)
to the request. When the request is checked, the system reads the attachment, extracts the details,
reads the CR's own data (name, address, bank, tax) and **raises a warning** in the request's
message log on mismatches.

> **All verified system facts, their sources, and the still-open questions live in
> [docs/MDG_SYSTEM_FACTS.md](MDG_SYSTEM_FACTS.md).** Read it before changing anything in the MDG
> path. What follows is the short version.

### 10.0. Two facts verified in the system (they drive the whole design)

Checked on **MDQ/100** (SE18 / SE24) — do not "improve" the design without re-checking these:

1. **BAdI `USMD_RULE_SERVICE` is NOT Multiple Use** (SE18 → Usability; Instance Creation Mode =
   *Reusing Instantiation*). That is a **per-filter-combination** rule, not a global one: the system
   in fact carries **53 implementations**, separated by filter (data model + entity type — e.g.
   `ZMDG_BP_BP_BKDTL_IMPL`, `ZMDG_BP_BP_CENTRL_IMPL`, `ZMDG_GTS_BP_VALIDATION`,
   `ZBADI_MDG_BP_DERIVATION_VALI`). → Never collide with a taken combination. Until the filter values
   are read (see MDG_SYSTEM_FACTS.md §C1), the **call-in into the existing BP implementation is the
   safe default**; registering our own implementation may become possible afterwards.
2. **`CHECK_CREQUEST_FINAL` is the right hook, not `CHECK_ENTITY`.** Verified signatures
   (SE24 `IF_EX_USMD_RULE_SERVICE` → Methods → Parameters):

   | method | importing | messages |
   |---|---|---|
   | `CHECK_CREQUEST_FINAL` (fires **once** per CR) | `id_edition`, `id_crequest`, `io_model`, `id_log_handle` | **no `et_message`** — write to the application log (BAL) via `id_log_handle` |
   | `CHECK_ENTITY` (fires per entity type **and** per record) | `io_model`, `id_edition`, `id_crequest`(opt), `id_entitytype`, `if_online_check`, `it_data` | `et_message TYPE usmd_t_message` |

   The interface has **11 methods** (`CHECK_ENTITY`, `CHECK_ENTITY_HIERARCHY`,
   `CHECK_CREQUEST_START`, `CHECK_CREQUEST`, `CHECK_CREQUEST_HIERARCHY`, `CHECK_CREQUEST_FINAL`,
   `CHECK_EDITION_START`, `CHECK_EDITION`, `CHECK_EDITION_HIERARCHY`, `CHECK_EDITION_FINAL`,
   `DERIVE_ENTITY`) — all must exist for a class to activate.

### 10.1. How it works

All the work lives in the plain service class **`ZCL_MDMDOC_MDG_CHECK`** (deliberately *not* a BAdI
implementation, see 10.0). It is called once per change request from
`IF_EX_USMD_RULE_SERVICE~CHECK_CREQUEST_FINAL`:

1. `ZCL_MDMDOC_MDG_READER( io_model, id_crequest )`.
2. `read_cr_attachments` → bytes of the CR attachment(s) (via GOS on the request object).
3. `read_cr_fields` → CR data via `io_model->read_entity_data_all` over the entities
   (name/address/bank/tax), mapped to SAP_KEYS through `ZCL_MDMDOC_MDG_MAP`.
4. For a PDF attachment: `ZCL_MDMDOC_PDF=>extract_text` → sniff → `ZCL_MDMDOC_REGEX` →
   `ZCL_MDMDOC_EXTRACT` (**LLM is off** — the BAdI is synchronous, no external HTTP; only the fast
   deterministic path). The parsed document is **cached by attachment SHA** because the BAdI runs
   under *Reusing Instantiation* and check methods may fire several times per session.
5. `ZCL_MDMDOC_COMPARE=>compare( doc, cr )` → findings `SAP-000..008`.
6. Findings → **application log** via `BAL_LOG_MSG_ADD` (message class `ZMDMDOC`, no. `001`).
   Everything is `W` by default; only with `iv_block = abap_true` does a REJECT finding become `E`.
   `SAP-000` (everything matched) is not shown.

The comparison logic fully reuses the core; the MDG specifics are concentrated in
`ZCL_MDMDOC_MDG_CHECK` + `ZCL_MDMDOC_MDG_READER` (+ the optional reference BAdI class).

### 10.2. Prerequisites

- SAP MDG active, data model **`BP`** (MDG-BP / MDG-Customer / MDG-Supplier).
- The base ZMDMDOC classes installed and activated (chapters 1–2).
- Message class **`ZMDMDOC`** (SE91), message `001` with text `&1&2&3&4` (the finding text is
  carried in MSGV1..MSGV4).

### 10.3. What to confirm on the dev system (VERIFY ON SYSTEM)

The MDG classes are deliberately **excluded from the offline abaplint check** (they use MDG
framework types that do not exist outside the system) and are marked in the code.

Already verified on MDQ/100 (see 10.0), no longer open: the `Multiple Use` flag, the type of
`io_model` (`IF_USMD_MODEL_EXT`), and the signatures of `CHECK_CREQUEST_FINAL` / `CHECK_ENTITY`.

Still to confirm before activation:

1. **Which implementation owns the `BP` filter value** — SE18 → `USMD_RULE_SERVICE` →
   `Implementations`. That is the class you paste the call-in into (10.5).
2. **The technical names of the entities and fields** of model `BP` (mapping table below) — from
   MDGIMG → "Edit Data Model" / tx `USMD_ENTITY`. Names differ between customers. Use
   `ZMDMDOC_MDG_DISCOVER` (chapter 12) to derive them automatically.
3. **The CR attachment API** — the request object type for GOS (`USMD_CREQ` in the template) and
   the class `CL_GOS_API` (or its alternative on your release). The method is written as a template
   with a graceful fallback: if the API is unavailable it returns an error, not a dump.
4. **Whether an `E` message in `CHECK_CREQUEST_FINAL`'s application log blocks the request.**
   The default is `W` only (`iv_block = abap_false`), so this is not on the critical path.

> The same enhancement spot also contains a second BAdI, `USMD_RULE_SERVICE_CROSS_ET`
> (interface `IF_EX_USMD_RULE_SERVICE2`, cross-entity-type validations). If its `Multiple Use` flag
> is set, it is an alternative home for this check that needs no call-in into a foreign class.

### 10.4. MDG-BP → SAP_KEYS mapping (to confirm)

| SAP_KEY | Entity (`read_entity_data_all`) | Field |
|---|---|---|
| account_holder / account_name | BP_CENTRL (or BP_HEADER) | NAME_ORG1(+2) / NAME_FIRST+LAST |
| street / city | ADDRESS | STREET / CITY1 |
| bank_country | BP_BANKDT | BANKS |
| bank_key | BP_BANKDT | BANKL |
| bank_account | BP_BANKDT | BANKN |
| control_key | BP_BANKDT | BKONT |
| iban | BP_IBAN (or BP_BANKDT) | IBAN |
| bank_name / swift_bic | from BANKS+BANKL → BNKA (active) | BANKA / SWIFT |
| tin (US) | BP_TAXNUM | TAXTYPE (US1/US2) + TAXNUM |

### 10.5. Installing — the call-in (recommended, because the BAdI is not Multiple Use)

1. Activate the base ZMDMDOC package (chapters 1–2), including `ZCL_MDMDOC_COMPARE`,
   `ZCL_MDMDOC_MDG_READER`, `ZCL_MDMDOC_MDG_CHECK`.
2. SE91 → message class `ZMDMDOC`, message `001` = `&1&2&3&4`.
3. SE18 → `USMD_RULE_SERVICE` → `Implementations` → find the class that owns the `BP` filter value
   (e.g. `ZCLMDG_GTS_BP_VALIDATION`). Open it in SE24 and paste **two lines** into its
   `IF_EX_USMD_RULE_SERVICE~CHECK_CREQUEST_FINAL` method:

   ```abap
   METHOD if_ex_usmd_rule_service~check_crequest_final.
     NEW zcl_mdmdoc_mdg_check( )->run_cr_check(
       io_model      = io_model
       id_crequest   = id_crequest
       id_log_handle = id_log_handle ).
   ENDMETHOD.
   ```

   Nothing else in that class changes. Activate.
4. Run `ZMDMDOC_MDG_DISCOVER` (chapter 12) to derive the real entity/field mapping into
   `ZMDMDOC_MAP`, then `ZMDMDOC_DOCTOR` with a test CR number to prove reading works.

**Only if the `BP` slot is free** you may instead activate the bundled reference implementation
`ZCL_MDG_BP_FIELD_DERR_VAL` (it implements all 11 interface methods and delegates from
`CHECK_CREQUEST_FINAL` to the same service). Do not activate it when another implementation already
holds the filter value — the BAdI is not Multiple Use.

> The technical names of entities and fields depend on the release and the configured data model,
> so the `c_ent_*` constants are only built-in defaults. `ZMDMDOC_MDG_DISCOVER` (chapter 12)
> proposes the real mapping of your system, and the `ZMDMDOC_MAP` table (created on the system)
> overrides the defaults without touching the code.

### 10.6. Authorizations and performance

- Runs in the context of the MDG request session — **no additional RFC/HTTP is needed** (LLM is
  disabled on the MDG path; no network is involved). Attachments/entities are read under the
  request user's authorizations.
- PDF parsing + regex take milliseconds. Execution is limited to the anchor entity and to PDF
  attachments only, so as not to slow down every check.

### 10.7. Where the result is visible

The warnings appear in the **Change Request message log** (Fiori "My Change Requests" / the request
UI). `W` does not block submit; `E` (if you enable it for hard mismatches) does.

### 10.8. Test on the system

1. Create a CR for a BP with bank data; attach a bank letter whose **IBAN differs** from the one
   entered in the request.
2. Press Check/Submit → the message log shows the warning `[SAP-001] IBAN mismatch …`
   (values are masked, e.g. `DE**…4931 vs DE**…4999`).
3. A matching document → no warnings (the internal `SAP-000` is not shown).

### 10.9. MDG implementation checklist

- [ ] Base ZMDMDOC package active (incl. COMPARE + both MDG classes).
- [ ] Message class `ZMDMDOC` / `001` created.
- [ ] Signature of `IF_EX_USMD_RULE_SERVICE~CHECK_ENTITY` and `read_entity_data_all` verified,
      code references adjusted where needed.
- [ ] Entity/field names of model `BP` verified (`c_ent_*`, the mapper), anchor entity chosen.
- [ ] CR attachment API (GOS/object type) confirmed and plugged in.
- [ ] BAdI implementation created (spot `USMD_RULE_SERVICE`), filter `USMD_MODEL = 'BP'`, active.
- [ ] End-to-end test: CR + attachment with a wrong IBAN → warning `SAP-001` in the request log.


---

## 11. Single onboarding script and pre-flight tests

### 11.0. ZMDMDOC_SETUP — "everything at once" (recommended entry point)

One report, **ZMDMDOC_SETUP** (SA38), runs the whole verification cycle in one go, in order:

1. **pre-flight tests** ("will it load / will it read data"),
2. **discovery** of the MDG field architecture (proposed mapping + uncovered keys),
3. (if `p_cr` is given) **live read of the request** — fields + attachments,
4. (flag `p_save`) writing the proposed mapping to `ZMDMDOC_MAP`.

**Parameters:** `p_model` (model, default `BP`), `p_cr` (CR number, opt.), `p_list` (show all
entities/fields), `p_save` (save the mapping). Output — a single colour-coded report with a
GO / NO-GO summary.

The standalone reports `ZMDMDOC_DOCTOR` (tests only) and `ZMDMDOC_MDG_DISCOVER` (mapping only) are
the same checks in focused form; all the logic lives in class `ZCL_MDMDOC_ONBOARD`.

### 11.1. ZMDMDOC_DOCTOR — pre-flight tests only

Before enabling the BAdI globally, run **ZMDMDOC_DOCTOR** (SA38) — a set of small independent
checks: "can it load / can it read the data". A red line immediately shows what exactly needs
fixing, without running the full validation.

**Parameters:** `p_model` (model, default `BP`), `p_cr` (CR number — optional, for a live check of
request reading).

**What it checks:**

- *Core (unit-tested, no MDG):* presence of `CL_ABAP_GZIP` / `CL_ABAP_ZIP` /
  `CL_ABAP_MESSAGE_DIGEST` / `CL_HTTP_CLIENT` / `ZCL_MDMDOC_COMPARE`; `/UI2/CL_JSON` round-trip;
  masking (an IBAN is never shown in full); text extraction from a test PDF; the comparator
  (artificial mismatch → `SAP-001`).
- *MDG:* presence of `IF_USMD_MODEL_EXT` / the MDG classes / `CL_GOS_API`; message class `ZMDMDOC/001`.
- *Live CR (if `p_cr` is given):* whether the request fields can actually be read (how many fields
  were read) and the attachments (how many attachments). This way you confirm that data and
  attachment reading work — separately, and **before** the check is switched on in the process.

Output — a PASS/FAIL/SKIP list with colours and an "N passed, M failed" summary. As long as
anything is red — do not enable the BAdI.

The core logic is factored into **`ZCL_MDMDOC_SELFTEST`** (a class with unit tests) — the same
checks can be invoked programmatically.

---

## 12. Adaptability: automatic field-mapping discovery (ZMDMDOC_MDG_DISCOVER)

MDG entity and field names differ between customers, so the mapping is **not hard-coded**:
`ZCL_MDMDOC_MDG_READER` takes the `SAP_KEY → entity.field` correspondence from class
**`ZCL_MDMDOC_MDG_MAP`** — first from the `ZMDMDOC_MAP` table (if created), otherwise from the
built-in defaults (standard MDG-BP names).

### 12.1. Discovery

Report **ZMDMDOC_MDG_DISCOVER** (SA38) reads the real architecture of the model (`p_model`, default
`BP`): it lists the entities and fields, then matches the real field names against a synonym list
(BANKS→bank_country, BANKL→bank_key, BANKN→bank_account, IBAN→iban, NAME_ORG1→account_holder,
STREET→street, CITY1→city, TAXNUM→tin…) and **proposes** a mapping. It shows: the entity/field
list (flag `p_list`), the proposed mapping, and the "uncovered keys" (what to fill in by hand).
Flag `p_save` — write the proposal to `ZMDMDOC_MAP`.

Order: `ZMDMDOC_MDG_DISCOVER` → review the proposal → adjust if needed →
save → `ZMDMDOC_DOCTOR` with a CR number (make sure the fields are readable) → enable the BAdI.

### 12.2. The ZMDMDOC_MAP table (optional, create in SE11)

A transparent customizing table (type "Customizing", delivery class `C`). If it does not exist —
the defaults apply. Key fields:

| Field | Type (example) | Key | Meaning |
|---|---|---|---|
| MODEL | USMD_MODEL (CHAR 30) | X | data model (e.g. BP) |
| SAP_KEY | CHAR 40 | X | SAP_KEY key (iban, bank_key, account_holder…) |
| ENTITY | USMD_ENTITY (CHAR 30) | | MDG entity |
| FIELD | USMD_FIELDNAME (CHAR 30) | | field within the entity |

`ZCL_MDMDOC_MDG_MAP` reads it **dynamically** (`SELECT … FROM ('ZMDMDOC_MAP')`), so the classes
activate and work even when the table does not exist.

### 12.3. What to confirm (verify-on-system)

`ZMDMDOC_MDG_DISCOVER` uses `cl_usmd_model_ext=>get_instance` / `get_entities` /
`create_data_reference` — verify these calls against your MDG release (marked in the code). Fields
are read via RTTI of the entity structure, so the field names themselves are discovered
automatically — only the way the entity list is obtained needs adjusting if the API differs.

### 12.4. Addendum to the MDG implementation checklist

- [ ] `ZMDMDOC_DOCTOR` without `p_cr` — core green.
- [ ] (Opt.) `ZMDMDOC_MAP` created in SE11 (MODEL/SAP_KEY/ENTITY/FIELD).
- [ ] `ZMDMDOC_MDG_DISCOVER` (`p_model=BP`) — mapping proposed, uncovered keys closed.
- [ ] `ZMDMDOC_DOCTOR` with a test CR number — "read CR fields" and "read CR attachments" green.
- [ ] Only after that — activate the BAdI.

---

## 13. Full list of tests

### 13.1. Pre-flight checks (ZMDMDOC_SETUP / ZMDMDOC_DOCTOR)

Each check is independent and returns PASS / FAIL / SKIP.

**Core (unit-tested, no SAP MDG — `ZCL_MDMDOC_SELFTEST`):**

| Check | What it confirms |
|---|---|
| `CL_ABAP_GZIP` available | inflating compressed PDF streams |
| `CL_ABAP_ZIP` available | unpacking `.zip` containers |
| `CL_ABAP_MESSAGE_DIGEST` available | SHA-256 (run id) |
| `CL_HTTP_CLIENT` available | Ollama calls (LLM mode) |
| `ZCL_MDMDOC_COMPARE` available | comparator installed |
| `ZIF_MDMDOC_SAP_READER` available | source adapter installed |
| `/UI2/CL_JSON` round-trip | JSON serialization works |
| masking | an IBAN is never printed in full |
| PDF text extraction | the parser lifts the text from a test PDF |
| comparator | artificial mismatch → `SAP-001` |

**MDG (verify-on-system):**

| Check | What it confirms |
|---|---|
| `IF_USMD_MODEL_EXT` available | the MDG framework is in place |
| `ZCL_MDMDOC_MDG_READER` / `ZCL_MDG_BP_FIELD_DERR_VAL` available | the MDG classes are installed |
| `CL_GOS_API` available | reading request attachments |
| message class `ZMDMDOC / 001` | messages for the CR log exist |
| MDG model read (`p_model`) | the model is readable, entities/fields visible |
| read CR fields (`p_cr`) | **request fields are actually read** (how many) |
| read CR attachments (`p_cr`) | **attachments are actually read** (how many) |

### 13.2. ABAP Unit tests (in the system: Ctrl+Shift+F10 on the package)

Local test classes on every class, `RISK LEVEL HARMLESS DURATION SHORT`, no network/files/GUI.
**209 test methods** in total (recount on your system with the package-level ABAP Unit run —
the number grows with updates):

| Class | Tests | Coverage |
|---|---:|---|
| ZCL_MDMDOC_RULES | 31 | rules engine, all when-operators, predicates, RU messages, JSON override, partial skill swap |
| ZCL_MDMDOC_EXTRACT | 25 | overlay regex-overrides-LLM, crosscheck, guard heuristics |
| ZCL_MDMDOC_MASK | 23 | SSN/EIN/IBAN/account masks, display policy, scrub, leak gate |
| ZCL_MDMDOC_SNIFF | 22 | document class/type, invoice/letter/W-8 heuristics |
| ZCL_MDMDOC_VERDICT | 19 | verdict precedence, next_step EN/RU, message_type |
| ZCL_MDMDOC_FILE | 18 | classify_ext, .eml/.zip parsing, sha16 |
| ZCL_MDMDOC_COMPARE | 16 | SAP-000..008 cross-check (IBAN/account/SWIFT/country/bank key/name), masking |
| ZCL_MDMDOC_REGEX | 13 | IBAN/SWIFT/routing/EIN/boxed-TIN extraction |
| ZCL_MDMDOC_NORM | 13 | IBAN mod-97, to_iso2, classification, date parsing |
| ZCL_MDMDOC_LLM | 11 | Ollama response parsing (behind a test double, no network) |
| ZCL_MDMDOC_REPORT | 7 | list/JSON, SAP COMPARISON block, masking |
| ZCL_MDMDOC_PDF | 5 | synthetic PDFs (uncompressed stream, /Encrypt, page counter) |
| ZCL_MDMDOC_SAP_MANUAL | 3 | JSON→fields, end-to-end compare run |
| ZCL_MDMDOC_SELFTEST | 2 | core of the pre-flight checks |
| ZCL_MDMDOC_GOLDEN_DATA | 1 | golden parity: the shared golden corpus through regex→extract→rules→verdict, fields/crosscheck notes/verdict match the Python engine |

For the developer: `npx --yes @abaplint/cli` — static syntax check (0 errors; the MDG classes are
excluded as verify-on-system). ABAP Unit runs only on the system.

### 13.3. Recommended order during rollout

1. Import the package → activation → **ABAP Unit** on the package (Ctrl+Shift+F10) — all 209 tests
   green (the number grows with updates).
2. **ZMDMDOC_SETUP** without `p_cr` — core + discovery green, review the proposed mapping.
3. If needed, create/fill `ZMDMDOC_MAP`, repeat `ZMDMDOC_SETUP` with `p_save`.
4. **ZMDMDOC_SETUP** with a test `p_cr` number — "read CR fields" and "read CR attachments" green.
5. Only after GO — activate the BAdI (chapter 10).
