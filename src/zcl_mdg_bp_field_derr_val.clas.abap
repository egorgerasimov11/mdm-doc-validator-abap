CLASS zcl_mdg_bp_field_derr_val DEFINITION
  PUBLIC
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* MDG BAdI implementation for enhancement spot / BAdI USMD_RULE_SERVICE
* (interface IF_EX_USMD_RULE_SERVICE), filter USMD_MODEL = 'BP'.
*
* On change-request check it reads the CR attachment (the uploaded bank
* letter / W-9), runs the deterministic mdmdoc pipeline on it, reads the CR
* staged fields, compares (ZCL_MDMDOC_COMPARE) and raises the findings as
* messages (default WARNING) in the CR message log.
*
* *** VERIFY ON SYSTEM *** — excluded from abaplint (MDG framework types).
* Confirm on your system: the exact IF_EX_USMD_RULE_SERVICE~CHECK_ENTITY
* signature (parameter names io_model / i_crequest / i_fieldname / ct_message),
* the message class for CR messages, and the anchor entity name. All logic is
* delegated to the reusable classes; this is a thin adapter.
*----------------------------------------------------------------------*
  PUBLIC SECTION.
    INTERFACES if_ex_usmd_rule_service.

  PRIVATE SECTION.
    " Fire the whole validation once, when the bank-data entity is checked.
    CONSTANTS c_anchor_entity TYPE usmd_entity VALUE 'BP_BANKDT'.
    " Message class for the emitted CR messages (create via SE91) — CONFIRM.
    CONSTANTS c_msgid TYPE symsgid VALUE 'ZMDMDOC'.

    METHODS run_cr_validation
      IMPORTING io_model    TYPE REF TO if_usmd_model_ext
                iv_crequest TYPE usmd_crequest
      CHANGING  ct_message  TYPE usmd_ts_message.

    METHODS extract_document
      IMPORTING is_doc        TYPE zif_mdmdoc_sap_reader=>ty_attachment
      RETURNING VALUE(rs_ext) TYPE zif_mdmdoc_types=>ty_extraction.

    METHODS emit_finding
      IMPORTING is_finding TYPE zif_mdmdoc_types=>ty_finding
      CHANGING  ct_message TYPE usmd_ts_message.
ENDCLASS.


CLASS zcl_mdg_bp_field_derr_val IMPLEMENTATION.

  METHOD if_ex_usmd_rule_service~check_entity.
    " Anchor guard: run once, when the bank-details entity is validated.
    IF i_fieldname <> c_anchor_entity.
      RETURN.
    ENDIF.
    run_cr_validation(
      EXPORTING io_model = io_model iv_crequest = i_crequest
      CHANGING  ct_message = ct_message ).
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~check.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~check_all.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~derive.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~derive_default.
  ENDMETHOD.

  METHOD if_ex_usmd_rule_service~initialize.
  ENDMETHOD.

  METHOD run_cr_validation.
    DATA(lo_reader) = NEW zcl_mdmdoc_mdg_reader( io_model = io_model iv_crequest = iv_crequest ).

    " 1. read the CR attachment(s) — the document(s) to validate
    lo_reader->zif_mdmdoc_sap_reader~read_cr_attachments(
      EXPORTING iv_cr = |{ iv_crequest }|
      IMPORTING et_docs = DATA(lt_docs) ).
    IF lt_docs IS INITIAL.
      RETURN.   " nothing attached to validate
    ENDIF.

    " 2. read the CR staged fields (SAP side)
    lo_reader->zif_mdmdoc_sap_reader~read_cr_fields(
      EXPORTING iv_cr = |{ iv_crequest }|
      IMPORTING et_sap = DATA(lt_sap) ).

    " 3. for each attached document: extract (deterministic, no LLM) + compare
    LOOP AT lt_docs INTO DATA(ls_doc).
      DATA(lv_kind) = zcl_mdmdoc_file=>classify_ext( ls_doc-ext ).
      IF lv_kind <> 'pdf'.
        CONTINUE.   " in-BAdI path validates PDFs with a text layer
      ENDIF.
      DATA(ls_ext) = extract_document( ls_doc ).

      zcl_mdmdoc_compare=>compare(
        EXPORTING is_ext = ls_ext it_sap = lt_sap iv_policy = 'masked'
        IMPORTING et_findings = DATA(lt_find) ).

      LOOP AT lt_find INTO DATA(ls_f).
        emit_finding( EXPORTING is_finding = ls_f CHANGING ct_message = ct_message ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD extract_document.
    zcl_mdmdoc_pdf=>extract_text(
      EXPORTING iv_pdf = is_doc-content
      IMPORTING ev_text = DATA(lv_text) ).
    DATA(lv_class) = zcl_mdmdoc_sniff=>sniff_doc_class( iv_text = lv_text iv_filename = is_doc-name ).
    DATA(lv_type)  = zcl_mdmdoc_sniff=>type_hint( iv_text = lv_text iv_filename = is_doc-name iv_doc_class = lv_class ).
    DATA(lt_cand)  = zcl_mdmdoc_regex=>extract_candidates( lv_text ).
    rs_ext = zcl_mdmdoc_extract=>build(
      iv_doc_class  = lv_class
      iv_doc_type   = lv_type
      it_llm_fields = VALUE #( )
      it_candidates = lt_cand
      iv_llm_used   = abap_false
      iv_raw_text   = lv_text
      iv_filename   = CONV string( is_doc-name ) ).
  ENDMETHOD.

  METHOD emit_finding.
    " Map a finding to a CR message. verdict_effect REJECT -> 'E' (blocks),
    " everything else -> 'W' (non-blocking warning). NOTE (SAP-000) -> skip.
    IF is_finding-severity = zif_mdmdoc_types=>c_severity-note.
      RETURN.
    ENDIF.
    DATA(lv_ty) = COND symsgty(
      WHEN is_finding-verdict_effect = zif_mdmdoc_types=>c_verdict-reject THEN 'E' ELSE 'W' ).

    " Message text carried in MSGV1..MSGV4 (message class ZMDMDOC, no. 001 = &1&2&3&4).
    DATA lv_msg TYPE string.
    lv_msg = |[{ is_finding-rule_id }] { is_finding-message }|.
    DATA ls_msg TYPE usmd_s_message.
    ls_msg-msgid = c_msgid.
    ls_msg-msgno = '001'.
    ls_msg-msgty = lv_ty.
    ls_msg-msgv1 = lv_msg(50).
    IF strlen( lv_msg ) > 50.
      ls_msg-msgv2 = lv_msg+50(50).
    ENDIF.
    IF strlen( lv_msg ) > 100.
      ls_msg-msgv3 = lv_msg+100(50).
    ENDIF.
    IF strlen( lv_msg ) > 150.
      ls_msg-msgv4 = lv_msg+150(50).
    ENDIF.
    INSERT ls_msg INTO TABLE ct_message.
  ENDMETHOD.

ENDCLASS.
