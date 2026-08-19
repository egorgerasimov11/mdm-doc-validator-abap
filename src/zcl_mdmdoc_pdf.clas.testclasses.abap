*"* use this source file for your ABAP unit test classes
CLASS ltcl_pdf DEFINITION DEFERRED.
CLASS zcl_mdmdoc_pdf DEFINITION LOCAL FRIENDS ltcl_pdf.

CLASS ltcl_pdf DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS to_x
      IMPORTING iv_str      TYPE string
      RETURNING VALUE(rv_x) TYPE xstring.

    METHODS uncompressed_tj    FOR TESTING.
    METHODS tj_array_and_hex   FOR TESTING.
    METHODS encrypted_detected FOR TESTING.
    METHODS page_count         FOR TESTING.
    METHODS garbage_no_dump    FOR TESTING.
    " the defect class of C-2026-08-20-01: real zlib-compressed /FlateDecode streams
    METHODS flate_stream_text  FOR TESTING.
    METHODS flate_corrupt_warn FOR TESTING.
    METHODS latin1_roundtrip   FOR TESTING.
ENDCLASS.

CLASS ltcl_pdf IMPLEMENTATION.

  METHOD to_x.
    " render an ASCII PDF skeleton to bytes (Latin-1 == ASCII for our test text)
    rv_x = cl_abap_codepage=>convert_to( source = iv_str codepage = `ISO-8859-1` ).
  ENDMETHOD.

  METHOD uncompressed_tj.
    DATA(lv_pdf) =
      |%PDF-1.4\n| &&
      |1 0 obj\n<< /Type /Page >>\nendobj\n| &&
      |2 0 obj\n<< /Length 30 >>\nstream\n| &&
      |BT (Hello World) Tj ET\n| &&
      |endstream\nendobj\n%%EOF\n|.
    zcl_mdmdoc_pdf=>extract_text(
      EXPORTING iv_pdf = to_x( lv_pdf )
      IMPORTING ev_text = DATA(lv_text) ev_encrypted = DATA(lv_enc) ).
    cl_abap_unit_assert=>assert_false( lv_enc ).
    cl_abap_unit_assert=>assert_true( boolc( lv_text CS 'Hello' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_text CS 'World' ) ).
  ENDMETHOD.

  METHOD tj_array_and_hex.
    " TJ array with kerning + a hex string <48656C6C6F> = 'Hello'
    DATA(lv_pdf) =
      |%PDF-1.4\n| &&
      |1 0 obj\n<< /Length 60 >>\nstream\n| &&
      |BT [(Good) -300 (Morning)] TJ <48656C6C6F> Tj ET\n| &&
      |endstream\nendobj\n%%EOF\n|.
    zcl_mdmdoc_pdf=>extract_text(
      EXPORTING iv_pdf = to_x( lv_pdf )
      IMPORTING ev_text = DATA(lv_text) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_text CS 'Good' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_text CS 'Morning' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_text CS 'Hello' ) ).
  ENDMETHOD.

  METHOD encrypted_detected.
    DATA(lv_pdf) =
      |%PDF-1.4\n| &&
      |1 0 obj\n<< /Type /Page >>\nendobj\n| &&
      |trailer\n<< /Root 1 0 R /Encrypt 9 0 R >>\n%%EOF\n|.
    zcl_mdmdoc_pdf=>extract_text(
      EXPORTING iv_pdf = to_x( lv_pdf )
      IMPORTING ev_encrypted = DATA(lv_enc) ).
    cl_abap_unit_assert=>assert_true( lv_enc ).
  ENDMETHOD.

  METHOD page_count.
    " two /Type /Page and one /Pages — count must be 2, not 3
    DATA(lv_pdf) =
      |%PDF-1.4\n| &&
      |1 0 obj\n<< /Type /Pages /Kids [2 0 R 3 0 R] /Count 2 >>\nendobj\n| &&
      |2 0 obj\n<< /Type /Page >>\nendobj\n| &&
      |3 0 obj\n<< /Type /Page >>\nendobj\n%%EOF\n|.
    zcl_mdmdoc_pdf=>extract_text(
      EXPORTING iv_pdf = to_x( lv_pdf )
      IMPORTING ev_pages = DATA(lv_pages) ).
    cl_abap_unit_assert=>assert_equals( act = lv_pages exp = 2 ).
  ENDMETHOD.

  METHOD garbage_no_dump.
    " random non-PDF bytes must not dump; text stays empty
    DATA lv_x TYPE xstring.
    lv_x = 'DEADBEEF00112233445566778899AABBCCDDEEFF'.
    zcl_mdmdoc_pdf=>extract_text(
      EXPORTING iv_pdf = lv_x
      IMPORTING ev_text = DATA(lv_text) ev_encrypted = DATA(lv_enc) ).
    cl_abap_unit_assert=>assert_initial( lv_text ).
    cl_abap_unit_assert=>assert_false( lv_enc ).
  ENDMETHOD.

  METHOD flate_stream_text.
    " a real zlib stream (Python zlib.compress) inside /FlateDecode — the case every
    " real-world PDF hits; the old kernel-only chain failed all of these
    DATA lv_z TYPE xstring.
    lv_z =
      '789C730A51D0773354303450084953303550303700B2521434DC72124B521532527372F215D28AF27315A27C5D7C5DFC9D35' &&
      '1542B2145C430087750EF6'.
    DATA lv_pdf TYPE xstring.
    DATA(lv_head) = |%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\n| &&
                    |2 0 obj\n<< /Length 61 /Filter /FlateDecode >>\nstream\n|.
    DATA(lv_tail) = |\nendstream\nendobj\n%%EOF\n|.
    DATA(lv_head_x) = to_x( lv_head ).
    DATA(lv_tail_x) = to_x( lv_tail ).
    CONCATENATE lv_head_x lv_z lv_tail_x INTO lv_pdf IN BYTE MODE.
    zcl_mdmdoc_pdf=>extract_text(
      EXPORTING iv_pdf = lv_pdf
      IMPORTING ev_text = DATA(lv_text) et_warnings = DATA(lt_warn) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_text CS 'Flate hello' ) ).
    cl_abap_unit_assert=>assert_true( boolc( lv_text CS 'ZMDMDOC' ) ).
    LOOP AT lt_warn INTO DATA(lv_w).
      cl_abap_unit_assert=>assert_false( boolc( lv_w CS 'inflate-failed' ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD flate_corrupt_warn.
    " a broken flate body must be counted, not extracted and not dumped
    DATA lv_bad TYPE xstring.
    lv_bad = '789CFFEEDDCCBBAA99887766554433221100'.
    DATA lv_pdf TYPE xstring.
    DATA(lv_head) = |%PDF-1.4\n2 0 obj\n<< /Length 18 /Filter /FlateDecode >>\nstream\n|.
    DATA(lv_tail) = |\nendstream\nendobj\n%%EOF\n|.
    DATA(lv_head_x) = to_x( lv_head ).
    DATA(lv_tail_x) = to_x( lv_tail ).
    CONCATENATE lv_head_x lv_bad lv_tail_x INTO lv_pdf IN BYTE MODE.
    zcl_mdmdoc_pdf=>extract_text(
      EXPORTING iv_pdf = lv_pdf
      IMPORTING ev_text = DATA(lv_text) et_warnings = DATA(lt_warn) ).
    DATA lv_seen TYPE abap_bool.
    LOOP AT lt_warn INTO DATA(lv_w).
      IF lv_w CS 'inflate-failed'.
        lv_seen = abap_true.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true( lv_seen ).
  ENDMETHOD.

  METHOD latin1_roundtrip.
    " compressed bodies survive extract_text's bytes->string->bytes round trip only
    " if the codepage maps all 256 byte values 1:1 — verify on THIS system's kernel
    DATA lv_in  TYPE xstring.
    DATA lv_b   TYPE x LENGTH 1.
    DATA lv_i   TYPE i.
    DO 256 TIMES.
      lv_i = sy-index - 1.
      lv_b = lv_i.
      CONCATENATE lv_in lv_b INTO lv_in IN BYTE MODE.
    ENDDO.
    DATA(lv_str) = zcl_mdmdoc_pdf=>bytes_to_latin1( lv_in ).
    DATA(lv_out) = zcl_mdmdoc_pdf=>latin1_to_bytes( lv_str ).
    cl_abap_unit_assert=>assert_equals( act = lv_out exp = lv_in
      msg = 'codepage 1100 round trip is not byte-transparent on this system' ).
  ENDMETHOD.

ENDCLASS.
