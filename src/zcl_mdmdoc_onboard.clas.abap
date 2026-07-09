CLASS zcl_mdmdoc_onboard DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* One-shot onboarding orchestrator: runs the whole deployment verification
* in the right order and returns a single consolidated result —
*   1. pre-flight checks (core self-test + MDG availability + message class)
*   2. MDG field-architecture discovery (proposed SAP_KEY -> entity.field map)
*   3. optional live change-request read (fields + attachments) for a given CR
* The report ZMDMDOC_SETUP just prints what this returns; ZMDMDOC_DOCTOR and
* ZMDMDOC_MDG_DISCOVER call the same logic for focused views (no duplication).
*
* *** VERIFY ON SYSTEM *** — touches MDG APIs; excluded from abaplint. The core
* checks come from the unit-tested ZCL_MDMDOC_SELFTEST; MDG parts degrade
* gracefully (a FAIL line instead of a dump) when an API differs.
*----------------------------------------------------------------------*
  PUBLIC SECTION.
    CLASS-METHODS run
      IMPORTING iv_model    TYPE usmd_model     DEFAULT 'BP'
                iv_cr       TYPE usmd_crequest  OPTIONAL
                iv_save     TYPE abap_bool      DEFAULT abap_false
      EXPORTING et_checks   TYPE zif_mdmdoc_types=>tt_check
                et_map      TYPE zif_mdmdoc_types=>tt_map
                et_gaps     TYPE string_table
                et_entities TYPE string_table.

    " list output (shared by the ZMDMDOC_SETUP / _DOCTOR / _MDG_DISCOVER reports)
    CLASS-METHODS print_checks
      IMPORTING it_checks TYPE zif_mdmdoc_types=>tt_check.

    CLASS-METHODS print_map
      IMPORTING it_map      TYPE zif_mdmdoc_types=>tt_map
                it_gaps     TYPE string_table
                it_entities TYPE string_table OPTIONAL
                iv_list     TYPE abap_bool DEFAULT abap_false.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_syn,
             sap_key TYPE string,
             cand    TYPE string,
           END OF ty_syn.

    CLASS-METHODS preflight
      IMPORTING iv_model   TYPE usmd_model
      CHANGING  ct_checks  TYPE zif_mdmdoc_types=>tt_check.

    CLASS-METHODS discover
      IMPORTING iv_model    TYPE usmd_model
      EXPORTING et_map      TYPE zif_mdmdoc_types=>tt_map
                et_gaps     TYPE string_table
                et_entities TYPE string_table
      CHANGING  ct_checks   TYPE zif_mdmdoc_types=>tt_check.

    CLASS-METHODS live_cr
      IMPORTING iv_model  TYPE usmd_model
                iv_cr     TYPE usmd_crequest
      CHANGING  ct_checks TYPE zif_mdmdoc_types=>tt_check.

    CLASS-METHODS add
      IMPORTING iv_name   TYPE string
                iv_ok     TYPE abap_bool
                iv_detail TYPE string
      CHANGING  ct_checks TYPE zif_mdmdoc_types=>tt_check.

    CLASS-METHODS save_map
      IMPORTING iv_model TYPE usmd_model
                it_map   TYPE zif_mdmdoc_types=>tt_map
      CHANGING  ct_checks TYPE zif_mdmdoc_types=>tt_check.
ENDCLASS.


