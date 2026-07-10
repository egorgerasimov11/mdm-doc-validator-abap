*&---------------------------------------------------------------------*
*& Report ZMDMDOC
*&---------------------------------------------------------------------*
*& mdmdoc — bank-document + W-9 validator (ABAP clone, no web panel).
*& CLI-style: give a document file path, the program reads it, extracts
*& banking / W-9 fields (deterministic regex + optional local Ollama LLM),
*& runs the declarative rules and prints a verdict.
*&
*& All heavy logic lives in the ZCL_MDMDOC_* classes; this report is a thin
*& orchestrator over them (mirrors pipeline.run_check in the Python original).
*&---------------------------------------------------------------------*
REPORT zmdmdoc.

CONSTANTS gc_memory_id TYPE c LENGTH 20 VALUE 'ZMDMDOC_RESULT'.

*----------------------------------------------------------------------*
* Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_file TYPE string LOWER CASE OBLIGATORY.
  PARAMETERS: rb_pc  RADIOBUTTON GROUP src DEFAULT 'X',
              rb_srv RADIOBUTTON GROUP src.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS: rb_auto RADIOBUTTON GROUP cls DEFAULT 'X',
              rb_bank RADIOBUTTON GROUP cls,
              rb_w9   RADIOBUTTON GROUP cls.
  PARAMETERS: p_lang TYPE c LENGTH 2 DEFAULT 'EN'.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-003.
  PARAMETERS: cb_llm AS CHECKBOX DEFAULT ' '.
  " p_ourl is resolved on the APPLICATION SERVER — the localhost default only
  " works when Ollama runs on the app server itself. For a remote host use its
  " full URL and save a report variant (background jobs need the variant too).
  PARAMETERS: p_ourl TYPE string LOWER CASE DEFAULT 'http://localhost:11434',
              p_omod TYPE string LOWER CASE DEFAULT 'qwen3:4b',
              p_ovis TYPE string LOWER CASE DEFAULT 'qwen2.5vl:7b',
              p_otmo TYPE i DEFAULT 120.
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE TEXT-004.
  PARAMETERS: cb_json AS CHECKBOX DEFAULT ' '.
  PARAMETERS: p_jfile TYPE string LOWER CASE,
              p_rules TYPE string LOWER CASE,
              cb_stri AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b4.

*----------------------------------------------------------------------*
* F4 for the file path (PC)
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  DATA lt_files TYPE filetable.
  DATA lv_rc    TYPE i.
  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING window_title = 'Select document'
    CHANGING  file_table   = lt_files
              rc           = lv_rc
    EXCEPTIONS OTHERS       = 1 ).
  IF sy-subrc = 0.
    READ TABLE lt_files INTO DATA(ls_file) INDEX 1.
    IF sy-subrc = 0.
      p_file = ls_file-filename.
    ENDIF.
  ENDIF.

*----------------------------------------------------------------------*
* Main
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM main.

