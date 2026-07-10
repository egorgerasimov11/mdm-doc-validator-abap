# mdm-doc-validator-abap (ZMDMDOC)

> Русская версия: [README.ru.md](README.ru.md) · Handing the project over? Start at [HANDOFF.md](HANDOFF.md)

ABAP twin of the local bank-document / W-9 validator
(the Python original, `mdm-doc-validator`, is the reference implementation).
No web panel: a classic Z-report — the user points at a document file, the program
reads it, extracts the banking/tax identifiers and folds a verdict from declarative,
human-approved rules.

```
SA38 → ZMDMDOC → file path → F8
────────────────────────────────────
[BANK DOC VERDICT]
Document   : vendor_bank_letter.pdf
Doc type   : bank_letter
Verdict    : WARNING
Why        : Bank letter appears unsigned/unstamped (no officer block either).
Next step  : usable with caution — note the warnings for the Data Owner
...
IBAN       : IT**…8412 (country IT, len 27)
```

## What's inside

Validator core (runs on any system ≥ 7.50):

| Component | Purpose |
|---|---|
| `ZMDMDOC` (report) | the "CLI": selection screen, pipeline orchestration, output, JSON export |
| `ZMDMDOC_RULES` (report) | view/export the ACTIVE rule set directly in SAP |
| `ZCL_MDMDOC_FILE` | file read (PC / application server), SHA-256 run id, `.zip`/`.eml` unwrap |
| `ZCL_MDMDOC_PDF` | PDF text-layer extraction in pure ABAP (FlateDecode + BT/ET + ToUnicode) |
| `ZCL_MDMDOC_SNIFF` | document class auto-detection (bank / w9) and type (invoice, bank_letter, w8…) |
| `ZCL_MDMDOC_REGEX` | deterministic ID extraction: IBAN, SWIFT, routing/ABA, account, EIN/SSN, boxed TIN |
| `ZCL_MDMDOC_LLM` | optional Ollama client (`/api/chat`): text-model field extraction, vision for scans |
| `ZCL_MDMDOC_EXTRACT` | merge: regex candidates cross-check the model read + deterministic guards, normalization |
| `ZCL_MDMDOC_NORM` | normalizers: ISO2 countries, mod-97, dates, classifications, names |
| `ZCL_MDMDOC_RULES` | rule engine: the original's YAML rules compiled to ABAP + runtime JSON override |
| `ZCL_MDMDOC_VERDICT` | verdict fold: REJECT > NEED_MANUAL_REVIEW > WARNING > ACCEPT |
| `ZCL_MDMDOC_MASK` | PII masking (TIN — always), leak gate over the output JSON |
| `ZCL_MDMDOC_REPORT` | text report + JSON in the `mdmdoc.v1`-compatible format |
| `ZCL_MDMDOC_COMPARE` | character-level document ↔ SAP/CR data comparison (rules SAP-000..009) |
| `ZCL_MDMDOC_SAP_MANUAL` | manual/test-double SAP reader (`ZIF_MDMDOC_SAP_READER`): fields from a table or flat JSON — the comparator runs without a live MDG |
| `ZCL_MDMDOC_RULES_DATA` | **generated** from `rules/*.yaml` — never edit by hand |
| `ZCL_MDMDOC_GOLDEN_DATA` | **generated**: the Python↔ABAP golden parity corpus (test data) |

MDG scenario (MDG systems only; on other systems these objects do not activate — see Install):

| Component | Purpose |
|---|---|
| `ZCL_MDG_BP_FIELD_DERR_VAL` | BAdI implementation `USMD_RULE_SERVICE` — Change Request attachment check |
| `ZCL_MDMDOC_MDG_READER` + `ZIF_MDMDOC_SAP_READER` | CR field + GOS attachment reads (verify-on-system) |
| `ZCL_MDMDOC_MDG_MAP` | SAP_KEY → model entity/field mapping (defaults + custom table `ZMDMDOC_MAP`) |
| `ZCL_MDMDOC_ONBOARD` / `ZCL_MDMDOC_SELFTEST` | pre-flight GO/NO-GO checks |
| `ZMDMDOC_SETUP` / `ZMDMDOC_DOCTOR` / `ZMDMDOC_MDG_DISCOVER` (reports) | onboarding, self-check, MDG model discovery |

