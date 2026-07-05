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
                                        ELSE `no text — check CL_ABAP_GZIP for compressed PDFs` ) ).
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
    APPEND check_json( ) TO rt_checks.
    APPEND check_mask( ) TO rt_checks.
    APPEND check_pdf( ) TO rt_checks.
    APPEND check_comparator( ) TO rt_checks.
  ENDMETHOD.

ENDCLASS.
