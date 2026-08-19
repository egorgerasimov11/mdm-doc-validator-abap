CLASS zcl_mdmdoc_selftest DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Small, independent pre-flight checks. Each returns PASS/FAIL/SKIP so you
    " can confirm — before enabling the MDG BAdI globally — that the building
    " blocks work in isolation. run_core() covers everything that does NOT need
    " a live SAP MDG system; the ZMDMDOC_DOCTOR report adds the MDG checks on top.
    CLASS-METHODS run_core
      RETURNING VALUE(rt_checks) TYPE zif_mdmdoc_types=>tt_check.

    CLASS-METHODS check_class
      IMPORTING iv_name         TYPE string
      RETURNING VALUE(rs_check) TYPE zif_mdmdoc_types=>ty_check.

    CLASS-METHODS check_json
      RETURNING VALUE(rs_check) TYPE zif_mdmdoc_types=>ty_check.

    CLASS-METHODS check_mask
      RETURNING VALUE(rs_check) TYPE zif_mdmdoc_types=>ty_check.

    CLASS-METHODS check_pdf
      RETURNING VALUE(rs_check) TYPE zif_mdmdoc_types=>ty_check.

    CLASS-METHODS check_pdf_flate
      RETURNING VALUE(rs_check) TYPE zif_mdmdoc_types=>ty_check.

    CLASS-METHODS check_codepage
      RETURNING VALUE(rs_check) TYPE zif_mdmdoc_types=>ty_check.

    CLASS-METHODS check_comparator
      RETURNING VALUE(rs_check) TYPE zif_mdmdoc_types=>ty_check.

  PRIVATE SECTION.
    CLASS-METHODS chk
      IMPORTING iv_name         TYPE string
                iv_ok           TYPE abap_bool
                iv_detail       TYPE string
      RETURNING VALUE(rs_check) TYPE zif_mdmdoc_types=>ty_check.
ENDCLASS.


