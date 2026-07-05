*&---------------------------------------------------------------------*
*& Report ZMDMDOC_MDG_DISCOVER
*&---------------------------------------------------------------------*
*& Adaptability helper: reads the actual field architecture of an MDG data
*& model (entities + fields), then proposes the SAP_KEY -> entity/field mapping
*& the comparator needs — by matching real field names against known synonyms.
*& You review the proposal and (optionally) save it to table ZMDMDOC_MAP, which
*& ZCL_MDMDOC_MDG_READER then uses at runtime. No code change per customer.
*&
*& *** VERIFY ON SYSTEM *** — touches MDG metadata APIs; excluded from abaplint.
*& Confirm the entity-list / structure calls against your MDG release.
*&---------------------------------------------------------------------*
REPORT zmdmdoc_mdg_discover.

PARAMETERS: p_model TYPE usmd_model DEFAULT 'BP'.
PARAMETERS: p_save  AS CHECKBOX DEFAULT ' '.     " persist proposal to ZMDMDOC_MAP
PARAMETERS: p_list  AS CHECKBOX DEFAULT 'X'.     " also list all entities/fields

TYPES: BEGIN OF ty_syn,
         sap_key TYPE string,
         cand    TYPE string,      " comma-separated candidate field names
       END OF ty_syn.

START-OF-SELECTION.
  " synonyms: SAP_KEY -> candidate MDG field names (first match wins)
  DATA(lt_syn) = VALUE STANDARD TABLE OF ty_syn(
    ( sap_key = 'account_holder' cand = 'NAME_ORG1,NAME_FIRST,NAME1,MC_NAME1' )
    ( sap_key = 'street'         cand = 'STREET' )
    ( sap_key = 'city'           cand = 'CITY1,ORT01' )
    ( sap_key = 'bank_country'   cand = 'BANKS,BANKN_BANKS' )
    ( sap_key = 'bank_key'       cand = 'BANKL' )
    ( sap_key = 'bank_account'   cand = 'BANKN' )
    ( sap_key = 'control_key'    cand = 'BKONT' )
    ( sap_key = 'iban'           cand = 'IBAN' )
    ( sap_key = 'tin'            cand = 'TAXNUM,TAXNUMBER' ) ).

  DATA lt_map TYPE zif_mdmdoc_types=>tt_map.

  TRY.
      " *** VERIFY ON SYSTEM ***: obtaining the model instance + entity list
      DATA(lo_model) = cl_usmd_model_ext=>get_instance( i_usmd_model = p_model ).
      DATA lt_ent TYPE usmd_ts_entity.
      lo_model->get_entities( IMPORTING et_entity = lt_ent ).

      IF p_list = abap_true.
        WRITE: / |Data model { p_model } — entities and fields:|. ULINE.
      ENDIF.

      LOOP AT lt_ent INTO DATA(ls_ent).
        " structure reference of the entity -> component (field) names via RTTI
        DATA lr TYPE REF TO data.
        CLEAR lr.
        TRY.
            lo_model->create_data_reference(
              EXPORTING i_fieldname = ls_ent-usmd_entity
                        i_struct    = if_usmd_model=>gc_struct_key_attr
                        if_table    = abap_false
              IMPORTING er_data     = lr ).
          CATCH cx_root.
            CONTINUE.
        ENDTRY.
        IF lr IS INITIAL.
          CONTINUE.
        ENDIF.
        DATA(lo_sd) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_data_ref( lr ) ).

        IF p_list = abap_true.
          DATA lv_fields TYPE string.
          CLEAR lv_fields.
          LOOP AT lo_sd->components INTO DATA(ls_c).
            lv_fields = COND #( WHEN lv_fields IS INITIAL THEN |{ ls_c-name }| ELSE |{ lv_fields }, { ls_c-name }| ).
          ENDLOOP.
          WRITE: / |{ ls_ent-usmd_entity }:|, AT 20 lv_fields.
        ENDIF.

        " match this entity's fields against the synonyms -> propose mapping
        LOOP AT lt_syn INTO DATA(ls_syn).
          IF line_exists( lt_map[ sap_key = ls_syn-sap_key ] ).
            CONTINUE.
          ENDIF.
          SPLIT ls_syn-cand AT ',' INTO TABLE DATA(lt_cand).
          LOOP AT lt_cand INTO DATA(lv_cand).
            IF line_exists( lo_sd->components[ name = lv_cand ] ).
              APPEND VALUE #( sap_key = ls_syn-sap_key
                              entity  = |{ ls_ent-usmd_entity }|
                              field   = lv_cand ) TO lt_map.
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDLOOP.
      ENDLOOP.
    CATCH cx_root INTO DATA(lx).
      WRITE: / |Could not read model { p_model }: { lx->get_text( ) }|.
      WRITE: / 'Verify cl_usmd_model_ext=>get_instance / get_entities on your release.'.
      RETURN.
  ENDTRY.

  " ---- proposed mapping ----
  SKIP. WRITE: / |Proposed SAP_KEY -> entity.field mapping for { p_model }:|. ULINE.
  LOOP AT lt_map INTO DATA(ls_m).
    WRITE: / ls_m-sap_key, AT 22 |{ ls_m-entity }.{ ls_m-field }|.
  ENDLOOP.

  " gaps: comparator keys with no match found
  DATA(lt_want) = VALUE string_table(
    ( `account_holder` ) ( `bank_country` ) ( `bank_key` ) ( `bank_account` )
    ( `iban` ) ( `control_key` ) ( `street` ) ( `city` ) ( `tin` ) ).
  SKIP. WRITE: / 'Unmatched keys (fill ZMDMDOC_MAP manually if needed):'.
  LOOP AT lt_want INTO DATA(lv_w).
    IF NOT line_exists( lt_map[ sap_key = lv_w ] ).
      WRITE: / '  -', lv_w.
    ENDIF.
  ENDLOOP.

  " ---- optional persist to ZMDMDOC_MAP ----
  IF p_save = abap_true AND lt_map IS NOT INITIAL.
    TRY.
        DATA lr_row TYPE REF TO data.
        CREATE DATA lr_row TYPE ('ZMDMDOC_MAP').
        ASSIGN lr_row->* TO FIELD-SYMBOL(<row>).
        LOOP AT lt_map INTO ls_m.
          CLEAR <row>.
          ASSIGN COMPONENT 'MODEL'   OF STRUCTURE <row> TO FIELD-SYMBOL(<f>). IF sy-subrc = 0. <f> = p_model. ENDIF.
          ASSIGN COMPONENT 'SAP_KEY' OF STRUCTURE <row> TO <f>.               IF sy-subrc = 0. <f> = ls_m-sap_key. ENDIF.
          ASSIGN COMPONENT 'ENTITY'  OF STRUCTURE <row> TO <f>.               IF sy-subrc = 0. <f> = ls_m-entity. ENDIF.
          ASSIGN COMPONENT 'FIELD'   OF STRUCTURE <row> TO <f>.               IF sy-subrc = 0. <f> = ls_m-field. ENDIF.
          MODIFY ('ZMDMDOC_MAP') FROM <row>.
        ENDLOOP.
        SKIP. WRITE: / |Saved { lines( lt_map ) } row(s) to ZMDMDOC_MAP.|.
      CATCH cx_root INTO DATA(lxs).
        SKIP. WRITE: / |Could not save (create table ZMDMDOC_MAP first): { lxs->get_text( ) }|.
    ENDTRY.
  ENDIF.
