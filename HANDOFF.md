# ZMDMDOC — Project Handover

**Audience:** the SAP/ABAP developer receiving this repository for implementation
on a corporate system. **Read this file first**, then [README.md](README.md), then
[docs/INTEGRATION.md](docs/INTEGRATION.md) when you get to the MDG scenario.

The component: a deterministic bank-document / W-9 validator (Z-report `ZMDMDOC`,
package `ZMDMDOC`, target ABAP ≥ 7.50, classic regex only — no PCRE) plus an
optional MDG Change-Request integration (BAdI skeleton). The verdict always comes
from a declarative, human-approved rule set; an optional local LLM only reads
text — it never decides.

---

## 1. Readiness matrix — what is DONE vs what is YOURS

| Layer | Status | Notes |
|---|---|---|
| Validator core: 13 classes (+2 generated data classes) + `ZMDMDOC` + `ZMDMDOC_RULES` reports | **DONE, tested** | 209 ABAP Unit tests, all `HARMLESS/SHORT`, no network/file/customizing dependencies |
| Rules data (`ZCL_MDMDOC_RULES_DATA`) + runtime JSON override | **DONE** | generated from `rules/*.yaml`; see [docs/RULES.md](docs/RULES.md) |
| Golden parity corpus (`ZCL_MDMDOC_GOLDEN_DATA`) | **DONE** | generated test data proving behavioral parity with the Python reference |
| PDF text-layer extraction (`ZCL_MDMDOC_PDF`) | **DONE, one on-system check** | `CL_ABAP_GZIP` smoke test is YOUR first task — see §3 item 2 |
| Optional LLM leg (`ZCL_MDMDOC_LLM`) | **DONE, off by default** | plain outbound HTTP; no SM59/SICF needed for HTTP |
| MDG scenario: BAdI + CR reader + mapping + pre-flight tools (7 objects) | **SKELETON — verify-on-system** | compiles against USMD types; release-dependent seams are yours (§3 items 5-10) |
| Message class `ZMDMDOC` | shipped as `zmdmdoc.msag.xml` | verify it imported; otherwise create via SE91 (§3 item 5) |
| Customizing table `ZMDMDOC_MAP` | **NOT shipped — create in SE11** | exact DDL in §4; everything works on built-in defaults without it |
| BAdI enhancement implementation (SE18/SE19 binding) | **NOT shipped — manual** | §3 item 10 |

**Bottom line:** on ANY system you can import, activate the core, run 209 green
tests and validate documents the same day. The MDG scenario is a guided
implementation project (the seams are isolated, documented and pre-flight-tested
by `ZMDMDOC_DOCTOR`), not a turnkey install.

## 2. Import & first run (any system, ~30 minutes)

1. abapGit → New Online (or ZIP import) → package `ZMDMDOC` → Pull.
2. Activate. **No MDG on the box?** The 7 MDG objects (`ZCL_MDMDOC_MDG_READER`,
   `ZCL_MDMDOC_MDG_MAP`, `ZCL_MDMDOC_ONBOARD`, `ZCL_MDG_BP_FIELD_DERR_VAL`,
   `ZMDMDOC_SETUP`, `ZMDMDOC_DOCTOR`, `ZMDMDOC_MDG_DISCOVER`) reference USMD types
   and will not activate — leave them inactive or delete them. The core does not
   need them.
3. ABAP Unit on the package (`Ctrl+Shift+F10` in ADT): expect **209 green** (recount
   on your system — the number grows with updates). Reds
   in the LLM/JSON test classes usually mean `/UI2/CL_JSON` (SAP_UI) is missing.
4. First verdict: upload `samples/sample_bank_letter.pdf` from this repo to your
   PC, then SA38 → `ZMDMDOC` → file path → F8. Expected output is documented in
   [samples/README.md](samples/README.md).

Authorizations for an operator: `S_TCODE` (SA38/ZMDMDOC), `S_GUI` (ACTVT 61 for PC
upload), `S_DATASET` (only for app-server files), `S_ICF` (only if the LLM leg is
used).

## 3. On-system checklist (in order)

1. **Import + activate + 209 green tests** (§2).
2. **`CL_ABAP_GZIP=>DECOMPRESS_BINARY` smoke test — the #1 risk.** Unit tests
   cover only uncompressed PDFs; real-world PDFs are FlateDecode-compressed.
   First probe ships in the repo: `samples/sample_invoice.pdf` is deliberately
   compressed — expect verdict REJECT/`BNK-001`; empty text instead means the
   kernel's zlib path needs investigation. Then repeat on a REAL vendor PDF
   (they vary more). `ZCL_MDMDOC_PDF` already tries three inflate strategies;
   workaround: print-to-PDF re-save, or the LLM-vision path.
3. **`/UI2/CL_JSON` present?** Standard since 7.40 SP08. Without it the core still
   validates; LLM, JSON export and the rules override are disabled.
4. **Optional LLM:** stand up Ollama reachable **from the application server**
   (not your SAPGUI PC): `ollama pull qwen3:4b` (+ `qwen2.5vl:7b` for scans).
   HTTPS endpoints need the CA cert in STRUST; plain HTTP needs nothing.
5. **Message class `ZMDMDOC`** — shipped in the repo (`zmdmdoc.msag.xml`, message
   `001 = &1&2&3&4`). Verify it imported with the pull; if your abapGit build
   skipped it, create it in SE91 (1 message). The BAdI's CR-log messages depend
   on it.
6. **MDG only — confirm the BAdI signature.** `ZCL_MDG_BP_FIELD_DERR_VAL`
   implements `IF_EX_USMD_RULE_SERVICE~CHECK_ENTITY`; parameter names
   (`io_model`, `i_crequest`, `i_fieldname`, `ct_message`) vary between MDG
   releases — align with SE18 on your system.
