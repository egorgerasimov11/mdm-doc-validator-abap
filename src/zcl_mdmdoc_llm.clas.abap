" Port of src/mdmdoc/stage_b.py (build_prompt + system prompts) and
" src/mdmdoc/model_client.py (Ollama request shape) — the LLM tier of the
" mdmdoc bank-doc / W-9 validator.
"
" The model CLASSIFIES and EXTRACTS only; verdicts come from the rule engine.
" All HTTP is funnelled through the PROTECTED http_post method so unit tests
" can subclass with canned responses (the class is therefore NON-final).
CLASS zcl_mdmdoc_llm DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_url          TYPE string
                iv_model_text   TYPE string
                iv_model_vision TYPE string
                iv_timeout      TYPE i DEFAULT 120.

    METHODS probe
      RETURNING VALUE(rv_up) TYPE abap_bool.

    METHODS extract_fields
      IMPORTING iv_doc_class  TYPE string
                iv_text       TYPE string
                it_candidates TYPE zif_mdmdoc_types=>tt_fields
      EXPORTING et_fields     TYPE zif_mdmdoc_types=>tt_fields
                ev_doc_type   TYPE string
                ev_ok         TYPE abap_bool
                ev_error      TYPE string.

    METHODS transcribe_image
      IMPORTING iv_image TYPE xstring
                iv_mime  TYPE string
      EXPORTING ev_text  TYPE string
                ev_ok    TYPE abap_bool
                ev_error TYPE string.

  PROTECTED SECTION.
    " HTTP isolated here so tests subclass and inject canned responses.
    METHODS http_post
      IMPORTING iv_path  TYPE string
                iv_body  TYPE string
      EXPORTING ev_body  TYPE string
                ev_ok    TYPE abap_bool
                ev_error TYPE string.

  PRIVATE SECTION.
    " ----- config (constructor-injected) ------------------------------------
    DATA mv_url          TYPE string.
    DATA mv_model_text   TYPE string.
    DATA mv_model_vision TYPE string.
    DATA mv_timeout      TYPE i.

    " ----- Ollama /api/chat request wire structures -------------------------
    TYPES: BEGIN OF ty_msg,
             role    TYPE string,
             content TYPE string,
             images  TYPE string_table,
           END OF ty_msg,
           tt_msg TYPE STANDARD TABLE OF ty_msg WITH EMPTY KEY.

    TYPES: BEGIN OF ty_options,
             temperature TYPE string,   " serialized as a bare number below
             num_ctx     TYPE i,
             num_predict TYPE i,
           END OF ty_options.

    TYPES: BEGIN OF ty_chat_req,
             model    TYPE string,
             stream   TYPE abap_bool,
             format   TYPE string,
             think    TYPE abap_bool,
             messages TYPE tt_msg,
             options  TYPE ty_options,
           END OF ty_chat_req.

    " ----- Ollama /api/chat response ----------------------------------------
    TYPES: BEGIN OF ty_resp_msg,
             role    TYPE string,
             content TYPE string,
           END OF ty_resp_msg.

    TYPES: BEGIN OF ty_chat_resp,
             message TYPE ty_resp_msg,
           END OF ty_chat_resp.

    " ----- second-level content payload (every bank + W-9 key, as strings) --
    " The model is asked for {doc_type, fields{...}} (nested), but stage_b's
    " _fields_from also accepts a FLAT object; we mirror that by deserializing
    " field names at the top level AND under a nested `fields` object — the
    " nested value wins when present (see content_to_fields).
    TYPES: BEGIN OF ty_field_bag,
             account_holder         TYPE string,
             account_type           TYPE string,
             bank_name              TYPE string,
             bank_country           TYPE string,
             bank_address           TYPE string,
             iban                   TYPE string,
             swift_bic              TYPE string,
             account_number         TYPE string,
             routing_aba            TYPE string,
             routing_aba_wires      TYPE string,
             branch_code            TYPE string,
             currency               TYPE string,
             doc_date               TYPE string,
             signed                 TYPE string,
             signature_evidence     TYPE string,
             partial_capture        TYPE string,
             line1_name             TYPE string,
             line2_business_name    TYPE string,
             line3_classification   TYPE string,
             tin_type               TYPE string,
             tin_raw                TYPE string,
             address_street         TYPE string,
             address_city_state_zip TYPE string,
             sign_date              TYPE string,
           END OF ty_field_bag.

    TYPES: BEGIN OF ty_content,
             doc_type               TYPE string,
             fields                 TYPE ty_field_bag,
             " flat fallback (payload with the keys at the top level)
             account_holder         TYPE string,
             account_type           TYPE string,
             bank_name              TYPE string,
             bank_country           TYPE string,
             bank_address           TYPE string,
             iban                   TYPE string,
             swift_bic              TYPE string,
             account_number         TYPE string,
             routing_aba            TYPE string,
             routing_aba_wires      TYPE string,
             branch_code            TYPE string,
             currency               TYPE string,
             doc_date               TYPE string,
             signed                 TYPE string,
             signature_evidence     TYPE string,
             partial_capture        TYPE string,
             line1_name             TYPE string,
             line2_business_name    TYPE string,
             line3_classification   TYPE string,
             tin_type               TYPE string,
             tin_raw                TYPE string,
             address_street         TYPE string,
             address_city_state_zip TYPE string,
             sign_date              TYPE string,
           END OF ty_content.

    " Build the user prompt (filename hint + regex-verified candidates + text head).
    METHODS build_prompt
      IMPORTING iv_doc_class     TYPE string
                iv_text          TYPE string
                it_candidates    TYPE zif_mdmdoc_types=>tt_fields
      RETURNING VALUE(rv_prompt) TYPE string.

    " Verbatim system prompts (regex-candidate wording), assembled with newlines.
    METHODS system_bank RETURNING VALUE(rv_text) TYPE string.
    METHODS system_w9   RETURNING VALUE(rv_text) TYPE string.

    " Transcription system prompt for the vision tier.
    METHODS system_vision RETURNING VALUE(rv_text) TYPE string.

    " Strip a leading <think>...</think> block defensively.
    METHODS strip_think
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    " Serialize the regex candidates as a compact JSON object for the prompt.
    METHODS candidates_json
      IMPORTING it_candidates  TYPE zif_mdmdoc_types=>tt_fields
      RETURNING VALUE(rv_json) TYPE string.

    " One /api/chat round-trip; parses message.content, strips <think>.
    METHODS chat_once
      IMPORTING iv_body     TYPE string
      EXPORTING ev_content  TYPE string
                ev_ok       TYPE abap_bool
                ev_error    TYPE string.

    " Pull the first JSON object out of a model reply (mirrors _extract_json):
    " strip code fences, then use the {...} span. ev_ok=false when none found.
    METHODS extract_json_object
      IMPORTING iv_text  TYPE string
      EXPORTING ev_json  TYPE string
                ev_ok    TYPE abap_bool.

    " Fold the flat content struct into tt_fields (skipping empties) + doc_type.
    METHODS content_to_fields
      IMPORTING is_content   TYPE ty_content
      EXPORTING et_fields    TYPE zif_mdmdoc_types=>tt_fields
                ev_doc_type  TYPE string.

    METHODS add_field
      IMPORTING iv_name  TYPE string
                iv_value TYPE string
      CHANGING  ct_fields TYPE zif_mdmdoc_types=>tt_fields.