Package `ZMDMDOC` total: **5 programs, 2 interfaces, 20 classes** (13 core + 2
generated + 5 MDG-scenario) + message class `ZMDMDOC`.

## Requirements

- SAP NetWeaver / S/4HANA, **ABAP ≥ 7.50** (classic regex, no PCRE — also runs on ECC EhP8).
- [abapGit](https://abapgit.org) for the import.
- `/UI2/CL_JSON` (component SAP_UI — standard since 7.40 SP08). Without it: LLM calls,
  JSON export and the rules override are disabled; the core (regex + rules + verdict)
  still works.
- Optional: [Ollama](https://ollama.com) for LLM field extraction and reading scans.

## Install

1. abapGit → New Online (or ZIP import of this repository) → package `ZMDMDOC` → Pull.
2. Activate the objects. **On a system without MDG**, the 7 MDG-scenario objects
   (table above) reference USMD types and **will not activate** — leave them inactive
   or delete them; the validator core works fully without them. On an MDG system
   everything activates.
3. Run the package unit tests: `Ctrl+Shift+F10` in ADT — expect **209 green**
   (all `HARMLESS/SHORT`, no network/files; the number grows with updates — recount
   on your system).
4. Run: SA38 → `ZMDMDOC`. For the first run see `samples/README.md` (demo document).

### Optional: local Ollama (LLM extraction + scans)

```bash
brew install ollama          # or curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen3:4b         # text model (field extraction)
ollama pull qwen2.5vl:7b     # vision (scan transcription)
```

**Important:** the URL in the "Ollama URL" parameter must be reachable **from the SAP
application server, not from your SAPGUI PC**. `http://localhost:11434` only works when
Ollama runs on the application server itself (e.g. a local ABAP Developer Trial in Docker
on the same machine). For Ollama on another host: `OLLAMA_HOST=0.0.0.0 ollama serve` and
URL `http://<host>:11434`. HTTPS endpoints need the CA certificate in STRUST (SSL client
PSE); plain HTTP needs nothing (outbound call — no SM59/SICF required).

## Usage

Selection screen:

- **Input**: file path; radio "PC" (`gui_upload`) / "application server" (`OPEN DATASET`).
- **Classification**: auto / force bank / force w9; output language EN/RU.
- **LLM (optional)**: checkbox + URL/models/timeout. Off → deterministic mode
  (regex extraction, narrative fields empty, NOTE `LLM-002`).
- **Output**: JSON file (mdmdoc.v1-compatible), path to a rules-override JSON,
  strict mode for background jobs.

Supported inputs: `.pdf` (text layer), images `.png/.jpg/...` (LLM-vision only),
`.zip` / `.eml` (best embedded document is taken). Editable formats
(`.docx/.xlsx/.txt/...`) are rejected by rule BNK-003 — same as the original.

**W-8 forms:** W-8BEN/-E is recognized (doc_type `w8`) and rule `W9-030` always routes it
to `NEED_MANUAL_REVIEW` — the W-8 compliance policy is deliberately not automated in v1.

### Python exit-code equivalents

| Python `mdmdoc` | ZMDMDOC |
|---|---|
| 0 ACCEPT | MESSAGE type S |
| 1 REJECT | MESSAGE S `DISPLAY LIKE 'E'`; in background with the "strict" flag — a real type E (job → Canceled) |
| 2 REVIEW/WARNING | MESSAGE S `DISPLAY LIKE 'W'` |
| 3 LLM unreachable | finding `LLM-001` (NEED_MANUAL_REVIEW) |
| 4 unreadable document | finding `EXT-001`/`EXT-002` (NEED_MANUAL_REVIEW) |

Programmatic call: `SUBMIT zmdmdoc ... AND RETURN`, then
`IMPORT verdict json FROM MEMORY ID 'ZMDMDOC_RESULT'`.

## Rules

Source of truth: `rules/banking.yaml` and `rules/w9.yaml` (copies of the Python
original's rules). Changing rules:

```bash
# edit the YAML, then:
python3 tools/gen_rules_abap.py     # regenerates src/zcl_mdmdoc_rules_data.clas.abap + rules/rules.json
# → abapGit Pull into the system
```

**Governance profile (tier).** Every rule carries `tier: corp|experimental|learned`.
`python3 tools/gen_rules_abap.py --tier-min corp` produces the strict corp profile
(drops the experimental `BNK-002` and `BNK-030`). **The DEFAULT generation ships the
full set including both experimental rules** — a deliberate operator decision
(BNK-030 is a safe manual-review backstop for unrecognized documents). Rules without
a tier always pass the filter.

Quick change without a transport: edit `rules/rules.json` and point the
"rules override" parameter at it — the rules load at runtime via `/UI2/CL_JSON`
(broken JSON → warning + fallback to the compiled rules).

**Rules as swappable "skills".** Each document type is a separate pack:
`rules/banking.rules.json` and `rules/w9.rules.json`. The override is **partial** —
a file with only `rules_w9` swaps just the W-9 pack, the banking module stays
(and vice versa). View/export rules inside SAP — report `ZMDMDOC_RULES`.
Full guide: [docs/RULES.md](docs/RULES.md).

## Masking (by design, not configurable)

- TIN (SSN/EIN) is **never** shown in full — not in the list output, the JSON or the notes.
- IBAN/account/routing are masked (`DE**…4931`, `…6971`); a leak gate scans the final JSON
  before it is written and cancels the export on a leak.

## Limitations

- **Scanned PDFs without a text layer** are not read (ABAP has no page rasterizer) —
  finding `EXT-001`. Workaround: convert the page to PNG and enable LLM-vision, or OCR
  outside.
- Image scans are read **only** with LLM enabled (vision model).
- PDFs with CID fonts and no ToUnicode map: text in those fonts is skipped (warning).
- Password-protected PDFs → `EXT-003`.
- `.msg` (Outlook) is not supported — re-save as `.eml` or extract the attachment (`EXT-005`).
- Text order ≈ object order inside the PDF (sufficient for keyword scoring and
  label-window regex; not for human reading).
- First things to verify on the target system: `CL_ABAP_GZIP=>DECOMPRESS_BINARY` with
  zlib streams (RFC 1950) — compressed-PDF reading depends on it (three fallback
  strategies inside `ZCL_MDMDOC_PDF`); then `/UI2/CL_JSON`; then `CL_ABAP_ZIP` behavior
  on CRC mismatch. Everything else is standard since 7.40.

## Change Request comparison (MDG)

Additionally the document can be compared against **MDG Change Request** data: on the CR
check (BAdI `USMD_RULE_SERVICE` → `ZCL_MDG_BP_FIELD_DERR_VAL`) the system reads the CR
attachment, extracts the identifiers, reads the CR's own fields
(`io_model->read_entity_data_all`) and emits **warnings** on mismatches
(IBAN/SWIFT/account/name/country…). The comparison logic (`ZCL_MDMDOC_COMPARE`, rules
`SAP-000..009`) is source-independent and unit-tested; the MDG specifics are isolated in
`ZCL_MDMDOC_MDG_READER` + the BAdI class (marked verify-on-system, outside abaplint).
Implementation guide — **chapter 10 of [docs/INTEGRATION.md](docs/INTEGRATION.md)**.

**Adaptivity and pre-flight tests.** The MDG field mapping is not hardcoded:
`ZMDMDOC_MDG_DISCOVER` reads the real model and proposes the `SAP_KEY → entity.field`
mapping (custom table `ZMDMDOC_MAP`, defaults otherwise). `ZMDMDOC_DOCTOR` is a set of
small "will it load / can it read data" checks (core = the testable
`ZCL_MDMDOC_SELFTEST`) to run before enabling the BAdI. Chapters 11–12 of INTEGRATION.md.

## What was deliberately NOT ported

Web panel/REST API, the teach loop (review → labels → few-shot → LoRA → adoption gate),
the eval framework, web enrichment. Intentional scope: the ABAP twin = the validation
pipeline.

## Development

```bash
npx --yes @abaplint/cli           # syntax check (config abaplint.json, target v750)
python3 tools/gen_rules_abap.py   # rules regeneration (deterministic)
```

Public class API contract: `docs/CONTRACT.md`. Project handover: `HANDOFF.md`.
