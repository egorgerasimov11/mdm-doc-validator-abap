CLASS zcl_mdmdoc_sap_manual DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_mdmdoc_sap_reader.

    " Manual / test-double reader. SAP fields come from either a direct table
    " or a flat JSON object {"iban":"..","bank_name":".."}; attachments (if any)
    " are supplied directly. Makes the comparator fully runnable without a
    " live SAP system.
    METHODS constructor
      IMPORTING it_sap  TYPE zif_mdmdoc_types=>tt_sap_fields OPTIONAL
                iv_json TYPE string OPTIONAL
                it_docs TYPE zif_mdmdoc_sap_reader=>tt_attachment OPTIONAL.

  PRIVATE SECTION.
    DATA mt_sap  TYPE zif_mdmdoc_types=>tt_sap_fields.
    DATA mt_docs TYPE zif_mdmdoc_sap_reader=>tt_attachment.

    METHODS parse_json
      IMPORTING iv_json       TYPE string
      RETURNING VALUE(rt_sap) TYPE zif_mdmdoc_types=>tt_sap_fields.
ENDCLASS.


CLASS zcl_mdmdoc_sap_manual IMPLEMENTATION.

  METHOD constructor.
    IF it_sap IS NOT INITIAL.
      mt_sap = it_sap.
    ELSEIF iv_json IS NOT INITIAL.
      mt_sap = parse_json( iv_json ).
    ENDIF.
    mt_docs = it_docs.
  ENDMETHOD.

  METHOD parse_json.
    " flat JSON object -> tt_sap_fields, keyed by SAP_KEYS
    TYPES: BEGIN OF ty_json,
             bank_details_id   TYPE string,
             bank_account      TYPE string,
             account_holder    TYPE string,
             iban              TYPE string,
             account_name      TYPE string,
             control_key       TYPE string,
             reference_details TYPE string,
             bank_country      TYPE string,
             bank_key          TYPE string,
             bank_name         TYPE string,
             street            TYPE string,
             city              TYPE string,
             bank_branch       TYPE string,
             swift_bic         TYPE string,
           END OF ty_json.
    DATA ls_json TYPE ty_json.
    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json = iv_json pretty_name = /ui2/cl_json=>pretty_mode-none
                                   CHANGING data = ls_json ).
      CATCH cx_root.
        RETURN.
    ENDTRY.
    SPLIT zif_mdmdoc_types=>c_sap_keys AT ',' INTO TABLE DATA(lt_keys).
    LOOP AT lt_keys INTO DATA(lv_key).
      ASSIGN COMPONENT lv_key OF STRUCTURE ls_json TO FIELD-SYMBOL(<v>).
      IF sy-subrc = 0 AND <v> IS NOT INITIAL.
        INSERT VALUE #( name = lv_key value = <v> ) INTO TABLE rt_sap.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_mdmdoc_sap_reader~read_cr_fields.
    CLEAR: et_sap, ev_found, ev_error.
    et_sap   = mt_sap.
    ev_found = boolc( mt_sap IS NOT INITIAL ).
  ENDMETHOD.

  METHOD zif_mdmdoc_sap_reader~read_cr_attachments.
    CLEAR: et_docs, ev_error.
    et_docs = mt_docs.
  ENDMETHOD.

ENDCLASS.