ENDCLASS.


CLASS zcl_mdmdoc_llm IMPLEMENTATION.

  METHOD constructor.
    " Trim a trailing slash off the base url (parity with model_client.host()).
    mv_url = iv_url.
    IF mv_url CP '*/'.
      mv_url = substring( val = mv_url len = strlen( mv_url ) - 1 ).
    ENDIF.
    mv_model_text   = iv_model_text.
    mv_model_vision = iv_model_vision.
    mv_timeout      = iv_timeout.
  ENDMETHOD.


  METHOD probe.
    " GET {url}/api/tags — any 200 means the endpoint is up. model_client._probe
    " uses a short 5s timeout; http_post honours mv_timeout, so probe just checks
    " reachability. We reuse http_post with an empty body (GET-style, see below).
    DATA lv_body  TYPE string.
    DATA lv_ok    TYPE abap_bool.
    DATA lv_error TYPE string.

    http_post( EXPORTING iv_path = `/api/tags`
                         iv_body = ``
               IMPORTING ev_body  = lv_body
                         ev_ok    = lv_ok
                         ev_error = lv_error ).
    rv_up = lv_ok.
  ENDMETHOD.


  METHOD extract_fields.
    " Build the /api/chat body and run one round-trip; on invalid-JSON content
    " retry ONCE with a stern reminder appended to the user message.
    DATA ls_req     TYPE ty_chat_req.
    DATA ls_content TYPE ty_content.
    DATA lv_prompt  TYPE string.
    DATA lv_system  TYPE string.
    DATA lv_body    TYPE string.
    DATA lv_reply   TYPE string.
    DATA lv_ok      TYPE abap_bool.
    DATA lv_error   TYPE string.
    DATA lv_attempt TYPE i.

    CLEAR: et_fields, ev_doc_type, ev_ok, ev_error.

    lv_prompt = build_prompt( iv_doc_class  = iv_doc_class
                              iv_text       = iv_text
                              it_candidates = it_candidates ).
    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9.
      lv_system = system_w9( ).
    ELSE.
      lv_system = system_bank( ).
    ENDIF.

    ls_req-model            = mv_model_text.
    ls_req-stream           = abap_false.
    ls_req-format           = `json`.
    ls_req-think            = abap_false.
    ls_req-options-temperature = `0.1`.
    ls_req-options-num_ctx     = 8192.
    ls_req-options-num_predict = 1536.

    DO 2 TIMES.
      lv_attempt = sy-index.
      CLEAR ls_req-messages.
      APPEND VALUE #( role = `system` content = lv_system ) TO ls_req-messages.
      APPEND VALUE #( role = `user`   content = lv_prompt ) TO ls_req-messages.

      lv_body = /ui2/cl_json=>serialize( data        = ls_req
                                         compress     = abap_false
                                         pretty_name = /ui2/cl_json=>pretty_mode-low_case ).
      " temperature must be a bare JSON number, not a quoted string.
      REPLACE ALL OCCURRENCES OF `"temperature":"0.1"` IN lv_body WITH `"temperature":0.1`.
      " drop the empty images array carried by every ty_msg row (text tier has none).
      REPLACE ALL OCCURRENCES OF `,"images":[]` IN lv_body WITH ``.

      chat_once( EXPORTING iv_body    = lv_body
                 IMPORTING ev_content = lv_reply
                           ev_ok      = lv_ok
                           ev_error   = lv_error ).
      IF lv_ok = abap_false.
        " HTTP / transport failure — no retry helps, surface it.
        ev_ok    = abap_false.
        ev_error = lv_error.
        RETURN.
      ENDIF.

      " Mirror model_client._extract_json: pull the first JSON object out of the
      " reply; a non-JSON reply (e.g. an apology) is the retry trigger.
      DATA lv_json  TYPE string.
      DATA lv_valid TYPE abap_bool.
      extract_json_object( EXPORTING iv_text  = lv_reply
                           IMPORTING ev_json  = lv_json
                                     ev_ok    = lv_valid ).
      IF lv_valid = abap_true.
        CLEAR ls_content.
        TRY.
            /ui2/cl_json=>deserialize( EXPORTING json = lv_json
                                       CHANGING  data = ls_content ).
            content_to_fields( EXPORTING is_content  = ls_content
                               IMPORTING et_fields   = et_fields
                                         ev_doc_type = ev_doc_type ).
            ev_ok    = abap_true.
            ev_error = ``.
            RETURN.
          CATCH cx_root INTO DATA(lx_json).
            lv_valid = abap_false.
            ev_error = |model returned no valid JSON: { lx_json->get_text( ) }|.
        ENDTRY.
      ELSE.
        ev_error = `model returned no valid JSON`.
      ENDIF.

      IF lv_attempt >= 2.
        ev_ok = abap_false.
        RETURN.
      ENDIF.
      " retry: stiffen the user message (parity with generate_json)
      lv_prompt = lv_prompt && cl_abap_char_utilities=>newline
                  && cl_abap_char_utilities=>newline
                  && `Return ONLY valid JSON, nothing else.`.
    ENDDO.
  ENDMETHOD.


  METHOD transcribe_image.
    " Vision tier: same /api/chat shape, but messages[1] carries the base64 image
    " and there is NO format:json — we want a plain-text transcription back.
    " iv_mime is accepted for caller parity; Ollama takes raw base64 (no data URI).
    DATA ls_req    TYPE ty_chat_req.
    DATA lv_b64    TYPE string.
    DATA lv_body   TYPE string.
    DATA lv_reply  TYPE string.
    DATA lv_ok     TYPE abap_bool.
    DATA lv_error  TYPE string.

    CLEAR: ev_text, ev_ok, ev_error.

    lv_b64 = cl_http_utility=>encode_x_base64( iv_image ).

    ls_req-model               = mv_model_vision.
    ls_req-stream              = abap_false.
    ls_req-think               = abap_false.
    ls_req-options-temperature = `0.1`.
    ls_req-options-num_ctx     = 8192.
    ls_req-options-num_predict = 1536.
    " NB: format stays empty -> the 'format' key is dropped by /ui2/cl_json.

    APPEND VALUE #( role = `system` content = system_vision( ) ) TO ls_req-messages.
    DATA ls_user TYPE ty_msg.
    ls_user-role    = `user`.
    ls_user-content = `Transcribe this document exactly as printed.`.
    APPEND lv_b64 TO ls_user-images.
    APPEND ls_user TO ls_req-messages.

    lv_body = /ui2/cl_json=>serialize( data        = ls_req
                                       compress     = abap_false
                                       pretty_name = /ui2/cl_json=>pretty_mode-low_case ).
    REPLACE ALL OCCURRENCES OF `"temperature":"0.1"` IN lv_body WITH `"temperature":0.1`.
    " no format:json on the vision tier -> drop the empty format key; strip the
    " empty images[] the system message carries (the user message keeps its base64).
    REPLACE ALL OCCURRENCES OF `,"format":""` IN lv_body WITH ``.
    REPLACE ALL OCCURRENCES OF `"format":"",`  IN lv_body WITH ``.
    REPLACE ALL OCCURRENCES OF `,"images":[]`  IN lv_body WITH ``.

    chat_once( EXPORTING iv_body    = lv_body
               IMPORTING ev_content = lv_reply
                         ev_ok      = lv_ok
                         ev_error   = lv_error ).
    IF lv_ok = abap_false.
      ev_ok    = abap_false.
      ev_error = lv_error.
      RETURN.
    ENDIF.

    ev_text = lv_reply.
    ev_ok   = abap_true.
  ENDMETHOD.


  METHOD chat_once.
    " POST /api/chat, read message.content, strip a leading <think> block.
    DATA lv_body  TYPE string.
    DATA lv_ok    TYPE abap_bool.
    DATA lv_error TYPE string.
    DATA ls_resp  TYPE ty_chat_resp.

    http_post( EXPORTING iv_path = `/api/chat`
                         iv_body = iv_body
               IMPORTING ev_body  = lv_body
                         ev_ok    = lv_ok
                         ev_error = lv_error ).
    IF lv_ok = abap_false.
      ev_ok      = abap_false.
      ev_error   = lv_error.
      ev_content = ``.
      RETURN.
    ENDIF.

    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json = lv_body
                                   CHANGING  data = ls_resp ).
      CATCH cx_root INTO DATA(lx).
        ev_ok      = abap_false.
        ev_error   = |chat envelope parse failed: { lx->get_text( ) }|.
        ev_content = ``.
        RETURN.
    ENDTRY.

    ev_content = strip_think( ls_resp-message-content ).
    ev_ok      = abap_true.
    ev_error   = ``.
  ENDMETHOD.


  METHOD http_post.
    " ONE place where HTTP happens. GET when iv_body is empty (probe/api/tags),
    " POST otherwise. Any exception -> ev_ok = abap_false + ev_error.
    DATA lo_client TYPE REF TO if_http_client.
    DATA lv_code   TYPE i.
    DATA lv_reason TYPE string.

    CLEAR: ev_body, ev_ok, ev_error.

    cl_http_client=>create_by_url(
      EXPORTING url                = mv_url && iv_path
      IMPORTING client             = lo_client
      EXCEPTIONS argument_not_found = 1
                 plugin_not_active  = 2
                 internal_error     = 3
                 OTHERS             = 4 ).
    IF sy-subrc <> 0.
      ev_ok    = abap_false.
      ev_error = |http client create failed (subrc { sy-subrc })|.
      RETURN.
    ENDIF.

    TRY.
        IF iv_body IS INITIAL.
          lo_client->request->set_method( if_http_request=>co_request_method_get ).
        ELSE.
          lo_client->request->set_method( if_http_request=>co_request_method_post ).
          lo_client->request->set_header_field( name  = 'Content-Type'
                                                value = 'application/json' ).
          lo_client->request->set_cdata( iv_body ).
        ENDIF.

        lo_client->send( EXPORTING timeout                = mv_timeout
                         EXCEPTIONS http_communication_failure = 1
                                    http_invalid_state         = 2
                                    http_processing_failed     = 3
                                    OTHERS                     = 4 ).
        IF sy-subrc <> 0.
          ev_ok    = abap_false.
          ev_error = |http send failed (subrc { sy-subrc })|.
          lo_client->close( EXCEPTIONS OTHERS = 0 ).
          RETURN.
        ENDIF.

        lo_client->receive( EXCEPTIONS http_communication_failure = 1
                                       http_invalid_state         = 2
                                       http_processing_failed     = 3
                                       OTHERS                     = 4 ).
        IF sy-subrc <> 0.
          ev_ok    = abap_false.
          ev_error = |http receive failed (subrc { sy-subrc })|.
          lo_client->close( EXCEPTIONS OTHERS = 0 ).
          RETURN.
        ENDIF.

        lo_client->response->get_status( IMPORTING code   = lv_code
                                                   reason = lv_reason ).
        ev_body = lo_client->response->get_cdata( ).
        lo_client->close( EXCEPTIONS OTHERS = 0 ).

        IF lv_code >= 200 AND lv_code < 300.
          ev_ok    = abap_true.
          ev_error = ``.
        ELSE.
          ev_ok    = abap_false.
          ev_error = |HTTP { lv_code } { lv_reason }|.
        ENDIF.
      CATCH cx_root INTO DATA(lx).
        ev_ok    = abap_false.
        ev_error = lx->get_text( ).
    ENDTRY.
  ENDMETHOD.


  METHOD build_prompt.
    " Port of stage_b.build_prompt (custom-model branch: no few-shot injection):
    "   DOCUMENT FILENAME: <n/a in ABAP — the caller has no path>
    "   REGEX-VERIFIED CANDIDATES (deterministic — trust over your own reading):
    "   <json>
    "   DOCUMENT TEXT:
    "   <text head, capped>
    "   Return JSON with exactly these keys ...
    DATA lv_nl    TYPE string.
    DATA lv_keys  TYPE string.
    DATA lv_types TYPE string.
    DATA lv_head  TYPE string.
    CONSTANTS lc_limit TYPE i VALUE 12000.

    lv_nl = cl_abap_char_utilities=>newline.

    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9.
      lv_keys  = zif_mdmdoc_types=>c_w9_keys.
      lv_types = `w9, w8, other_tax, unknown`.
    ELSE.
      lv_keys  = zif_mdmdoc_types=>c_bank_keys.
      lv_types = `bank_letter, bank_statement, supplier_letterhead, bank_screenshot, ` &&
                 `voided_check, payment_instructions, ap_document, invoice, email, ` &&
                 `editable_source, other`.
    ENDIF.

    " text head (cap without splitting mid-run; classic substring is byte-safe here)
    IF strlen( iv_text ) > lc_limit.
      lv_head = substring( val = iv_text off = 0 len = lc_limit ).
    ELSE.
      lv_head = iv_text.
    ENDIF.

    rv_prompt =
      `REGEX-VERIFIED CANDIDATES (from deterministic regex — trust these over your own reading):`
      && lv_nl
      && candidates_json( it_candidates )
      && lv_nl && lv_nl
      && `DOCUMENT TEXT:` && lv_nl
      && lv_head
      && lv_nl && lv_nl
      && `Return JSON with exactly these keys: doc_type (one of `
      && lv_types
      && `), fields {` && lv_keys && `}. `
      && `Use "" for absent string fields, false for absent boolean flags. Do not invent values.`.

    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank.
      rv_prompt = rv_prompt && lv_nl
        && `Classify by what the document IS, not by keywords: supplier ACH/remittance `
        && `payment instructions are doc_type payment_instructions even though they `
        && `mention invoices; a real invoice carries its own invoice number, date and `
        && `amount due.`.
    ENDIF.
  ENDMETHOD.


  METHOD candidates_json.
    " Compact {"name":"value",...} object mirroring json.dumps of raw.regex_candidates.
    " Values are string; JSON-escape the essentials (\ and ").
    DATA lv_out  TYPE string.
    DATA lv_val  TYPE string.
    DATA lv_first TYPE abap_bool VALUE abap_true.

    lv_out = `{`.
    LOOP AT it_candidates ASSIGNING FIELD-SYMBOL(<ls_c>).
      lv_val = <ls_c>-value.
      REPLACE ALL OCCURRENCES OF `\` IN lv_val WITH `\\`.
      REPLACE ALL OCCURRENCES OF `"` IN lv_val WITH `\"`.
      IF lv_first = abap_false.
        lv_out = lv_out && `,`.
      ENDIF.
      lv_out = lv_out && `"` && <ls_c>-name && `":"` && lv_val && `"`.
      lv_first = abap_false.
    ENDLOOP.
    lv_out = lv_out && `}`.
    rv_json = lv_out.
  ENDMETHOD.


  METHOD strip_think.
    " Defensive removal of a <think>...</think> span. Classic regex, no (?s):
    " flatten newlines to spaces so '.' spans the block, then REPLACE.
    " No think tag present -> return the text untouched.
    DATA lv_flat TYPE string.

    rv_text = iv_text.
    IF rv_text NS `<think>`.
      RETURN.
    ENDIF.
    lv_flat = rv_text.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline        IN lv_flat WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf          IN lv_flat WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_flat WITH ` `.
    REPLACE ALL OCCURRENCES OF REGEX `<think>.*</think>` IN lv_flat WITH `` IGNORING CASE.
    " trim leading/trailing whitespace only (Python .strip()); do NOT CONDENSE —
    " that would collapse interior double-spaces inside JSON string values.
    SHIFT lv_flat LEFT  DELETING LEADING ` `.
    SHIFT lv_flat RIGHT DELETING TRAILING ` `.
    SHIFT lv_flat LEFT  DELETING LEADING ` `.
    rv_text = lv_flat.
  ENDMETHOD.


  METHOD extract_json_object.
    " Best-effort: locate the first {...} object in the reply. Code fences and a
    " <think> block (already stripped upstream) are removed defensively.
    DATA lv_t   TYPE string.
    DATA lv_i   TYPE i.
    DATA lv_j   TYPE i.

    CLEAR: ev_json, ev_ok.
    lv_t = iv_text.
    REPLACE ALL OCCURRENCES OF REGEX '```json' IN lv_t WITH `` IGNORING CASE.
    REPLACE ALL OCCURRENCES OF '```' IN lv_t WITH ``.
    CONDENSE lv_t.
    IF lv_t IS INITIAL.
      RETURN.
    ENDIF.

    FIND FIRST OCCURRENCE OF `{` IN lv_t MATCH OFFSET lv_i.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    " last '}' — scan from the end
    lv_j = -1.
    DATA lv_off TYPE i.
    lv_off = 0.
    DO.
      FIND FIRST OCCURRENCE OF `}` IN SECTION OFFSET lv_off OF lv_t MATCH OFFSET lv_j.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      lv_off = lv_j + 1.
    ENDDO.
    IF lv_j < lv_i.
      RETURN.
    ENDIF.
    ev_json = substring( val = lv_t off = lv_i len = lv_j - lv_i + 1 ).
    ev_ok   = abap_true.
  ENDMETHOD.


  METHOD content_to_fields.
    " Fold the content payload into tt_fields, skipping empties. Values are read
    " from the nested `fields` object first (the shape the prompt asks for) and
    " fall back to the flat top-level key (parity with stage_b._fields_from).
    " doc_type is exported separately, lower-cased and trimmed.
    DATA lv_dt TYPE string.
    DATA ls_n  TYPE ty_field_bag.

    CLEAR: et_fields, ev_doc_type.
    ls_n = is_content-fields.

    lv_dt = is_content-doc_type.
    CONDENSE lv_dt.
    ev_doc_type = to_lower( lv_dt ).

    " Merge the flat top-level values into the nested bag where the nested one is
    " empty, then emit each field once from the merged bag.
    IF ls_n-account_holder         IS INITIAL. ls_n-account_holder         = is_content-account_holder.         ENDIF.
    IF ls_n-account_type           IS INITIAL. ls_n-account_type           = is_content-account_type.           ENDIF.
    IF ls_n-bank_name              IS INITIAL. ls_n-bank_name              = is_content-bank_name.              ENDIF.
    IF ls_n-bank_country           IS INITIAL. ls_n-bank_country           = is_content-bank_country.           ENDIF.
    IF ls_n-bank_address           IS INITIAL. ls_n-bank_address           = is_content-bank_address.           ENDIF.
    IF ls_n-iban                   IS INITIAL. ls_n-iban                   = is_content-iban.                   ENDIF.
    IF ls_n-swift_bic              IS INITIAL. ls_n-swift_bic              = is_content-swift_bic.              ENDIF.
    IF ls_n-account_number         IS INITIAL. ls_n-account_number         = is_content-account_number.         ENDIF.
    IF ls_n-routing_aba            IS INITIAL. ls_n-routing_aba            = is_content-routing_aba.            ENDIF.
    IF ls_n-routing_aba_wires      IS INITIAL. ls_n-routing_aba_wires      = is_content-routing_aba_wires.      ENDIF.
    IF ls_n-branch_code            IS INITIAL. ls_n-branch_code            = is_content-branch_code.            ENDIF.
    IF ls_n-currency               IS INITIAL. ls_n-currency               = is_content-currency.               ENDIF.
    IF ls_n-doc_date               IS INITIAL. ls_n-doc_date               = is_content-doc_date.               ENDIF.
    IF ls_n-signed                 IS INITIAL. ls_n-signed                 = is_content-signed.                 ENDIF.
    IF ls_n-signature_evidence     IS INITIAL. ls_n-signature_evidence     = is_content-signature_evidence.     ENDIF.
    IF ls_n-partial_capture        IS INITIAL. ls_n-partial_capture        = is_content-partial_capture.        ENDIF.
    IF ls_n-line1_name             IS INITIAL. ls_n-line1_name             = is_content-line1_name.             ENDIF.
    IF ls_n-line2_business_name    IS INITIAL. ls_n-line2_business_name    = is_content-line2_business_name.    ENDIF.
    IF ls_n-line3_classification   IS INITIAL. ls_n-line3_classification   = is_content-line3_classification.   ENDIF.
    IF ls_n-tin_type               IS INITIAL. ls_n-tin_type               = is_content-tin_type.               ENDIF.
    IF ls_n-tin_raw                IS INITIAL. ls_n-tin_raw                = is_content-tin_raw.                ENDIF.
    IF ls_n-address_street         IS INITIAL. ls_n-address_street         = is_content-address_street.         ENDIF.
    IF ls_n-address_city_state_zip IS INITIAL. ls_n-address_city_state_zip = is_content-address_city_state_zip. ENDIF.
    IF ls_n-sign_date              IS INITIAL. ls_n-sign_date              = is_content-sign_date.              ENDIF.

    " bank keys
    add_field( EXPORTING iv_name = `account_holder`     iv_value = ls_n-account_holder     CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `account_type`       iv_value = ls_n-account_type       CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `bank_name`          iv_value = ls_n-bank_name          CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `bank_country`       iv_value = ls_n-bank_country       CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `bank_address`       iv_value = ls_n-bank_address       CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `iban`               iv_value = ls_n-iban               CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `swift_bic`          iv_value = ls_n-swift_bic          CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `account_number`     iv_value = ls_n-account_number     CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `routing_aba`        iv_value = ls_n-routing_aba        CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `routing_aba_wires`  iv_value = ls_n-routing_aba_wires  CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `branch_code`        iv_value = ls_n-branch_code        CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `currency`           iv_value = ls_n-currency           CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `doc_date`           iv_value = ls_n-doc_date           CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `signed`             iv_value = ls_n-signed             CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `signature_evidence` iv_value = ls_n-signature_evidence CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `partial_capture`    iv_value = ls_n-partial_capture    CHANGING ct_fields = et_fields ).
    " w9 keys
    add_field( EXPORTING iv_name = `line1_name`             iv_value = ls_n-line1_name             CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `line2_business_name`    iv_value = ls_n-line2_business_name    CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `line3_classification`   iv_value = ls_n-line3_classification   CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `tin_type`               iv_value = ls_n-tin_type               CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `tin_raw`                iv_value = ls_n-tin_raw                CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `address_street`         iv_value = ls_n-address_street         CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `address_city_state_zip` iv_value = ls_n-address_city_state_zip CHANGING ct_fields = et_fields ).
    add_field( EXPORTING iv_name = `sign_date`              iv_value = ls_n-sign_date              CHANGING ct_fields = et_fields ).
  ENDMETHOD.


  METHOD add_field.
    " Skip empty values; store booleans/strings as-is (LLM JSON parity: 'true'/'false').
    IF iv_value IS INITIAL.
      RETURN.
    ENDIF.
    INSERT VALUE #( name = iv_name value = iv_value ) INTO TABLE ct_fields.
  ENDMETHOD.


  METHOD system_bank.
    " Verbatim port of prompts/system_bank.txt, OCR wording adapted to REGEX.
    DATA lv_nl TYPE string.
    lv_nl = cl_abap_char_utilities=>newline.
    rv_text =
      `You are a document reader for a banking-support validator. You receive the regex/text` && lv_nl &&
      `transcription of ONE document (a PDF or image a vendor submitted as banking proof).` && lv_nl &&
      `` && lv_nl &&
      `Your only job is to CLASSIFY the document type and EXTRACT fields exactly as printed.` && lv_nl &&
      `You never judge whether the document is acceptable — explicit rules outside the model do that.` && lv_nl &&
      `` && lv_nl &&
      `Document types:` && lv_nl &&
      `- bank_letter: issued BY a bank on bank letterhead (bank confirmation, account confirmation` && lv_nl &&
      `  letter, certificación bancaria, Bankbestätigung, conferma coordinate bancarie,` && lv_nl &&
      `  account-opening permit)` && lv_nl &&
      `- bank_statement: a periodic account statement / eStatement (statement period, transactions,` && lv_nl &&
      `  balances) — NOT a bank letter; no signature is expected on a statement` && lv_nl &&
      `- supplier_letterhead: the SUPPLIER's own letterhead stating their bank/payment details` && lv_nl &&
      `- bank_screenshot: online-banking or bank-app screenshot` && lv_nl &&
      `- voided_check: a voided/cancelled check` && lv_nl &&
      `- payment_instructions: the supplier's ACH/remittance payment instructions (how to pay` && lv_nl &&
      `  their future invoices). These often say "invoice number(s) being paid" — that does NOT` && lv_nl &&
      `  make them an invoice: a real invoice carries its OWN invoice number, date and amount due.` && lv_nl &&
      `- ap_document: an accounts-payable / remittance setup document` && lv_nl &&
      `- invoice: an invoice or pro forma invoice (even if it shows bank details)` && lv_nl &&
      `- email: plain email text, OR a PDF that is a printed email thread (From:/Sent:/To:/` && lv_nl &&
      `  Subject: headers) — even when a bank certificate is embedded as a screenshot` && lv_nl &&
      `- editable_source: editable office file` && lv_nl &&
      `- other: anything else` && lv_nl &&
      `Classify by what the document IS (its function), never by a single keyword.` && lv_nl &&
      `A PACKET that contains a bank confirmation letter is classified by that letter —` && lv_nl &&
      `an invoice page elsewhere in the packet does not make it an invoice.` && lv_nl &&
      `` && lv_nl &&
      `Field rules:` && lv_nl &&
      `- account_holder: the beneficiary/account OWNER name exactly as printed (a company or person).` && lv_nl &&
      `- account_type: the account name/type when labeled (e.g. "CHECKING ACCOUNT", "SAVINGS",` && lv_nl &&
      `  "DBS Business Multi-Currency Account", "普通口座" = ordinary account) —` && lv_nl &&
      `  this is NOT the holder; never put it into account_holder.` && lv_nl &&
      `- bank_name: full official bank name; bank_country: country of the BANK (name or ISO2) —` && lv_nl &&
      `  infer it from the bank's city when not printed (Wichita, KS -> US; 福岡県 -> JP).` && lv_nl &&
      `  Regulator watermarks in the page margin (e.g. "VIGILADO Superintendencia Financiera` && lv_nl &&
      `  de Colombia") are NOT the bank name.` && lv_nl &&
      `- bank_address: the BANK's own address/city (a "Bank City" field) — never the company's,` && lv_nl &&
      `  the requestor's or a home address.` && lv_nl &&
      `- iban / swift_bic / account_number: copy character-for-character (KEEP leading zeros,` && lv_nl &&
      `  printed separators like 072-154506-3, and rejoin digit groups printed with spaces);` && lv_nl &&
      `  prefer the REGEX-VERIFIED CANDIDATES when given; "" when absent — NEVER invent.` && lv_nl &&
      `  IBAN "N/A" means "". When both a printed account number and an IBAN appear, use the` && lv_nl &&
      `  PRINTED account number, not the zero-padded IBAN part. A postal code (〒NNN-NNNN or a` && lv_nl &&
      `  ZIP near an address) is NEVER the account number.` && lv_nl &&
      `- routing_aba: 9-digit US ABA numbers ONLY. Italian ABI/CAB, Japanese bank/branch codes` && lv_nl &&
      `  and other domestic codes do NOT go here — leave routing empty for non-US banks.` && lv_nl &&
      `  US letters often list TWO: "Bank ABA (standard)", "ACH routing" -> routing_aba;` && lv_nl &&
      `  "Bank ABA (domestic wires)", "wire routing" -> routing_aba_wires. Extract BOTH,` && lv_nl &&
      `  as separate fields — never merge or drop one.` && lv_nl &&
      `- branch_code: the bank branch number when labeled (支店 / Branch No / CAB), e.g. "258".` && lv_nl &&
      `- doc_date: the date PRINTED in the document body/header. File metadata or today's` && lv_nl &&
      `  date is NOT a document date — "" when no date is visibly printed. For statements use` && lv_nl &&
      `  the statement period (e.g. "01-Jun-2026 to 30-Jun-2026"); a DocuSign/e-signature` && lv_nl &&
      `  timestamp counts as the signing date.` && lv_nl &&
      `- currency: if stated.` && lv_nl &&
      `- signed: true ONLY for a visible HANDWRITTEN signature or ink stamp. A typed name,` && lv_nl &&
      `  title or contact block of a bank officer is NOT a signature -> signed=false and` && lv_nl &&
      `  describe it in signature_evidence (e.g. "typed officer block"). A statement like` && lv_nl &&
      `  "this is a computer generated confirmation and requires no signature" also means` && lv_nl &&
      `  signed=false — copy that statement into signature_evidence. A DocuSign/Adobe-Sign` && lv_nl &&
      `  box with a typed name IS an electronic signature: signed=true, signature_evidence` && lv_nl &&
      `  "electronically signed (DocuSign)".` && lv_nl &&
      `- partial_capture: true if the capture looks cropped/incomplete.` && lv_nl &&
      `Respond with JSON only.`.
  ENDMETHOD.


  METHOD system_w9.
    " Verbatim port of prompts/system_w9.txt, OCR wording adapted to REGEX.
    DATA lv_nl TYPE string.
    lv_nl = cl_abap_char_utilities=>newline.
    rv_text =
      `You are a document reader for a US tax-form validator. You receive the regex/text` && lv_nl &&
      `transcription of ONE document (usually an IRS Form W-9 or W-8).` && lv_nl &&
      `` && lv_nl &&
      `Your only job is to CLASSIFY the form and EXTRACT fields exactly as printed. You never` && lv_nl &&
      `judge acceptability — explicit rules outside the model do that.` && lv_nl &&
      `` && lv_nl &&
      `Document types:` && lv_nl &&
      `- w9: IRS Form W-9 (Request for Taxpayer Identification Number and Certification)` && lv_nl &&
      `- w8: any W-8 variant (W-8BEN, W-8BEN-E, ... — Certificate of Foreign Status)` && lv_nl &&
      `- other_tax: some other tax document` && lv_nl &&
      `- unknown: cannot tell` && lv_nl &&
      `` && lv_nl &&
      `Field rules:` && lv_nl &&
      `- line1_name: W-9 Line 1 taxpayer legal name EXACTLY as printed (this maps to SAP Name 1)` && lv_nl &&
      `- line2_business_name: W-9 Line 2 business/disregarded-entity name, "" if empty` && lv_nl &&
      `  (NEVER swap or merge Line 1 and Line 2)` && lv_nl &&
      `- line3_classification: the federal tax classification box that is checked` && lv_nl &&
      `  (Individual/sole proprietor, C corporation, S corporation, Partnership, Trust/estate, LLC, Other)` && lv_nl &&
      `- tin_type: "SSN" if the Social Security Number boxes are filled, "EIN" if the Employer` && lv_nl &&
      `  Identification Number boxes are filled, "" if unreadable` && lv_nl &&
      `- tin_raw: the tax number exactly as printed INCLUDING hyphens; "" if unreadable — NEVER` && lv_nl &&
      `  invent. The TIN lives ONLY in the SSN/EIN boxes of Part I. A DATE (like 1/1/2026 next` && lv_nl &&
      `  to the signature) is NEVER a TIN — dates go to sign_date. Box digits may appear` && lv_nl &&
      `  separated ("8 1 - 0 8 2 6 7 3 4" means 81-0826734).` && lv_nl &&
      `- address_street / address_city_state_zip: address parts exactly as shown, "" when absent` && lv_nl &&
      `- signed: true only if a signature is present; sign_date: the date next to it, "" if none` && lv_nl &&
      `` && lv_nl &&
      `Reading hint: in flattened W-9 PDFs the FILLED values (names, address, TIN digits,` && lv_nl &&
      `checkbox marks) usually appear near the END of the text, AFTER all the printed form` && lv_nl &&
      `boilerplate — look there first. A lone "x"/"✔" next to a classification name marks the` && lv_nl &&
      `checked box.` && lv_nl &&
      `Respond with JSON only.`.
  ENDMETHOD.


  METHOD system_vision.
    " Plain-text transcription system prompt for the vision tier (no JSON).
    " ONE text, shared with the Python extractor: ZCL_MDMDOC_PROMPTS is generated
    " from prompts/vision/transcribe_md.v1.txt by tools/gen_prompts_abap.py. The
    " three sentences that used to live here lacked the rules the benchmark showed
    " to matter — above all "never translate or romanize", without which a CJK page
    " comes back in latin letters and every value on it is lost.
    rv_text = zcl_mdmdoc_prompts=>vision_transcribe( ).
  ENDMETHOD.

ENDCLASS.
