CLASS zcl_mdmdoc_mdg_reader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* MDG change-request reader (implements ZIF_MDMDOC_SAP_READER).
*
* *** VERIFY ON SYSTEM ***
* This class touches MDG framework types/APIs that are NOT available in the
* offline abaplint check, so it is excluded from abaplint (see abaplint.json).
* The read_entity_data_all pattern matches the standard MDG model call; the
* exact entity/field technical names below MUST be confirmed against your data
* model 'BP' (MDGIMG -> Data Modelling -> Edit Data Model / tx USMD_ENTITY),
* and the attachment API against your MDG release. All SAP-specific access is
* contained here; the comparator, types, report and tests do not depend on it.
*----------------------------------------------------------------------*
  PUBLIC SECTION.
    INTERFACES zif_mdmdoc_sap_reader.

    METHODS constructor
      IMPORTING io_model    TYPE REF TO if_usmd_model_ext
                iv_crequest TYPE usmd_crequest.

  PRIVATE SECTION.
    DATA mo_model TYPE REF TO if_usmd_model_ext.
    DATA mv_creq  TYPE usmd_crequest.
    DATA mt_sap   TYPE zif_mdmdoc_types=>tt_sap_fields.

    " Entity technical names in data model BP — CONFIRM against your model.
    CONSTANTS: c_ent_centrl  TYPE usmd_entity VALUE 'BP_CENTRL',
               c_ent_header  TYPE usmd_entity VALUE 'BP_HEADER',
               c_ent_address TYPE usmd_entity VALUE 'ADDRESS',
               c_ent_bankdt  TYPE usmd_entity VALUE 'BP_BANKDT',
               c_ent_iban    TYPE usmd_entity VALUE 'BP_IBAN',
               c_ent_taxnum  TYPE usmd_entity VALUE 'BP_TAXNUM'.

    METHODS read_entity
      IMPORTING iv_entity TYPE usmd_entity
      EXPORTING er_data   TYPE REF TO data.

    METHODS set_sap
      IMPORTING iv_key   TYPE string
                iv_value TYPE string.

    METHODS comp
      IMPORTING is_row          TYPE any
                iv_comp         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS map_name.
    METHODS map_address.
    METHODS map_bank.
    METHODS map_tax.
    METHODS derive_bank_master.
ENDCLASS.