*&---------------------------------------------------------------------*
FORM main.
  DATA ls_doc   TYPE zcl_mdmdoc_file=>ty_doc.
  DATA lv_error TYPE string.
  DATA lt_pipe  TYPE zif_mdmdoc_types=>tt_findings.   " EXT-*/LLM-* pipeline findings
  DATA lv_text  TYPE string.
  DATA lv_lang  TYPE string.
  DATA lv_from_server TYPE abap_bool.

  lv_lang = to_upper( p_lang ).
  lv_from_server = boolc( rb_srv = abap_true ).

  " 1. read file
  zcl_mdmdoc_file=>read(
    EXPORTING iv_path = p_file iv_from_server = lv_from_server
    IMPORTING es_doc = ls_doc ev_error = lv_error ).
  IF lv_error IS NOT INITIAL.
    MESSAGE |Cannot read file: { lv_error }| TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " 2. unwrap containers (.zip/.eml)
  DATA(lv_kind0) = zcl_mdmdoc_file=>classify_ext( ls_doc-ext ).
  IF lv_kind0 = 'zip' OR lv_kind0 = 'email'.
    zcl_mdmdoc_file=>unwrap(
      IMPORTING et_notes = DATA(lt_notes) ev_error = lv_error
      CHANGING  cs_doc = ls_doc ).
    IF lv_error IS NOT INITIAL.
      MESSAGE |Container: { lv_error }| TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDIF.

  " 3. acquire text per resolved file kind
  DATA(lv_kind) = zcl_mdmdoc_file=>classify_ext( ls_doc-ext ).
  DATA lv_forced_type TYPE string.
  PERFORM acquire_text USING ls_doc lv_kind
                       CHANGING lv_text lv_forced_type lt_pipe.

  " 4. doc class (forced or sniffed) — pass filename + text so filename hints survive
  DATA lv_class TYPE string.
  IF rb_bank = abap_true.
    lv_class = zif_mdmdoc_types=>c_doc_class-bank.
  ELSEIF rb_w9 = abap_true.
    lv_class = zif_mdmdoc_types=>c_doc_class-w9.
  ELSE.
    lv_class = zcl_mdmdoc_sniff=>sniff_doc_class( iv_text = lv_text iv_filename = ls_doc-name ).
  ENDIF.

  " 5. doc type: forced (editable/msg/unreadable) wins, else hint
  DATA lv_type TYPE string.
  IF lv_forced_type IS NOT INITIAL.
    lv_type = lv_forced_type.
  ELSE.
    lv_type = zcl_mdmdoc_sniff=>type_hint( iv_text = lv_text iv_filename = ls_doc-name iv_doc_class = lv_class ).
  ENDIF.

  " 6. deterministic regex candidates (always)
  DATA(lt_cand) = zcl_mdmdoc_regex=>extract_candidates( lv_text ).

  " 7. optional LLM field extraction
  DATA lt_llm    TYPE zif_mdmdoc_types=>tt_fields.
  DATA lv_llm_used TYPE abap_bool.
  IF cb_llm = abap_true.
    PERFORM run_llm USING lv_class lv_text lt_cand
                    CHANGING lt_llm lv_type lv_llm_used lt_pipe.
  ELSE.
    APPEND VALUE #( rule_id = 'LLM-002' severity = zif_mdmdoc_types=>c_severity-note
                    message = 'LLM disabled — deterministic (regex-only) extraction; narrative fields not populated.' )
           TO lt_pipe.
  ENDIF.

  " 8. merge (regex overrides model) + normalize
  DATA(ls_ext) = zcl_mdmdoc_extract=>build(
    iv_doc_class = lv_class iv_doc_type = lv_type
    it_llm_fields = lt_llm it_candidates = lt_cand iv_llm_used = lv_llm_used
    iv_raw_text = lv_text iv_filename = p_file ).

  " 9. rules (optional JSON override) + pipeline findings before the verdict
  DATA lv_rules_json TYPE string.
  PERFORM read_rules_override USING lv_from_server CHANGING lv_rules_json.

  DATA(lo_rules) = NEW zcl_mdmdoc_rules( lv_rules_json ).
  DATA(lt_find) = lo_rules->run( is_ext = ls_ext iv_lang = lv_lang ).
  APPEND LINES OF lt_pipe TO lt_find.

  " 10. verdict
  DATA(lv_verdict) = zcl_mdmdoc_verdict=>decide( lt_find ).

  " 11. print report
  DATA(lv_policy) = COND string( WHEN cb_llm = abap_true AND p_jfile IS NOT INITIAL THEN 'full' ELSE 'masked' ).
  " display policy stays 'masked' for the on-screen list; 'full' only affects the JSON file
  DATA(lt_lines) = zcl_mdmdoc_report=>build_list(
    is_ext = ls_ext it_findings = lt_find iv_verdict = lv_verdict iv_lang = lv_lang iv_policy = 'masked' ).
  PERFORM write_lines USING lt_lines lv_verdict.

  " 12. optional JSON file (leak-gated)
  IF cb_json = abap_true AND p_jfile IS NOT INITIAL.
    PERFORM write_json USING ls_ext lt_find lv_verdict lv_lang lv_from_server.
  ENDIF.

  " 13. hand result to SUBMIT callers
  DATA(lv_json_mem) = zcl_mdmdoc_report=>build_json(
    is_ext = ls_ext it_findings = lt_find iv_verdict = lv_verdict
    iv_doc_path = ls_doc-path iv_run_id = ls_doc-sha16 iv_lang = lv_lang iv_policy = 'masked' ).
  EXPORT verdict = lv_verdict json = lv_json_mem TO MEMORY ID gc_memory_id.

  " 14. closing message (+ batch cancel in strict mode)
  PERFORM final_message USING lv_verdict.
