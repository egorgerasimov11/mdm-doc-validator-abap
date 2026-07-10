CLASS zcl_mdmdoc_mdg_check DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* The MDG entry point of the document validator — a plain SERVICE class,
* deliberately NOT a BAdI implementation.
*
* WHY: BAdI USMD_RULE_SERVICE is *** NOT Multiple Use *** (verified in SE18 on
* MDQ/100). For one filter combination only ONE implementation runs, and the BP
* model slot is already taken (e.g. ZCLMDG_GTS_BP_VALIDATION). So instead of
* competing for the slot, call this service from the EXISTING implementation:
*
*   METHOD if_ex_usmd_rule_service~check_crequest_final.
*     NEW zcl_mdmdoc_mdg_check( )->run_cr_check(
*       io_model = io_model  id_crequest = id_crequest  id_log_handle = id_log_handle ).
*   ENDMETHOD.
*
* CHECK_CREQUEST_FINAL is the right hook: it fires ONCE per change request
* ("Completion of Check of a Change Request") and carries id_crequest + io_model.
* Its signature has NO et_message — messages go to the application log through
* ID_LOG_HANDLE (BAL). CHECK_ENTITY is the wrong hook: it fires per entity type
* AND per record.
*
* Verified signatures (SE24 IF_EX_USMD_RULE_SERVICE):
*   CHECK_CREQUEST_FINAL: id_edition, id_crequest, io_model, id_log_handle
*   CHECK_ENTITY        : io_model, id_edition, id_crequest(opt), id_entitytype,
*                         if_online_check, it_data -> et_message (usmd_t_message)
*
* *** VERIFY ON SYSTEM *** — excluded from abaplint (MDG framework types).
*----------------------------------------------------------------------*
  PUBLIC SECTION.
    " Read the CR attachment + the CR staged fields, compare, emit findings.
    " Serves both hooks: writes to the application log when id_log_handle is
    " supplied (CHECK_CREQUEST_FINAL), and/or returns et_message (CHECK_ENTITY).
    METHODS run_cr_check
      IMPORTING io_model      TYPE REF TO if_usmd_model_ext
                id_crequest   TYPE usmd_crequest
                id_log_handle TYPE balloghndl OPTIONAL
                iv_model      TYPE usmd_model DEFAULT 'BP'
                iv_block      TYPE abap_bool DEFAULT abap_false
      EXPORTING et_message    TYPE usmd_t_message.

  PRIVATE SECTION.
    " Message class for the emitted CR messages (SE91) — 001 = &1&2&3&4.
    CONSTANTS c_msgid TYPE symsgid VALUE 'ZMDMDOC'.
    CONSTANTS c_msgno TYPE symsgno VALUE '001'.

    " The BAdI runs under "Reusing Instantiation" and CHECK_* may fire several
    " times per session, so parse each attachment ONCE, keyed by its SHA.
    TYPES: BEGIN OF ty_cache,
             sha TYPE string,
             ext TYPE zif_mdmdoc_types=>ty_extraction,
           END OF ty_cache.
    CLASS-DATA gt_cache TYPE HASHED TABLE OF ty_cache WITH UNIQUE KEY sha.

    METHODS extract_document
      IMPORTING is_doc        TYPE zif_mdmdoc_sap_reader=>ty_attachment
      RETURNING VALUE(rs_ext) TYPE zif_mdmdoc_types=>ty_extraction.

    METHODS sha16
      IMPORTING iv_data       TYPE xstring
      RETURNING VALUE(rv_sha) TYPE string.

    METHODS split_text
      IMPORTING iv_text  TYPE string
      EXPORTING ev_v1    TYPE symsgv
                ev_v2    TYPE symsgv
                ev_v3    TYPE symsgv
                ev_v4    TYPE symsgv.

    METHODS emit
      IMPORTING is_finding    TYPE zif_mdmdoc_types=>ty_finding
                id_log_handle TYPE balloghndl
                iv_block      TYPE abap_bool
      CHANGING  ct_message    TYPE usmd_t_message.
ENDCLASS.


