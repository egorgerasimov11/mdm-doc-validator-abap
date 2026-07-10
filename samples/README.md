# Samples — first-run demo (invented data only)

Two tiny PDFs for verifying the freshly imported `ZMDMDOC` report without any
real vendor data. Every name, IBAN and phone number is **invented** (the IBAN
is mod-97-valid on purpose so the checksum rule stays quiet). The files were
generated from the Python reference repository's synthetic-document tooling —
they are safe to keep in the repository and to upload to any system.

How to run: SA38 → `ZMDMDOC` → file path (PC upload) → doc class **auto** →
F8. No LLM, no customizing, no `ZMDMDOC_MAP` needed — everything below is the
**deterministic** path.

## 1. `sample_bank_letter.pdf` — the first-run demo

An unsigned bank confirmation letter with a typed officer block
("Jordan Q. Sample, Vice President …"). The PDF text layer is deliberately
**uncompressed**, so this demo works even before the gzip check (see §2).

Expected result:

| | |
|---|---|
| Verdict | **NEED_MANUAL_REVIEW** |
| `BNK-026` | NOTE — no wet signature/stamp, but compensating evidence: the typed officer block was detected deterministically |
| `BNK-023` | WARNING → NEED_MANUAL_REVIEW — account holder not readable |
| `BNK-025` | WARNING — bank name not readable |
| IBAN | `DE89…3000` extracted, mod-97 valid (no `BNK-011`) |

Why the holder/bank-name findings: those are narrative fields that the
deterministic engine does not extract — this is the honest no-LLM behavior.
With the optional LLM leg enabled the same letter fills `account_holder` /
`bank_name` and the two findings clear. Note that `BNK-021` (unsigned, no
compensating evidence) correctly does NOT fire — the officer block counts.

## 2. `sample_invoice.pdf` — REJECT demo + gzip smoke test

An invoice carrying an IBAN — the classic "invoice used as bank proof" case.
This PDF is deliberately **FlateDecode-compressed**: reading it exercises the
`CL_ABAP_GZIP` kernel path (on-system checklist item 2 in
[../HANDOFF.md](../HANDOFF.md)).

Expected result:

| | |
|---|---|
| Verdict | **REJECT** |
| `BNK-001` | CRITICAL → REJECT — invoice used as banking support |

If instead you get "no text layer" warnings and empty fields, the gzip
decompression path needs investigation (HANDOFF §3 item 2) — the file itself
is fine. Still run the smoke test on a REAL vendor PDF afterwards; real-world
files vary more than this sample.

## Keeping expectations honest

The verdicts above were produced by the Python reference implementation
(`mdmdoc check --engine deterministic`, approval gate off — the rule set that
ships compiled into `ZCL_MDMDOC_RULES_DATA` is already the approved one) at
the time this repository snapshot was made. If a future rules regeneration
changes them, regenerate this table the same way.