CLASS zcl_mdmdoc_selftest IMPLEMENTATION.

  METHOD chk.
    rs_check-name   = iv_name.
    rs_check-status = COND #( WHEN iv_ok = abap_true THEN zif_mdmdoc_types=>c_check-pass ELSE zif_mdmdoc_types=>c_check-fail ).
    rs_check-detail = iv_detail.
  ENDMETHOD.

  METHOD check_class.
    " existence of a class / interface by name (RTTI)
    cl_abap_typedescr=>describe_by_name(
      EXPORTING p_name = iv_name
      RECEIVING p_descr_ref = DATA(lo)
      EXCEPTIONS type_not_found = 1 OTHERS = 2 ).
    rs_check = chk( iv_name = |type available: { iv_name }|
                    iv_ok = boolc( sy-subrc = 0 )
                    iv_detail = COND #( WHEN sy-subrc = 0 THEN `found` ELSE `NOT found — check the component/install` ) ).
  ENDMETHOD.

  METHOD check_json.
    TYPES: BEGIN OF ty_p, a TYPE string, END OF ty_p.
    DATA ls_in TYPE ty_p.
    DATA ls_out TYPE ty_p.
    ls_in-a = 'ping'.
    DATA lv_ok TYPE abap_bool.
    TRY.
        DATA(lv_json) = /ui2/cl_json=>serialize( data = ls_in ).
        /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_out ).
        lv_ok = boolc( ls_out-a = 'ping' ).
      CATCH cx_root.
        lv_ok = abap_false.
    ENDTRY.
    rs_check = chk( iv_name = '/UI2/CL_JSON serialize/deserialize'
                    iv_ok = lv_ok
                    iv_detail = COND #( WHEN lv_ok = abap_true THEN `round-trip ok` ELSE `unavailable — LLM/JSON features disabled` ) ).
  ENDMETHOD.

  METHOD check_mask.
    DATA(lv_m) = zcl_mdmdoc_mask=>mask( iv_kind = zif_mdmdoc_types=>c_kind-iban iv_value = 'DE44500105175407324931' ).
    DATA lv_ok TYPE abap_bool.
    lv_ok = boolc( lv_m CS 'DE' AND lv_m CS '*' AND NOT lv_m CS '500105175407324931' ).
    rs_check = chk( iv_name = 'masking (IBAN never shown in full)'
                    iv_ok = lv_ok iv_detail = |sample -> { lv_m }| ).
  ENDMETHOD.

  METHOD check_pdf.
    " tiny uncompressed PDF with a text stream -> the parser must recover the text
    DATA(lv_pdf) =
      |%PDF-1.4\n1 0 obj\n<< /Length 24 >>\nstream\n| &&
      |BT (mdmdoc ok) Tj ET\n| &&
      |endstream\nendobj\n%%EOF\n|.
    DATA(lv_x) = cl_abap_codepage=>convert_to( source = lv_pdf codepage = `ISO-8859-1` ).
    zcl_mdmdoc_pdf=>extract_text( EXPORTING iv_pdf = lv_x IMPORTING ev_text = DATA(lv_text) ).
    DATA lv_ok TYPE abap_bool.
    lv_ok = boolc( lv_text CS 'mdmdoc ok' ).
    rs_check = chk( iv_name = 'PDF text-layer extraction (uncompressed)'
                    iv_ok = lv_ok
                    iv_detail = COND #( WHEN lv_ok = abap_true THEN `recovered text`
                                        ELSE `no text — PDF scanner broken` ) ).
  ENDMETHOD.


  METHOD check_pdf_flate.
    " tiny PDF whose stream is REAL zlib (the format of every real-world PDF) — this is
    " the check that would have caught C-2026-08-20-01 on day one
    DATA lv_z TYPE xstring.
    lv_z =
      '789C730A51D0773354303450084953303550303700B2521434DC72124B521532527372F215D28AF27315A27C5D7C5DFC9D35' &&
      '1542B2145C430087750EF6'.
    DATA(lv_head) = |%PDF-1.4\n1 0 obj\n<< /Length 61 /Filter /FlateDecode >>\nstream\n|.
    DATA(lv_tail) = |\nendstream\nendobj\n%%EOF\n|.
    DATA(lv_head_x) = cl_abap_codepage=>convert_to( source = lv_head codepage = `ISO-8859-1` ).
    DATA(lv_tail_x) = cl_abap_codepage=>convert_to( source = lv_tail codepage = `ISO-8859-1` ).
    DATA lv_pdf TYPE xstring.
    CONCATENATE lv_head_x lv_z lv_tail_x INTO lv_pdf IN BYTE MODE.
    zcl_mdmdoc_pdf=>extract_text( EXPORTING iv_pdf = lv_pdf
                                  IMPORTING ev_text = DATA(lv_text) et_warnings = DATA(lt_warn) ).
    DATA lv_failed TYPE abap_bool.
    DATA lv_w TYPE string.
    LOOP AT lt_warn INTO lv_w.
      IF lv_w CS 'inflate-failed'.
        lv_failed = abap_true.
      ENDIF.
    ENDLOOP.
    DATA lv_ok TYPE abap_bool.
    lv_ok = boolc( lv_text CS 'Flate hello' AND lv_failed = abap_false ).
    rs_check = chk( iv_name = 'PDF text-layer extraction (zlib /FlateDecode)'
                    iv_ok = lv_ok
                    iv_detail = COND #( WHEN lv_ok = abap_true THEN `inflated + recovered text`
                                        ELSE `inflate broken — real PDFs will all fall back to manual review` ) ).
  ENDMETHOD.


  METHOD check_codepage.
    " compressed stream bodies survive the bytes->string->bytes round trip only if the
    " codepage maps all 256 byte values 1:1 on THIS kernel
    DATA lv_in TYPE xstring.
    DATA lv_b  TYPE x LENGTH 1.
    DATA lv_i  TYPE i.
    DO 256 TIMES.
      lv_i = sy-index - 1.
      lv_b = lv_i.
      CONCATENATE lv_in lv_b INTO lv_in IN BYTE MODE.
    ENDDO.
    DATA lv_ok TYPE abap_bool.
    DATA lv_detail TYPE string.
    TRY.
        DATA(lo_in)  = cl_abap_conv_in_ce=>create( encoding = '1100' ).
        DATA(lo_out) = cl_abap_conv_out_ce=>create( encoding = '1100' ).
        DATA lv_str TYPE string.
        lo_in->convert( EXPORTING input = lv_in IMPORTING data = lv_str ).
        DATA lv_back TYPE xstring.
        lo_out->convert( EXPORTING data = lv_str IMPORTING buffer = lv_back ).
        lv_ok = boolc( lv_back = lv_in ).
        lv_detail = COND #( WHEN lv_ok = abap_true THEN `all 256 byte values round-trip 1:1`
                            ELSE `codepage 1100 mangles bytes — compressed PDF streams will corrupt` ).
      CATCH cx_root.
        lv_ok = abap_false.
        lv_detail = `conversion dumps on some byte values`.
    ENDTRY.
    rs_check = chk( iv_name = 'codepage 1100 byte transparency (0x00-0xFF)'
                    iv_ok = lv_ok
                    iv_detail = lv_detail ).
  ENDMETHOD.

  METHOD check_comparator.
    DATA ls_ext TYPE zif_mdmdoc_types=>ty_extraction.
    ls_ext-doc_class = 'bank'.
    INSERT VALUE #( name = 'iban' value = 'DE44500105175407324931' ) INTO TABLE ls_ext-fields.
    DATA(lt_sap) = VALUE zif_mdmdoc_types=>tt_sap_fields( ( name = 'iban' value = 'DE44500105175407324999' ) ).
    zcl_mdmdoc_compare=>compare( EXPORTING is_ext = ls_ext it_sap = lt_sap IMPORTING et_findings = DATA(lt_find) ).
    DATA lv_ok TYPE abap_bool.
    LOOP AT lt_find TRANSPORTING NO FIELDS WHERE rule_id = 'SAP-001'.
      lv_ok = abap_true.
    ENDLOOP.
    rs_check = chk( iv_name = 'comparator (IBAN mismatch -> SAP-001)'
                    iv_ok = lv_ok iv_detail = COND #( WHEN lv_ok = abap_true THEN `fires as expected` ELSE `no SAP-001` ) ).
  ENDMETHOD.

  METHOD run_core.
    APPEND check_class( 'CL_ABAP_GZIP' ) TO rt_checks.
    APPEND check_class( 'CL_ABAP_ZIP' ) TO rt_checks.
    APPEND check_class( 'CL_ABAP_MESSAGE_DIGEST' ) TO rt_checks.
    APPEND check_class( 'CL_HTTP_CLIENT' ) TO rt_checks.
    APPEND check_class( 'ZCL_MDMDOC_COMPARE' ) TO rt_checks.
    APPEND check_class( 'ZIF_MDMDOC_SAP_READER' ) TO rt_checks.
    APPEND check_class( 'ZCL_MDMDOC_INFLATE' ) TO rt_checks.
    APPEND check_json( ) TO rt_checks.
    APPEND check_mask( ) TO rt_checks.
    APPEND check_pdf( ) TO rt_checks.
    APPEND check_pdf_flate( ) TO rt_checks.
    APPEND check_codepage( ) TO rt_checks.
    APPEND check_comparator( ) TO rt_checks.
  ENDMETHOD.

ENDCLASS.
