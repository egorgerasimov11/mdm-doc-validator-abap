# Rules: how to view, change, delete and swap them ("skills")

> Русская версия: [RULES.ru.md](RULES.ru.md)

Rules decide the verdict (the model decides nothing). Every **document type is a
separate rule pack — a "skill"** — that can be swapped as a whole: `banking`
(bank-document validation) and `w9` (W-9 checking).

## Where they live (3 layers, never hard-wired)

1. **Source** — YAML: [`rules/banking.yaml`](../rules/banking.yaml),
   [`rules/w9.yaml`](../rules/w9.yaml). Human-readable; the right place for
   permanent edits.
2. **Compiled ABAP** — `ZCL_MDMDOC_RULES_DATA` (generated from the YAML, executed
   in SAP). Never edited by hand.
3. **Runtime override JSON** — `rules/rules.json` (the full set),
   `rules/banking.rules.json`, `rules/w9.rules.json` (per-class "skills"). Loaded
   by the `p_rules` parameter of report `ZMDMDOC` at runtime — **no regeneration,
   no transport**.

## Viewing the rules inside SAP

Report **`ZMDMDOC_RULES`** (SA38): shows every rule (id, severity → verdict, which
doc types it applies to, the condition in human-readable form, EN/RU message;
color by severity). Radio `All / Banking / W-9`.

## Anatomy of one rule

```json
{
  "id": "W9-010",
  "name": "ein_9_digits",
  "applies_to": ["w9"],                 // empty = applies to all types
  "when_op": "check",                   // always | field_missing | flag_true/false | equals | in | regex_mismatch | check
  "when_field": "tin_raw",
  "check_name": "ein_shape",            // for when_op=check — which predicate
  "check_args": [{ "name": "digits", "value": "9" }],
  "severity": "CRITICAL",               // CRITICAL | WARNING | NOTE
  "verdict_effect": "NEED_MANUAL_REVIEW", // REJECT | NEED_MANUAL_REVIEW | WARNING | "" (no effect)
  "message": "TIN {value} has the wrong digit count ...",
  "message_ru": "…",                    // optional
  "tier": "corp"                        // governance: corp | experimental | learned
}
```

## Governance profile (tier)

Every rule carries a `tier` tag. The default generation ships the **full set**
(including the experimental `BNK-002` — plain email as bank proof → REJECT, and
`BNK-030` — unrecognized document → NEED_MANUAL_REVIEW, a safe backstop). The
strict corp profile: `python3 tools/gen_rules_abap.py --tier-min corp` — the
experimental rules are excluded. Rules without a tier always pass the filter.

## Special rules you should know about

- **`W9-030`**: any document recognized as a **W-8** (W-8BEN/-E) unconditionally
  goes to `NEED_MANUAL_REVIEW` — the W-8 compliance policy is deliberately not
  automated in v1.
- **`BNK-030`** (experimental): a document whose type could not be established is
  never auto-accepted — `NEED_MANUAL_REVIEW`.
- **Engine errors are fail-closed**: a rule that crashes during evaluation (or
  declares an invalid `verdict_effect`) yields an `ENGINE-GUARD` finding with
  effect `NEED_MANUAL_REVIEW` — a broken rule can never cause a silent ACCEPT.

## Method 1 — at runtime, no transport (easiest)

1. `ZMDMDOC_RULES` → "Export" checkbox → file path (a single class can be chosen:
   `W-9 only` → exports just `w9.rules.json`).
2. Open the file and edit:
   - **change** a rule — adjust its fields (severity, message, verdict_effect…);
   - **delete** a rule — remove its `{ ... }` block from the array;
   - **add** — insert a new block with a unique `id`;
   - **swap a whole "skill"** (e.g. W-9) — replace the entire `w9.rules.json`
     with your own.
3. Run `ZMDMDOC` and point the **rules override** parameter (`p_rules`) in the
   Output block at that file. The rules load from the file. Broken JSON → warning
   + fallback to the compiled rules.

**Per-class "skill" swap:** a file containing only `rules_w9` swaps **just** the
W-9 pack; the banking module keeps its defaults (and vice versa). "Something is
off with W-9 → drop in a replacement `w9.rules.json`" without touching banking.

## Method 2 — permanently, through the source

1. Edit `rules/banking.yaml` / `rules/w9.yaml` (same field semantics, YAML form).
   Deleting a rule = removing its item from the `rules:` list.
2. `python3 tools/gen_rules_abap.py` — regenerates `ZCL_MDMDOC_RULES_DATA` + all
   `*.rules.json` (needs Python 3 + PyYAML; the repository's only Python
   dependency).
3. abapGit Pull into the system → activate → (for promotion) transport.

## Methods 3–4 — author-side only (the Python repository)

The Python original's web panel (`mdmdoc ui`) and the checker-skill sync
(`mdmdoc skill-rules`, the `mdmdoc-skill-sync` procedure) live in the parent
Python project and are **not available on the target SAP system** — mentioned for
the full picture: that is where new rules are born and pass human approval before
arriving here via Method 2.

## Important

- Low-level checks (IBAN mod-97, `ein_shape`, `swift_valid`…) are compiled ABAP
  "bricks" shared by all rules; they are not changed through files. What you
  change is the **rule set** (which checks apply, severities, messages) — and
  that is swappable.
- After an edit: `ZMDMDOC_RULES` shows what is actually active; the
  `describe_conditions` + `skill_swap_partial` unit tests pin the format and the
  per-class behavior.
