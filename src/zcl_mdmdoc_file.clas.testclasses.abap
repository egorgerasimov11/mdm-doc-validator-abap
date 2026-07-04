CLASS ltcl_file DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    " helpers
    METHODS str_to_x
      IMPORTING iv_str      TYPE string
      RETURNING VALUE(rv_x) TYPE xstring.
    METHODS build_eml
      IMPORTING iv_pdf_b64  TYPE string
                iv_png_b64  TYPE string
      RETURNING VALUE(rv_x) TYPE xstring.

    " classify_ext coverage
    METHODS classify_pdf         FOR TESTING.
    METHODS classify_image       FOR TESTING.
    METHODS classify_email       FOR TESTING.
    METHODS classify_msg         FOR TESTING.
    METHODS classify_zip         FOR TESTING.
    METHODS classify_editable    FOR TESTING.
    METHODS classify_other       FOR TESTING.
    METHODS classify_uppercase   FOR TESTING.
    METHODS classify_leading_dot FOR TESTING.

    " basename / ext_of
    METHODS basename_unix        FOR TESTING.
    METHODS basename_windows     FOR TESTING.
    METHODS ext_of_multi_dot     FOR TESTING.
    METHODS ext_of_none          FOR TESTING.

    " sha16
    METHODS sha16_known          FOR TESTING.

    " eml unwrap
    METHODS eml_picks_pdf        FOR TESTING.
    METHODS eml_no_attachment    FOR TESTING.

    " zip unwrap
    METHODS zip_picks_pdf        FOR TESTING.
    METHODS zip_empty            FOR TESTING.
ENDCLASS.