ENDFORM.

*&---------------------------------------------------------------------*
FORM acquire_text USING is_doc TYPE zcl_mdmdoc_file=>ty_doc
                        iv_kind TYPE string
                  CHANGING cv_text TYPE string
                           cv_forced_type TYPE string
                           ct_pipe TYPE zif_mdmdoc_types=>tt_findings.
  CLEAR: cv_text, cv_forced_type.
  CASE iv_kind.
    WHEN 'editable'.
      cv_forced_type = 'editable_source'.   " BNK-003 rejects it

    WHEN 'msg'.
      cv_forced_type = 'other'.
      APPEND VALUE #( rule_id = 'EXT-005' severity = zif_mdmdoc_types=>c_severity-warning
                      verdict_effect = zif_mdmdoc_types=>c_verdict-review
                      message = 'Outlook .msg not supported — save the attachment or forward the mail as .eml.' )
             TO ct_pipe.

    WHEN 'pdf'.
      DATA lv_pages TYPE i.
      DATA lv_enc   TYPE abap_bool.
      DATA lt_warn  TYPE string_table.
      zcl_mdmdoc_pdf=>extract_text(
        EXPORTING iv_pdf = is_doc-content
        IMPORTING ev_text = cv_text ev_pages = lv_pages ev_encrypted = lv_enc et_warnings = lt_warn ).
      IF lv_enc = abap_true.
        APPEND VALUE #( rule_id = 'EXT-003' severity = zif_mdmdoc_types=>c_severity-warning
                        verdict_effect = zif_mdmdoc_types=>c_verdict-review
                        message = 'PDF is encrypted/password-protected — cannot read the text layer.' )
               TO ct_pipe.
      ELSEIF strlen( cv_text ) < 40.
        APPEND VALUE #( rule_id = 'EXT-001' severity = zif_mdmdoc_types=>c_severity-warning
                        verdict_effect = zif_mdmdoc_types=>c_verdict-review
                        message = 'No readable text layer (scanned PDF?) — run OCR externally or convert a page to PNG for the LLM.' )
               TO ct_pipe.
      ENDIF.
      LOOP AT lt_warn INTO DATA(lv_w).
        APPEND VALUE #( rule_id = 'EXT-004' severity = zif_mdmdoc_types=>c_severity-note message = |PDF: { lv_w }| ) TO ct_pipe.
      ENDLOOP.

    WHEN 'image'.
      IF cb_llm = abap_true.
        DATA(lo_llm) = NEW zcl_mdmdoc_llm( iv_url = p_ourl iv_model_text = p_omod
                                           iv_model_vision = p_ovis iv_timeout = p_otmo ).
        IF lo_llm->probe( ) = abap_true.
          DATA lv_ok TYPE abap_bool.
          DATA lv_err TYPE string.
          lo_llm->transcribe_image(
            EXPORTING iv_image = is_doc-content iv_mime = |image/{ is_doc-ext }|
            IMPORTING ev_text = cv_text ev_ok = lv_ok ev_error = lv_err ).
          IF lv_ok <> abap_true.
            APPEND VALUE #( rule_id = 'EXT-002' severity = zif_mdmdoc_types=>c_severity-warning
                            verdict_effect = zif_mdmdoc_types=>c_verdict-review
                            message = |Image transcription failed: { lv_err }| ) TO ct_pipe.
          ENDIF.
        ELSE.
          APPEND VALUE #( rule_id = 'EXT-002' severity = zif_mdmdoc_types=>c_severity-warning
                          verdict_effect = zif_mdmdoc_types=>c_verdict-review
                          message = 'Image scan needs the LLM vision option, but Ollama is unreachable.' ) TO ct_pipe.
        ENDIF.
      ELSE.
        APPEND VALUE #( rule_id = 'EXT-002' severity = zif_mdmdoc_types=>c_severity-warning
                        verdict_effect = zif_mdmdoc_types=>c_verdict-review
                        message = 'Image scan needs the LLM vision option or external OCR — enable the LLM checkbox.' ) TO ct_pipe.
      ENDIF.

    WHEN 'zip' OR 'email'.
      APPEND VALUE #( rule_id = 'EXT-001' severity = zif_mdmdoc_types=>c_severity-warning
                      verdict_effect = zif_mdmdoc_types=>c_verdict-review
                      message = 'Container held no readable document.' ) TO ct_pipe.

    WHEN OTHERS.
      APPEND VALUE #( rule_id = 'EXT-001' severity = zif_mdmdoc_types=>c_severity-warning
                      verdict_effect = zif_mdmdoc_types=>c_verdict-review
                      message = 'Unsupported / unreadable file type.' ) TO ct_pipe.
  ENDCASE.
