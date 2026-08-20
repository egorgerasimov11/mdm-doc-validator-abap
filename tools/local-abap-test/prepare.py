#!/usr/bin/env python3
"""Copy the classes under test out of ../../src and apply the local-harness shims.

The shims exist only because open-abap does not implement some kernel behaviour —
each one is documented in README.md under "Known emulator gaps". Nothing here
changes the logic being tested; ./src is throwaway and gitignored.
"""
import pathlib
import re
import shutil

# classes to transpile; add more as they become dependency-free enough to run
CLASSES = ['zcl_mdmdoc_inflate', 'zcl_mdmdoc_pdf']
SUFFIXES = ['.clas.abap', '.clas.testclasses.abap', '.clas.xml']

HERE = pathlib.Path(__file__).parent
REPO_SRC = (HERE / '..' / '..' / 'src').resolve()
SRC = HERE / 'src'

SRC.mkdir(exist_ok=True)
for name in CLASSES:
    for suffix in SUFFIXES:
        source = REPO_SRC / (name + suffix)
        if source.exists():
            shutil.copy(source, SRC / (name + suffix))

# ---- gap 1: no codepage 1100 — express Latin-1 through UTF-16LE instead ----------
CONV_IN = '''  METHOD bytes_to_latin1.
    DATA lv_u16  TYPE xstring.
    DATA lv_i    TYPE i.
    DATA lv_b    TYPE x LENGTH 1.
    DATA lv_zero TYPE x LENGTH 1 VALUE '00'.
    DATA lv_len  TYPE i.
    lv_len = xstrlen( iv_x ).
    WHILE lv_i < lv_len.
      lv_b = iv_x+lv_i(1).
      CONCATENATE lv_u16 lv_b lv_zero INTO lv_u16 IN BYTE MODE.
      lv_i = lv_i + 1.
    ENDWHILE.
    DATA lo_conv TYPE REF TO cl_abap_conv_in_ce.
    lo_conv = cl_abap_conv_in_ce=>create( encoding = '4103' ).
    lo_conv->convert( EXPORTING input = lv_u16 IMPORTING data = rv_str ).
  ENDMETHOD.'''

CONV_OUT = '''    DATA lo_conv TYPE REF TO cl_abap_conv_out_ce.
    lo_conv = cl_abap_conv_out_ce=>create( encoding = '4103' ).
    DATA lv_u16 TYPE xstring.
    lo_conv->convert( EXPORTING data = iv_str IMPORTING buffer = lv_u16 ).
    DATA lv_i   TYPE i.
    DATA lv_b   TYPE x LENGTH 1.
    DATA lv_len TYPE i.
    lv_len = xstrlen( lv_u16 ).
    WHILE lv_i < lv_len.
      lv_b = lv_u16+lv_i(1).
      CONCATENATE rv_x lv_b INTO rv_x IN BYTE MODE.
      lv_i = lv_i + 2.
    ENDWHILE.'''

pdf = SRC / 'zcl_mdmdoc_pdf.clas.abap'
s = pdf.read_text()
s = re.sub(r'  METHOD bytes_to_latin1\..*?\n  ENDMETHOD\.', CONV_IN, s, count=1, flags=re.S)
s = re.sub(r'  METHOD latin1_to_bytes\..*?\n  ENDMETHOD\.',
           '  METHOD latin1_to_bytes.\n' + CONV_OUT + '\n  ENDMETHOD.', s, count=1, flags=re.S)

# ---- gap 2: open-abap lets Node zlib errors escape ABAP exception handling -------
s = re.sub(r'    " \(a\) the stream may genuinely be gzip.*?\n    ENDTRY\.\n',
           '    " (a) kernel gzip attempt skipped locally — see README.md gap 2\n',
           s, count=1, flags=re.S)
pdf.write_text(s)

tests = SRC / 'zcl_mdmdoc_pdf.clas.testclasses.abap'
t = tests.read_text()
t = re.sub(r'  METHOD to_x\..*?\n  ENDMETHOD\.',
           '  METHOD to_x.\n' + CONV_OUT + '\n  ENDMETHOD.', t, count=1, flags=re.S)

# these two can only be judged on a real kernel / are blocked by a transpiler defect
for method in ['latin1_roundtrip', 'page_count']:
    t = re.sub(r'    METHODS %s\s+FOR TESTING\.\n' % method, '', t, count=1)
    t = re.sub(r'  METHOD %s\..*?\n  ENDMETHOD\.\n\n' % method, '', t, count=1, flags=re.S)
tests.write_text(t)

print('prepared: %s (latin1_roundtrip + page_count are on-system only)' % ', '.join(CLASSES))