CLASS ltcl_file IMPLEMENTATION.

  METHOD str_to_x.
    rv_x = cl_abap_conv_out_ce=>create( encoding = 'UTF-8' )->convert( iv_str ).
  ENDMETHOD.

  METHOD build_eml.
    " Synthetic multipart/mixed message: a text body part, a base64 PDF attachment
    " and a base64 PNG attachment. CRLF line endings like a real MIME message.
    DATA(lv_crlf) = cl_abap_char_utilities=>cr_lf.
    DATA lv_eml TYPE string.
    lv_eml =
      |From: a@b.com{ lv_crlf }| &&
      |To: c@d.com{ lv_crlf }| &&
      |Subject: bank confirmation{ lv_crlf }| &&
      |MIME-Version: 1.0{ lv_crlf }| &&
      |Content-Type: multipart/mixed; boundary="MYBOUND42"{ lv_crlf }| &&
      |{ lv_crlf }| &&
      |--MYBOUND42{ lv_crlf }| &&
      |Content-Type: text/plain; charset="utf-8"{ lv_crlf }| &&
      |{ lv_crlf }| &&
      |Please find the bank letter attached.{ lv_crlf }| &&
      |--MYBOUND42{ lv_crlf }| &&
      |Content-Type: image/png; name="logo.png"{ lv_crlf }| &&
      |Content-Transfer-Encoding: base64{ lv_crlf }| &&
      |Content-Disposition: attachment; filename="logo.png"{ lv_crlf }| &&
      |{ lv_crlf }| &&
      |{ iv_png_b64 }{ lv_crlf }| &&
      |--MYBOUND42{ lv_crlf }| &&
      |Content-Type: application/pdf; name="bank.pdf"{ lv_crlf }| &&
      |Content-Transfer-Encoding: base64{ lv_crlf }| &&
      |Content-Disposition: attachment; filename="bank.pdf"{ lv_crlf }| &&
      |{ lv_crlf }| &&
      |{ iv_pdf_b64 }{ lv_crlf }| &&
      |--MYBOUND42--{ lv_crlf }|.
    rv_x = str_to_x( lv_eml ).
  ENDMETHOD.


  METHOD classify_pdf.
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'pdf' ) exp = 'pdf' ).
  ENDMETHOD.

  METHOD classify_image.
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'png' )  exp = 'image' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'jpg' )  exp = 'image' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'jpeg' ) exp = 'image' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'bmp' )  exp = 'image' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'tif' )  exp = 'image' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'tiff' ) exp = 'image' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'gif' )  exp = 'image' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'webp' ) exp = 'image' ).
  ENDMETHOD.

  METHOD classify_email.
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'eml' ) exp = 'email' ).
  ENDMETHOD.

  METHOD classify_msg.
    " .msg maps to its own kind 'msg' (unsupported downstream).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'msg' ) exp = 'msg' ).
  ENDMETHOD.

  METHOD classify_zip.
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'zip' ) exp = 'zip' ).
  ENDMETHOD.

  METHOD classify_editable.
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'docx' ) exp = 'editable' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'doc' )  exp = 'editable' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'xlsx' ) exp = 'editable' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'xls' )  exp = 'editable' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'txt' )  exp = 'editable' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'rtf' )  exp = 'editable' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'csv' )  exp = 'editable' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'odt' )  exp = 'editable' ).
  ENDMETHOD.

  METHOD classify_other.
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'exe' ) exp = 'other' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( '' )    exp = 'other' ).
  ENDMETHOD.

  METHOD classify_uppercase.
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'PDF' ) exp = 'pdf' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( 'JPEG' ) exp = 'image' ).
  ENDMETHOD.

  METHOD classify_leading_dot.
    cl_abap_unit_assert=>assert_equals( act = zcl_mdmdoc_file=>classify_ext( '.zip' ) exp = 'zip' ).
  ENDMETHOD.


  METHOD basename_unix.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_file=>basename( '/foo/bar/baz.pdf' ) exp = 'baz.pdf' ).
  ENDMETHOD.

  METHOD basename_windows.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_file=>basename( 'C:\docs\bank.eml' ) exp = 'bank.eml' ).
  ENDMETHOD.

  METHOD ext_of_multi_dot.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_file=>ext_of( 'my.bank.letter.PDF' ) exp = 'pdf' ).
  ENDMETHOD.

  METHOD ext_of_none.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_file=>ext_of( 'README' ) exp = '' ).
  ENDMETHOD.


  METHOD sha16_known.
    " sha256('abc') = ba7816bf8f01cfea...; first 16 hex chars lowercase.
    DATA(lv_x) = str_to_x( 'abc' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mdmdoc_file=>sha16( lv_x )
      exp = 'ba7816bf8f01cfea'
      msg = 'sha16 of "abc"' ).
  ENDMETHOD.


  METHOD eml_picks_pdf.
    " Build distinct payloads, base64 them, embed in a multipart message,
    " and assert unwrap picks the PDF (higher preference than the PNG).
    DATA(lv_pdf) = str_to_x( '%PDF-1.4 fake bank letter body content here' ).
    DATA(lv_png) = str_to_x( 'PNGFAKE logo image content bytes here ....' ).
    DATA(lv_pdf_b64) = cl_http_utility=>encode_x_base64( lv_pdf ).
    DATA(lv_png_b64) = cl_http_utility=>encode_x_base64( lv_png ).

    DATA ls_doc TYPE zcl_mdmdoc_file=>ty_doc.
    ls_doc-name    = 'mail.eml'.
    ls_doc-ext     = 'eml'.
    ls_doc-content = build_eml( iv_pdf_b64 = lv_pdf_b64 iv_png_b64 = lv_png_b64 ).

    DATA lt_notes TYPE string_table.
    DATA lv_error TYPE string.
    zcl_mdmdoc_file=>unwrap( IMPORTING et_notes = lt_notes ev_error = lv_error
                             CHANGING  cs_doc   = ls_doc ).

    cl_abap_unit_assert=>assert_initial( act = lv_error msg = 'eml unwrap should succeed' ).
    cl_abap_unit_assert=>assert_equals( act = ls_doc-ext exp = 'pdf' msg = 'PDF chosen over PNG' ).
    cl_abap_unit_assert=>assert_equals( act = ls_doc-content exp = lv_pdf
                                        msg = 'chosen content is the decoded PDF' ).
    cl_abap_unit_assert=>assert_not_initial( act = lt_notes msg = 'unwrap records a note' ).
  ENDMETHOD.

  METHOD eml_no_attachment.
    " A multipart message with only a text body -> no candidate -> error.
    DATA(lv_crlf) = cl_abap_char_utilities=>cr_lf.
    DATA lv_eml TYPE string.
    lv_eml =
      |Content-Type: multipart/mixed; boundary="B1"{ lv_crlf }| &&
      |{ lv_crlf }| &&
      |--B1{ lv_crlf }| &&
      |Content-Type: text/plain{ lv_crlf }| &&
      |{ lv_crlf }| &&
      |just a note, no attachment{ lv_crlf }| &&
      |--B1--{ lv_crlf }|.

    DATA ls_doc TYPE zcl_mdmdoc_file=>ty_doc.
    ls_doc-name    = 'plain.eml'.
    ls_doc-ext     = 'eml'.
    ls_doc-content = str_to_x( lv_eml ).

    DATA lt_notes TYPE string_table.
    DATA lv_error TYPE string.
    zcl_mdmdoc_file=>unwrap( IMPORTING et_notes = lt_notes ev_error = lv_error
                             CHANGING  cs_doc   = ls_doc ).
    cl_abap_unit_assert=>assert_not_initial( act = lv_error
      msg = 'plain email without attachment reports an error' ).
  ENDMETHOD.


  METHOD zip_picks_pdf.
    " Create a zip with a PDF and a PNG member; unwrap must select the PDF.
    DATA(lv_pdf) = str_to_x( '%PDF-1.4 zipped bank letter body content' ).
    DATA(lv_png) = str_to_x( 'PNGFAKE zipped logo image content bytes' ).

    DATA(lo_zip) = NEW cl_abap_zip( ).
    lo_zip->add( name = 'logo.png'  content = lv_png ).
    lo_zip->add( name = 'bank.pdf'  content = lv_pdf ).
    " macOS junk that must be skipped:
    lo_zip->add( name = '__MACOSX/._bank.pdf' content = str_to_x( 'junk' ) ).
    DATA(lv_zip) = lo_zip->save( ).

    DATA ls_doc TYPE zcl_mdmdoc_file=>ty_doc.
    ls_doc-name    = 'packet.zip'.
    ls_doc-ext     = 'zip'.
    ls_doc-content = lv_zip.

    DATA lt_notes TYPE string_table.
    DATA lv_error TYPE string.
    zcl_mdmdoc_file=>unwrap( IMPORTING et_notes = lt_notes ev_error = lv_error
                             CHANGING  cs_doc   = ls_doc ).

    cl_abap_unit_assert=>assert_initial( act = lv_error msg = 'zip unwrap should succeed' ).
    cl_abap_unit_assert=>assert_equals( act = ls_doc-ext  exp = 'pdf'
                                        msg = 'PDF chosen over PNG in zip' ).
    cl_abap_unit_assert=>assert_equals( act = ls_doc-name exp = 'bank.pdf' ).
    cl_abap_unit_assert=>assert_equals( act = ls_doc-content exp = lv_pdf
                                        msg = 'chosen content is the PDF member' ).
    cl_abap_unit_assert=>assert_not_initial( act = lt_notes msg = 'zip unwrap records a note' ).
  ENDMETHOD.

  METHOD zip_empty.
    " A zip with only non-document members -> error.
    DATA(lo_zip) = NEW cl_abap_zip( ).
    lo_zip->add( name = 'readme.txt' content = str_to_x( 'nothing to see' ) ).
    DATA(lv_zip) = lo_zip->save( ).

    DATA ls_doc TYPE zcl_mdmdoc_file=>ty_doc.
    ls_doc-name    = 'empty.zip'.
    ls_doc-ext     = 'zip'.
    ls_doc-content = lv_zip.

    DATA lt_notes TYPE string_table.
    DATA lv_error TYPE string.
    zcl_mdmdoc_file=>unwrap( IMPORTING et_notes = lt_notes ev_error = lv_error
                             CHANGING  cs_doc   = ls_doc ).
    cl_abap_unit_assert=>assert_not_initial( act = lv_error
      msg = 'zip with no readable document reports an error' ).
  ENDMETHOD.

ENDCLASS.
