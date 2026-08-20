# Running the ABAP unit tests locally (no SAP system)

The abaplint transpiler compiles ABAP to JavaScript and runs ABAP Unit under Node,
using [open-abap-core](https://github.com/open-abap/open-abap-core) for the standard
classes. That turns "we can only test on a system" into "we can test in ~40 seconds
on a laptop" for the classes that do not depend on kernel behaviour.

It is a **pre-filter, not a replacement** for the on-system run: see Coverage below.

## Run

```bash
cd tools/local-abap-test
npm install          # first time only
python3 prepare.py   # copy the classes under test out of src/ and apply the shims
npx abap_transpile abap_transpile.json
node --expose-gc output/index.mjs && echo GREEN
```

Exit code 0 with no `msg:` lines means every test passed. The runner stops at the
first failure and prints the expected/actual values.

`prepare.py` copies from `../../src` into `./src`, so the transpiled sources are
throwaway; edit the real ones under `src/` in the repo root.

## Coverage

Covered today: `ZCL_MDMDOC_INFLATE` (all of it — it has no external dependencies)
and `ZCL_MDMDOC_PDF` (stream walking, inflate integration, the BT/ET tokenizer,
literal/hex decoding, CMaps).

Add another class by extending the list at the top of `prepare.py`. Classes that
touch MDG types, HTTP, or the database will not transpile — those stay
verify-on-system.

## Known emulator gaps — these are NOT defects in our code

`prepare.py` works around three, each verified against the real system or by probe.
If you see one of these locally, do not "fix" production code for it.

1. **No codepage 1100.** open-abap's `CL_ABAP_CONV_*` support only UTF-8 and `4103`
   (UTF-16LE). `prepare.py` swaps `bytes_to_latin1` / `latin1_to_bytes` for a
   UTF-16LE-based Latin-1 equivalent (byte N ↔ code point N). The real conversion
   is covered on-system by the `latin1_roundtrip` unit test and by the
   `codepage 1100 byte transparency` check in `ZMDMDOC_DOCTOR`.
2. **`CL_ABAP_GZIP` errors are not catchable.** open-abap implements it over Node
   zlib and lets the Node error escape as a raw JS error, so ABAP's `CATCH cx_root`
   never sees it. On a real kernel that call *is* catchable — the MDD screenshots
   in case C-2026-08-20-01 show a clean `inflate-failed(2)` warning, which can only
   render if the exception was caught. `prepare.py` drops that first attempt locally.
3. **Transpiler defect: a built-in nested directly in a named argument.**
   `substring( val = x off = y len = nmin( val1 = 16 val2 = z ) )` evaluates the
   length as `1`. Proven by probe: literal `len = 16` → 16, `nmin` assigned to a
   variable first → 16, nested inline → 1. This is why `page_count` fails locally;
   `count_pages` itself is correct, so `prepare.py` skips that test.

## Why it earns its keep

The very first local run found a real defect that no amount of reading had caught
(case C-2026-08-20-03): a paren-depth counter declared as `DATA lv_depth TYPE i
VALUE 1.` *inside* a loop. In ABAP a `DATA ... VALUE` declaration initializes once
per call, not once per iteration, so every text fragment after the first was
silently dropped from every content stream. A green transpiled run would have
flagged it the day it was written.
