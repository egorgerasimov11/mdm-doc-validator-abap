*&---------------------------------------------------------------------*
*& Report ZMDMDOC_DOCTOR
*&---------------------------------------------------------------------*
*& Focused pre-flight view: the deployment checks only ("can it load / can it
*& read"). Thin wrapper over ZCL_MDMDOC_ONBOARD — for the full one-shot setup
*& (checks + discovery + save) use ZMDMDOC_SETUP.
*&
*& Core checks are the unit-tested ZCL_MDMDOC_SELFTEST; MDG parts are
*& *** VERIFY ON SYSTEM *** (excluded from abaplint). Give a change-request
*& number to also test live CR field + attachment reading.
*&---------------------------------------------------------------------*
REPORT zmdmdoc_doctor.

PARAMETERS: p_model TYPE usmd_model DEFAULT 'BP'.
PARAMETERS: p_cr    TYPE usmd_crequest.     " optional: test reading this CR

START-OF-SELECTION.
  zcl_mdmdoc_onboard=>run(
    EXPORTING iv_model = p_model iv_cr = p_cr
    IMPORTING et_checks = DATA(lt_checks) ).
  WRITE: / 'mdmdoc — deployment pre-flight (doctor)', AT 60 'model', p_model.
  SKIP.
  zcl_mdmdoc_onboard=>print_checks( lt_checks ).