7. **MDG only — GOS attachment read.** `ZCL_MDMDOC_MDG_READER` reads CR
   attachments via GOS with object type `USMD_CREQ` — confirm the object type and
   `CL_GOS_API` availability on your release.
8. **MDG only — entity/field names.** Built-in defaults are standard MDG-BP names
   (see §4). Run `ZMDMDOC_MDG_DISCOVER` against your model (`BP`) — it reads the
   real model and proposes the mapping; persist overrides to `ZMDMDOC_MAP` (§4)
   or accept defaults.
9. **MDG only — pre-flight.** Run `ZMDMDOC_SETUP` / `ZMDMDOC_DOCTOR` until all
   checks are GO before touching the BAdI. These wrap `ZCL_MDMDOC_SELFTEST` +
   `ZCL_MDMDOC_ONBOARD` (incl. a synthetic-PDF end-to-end check).
10. **MDG only — bind the BAdI.** Create the enhancement implementation for spot
    `USMD_RULE_SERVICE` (SE18/SE19), filter `USMD_MODEL = 'BP'`, implementing
    class `ZCL_MDG_BP_FIELD_DERR_VAL`. The class ships; the binding object does
    not. Behavior: **warnings only** — no compare rule carries REJECT today, so
    the CR is never blocked (see docs/INTEGRATION.md ch. 10).
11. **Strict corp rule profile (optional).** The default rule set includes two
    experimental rules (`BNK-002` email-REJECT, `BNK-030` unrecognized→review —
    a safe backstop). For a corp-only profile:
    `python3 tools/gen_rules_abap.py --tier-min corp` → re-pull. See
    [docs/RULES.md](docs/RULES.md).

## 4. `ZMDMDOC_MAP` — the one table you may create (SE11)

Optional customizing table overriding the built-in MDG field mapping. Accessed
dynamically — nothing dumps while it does not exist; defaults apply.

| Field | Type | Key | Notes |
|---|---|---|---|
| `MODEL` | `USMD_MODEL` (CHAR 3) | ✕ key | e.g. `BP` |
| `SAP_KEY` | `CHAR 30` | ✕ key | one of: `account_holder`, `street`, `city`, `bank_country`, `bank_key`, `bank_account`, `control_key`, `iban`, `tin` |
| `ENTITY` | `CHAR 30` (or `USMD_ENTITY`) | | e.g. `BP_BANKDT` |
| `FIELD` | `CHAR 30` (or `USMD_FIELDNAME`) | | e.g. `IBAN` |

Built-in defaults (used when the table is absent/empty): `account_holder →
BP_CENTRL.NAME_ORG1`, `street → ADDRESS.STREET`, `city → ADDRESS.CITY1`,
`bank_country → BP_BANKDT.BANKS`, `bank_key → BP_BANKDT.BANKL`, `bank_account →
BP_BANKDT.BANKN`, `control_key → BP_BANKDT.BKONT`, `iban → BP_BANKDT.IBAN`,
`tin → BP_TAXNUM.TAXNUM`. Delivery class `C`, maintenance via SM30 allowed.
`ZMDMDOC_MDG_DISCOVER` (with `p_save`) writes proposals into it.

## 5. How rules are updated after handover

- **Runtime, no transport:** export the active set with `ZMDMDOC_RULES`, edit the
  JSON, feed it to `ZMDMDOC` via the rules-override parameter. Per-class packs
  swap independently. ([docs/RULES.md](docs/RULES.md))
- **Permanently:** edit `rules/*.yaml` → `python3 tools/gen_rules_abap.py`
  (Python 3 + PyYAML — the repo's only Python dependency) → abapGit pull →
  activate → transport.
- Rule governance (who approves what, tiers) stays with the MDM analyst who owns
  the Python reference implementation; you receive rule updates as regenerated
  `ZCL_MDMDOC_RULES_DATA` + `rules/*.json` through this repository.

## 6. Guarantees & invariants you must not break

- **The verdict comes only from the rule set.** The LLM (when enabled) only reads
  text. Engine errors are fail-closed: a broken rule yields `ENGINE-GUARD` →
  `NEED_MANUAL_REVIEW`, never a silent ACCEPT.
- **TIN (SSN/EIN) is never printed in full** — list, JSON, notes are masked; a
  leak gate scans the output JSON and cancels the export on a leak. Do not add
  logging of raw extraction values.
- **W-8 forms route to manual review by design** (rule `W9-030`) — the W-8 policy
  is not automated in v1.
- **In MDG the component only warns** — it must not block CR submission unless
  the business explicitly upgrades a compare rule to REJECT.

## 7. Known limitations (honest list)

See README "Limitations". Highlights: no scanned-PDF OCR inside ABAP (LLM-vision
or external OCR required); CID fonts without ToUnicode are skipped with a
warning; `.msg` unsupported (re-save as `.eml`); compressed-PDF reading depends
on the `CL_ABAP_GZIP` smoke test (§3 item 2).

## 8. Where everything is

| Question | Document |
|---|---|
| Install / run / limitations | [README.md](README.md) (RU: [README.ru.md](README.ru.md)) |
| MDG integration step-by-step (13 chapters) | [docs/INTEGRATION.md](docs/INTEGRATION.md) (RU: [docs/INTEGRATION.ru.md](docs/INTEGRATION.ru.md)) |
| Rules: view / edit / swap / tiers | [docs/RULES.md](docs/RULES.md) (RU: [docs/RULES.ru.md](docs/RULES.ru.md)) |
| Public API of every class | [docs/CONTRACT.md](docs/CONTRACT.md) |
| First-run demo | [samples/README.md](samples/README.md) |
| Rule-set source of truth | `rules/banking.yaml`, `rules/w9.yaml` |
