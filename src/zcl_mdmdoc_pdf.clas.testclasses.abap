*"* use this source file for your ABAP unit test classes
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

ENDCLASS.