ENDFORM.

*&---------------------------------------------------------------------*
FORM run_llm USING iv_class TYPE string iv_text TYPE string
                   it_cand TYPE zif_mdmdoc_types=>tt_fields
             CHANGING ct_llm TYPE zif_mdmdoc_types=>tt_fields
                      cv_type TYPE string
                      cv_used TYPE abap_bool
                      ct_pipe TYPE zif_mdmdoc_types=>tt_findings.
  DATA(lo_llm) = NEW zcl_mdmdoc_llm( iv_url = p_ourl iv_model_text = p_omod
                                     iv_model_vision = p_ovis iv_timeout = p_otmo ).
  IF lo_llm->probe( ) <> abap_true.
    APPEND VALUE #( rule_id = 'LLM-001' severity = zif_mdmdoc_types=>c_severity-warning
                    verdict_effect = zif_mdmdoc_types=>c_verdict-review
                    message = |LLM enabled but Ollama unreachable at { p_ourl } — deterministic fallback (verify manually).| )
           TO ct_pipe.
    RETURN.
  ENDIF.
  DATA lv_type TYPE string.
  DATA lv_ok   TYPE abap_bool.
  DATA lv_err  TYPE string.
  lo_llm->extract_fields(
    EXPORTING iv_doc_class = iv_class iv_text = iv_text it_candidates = it_cand
    IMPORTING et_fields = ct_llm ev_doc_type = lv_type ev_ok = lv_ok ev_error = lv_err ).
  IF lv_ok = abap_true.
    cv_used = abap_true.
    IF cv_type IS INITIAL AND lv_type IS NOT INITIAL.
      cv_type = lv_type.
    ENDIF.
  ELSE.
    APPEND VALUE #( rule_id = 'LLM-001' severity = zif_mdmdoc_types=>c_severity-warning
                    verdict_effect = zif_mdmdoc_types=>c_verdict-review
                    message = |LLM extraction failed: { lv_err } — deterministic fallback (verify manually).| )
           TO ct_pipe.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM read_rules_override USING iv_from_server TYPE abap_bool
                         CHANGING cv_json TYPE string.
  CLEAR cv_json.
  IF p_rules IS INITIAL.
    RETURN.
  ENDIF.
  DATA ls_rdoc TYPE zcl_mdmdoc_file=>ty_doc.
  DATA lv_err  TYPE string.
  zcl_mdmdoc_file=>read(
    EXPORTING iv_path = p_rules iv_from_server = iv_from_server
    IMPORTING es_doc = ls_rdoc ev_error = lv_err ).
  IF lv_err IS NOT INITIAL.
    MESSAGE |Rules override ignored: { lv_err }| TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.
  TRY.
      DATA(lo_conv) = cl_abap_conv_in_ce=>create( input = ls_rdoc-content encoding = 'UTF-8' ).
      lo_conv->read( IMPORTING data = cv_json ).
    CATCH cx_root.
      CLEAR cv_json.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
