*&---------------------------------------------------------------------*
*& Report ZMDMDOC_MDG_DISCOVER
*&---------------------------------------------------------------------*
*& Focused discovery view: read the MDG data model's field architecture and
*& propose the SAP_KEY -> entity.field mapping (+ gaps); optionally save it to
*& ZMDMDOC_MAP. Thin wrapper over ZCL_MDMDOC_ONBOARD — for the full one-shot
*& setup (checks + discovery + CR read) use ZMDMDOC_SETUP.
*&
*& *** VERIFY ON SYSTEM *** — touches MDG metadata APIs; excluded from abaplint.
*&---------------------------------------------------------------------*
REPORT zmdmdoc_mdg_discover.

PARAMETERS: p_model TYPE usmd_model DEFAULT 'BP'.
PARAMETERS: p_save  AS CHECKBOX DEFAULT ' '.     " persist proposal to ZMDMDOC_MAP
PARAMETERS: p_list  AS CHECKBOX DEFAULT 'X'.     " also list all entities/fields

START-OF-SELECTION.
  zcl_mdmdoc_onboard=>run(
    EXPORTING iv_model = p_model iv_save = p_save
    IMPORTING et_checks = DATA(lt_checks) et_map = DATA(lt_map)
              et_gaps = DATA(lt_gaps) et_entities = DATA(lt_ent) ).
  WRITE: / 'mdmdoc — MDG field-mapping discovery', AT 60 'model', p_model.
  zcl_mdmdoc_onboard=>print_map( it_map = lt_map it_gaps = lt_gaps it_entities = lt_ent iv_list = p_list ).