CLASS zcl_mdmdoc_mdg_check IMPLEMENTATION.

  METHOD sha16.
    TRY.
        cl_abap_message_digest=>calculate_hash_for_raw(
          EXPORTING if_algorithm = 'SHA256' if_data = iv_data
          IMPORTING ef_hashstring = DATA(lv_hash) ).
        rv_sha = to_lower( lv_hash(16) ).
      CATCH cx_root.
        CLEAR rv_sha.
    ENDTRY.
  ENDMETHOD.

  METHOD extract_document.
    " cache hit: the same attachment was already parsed this session
    DATA(lv_sha) = sha16( is_doc-content ).
    IF lv_sha IS NOT INITIAL.
      READ TABLE gt_cache WITH KEY sha = lv_sha INTO DATA(ls_hit).
      IF sy-subrc = 0.
        rs_ext = ls_hit-ext.
        RETURN.
      ENDIF.
    ENDIF.

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

    IF lv_sha IS NOT INITIAL.
      INSERT VALUE #( sha = lv_sha ext = rs_ext ) INTO TABLE gt_cache.
    ENDIF.
  ENDMETHOD.

  METHOD split_text.
    CLEAR: ev_v1, ev_v2, ev_v3, ev_v4.
    DATA(lv_len) = strlen( iv_text ).
    ev_v1 = iv_text.
    IF lv_len > 50.
      ev_v2 = iv_text+50.
    ENDIF.
    IF lv_len > 100.
      ev_v3 = iv_text+100.
    ENDIF.
    IF lv_len > 150.
      ev_v4 = iv_text+150.
    ENDIF.
  ENDMETHOD.

  METHOD emit.
    " NOTE (SAP-000 "all match") is informational — do not clutter the CR log.
    IF is_finding-severity = zif_mdmdoc_types=>c_severity-note.
      RETURN.
    ENDIF.
    " Default: everything is a WARNING. Only with iv_block does a REJECT finding
    " become an error that stops the change request.
    DATA(lv_ty) = COND symsgty(
      WHEN iv_block = abap_true AND is_finding-verdict_effect = zif_mdmdoc_types=>c_verdict-reject
      THEN 'E' ELSE 'W' ).

    DATA(lv_text) = |[{ is_finding-rule_id }] { is_finding-message }|.
    split_text( EXPORTING iv_text = lv_text
                IMPORTING ev_v1 = DATA(lv_v1) ev_v2 = DATA(lv_v2)
                          ev_v3 = DATA(lv_v3) ev_v4 = DATA(lv_v4) ).

    " 1) application log (CHECK_CREQUEST_FINAL path)
    IF id_log_handle IS NOT INITIAL.
      DATA ls_bal TYPE bal_s_msg.
      ls_bal-msgty = lv_ty.
      ls_bal-msgid = c_msgid.
      ls_bal-msgno = c_msgno.
      ls_bal-msgv1 = lv_v1.
      ls_bal-msgv2 = lv_v2.
      ls_bal-msgv3 = lv_v3.
      ls_bal-msgv4 = lv_v4.
      CALL FUNCTION 'BAL_LOG_MSG_ADD'
        EXPORTING  i_log_handle = id_log_handle
                   i_s_msg      = ls_bal
        EXCEPTIONS OTHERS       = 0.
    ENDIF.

    " 2) message table (CHECK_ENTITY path)
    DATA ls_msg TYPE usmd_s_message.
    ls_msg-msgid = c_msgid.
    ls_msg-msgno = c_msgno.
    ls_msg-msgty = lv_ty.
    ls_msg-msgv1 = lv_v1.
    ls_msg-msgv2 = lv_v2.
    ls_msg-msgv3 = lv_v3.
    ls_msg-msgv4 = lv_v4.
    APPEND ls_msg TO ct_message.
  ENDMETHOD.

  METHOD run_cr_check.
    CLEAR et_message.
    DATA(lo_reader) = NEW zcl_mdmdoc_mdg_reader(
      io_model = io_model iv_crequest = id_crequest iv_model = iv_model ).

    " 1. the attached document(s) — nothing to validate without one
    lo_reader->zif_mdmdoc_sap_reader~read_cr_attachments(
      EXPORTING iv_cr = |{ id_crequest }|
      IMPORTING et_docs = DATA(lt_docs) ).
    IF lt_docs IS INITIAL.
      RETURN.
    ENDIF.

    " 2. the CR staged fields (SAP side of the comparison)
    lo_reader->zif_mdmdoc_sap_reader~read_cr_fields(
      EXPORTING iv_cr = |{ id_crequest }|
      IMPORTING et_sap = DATA(lt_sap) ).
    IF lt_sap IS INITIAL.
      RETURN.
    ENDIF.

    " 3. per document: deterministic extraction (no LLM, no outbound HTTP) + compare
    LOOP AT lt_docs INTO DATA(ls_doc).
      IF zcl_mdmdoc_file=>classify_ext( ls_doc-ext ) <> 'pdf'.
        CONTINUE.   " in-MDG path validates PDFs carrying a text layer
      ENDIF.
      DATA(ls_ext) = extract_document( ls_doc ).

      zcl_mdmdoc_compare=>compare(
        EXPORTING is_ext = ls_ext it_sap = lt_sap iv_policy = 'masked'
        IMPORTING et_findings = DATA(lt_find) ).

      LOOP AT lt_find INTO DATA(ls_f).
        emit( EXPORTING is_finding = ls_f id_log_handle = id_log_handle iv_block = iv_block
              CHANGING ct_message = et_message ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