FORM write_lines USING it_lines TYPE string_table iv_verdict TYPE string.
  DATA lv_col TYPE i.
  lv_col = SWITCH #( iv_verdict
                     WHEN zif_mdmdoc_types=>c_verdict-reject  THEN col_negative
                     WHEN zif_mdmdoc_types=>c_verdict-accept  THEN col_positive
                     ELSE col_total ).
  LOOP AT it_lines INTO DATA(lv_l).
    IF lv_l CS '[BANK DOC VERDICT]' OR lv_l CS '[W-9 VERDICT]'
       OR lv_l CS 'Verdict' OR lv_l CS 'Вердикт'.
      FORMAT COLOR = lv_col INTENSIFIED OFF.
      WRITE: / lv_l.
      FORMAT COLOR OFF.
    ELSE.
      WRITE: / lv_l.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
FORM write_json USING is_ext TYPE zif_mdmdoc_types=>ty_extraction
                      it_find TYPE zif_mdmdoc_types=>tt_findings
                      iv_verdict TYPE string iv_lang TYPE string
                      iv_from_server TYPE abap_bool.
  " banking values may be full in the file only when the operator opted into the LLM run;
  " TIN is always masked regardless (enforced inside display_value)
  DATA(lv_policy) = COND string( WHEN cb_llm = abap_true THEN 'full' ELSE 'masked' ).
  DATA(lv_gate)   = COND string( WHEN lv_policy = 'full' THEN 'tin-only' ELSE 'strict' ).
  DATA(lv_json) = zcl_mdmdoc_report=>build_json(
    is_ext = is_ext it_findings = it_find iv_verdict = iv_verdict
    iv_doc_path = p_file iv_run_id = is_ext-doc_type iv_lang = iv_lang iv_policy = lv_policy ).

  DATA lt_hits TYPE string_table.
  DATA lv_clean TYPE abap_bool.
  zcl_mdmdoc_mask=>assert_no_leak(
    EXPORTING iv_blob = lv_json it_secrets = is_ext-secrets iv_policy = lv_gate
    IMPORTING et_hits = lt_hits ev_clean = lv_clean ).
  IF lv_clean <> abap_true.
    MESSAGE 'JSON withheld: leak gate detected a full sensitive value.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  DATA lv_err TYPE string.
  zcl_mdmdoc_file=>save_text(
    EXPORTING iv_path = p_jfile iv_text = lv_json iv_to_server = iv_from_server
    IMPORTING ev_error = lv_err ).
  IF lv_err IS NOT INITIAL.
    MESSAGE |JSON not saved: { lv_err }| TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    WRITE: / |JSON written to { p_jfile }|.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM final_message USING iv_verdict TYPE string.
  DATA(lv_ty) = zcl_mdmdoc_verdict=>message_type( iv_verdict ).
  DATA(lv_txt) = |Verdict: { iv_verdict }|.

  IF cb_stri = abap_true AND sy-batch = abap_true AND iv_verdict = zif_mdmdoc_types=>c_verdict-reject.
    MESSAGE lv_txt TYPE 'E'.          " cancels the background job
    RETURN.
  ENDIF.

  CASE lv_ty.
    WHEN 'E'.
      MESSAGE lv_txt TYPE 'S' DISPLAY LIKE 'E'.
    WHEN 'W'.
      MESSAGE lv_txt TYPE 'S' DISPLAY LIKE 'W'.
    WHEN OTHERS.
      MESSAGE lv_txt TYPE 'S'.
  ENDCASE.
ENDFORM.
