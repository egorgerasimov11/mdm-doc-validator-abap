*&---------------------------------------------------------------------*
*& Report ZMDMDOC_SETUP
*&---------------------------------------------------------------------*
*& ONE-SHOT onboarding: run everything at once, in order —
*&   1. pre-flight tests (can it load / can it read),
*&   2. MDG field-architecture discovery (proposed mapping + gaps),
*&   3. optional live change-request read (fields + attachments),
*&   4. optional save of the mapping to ZMDMDOC_MAP.
*& Use this single report to verify a deployment end to end before enabling
*& the MDG BAdI. All logic is in ZCL_MDMDOC_ONBOARD (verify-on-system).
*& *** VERIFY ON SYSTEM *** (uses MDG types; excluded from offline abaplint).
*&---------------------------------------------------------------------*
REPORT zmdmdoc_setup.

PARAMETERS: p_model TYPE usmd_model DEFAULT 'BP'.
PARAMETERS: p_cr    TYPE usmd_crequest.            " optional: live CR read
PARAMETERS: p_list  AS CHECKBOX DEFAULT 'X'.       " list all entities/fields
PARAMETERS: p_save  AS CHECKBOX DEFAULT ' '.       " save proposed map to ZMDMDOC_MAP

START-OF-SELECTION.
  zcl_mdmdoc_onboard=>run(
    EXPORTING iv_model = p_model iv_cr = p_cr iv_save = p_save
    IMPORTING et_checks = DATA(lt_checks) et_map = DATA(lt_map)
              et_gaps = DATA(lt_gaps) et_entities = DATA(lt_ent) ).

  WRITE: / 'mdmdoc — deployment setup & self-test', AT 60 'model', p_model.
  SKIP.
  zcl_mdmdoc_onboard=>print_checks( lt_checks ).
  zcl_mdmdoc_onboard=>print_map( it_map = lt_map it_gaps = lt_gaps it_entities = lt_ent iv_list = p_list ).