CLASS zcl_mdmdoc_mdg_reader IMPLEMENTATION.

  METHOD constructor.
    mo_model = io_model.
    mv_creq  = iv_crequest.
  ENDMETHOD.

  METHOD read_entity.
    " Build a data reference matching the entity structure, then read the
    " change-request (staged, if_active = space) data for that entity.
    CLEAR er_data.
    TRY.
        mo_model->create_data_reference(
          EXPORTING i_fieldname  = iv_entity
                    i_struct     = if_usmd_model=>gc_struct_key_attr   " key + attributes
                    if_table     = abap_true
          IMPORTING er_data      = er_data ).
        ASSIGN er_data->* TO FIELD-SYMBOL(<lt>).
        IF <lt> IS NOT ASSIGNED.
          RETURN.
        ENDIF.
        DATA lt_sel TYPE usmd_ts_sel.
        mo_model->read_entity_data_all(
          EXPORTING i_fieldname    = iv_entity
                    if_active      = space
                    i_crequest     = mv_creq
                    it_sel         = lt_sel
          IMPORTING et_data_entity = <lt> ).
      CATCH cx_root.
        CLEAR er_data.
    ENDTRY.
  ENDMETHOD.

  METHOD comp.
    ASSIGN COMPONENT iv_comp OF STRUCTURE is_row TO FIELD-SYMBOL(<v>).
    IF sy-subrc = 0.
      rv_value = |{ <v> }|.
      CONDENSE rv_value.
    ENDIF.
  ENDMETHOD.

  METHOD set_sap.
    IF iv_value IS INITIAL.
      RETURN.
    ENDIF.
    READ TABLE mt_sap WITH KEY name = iv_key TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      INSERT VALUE #( name = iv_key value = iv_value ) INTO TABLE mt_sap.
    ENDIF.
  ENDMETHOD.

  METHOD map_name.
    read_entity( EXPORTING iv_entity = c_ent_centrl IMPORTING er_data = DATA(lr) ).
    IF lr IS INITIAL.
      read_entity( EXPORTING iv_entity = c_ent_header IMPORTING er_data = lr ).
    ENDIF.
    IF lr IS INITIAL.
      RETURN.
    ENDIF.
    ASSIGN lr->* TO FIELD-SYMBOL(<lt>).
    LOOP AT <lt> ASSIGNING FIELD-SYMBOL(<row>).
      " organisation name (NAME_ORG1/2) or person (NAME_FIRST/LAST) — CONFIRM
      DATA(lv_name) = comp( is_row = <row> iv_comp = 'NAME_ORG1' ).
      DATA(lv_org2) = comp( is_row = <row> iv_comp = 'NAME_ORG2' ).
      IF lv_name IS INITIAL.
        lv_name = |{ comp( is_row = <row> iv_comp = 'NAME_FIRST' ) } { comp( is_row = <row> iv_comp = 'NAME_LAST' ) }|.
        CONDENSE lv_name.
      ELSEIF lv_org2 IS NOT INITIAL.
        lv_name = |{ lv_name } { lv_org2 }|.
      ENDIF.
      set_sap( iv_key = 'account_holder' iv_value = lv_name ).
      set_sap( iv_key = 'account_name'   iv_value = lv_name ).
      EXIT.
    ENDLOOP.
  ENDMETHOD.

  METHOD map_address.
    read_entity( EXPORTING iv_entity = c_ent_address IMPORTING er_data = DATA(lr) ).
    IF lr IS INITIAL.
      RETURN.
    ENDIF.
    ASSIGN lr->* TO FIELD-SYMBOL(<lt>).
    LOOP AT <lt> ASSIGNING FIELD-SYMBOL(<row>).
      set_sap( iv_key = 'street' iv_value = comp( is_row = <row> iv_comp = 'STREET' ) ).
      set_sap( iv_key = 'city'   iv_value = comp( is_row = <row> iv_comp = 'CITY1' ) ).
      EXIT.
    ENDLOOP.
  ENDMETHOD.

  METHOD map_bank.
    read_entity( EXPORTING iv_entity = c_ent_bankdt IMPORTING er_data = DATA(lr) ).
    IF lr IS NOT INITIAL.
      ASSIGN lr->* TO FIELD-SYMBOL(<lt>).
      LOOP AT <lt> ASSIGNING FIELD-SYMBOL(<row>).
        set_sap( iv_key = 'bank_country' iv_value = comp( is_row = <row> iv_comp = 'BANKS' ) ).
        set_sap( iv_key = 'bank_key'     iv_value = comp( is_row = <row> iv_comp = 'BANKL' ) ).
        set_sap( iv_key = 'bank_account' iv_value = comp( is_row = <row> iv_comp = 'BANKN' ) ).
        set_sap( iv_key = 'control_key'  iv_value = comp( is_row = <row> iv_comp = 'BKONT' ) ).
        set_sap( iv_key = 'iban'         iv_value = comp( is_row = <row> iv_comp = 'IBAN' ) ).
        EXIT.
      ENDLOOP.
    ENDIF.
    " IBAN may live in a separate entity
    IF NOT line_exists( mt_sap[ name = 'iban' ] ).
      read_entity( EXPORTING iv_entity = c_ent_iban IMPORTING er_data = DATA(lri) ).
      IF lri IS NOT INITIAL.
        ASSIGN lri->* TO FIELD-SYMBOL(<lti>).
        LOOP AT <lti> ASSIGNING FIELD-SYMBOL(<ri>).
          set_sap( iv_key = 'iban' iv_value = comp( is_row = <ri> iv_comp = 'IBAN' ) ).
          EXIT.
        ENDLOOP.
      ENDIF.
    ENDIF.
    derive_bank_master( ).
  ENDMETHOD.

  METHOD derive_bank_master.
    " bank name + SWIFT from the active bank master (BNKA) by country + bank key
    DATA(lv_banks) = COND banks( WHEN line_exists( mt_sap[ name = 'bank_country' ] )
                                 THEN CONV banks( mt_sap[ name = 'bank_country' ]-value ) ).
    DATA(lv_bankl) = COND bankk( WHEN line_exists( mt_sap[ name = 'bank_key' ] )
                                 THEN CONV bankk( mt_sap[ name = 'bank_key' ]-value ) ).
    IF lv_banks IS INITIAL OR lv_bankl IS INITIAL.
      RETURN.
    ENDIF.
    SELECT SINGLE banka, swift FROM bnka
      INTO @DATA(ls_bnka)
      WHERE banks = @lv_banks AND bankl = @lv_bankl.
    IF sy-subrc = 0.
      set_sap( iv_key = 'bank_name' iv_value = |{ ls_bnka-banka }| ).
      set_sap( iv_key = 'swift_bic' iv_value = |{ ls_bnka-swift }| ).
    ENDIF.
  ENDMETHOD.

  METHOD map_tax.
    read_entity( EXPORTING iv_entity = c_ent_taxnum IMPORTING er_data = DATA(lr) ).
    IF lr IS INITIAL.
      RETURN.
    ENDIF.
    ASSIGN lr->* TO FIELD-SYMBOL(<lt>).
    LOOP AT <lt> ASSIGNING FIELD-SYMBOL(<row>).
      DATA(lv_type) = comp( is_row = <row> iv_comp = 'TAXTYPE' ).
      " US tax types (US1 = SSN, US2 = EIN) — CONFIRM the types you use
      IF lv_type CP 'US*'.
        set_sap( iv_key = 'tin' iv_value = comp( is_row = <row> iv_comp = 'TAXNUM' ) ).
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_mdmdoc_sap_reader~read_cr_fields.
    CLEAR: et_sap, ev_found, ev_error.
    CLEAR mt_sap.
    TRY.
        map_name( ).
        map_address( ).
        map_bank( ).
        map_tax( ).
      CATCH cx_root INTO DATA(lx).
        ev_error = lx->get_text( ).
    ENDTRY.
    et_sap   = mt_sap.
    ev_found = boolc( mt_sap IS NOT INITIAL ).
  ENDMETHOD.

  METHOD zif_mdmdoc_sap_reader~read_cr_attachments.
    CLEAR: et_docs, ev_error.
    " CR attachments are GOS attachments on the change-request object.
    " *** VERIFY ON SYSTEM ***: object type + GOS API differ by MDG release.
    " Typical path (S/4): cl_gos_api for object { objtype='USMD_CREQ' objkey=cr }.
    DATA ls_obj TYPE sibflporb.
    ls_obj-typeid = 'USMD_CREQ'.               " CONFIRM BOR/IBO object type of the CR
    ls_obj-instid = iv_cr.
    ls_obj-catid  = 'BO'.
    TRY.
        DATA(lo_gos) = cl_gos_api=>create_instance( is_object = ls_obj ).
        DATA(lt_att) = lo_gos->get_atta_list( ).
        LOOP AT lt_att INTO DATA(ls_att).
          DATA(lo_doc) = lo_gos->read_attachment( is_attachment_key = ls_att-atta_key ).
          DATA(lv_content) = lo_doc->get_content( ).       " xstring
          DATA(lv_name)    = lo_doc->get_description( ).
          DATA lv_ext TYPE string.
          FIND REGEX '\.([A-Za-z0-9]+)$' IN lv_name SUBMATCHES lv_ext.
          APPEND VALUE #( name = lv_name ext = to_lower( lv_ext ) content = lv_content ) TO et_docs.
        ENDLOOP.
      CATCH cx_root INTO DATA(lx).
        ev_error = |CR attachment read not available on this release: { lx->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
