CLASS zcl_mdmdoc_mdg_reader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* MDG change-request reader (implements ZIF_MDMDOC_SAP_READER).
*
* Config-driven: the SAP_KEY -> (entity, field) mapping comes from
* ZCL_MDMDOC_MDG_MAP (defaults, overridable by table ZMDMDOC_MAP), so entity
* and field names are NOT hard-coded here — run ZMDMDOC_MDG_DISCOVER to adapt
* the mapping to your data model.
*
* *** VERIFY ON SYSTEM *** — excluded from abaplint (MDG framework types).
* Confirm the read_entity_data_all / create_data_reference calls and the
* attachment API against your MDG release. All SAP-specific access is here;
* the comparator, types, report, self-test and tests do not depend on it.
*----------------------------------------------------------------------*
  PUBLIC SECTION.
    INTERFACES zif_mdmdoc_sap_reader.

    METHODS constructor
      IMPORTING io_model    TYPE REF TO if_usmd_model_ext
                iv_crequest TYPE usmd_crequest
                iv_model    TYPE usmd_model DEFAULT 'BP'.

  PRIVATE SECTION.
    DATA mo_model TYPE REF TO if_usmd_model_ext.
    DATA mv_creq  TYPE usmd_crequest.
    DATA mv_model TYPE usmd_model.
    DATA mt_sap   TYPE zif_mdmdoc_types=>tt_sap_fields.

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

    METHODS derive_bank_master.
ENDCLASS.


CLASS zcl_mdmdoc_mdg_reader IMPLEMENTATION.

  METHOD constructor.
    mo_model = io_model.
    mv_creq  = iv_crequest.
    mv_model = iv_model.
  ENDMETHOD.

  METHOD read_entity.
    CLEAR er_data.
    TRY.
        mo_model->create_data_reference(
          EXPORTING i_fieldname = iv_entity
                    i_struct    = if_usmd_model=>gc_struct_key_attr
                    if_table    = abap_true
          IMPORTING er_data     = er_data ).
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

  METHOD derive_bank_master.
    " bank name + SWIFT from the active bank master (BNKA) by country + bank key
    IF NOT line_exists( mt_sap[ name = 'bank_country' ] ) OR NOT line_exists( mt_sap[ name = 'bank_key' ] ).
      RETURN.
    ENDIF.
    DATA(lv_banks) = CONV banks( mt_sap[ name = 'bank_country' ]-value ).
    DATA(lv_bankl) = CONV bankk( mt_sap[ name = 'bank_key' ]-value ).
    SELECT SINGLE banka, swift FROM bnka
      INTO @DATA(ls_bnka)
      WHERE banks = @lv_banks AND bankl = @lv_bankl.
    IF sy-subrc = 0.
      set_sap( iv_key = 'bank_name' iv_value = |{ ls_bnka-banka }| ).
      set_sap( iv_key = 'swift_bic' iv_value = |{ ls_bnka-swift }| ).
    ENDIF.
  ENDMETHOD.

  METHOD zif_mdmdoc_sap_reader~read_cr_fields.
    CLEAR: et_sap, ev_found, ev_error.
    CLEAR mt_sap.
    TRY.
        DATA(lt_map) = zcl_mdmdoc_mdg_map=>get_map( mv_model ).

        " distinct entities in the mapping
        DATA lt_ent TYPE STANDARD TABLE OF usmd_entity.
        LOOP AT lt_map INTO DATA(ls_m).
          IF ls_m-entity IS NOT INITIAL AND NOT line_exists( lt_ent[ table_line = ls_m-entity ] ).
            APPEND CONV usmd_entity( ls_m-entity ) TO lt_ent.
          ENDIF.
        ENDLOOP.

        " read each entity once, copy the mapped fields from its first row
        LOOP AT lt_ent INTO DATA(lv_ent).
          read_entity( EXPORTING iv_entity = lv_ent IMPORTING er_data = DATA(lr) ).
          IF lr IS INITIAL.
            CONTINUE.
          ENDIF.
          ASSIGN lr->* TO FIELD-SYMBOL(<lt>).
          LOOP AT <lt> ASSIGNING FIELD-SYMBOL(<row>).
            LOOP AT lt_map INTO ls_m WHERE entity = lv_ent.
              set_sap( iv_key = ls_m-sap_key iv_value = comp( is_row = <row> iv_comp = ls_m-field ) ).
            ENDLOOP.
            EXIT.   " first row per entity (e.g. primary bank detail)
          ENDLOOP.
        ENDLOOP.

        " mirror holder into account_name, derive bank master (name/SWIFT)
        IF line_exists( mt_sap[ name = 'account_holder' ] ) AND NOT line_exists( mt_sap[ name = 'account_name' ] ).
          set_sap( iv_key = 'account_name' iv_value = mt_sap[ name = 'account_holder' ]-value ).
        ENDIF.
        derive_bank_master( ).
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
    DATA ls_obj TYPE sibflporb.
    ls_obj-typeid = 'USMD_CREQ'.               " CONFIRM BOR/IBO object type of the CR
    ls_obj-instid = iv_cr.
    ls_obj-catid  = 'BO'.
    TRY.
        DATA(lo_gos) = cl_gos_api=>create_instance( is_object = ls_obj ).
        DATA(lt_att) = lo_gos->get_atta_list( ).
        LOOP AT lt_att INTO DATA(ls_att).
          DATA(lo_doc)     = lo_gos->read_attachment( is_attachment_key = ls_att-atta_key ).
          DATA(lv_content) = lo_doc->get_content( ).
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