CLASS zcl_mdmdoc_onboard IMPLEMENTATION.

  METHOD add.
    APPEND VALUE #( name = iv_name detail = iv_detail
                    status = COND #( WHEN iv_ok = abap_true THEN zif_mdmdoc_types=>c_check-pass
                                     ELSE zif_mdmdoc_types=>c_check-fail ) ) TO ct_checks.
  ENDMETHOD.

  METHOD preflight.
    " core (unit-tested, no MDG)
    ct_checks = zcl_mdmdoc_selftest=>run_core( ).
    " MDG availability
    APPEND zcl_mdmdoc_selftest=>check_class( 'IF_USMD_MODEL_EXT' ) TO ct_checks.
    APPEND zcl_mdmdoc_selftest=>check_class( 'ZCL_MDMDOC_MDG_READER' ) TO ct_checks.
    APPEND zcl_mdmdoc_selftest=>check_class( 'ZCL_MDG_BP_FIELD_DERR_VAL' ) TO ct_checks.
    APPEND zcl_mdmdoc_selftest=>check_class( 'CL_GOS_API' ) TO ct_checks.
    " message class ZMDMDOC / 001
    DATA lv_txt TYPE string.
    SELECT SINGLE text FROM t100 INTO @lv_txt
      WHERE sprsl = @sy-langu AND arbgb = 'ZMDMDOC' AND msgnr = '001'.
    add( EXPORTING iv_name = 'message class ZMDMDOC / 001' iv_ok = boolc( sy-subrc = 0 )
                   iv_detail = COND #( WHEN sy-subrc = 0 THEN 'defined' ELSE 'create in SE91 (001 = &1&2&3&4)' )
         CHANGING ct_checks = ct_checks ).
  ENDMETHOD.

  METHOD discover.
    DATA(lt_syn) = VALUE STANDARD TABLE OF ty_syn(
      ( sap_key = 'account_holder' cand = 'NAME_ORG1,NAME_FIRST,NAME1,MC_NAME1,KOINH,ACCNAME' )
      ( sap_key = 'street'         cand = 'STREET' )
      ( sap_key = 'city'           cand = 'CITY1,ORT01' )
      ( sap_key = 'bank_country'   cand = 'BANKS' )
      ( sap_key = 'bank_key'       cand = 'BANKL' )
      ( sap_key = 'bank_account'   cand = 'BANKN' )
      ( sap_key = 'control_key'    cand = 'BKONT' )
      ( sap_key = 'iban'           cand = 'IBAN' )
      ( sap_key = 'tin'            cand = 'TAXNUM,TAXNUMBER' ) ).

    TRY.
        DATA(lo_model) = cl_usmd_model_ext=>get_instance( i_usmd_model = iv_model ).
        DATA lt_ent TYPE usmd_ts_entity.
        lo_model->get_entities( IMPORTING et_entity = lt_ent ).

        LOOP AT lt_ent INTO DATA(ls_ent).
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

          DATA lv_fields TYPE string.
          CLEAR lv_fields.
          LOOP AT lo_sd->components INTO DATA(ls_c).
            lv_fields = COND #( WHEN lv_fields IS INITIAL THEN |{ ls_c-name }| ELSE |{ lv_fields }, { ls_c-name }| ).
          ENDLOOP.
          APPEND |{ ls_ent-usmd_entity }: { lv_fields }| TO et_entities.

          LOOP AT lt_syn INTO DATA(ls_syn).
            IF line_exists( et_map[ sap_key = ls_syn-sap_key ] ).
              CONTINUE.
            ENDIF.
            SPLIT ls_syn-cand AT ',' INTO TABLE DATA(lt_cand).
            LOOP AT lt_cand INTO DATA(lv_cand).
              IF line_exists( lo_sd->components[ name = lv_cand ] ).
                APPEND VALUE #( sap_key = ls_syn-sap_key entity = |{ ls_ent-usmd_entity }| field = lv_cand ) TO et_map.
                EXIT.
              ENDIF.
            ENDLOOP.
          ENDLOOP.
        ENDLOOP.
        add( EXPORTING iv_name = |MDG model read ({ iv_model })| iv_ok = abap_true
                       iv_detail = |{ lines( lt_ent ) } entities, { lines( et_map ) } fields mapped|
             CHANGING ct_checks = ct_checks ).
      CATCH cx_root INTO DATA(lx).
        add( EXPORTING iv_name = |MDG model read ({ iv_model })| iv_ok = abap_false
                       iv_detail = |{ lx->get_text( ) } — verify cl_usmd_model_ext API|
             CHANGING ct_checks = ct_checks ).
    ENDTRY.

    " gaps
    DATA(lt_want) = VALUE string_table(
      ( `account_holder` ) ( `bank_country` ) ( `bank_key` ) ( `bank_account` )
      ( `iban` ) ( `control_key` ) ( `street` ) ( `city` ) ( `tin` ) ).
    LOOP AT lt_want INTO DATA(lv_w).
      IF NOT line_exists( et_map[ sap_key = lv_w ] ).
        APPEND lv_w TO et_gaps.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD live_cr.
    TRY.
        DATA(lo_model)  = cl_usmd_model_ext=>get_instance( i_usmd_model = iv_model ).
        DATA(lo_reader) = NEW zcl_mdmdoc_mdg_reader( io_model = lo_model iv_crequest = iv_cr iv_model = iv_model ).

        lo_reader->zif_mdmdoc_sap_reader~read_cr_fields(
          EXPORTING iv_cr = |{ iv_cr }|
          IMPORTING et_sap = DATA(lt_sap) ev_found = DATA(lv_found) ev_error = DATA(lv_err) ).
        add( EXPORTING iv_name = |read CR fields ({ iv_cr })| iv_ok = lv_found
                       iv_detail = COND #( WHEN lv_found = abap_true THEN |{ lines( lt_sap ) } field(s) read| ELSE |nothing read { lv_err }| )
             CHANGING ct_checks = ct_checks ).

        lo_reader->zif_mdmdoc_sap_reader~read_cr_attachments(
          EXPORTING iv_cr = |{ iv_cr }|
          IMPORTING et_docs = DATA(lt_docs) ev_error = DATA(lv_aerr) ).
        add( EXPORTING iv_name = |read CR attachments ({ iv_cr })|
                       iv_ok = boolc( lt_docs IS NOT INITIAL )
                       iv_detail = COND #( WHEN lt_docs IS NOT INITIAL THEN |{ lines( lt_docs ) } attachment(s)|
                                           WHEN lv_aerr IS NOT INITIAL THEN lv_aerr ELSE 'no attachments on this CR' )
             CHANGING ct_checks = ct_checks ).
      CATCH cx_root INTO DATA(lx).
        add( EXPORTING iv_name = |live CR read ({ iv_cr })| iv_ok = abap_false iv_detail = lx->get_text( )
             CHANGING ct_checks = ct_checks ).
    ENDTRY.
  ENDMETHOD.

  METHOD save_map.
    TRY.
        DATA lr_row TYPE REF TO data.
        CREATE DATA lr_row TYPE ('ZMDMDOC_MAP').
        ASSIGN lr_row->* TO FIELD-SYMBOL(<row>).
        LOOP AT it_map INTO DATA(ls_m).
          CLEAR <row>.
          ASSIGN COMPONENT 'MODEL'   OF STRUCTURE <row> TO FIELD-SYMBOL(<f>). IF sy-subrc = 0. <f> = iv_model. ENDIF.
          ASSIGN COMPONENT 'SAP_KEY' OF STRUCTURE <row> TO <f>.               IF sy-subrc = 0. <f> = ls_m-sap_key. ENDIF.
          ASSIGN COMPONENT 'ENTITY'  OF STRUCTURE <row> TO <f>.               IF sy-subrc = 0. <f> = ls_m-entity. ENDIF.
          ASSIGN COMPONENT 'FIELD'   OF STRUCTURE <row> TO <f>.               IF sy-subrc = 0. <f> = ls_m-field. ENDIF.
          MODIFY ('ZMDMDOC_MAP') FROM <row>.
        ENDLOOP.
        add( EXPORTING iv_name = 'save mapping to ZMDMDOC_MAP' iv_ok = abap_true
                       iv_detail = |{ lines( it_map ) } row(s) saved| CHANGING ct_checks = ct_checks ).
      CATCH cx_root INTO DATA(lx).
        add( EXPORTING iv_name = 'save mapping to ZMDMDOC_MAP' iv_ok = abap_false
                       iv_detail = |create table ZMDMDOC_MAP first: { lx->get_text( ) }| CHANGING ct_checks = ct_checks ).
    ENDTRY.
  ENDMETHOD.

  METHOD run.
    CLEAR: et_checks, et_map, et_gaps, et_entities.
    preflight( EXPORTING iv_model = iv_model CHANGING ct_checks = et_checks ).
    discover( EXPORTING iv_model = iv_model
              IMPORTING et_map = et_map et_gaps = et_gaps et_entities = et_entities
              CHANGING ct_checks = et_checks ).
    IF iv_save = abap_true AND et_map IS NOT INITIAL.
      save_map( EXPORTING iv_model = iv_model it_map = et_map CHANGING ct_checks = et_checks ).
    ENDIF.
    IF iv_cr IS NOT INITIAL.
      live_cr( EXPORTING iv_model = iv_model iv_cr = iv_cr CHANGING ct_checks = et_checks ).
    ENDIF.
  ENDMETHOD.

  METHOD print_checks.
    DATA lv_pass TYPE i.
    DATA lv_fail TYPE i.
    WRITE: / 'Pre-flight checks'. ULINE.
    LOOP AT it_checks ASSIGNING FIELD-SYMBOL(<c>).
      CASE <c>-status.
        WHEN zif_mdmdoc_types=>c_check-pass. FORMAT COLOR COL_POSITIVE. lv_pass = lv_pass + 1.
        WHEN zif_mdmdoc_types=>c_check-fail. FORMAT COLOR COL_NEGATIVE. lv_fail = lv_fail + 1.
        WHEN OTHERS.                          FORMAT COLOR COL_TOTAL.
      ENDCASE.
      WRITE: / <c>-status, AT 8 <c>-name.
      FORMAT COLOR OFF.
      IF <c>-detail IS NOT INITIAL.
        WRITE: AT 55 <c>-detail.
      ENDIF.
    ENDLOOP.
    ULINE.
    WRITE: / |{ lv_pass } passed, { lv_fail } failed|.
    IF lv_fail = 0.
      FORMAT COLOR COL_POSITIVE.
      WRITE: / 'GO — pre-flight clean.'.
    ELSE.
      FORMAT COLOR COL_NEGATIVE.
      WRITE: / 'NO-GO — fix the red checks before enabling the BAdI.'.
    ENDIF.
    FORMAT COLOR OFF.
  ENDMETHOD.

  METHOD print_map.
    IF iv_list = abap_true AND it_entities IS NOT INITIAL.
      SKIP. WRITE: / 'Entities and fields'. ULINE.
      LOOP AT it_entities INTO DATA(lv_e).
        WRITE: / lv_e.
      ENDLOOP.
    ENDIF.
    SKIP. WRITE: / 'Proposed SAP_KEY -> entity.field mapping'. ULINE.
    LOOP AT it_map INTO DATA(ls_m).
      WRITE: / ls_m-sap_key, AT 22 |{ ls_m-entity }.{ ls_m-field }|.
    ENDLOOP.
    IF it_gaps IS NOT INITIAL.
      SKIP. WRITE: / 'Unmatched keys (fill ZMDMDOC_MAP manually if needed):'.
      LOOP AT it_gaps INTO DATA(lv_g).
        WRITE: / '  -', lv_g.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
