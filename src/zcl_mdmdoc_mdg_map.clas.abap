CLASS zcl_mdmdoc_mdg_map DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* Adaptable SAP_KEY -> (MDG entity, field) mapping.
*
* Purpose: make the MDG reader flexible instead of hard-coding entity/field
* names. The mapping comes from:
*   1. the optional customizing table ZMDMDOC_MAP (per data model), if it
*      exists — filled by the discovery report ZMDMDOC_MDG_DISCOVER; else
*   2. built-in defaults (standard MDG-BP technical names).
*
* *** VERIFY ON SYSTEM *** — excluded from abaplint. The ZMDMDOC_MAP table is
* optional; create it in SE11 (fields: MODEL, SAP_KEY, ENTITY, FIELD) to
* override the defaults without changing code. The table is read dynamically,
* so the class activates even when the table does not exist.
*----------------------------------------------------------------------*
  PUBLIC SECTION.
    " Effective mapping for a data model: defaults overlaid by ZMDMDOC_MAP rows.
    CLASS-METHODS get_map
      IMPORTING iv_model      TYPE usmd_model
      RETURNING VALUE(rt_map) TYPE zif_mdmdoc_types=>tt_map.

    " Built-in defaults (standard MDG-BP names) — used when no override exists.
    CLASS-METHODS defaults
      RETURNING VALUE(rt_map) TYPE zif_mdmdoc_types=>tt_map.

  PRIVATE SECTION.
    CLASS-METHODS overrides
      IMPORTING iv_model      TYPE usmd_model
      RETURNING VALUE(rt_map) TYPE zif_mdmdoc_types=>tt_map.
ENDCLASS.


CLASS zcl_mdmdoc_mdg_map IMPLEMENTATION.

  METHOD defaults.
    " Entity names observed on MDQ/100: the customer's own BAdI implementations
    " are named after the entity they filter on — ZMDG_BP_BP_BKDTL_IMPL and
    " ZMDG_BP_BP_CENTRL_IMPL. So bank details = BP_BKDTL (NOT BP_BANKDT).
    " ZMDMDOC_MDG_DISCOVER overrides all of this from the live model anyway.
    rt_map = VALUE #(
      ( sap_key = 'account_holder' entity = 'BP_CENTRL' field = 'NAME_ORG1' )
      ( sap_key = 'street'         entity = 'ADDRESS'   field = 'STREET' )
      ( sap_key = 'city'           entity = 'ADDRESS'   field = 'CITY1' )
      ( sap_key = 'bank_country'   entity = 'BP_BKDTL'  field = 'BANKS' )
      ( sap_key = 'bank_key'       entity = 'BP_BKDTL'  field = 'BANKL' )
      ( sap_key = 'bank_account'   entity = 'BP_BKDTL'  field = 'BANKN' )
      ( sap_key = 'control_key'    entity = 'BP_BKDTL'  field = 'BKONT' )
      ( sap_key = 'iban'           entity = 'BP_BKDTL'  field = 'IBAN' )
      ( sap_key = 'tin'            entity = 'BP_TAXNUM' field = 'TAXNUM' ) ).
  ENDMETHOD.

  METHOD overrides.
    " Optional customizing table ZMDMDOC_MAP — read dynamically so this class
    " activates even when the table has not been created.
    TRY.
        SELECT sap_key, entity, field
          FROM ('ZMDMDOC_MAP')
          WHERE model = @iv_model
          INTO CORRESPONDING FIELDS OF TABLE @rt_map.
      CATCH cx_root.
        CLEAR rt_map.
    ENDTRY.
  ENDMETHOD.

  METHOD get_map.
    rt_map = defaults( ).
    DATA(lt_ovr) = overrides( iv_model ).
    LOOP AT lt_ovr INTO DATA(ls_ovr).
      IF ls_ovr-sap_key IS INITIAL.
        CONTINUE.
      ENDIF.
      READ TABLE rt_map WITH KEY sap_key = ls_ovr-sap_key ASSIGNING FIELD-SYMBOL(<m>).
      IF sy-subrc = 0.
        <m>-entity = ls_ovr-entity.
        <m>-field  = ls_ovr-field.
      ELSE.
        APPEND ls_ovr TO rt_map.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
