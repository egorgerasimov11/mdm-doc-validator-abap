CLASS zcl_mdg_bp_field_derr_val DEFINITION
  PUBLIC
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* REFERENCE implementation of BAdI USMD_RULE_SERVICE (IF_EX_USMD_RULE_SERVICE).
*
* *** READ THIS BEFORE ACTIVATING ***
* The BAdI is **NOT Multiple Use** (verified in SE18: Usability -> Multiple Use
* is unchecked; Instance Creation Mode = Reusing Instantiation). For a given
* filter value only ONE implementation runs, and the BP data-model slot is
* usually already taken (e.g. ZCLMDG_GTS_BP_VALIDATION). Therefore:
*
*   - If the BP slot is TAKEN (the normal case): do NOT activate this class.
*     Instead paste two lines into the EXISTING implementation:
*
*       METHOD if_ex_usmd_rule_service~check_crequest_final.
*         NEW zcl_mdmdoc_mdg_check( )->run_cr_check(
*           io_model = io_model  id_crequest = id_crequest
*           id_log_handle = id_log_handle ).
*       ENDMETHOD.
*
*   - If the slot is FREE, this class can be used as-is.
*
* All the work lives in ZCL_MDMDOC_MDG_CHECK, so both paths share one code path.
* CHECK_CREQUEST_FINAL is the hook (fires ONCE per change request and carries
* id_crequest + io_model + id_log_handle); CHECK_ENTITY fires per entity type AND
* per record, so it stays empty here.
*
* Method signatures below match SE24 IF_EX_USMD_RULE_SERVICE on MDQ/100. If your
* release differs, ADT/SE24 regenerates the stubs when you add the interface.
* *** VERIFY ON SYSTEM *** — excluded from abaplint (MDG framework types).
*----------------------------------------------------------------------*
  PUBLIC SECTION.
    INTERFACES if_ex_usmd_rule_service.
ENDCLASS.


CLASS zcl_mdg_bp_field_derr_val IMPLEMENTATION.

  METHOD if_ex_usmd_rule_service~check_crequest_final.
    " Completion of Check of a Change Request — fires once, everything is here.
    " Messages go to the application log via id_log_handle (this method has no
    " et_message parameter).
    NEW zcl_mdmdoc_mdg_check( )->run_cr_check(
      io_model      = io_model
      id_crequest   = id_crequest
      id_log_handle = id_log_handle ).
  ENDMETHOD.

  " ---- remaining interface methods: intentionally empty --------------------
  " (all 11 must exist for the class to activate)

  METHOD if_ex_usmd_rule_service~check_entity.
    " Fires per entity type AND per record — wrong granularity for a document
    " check. Left empty on purpose; see check_crequest_final above.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~check_entity_hierarchy.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~check_crequest_start.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~check_crequest.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~check_crequest_hierarchy.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~check_edition_start.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~check_edition.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~check_edition_hierarchy.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~check_edition_final.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~derive_entity.
  ENDMETHOD.

ENDCLASS.
