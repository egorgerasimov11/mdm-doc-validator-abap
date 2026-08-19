#!/usr/bin/env python3
"""Regenerate the zlib fixtures embedded in ltcl_inflate / ltcl_pdf / zcl_mdmdoc_selftest.

Each fixture is real `zlib.compress` output chosen to force one DEFLATE block type
(fixed Huffman, dynamic Huffman, stored) plus one overlapping-match case. Output is
ABAP-ready hex, wrapped to respect the 140-char abaplint line limit.
"""
import zlib

FIXTURES = {
    # fixed Huffman — also embedded in zcl_mdmdoc_selftest=>check_pdf_flate and
    # ltcl_pdf->flate_stream_text (as a /FlateDecode stream body)
    'fixed': b'BT /F1 10 Tf 50 700 Td (Flate hello from ZMDMDOC) Tj ET',
    # dynamic Huffman — repetitive banking text, level 9
    'dyn': (b'BT /F1 9 Tf 40 720 Td (JPMorgan Chase Bank, N.A. '
            b'Account holder: ACME Industries LLC) Tj '
            b'0 -12 Td (IBAN: DE44500105175407324931 SWIFT/BIC: CHASUS33) Tj '
            b'0 -12 Td (Routing ABA: 021000021 Account number: 000123456789) Tj ET\n') * 3,
    # stored block — level 0
    'stored': b'BT (stored block) Tj ET',
    # overlapping match (dist < length) — long run of one byte
    'overlap': b'BT (' + b'A' * 120 + b') Tj ET',
}
LEVELS = {'fixed': 6, 'dyn': 9, 'stored': 0, 'overlap': 6}


def wrap(hexstr, width=100):
    lines = [hexstr[i:i + width] for i in range(0, len(hexstr), width)]
    return "\n      '" + "' &&\n      '".join(lines) + "'."


for name, raw in FIXTURES.items():
    z = zlib.compress(raw, LEVELS[name])
    btype = (z[2] >> 1) & 3
    print(f'* --- {name}: zlib {len(z)}B, raw {len(raw)}B, first block type {btype}')
    print(f'    lv_{name}_z ={wrap(z.hex().upper())}')
    print(f'    lv_{name}_raw ={wrap(raw.hex().upper())}')
    print()
