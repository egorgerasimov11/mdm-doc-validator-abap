" Local test classes for ZCL_MDMDOC_LLM.
" The class isolates ALL HTTP inside the PROTECTED http_post method; the test
" double subclasses it and serves canned bodies (no network / filesystem / GUI).
CLASS ltd_llm DEFINITION FINAL INHERITING FROM zcl_mdmdoc_llm.
  PUBLIC SECTION.
    " Queue of canned responses; each http_post call pops the next one.
    TYPES: BEGIN OF ty_canned,
             body TYPE string,
             ok   TYPE abap_bool,
             err  TYPE string,
           END OF ty_canned.
    DATA mt_canned   TYPE STANDARD TABLE OF ty_canned WITH EMPTY KEY.
    DATA mt_seen_path TYPE string_table.   " paths http_post was asked for
    DATA mt_seen_body TYPE string_table.   " request bodies passed in
    DATA mv_calls    TYPE i.

    METHODS queue
      IMPORTING iv_body TYPE string
                iv_ok   TYPE abap_bool DEFAULT abap_true
                iv_err  TYPE string    DEFAULT ``.

  PROTECTED SECTION.
    METHODS http_post REDEFINITION.
ENDCLASS.

CLASS ltd_llm IMPLEMENTATION.
  METHOD queue.
    APPEND VALUE #( body = iv_body ok = iv_ok err = iv_err ) TO mt_canned.
  ENDMETHOD.

  METHOD http_post.
    DATA ls_canned TYPE ty_canned.
    mv_calls = mv_calls + 1.
    APPEND iv_path TO mt_seen_path.
    APPEND iv_body TO mt_seen_body.
    IF mv_calls <= lines( mt_canned ).
      ls_canned = mt_canned[ mv_calls ].
    ELSE.
      " nothing queued -> behave like a transport failure
      ls_canned-ok  = abap_false.
      ls_canned-err = `no canned response queued`.
    ENDIF.
    ev_body  = ls_canned-body.
    ev_ok    = ls_canned-ok.
    ev_error = ls_canned-err.
  ENDMETHOD.
ENDCLASS.


CLASS ltcl_llm DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    DATA mo TYPE REF TO ltd_llm.

    METHODS make
      RETURNING VALUE(ro) TYPE REF TO ltd_llm.

    " helper: wrap a content JSON string as an Ollama /api/chat envelope
    METHODS envelope
      IMPORTING iv_content     TYPE string
      RETURNING VALUE(rv_body) TYPE string.

    METHODS extract_happy_bank        FOR TESTING.
    METHODS extract_strips_think      FOR TESTING.
    METHODS extract_retry_then_ok     FOR TESTING.
    METHODS extract_http_failure      FOR TESTING.
    METHODS extract_skips_empty       FOR TESTING.
    METHODS prompt_has_candidates     FOR TESTING.
    METHODS prompt_has_doc_text       FOR TESTING.
    METHODS probe_up                  FOR TESTING.
    METHODS probe_down                FOR TESTING.
    METHODS transcribe_ok             FOR TESTING.
    METHODS transcribe_http_failure   FOR TESTING.
ENDCLASS.

CLASS ltcl_llm IMPLEMENTATION.

  METHOD make.
    ro = NEW ltd_llm( iv_url          = `http://127.0.0.1:11435/`
                      iv_model_text   = `qwen3:4b`
                      iv_model_vision = `qwen2.5vl:7b`
                      iv_timeout      = 120 ).
  ENDMETHOD.

  METHOD envelope.
    " JSON-escape the content (it is itself JSON with quotes) into the envelope.
    DATA lv_esc TYPE string.
    lv_esc = iv_content.
    REPLACE ALL OCCURRENCES OF `\` IN lv_esc WITH `\\`.
    REPLACE ALL OCCURRENCES OF `"` IN lv_esc WITH `\"`.
    rv_body = `{"model":"qwen3:4b","message":{"role":"assistant","content":"`
              && lv_esc && `"}}`.
  ENDMETHOD.

  METHOD extract_happy_bank.
    DATA lt_cand   TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_fields TYPE zif_mdmdoc_types=>tt_fields.
    DATA lv_type   TYPE string.
    DATA lv_ok     TYPE abap_bool.
    DATA lv_err    TYPE string.

    mo = make( ).
    INSERT VALUE #( name = `iban` value = `DE89370400440532013000` ) INTO TABLE lt_cand.
    mo->queue( envelope(
      `{"doc_type":"bank_letter","fields":{"account_holder":"ACME GmbH",`
      && `"bank_name":"Deutsche Bank","iban":"DE89370400440532013000","signed":"true"}}` ) ).

    mo->extract_fields( EXPORTING iv_doc_class  = zif_mdmdoc_types=>c_doc_class-bank
                                  iv_text       = `Bank confirmation letter ...`
                                  it_candidates = lt_cand
                        IMPORTING et_fields     = lt_fields
                                  ev_doc_type   = lv_type
                                  ev_ok         = lv_ok
                                  ev_error      = lv_err ).

    cl_abap_unit_assert=>assert_equals( act = lv_ok exp = abap_true msg = `happy path ok` ).
    cl_abap_unit_assert=>assert_equals( act = lv_type exp = `bank_letter` ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_fields[ name = `account_holder` ]-value exp = `ACME GmbH` ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_fields[ name = `iban` ]-value exp = `DE89370400440532013000` ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_fields[ name = `signed` ]-value exp = `true`
      msg = `booleans stored as the string 'true'` ).
  ENDMETHOD.

  METHOD extract_strips_think.
    DATA lt_cand   TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_fields TYPE zif_mdmdoc_types=>tt_fields.
    DATA lv_type   TYPE string.
    DATA lv_ok     TYPE abap_bool.
    DATA lv_err    TYPE string.
    DATA lv_content TYPE string.

    mo = make( ).
    lv_content = `<think>` && cl_abap_char_utilities=>newline
                 && `let me reason about the doc` && cl_abap_char_utilities=>newline
                 && `</think>`
                 && `{"doc_type":"w9","fields":{"line1_name":"John Smith","tin_type":"SSN"}}`.
    mo->queue( envelope( lv_content ) ).

    mo->extract_fields( EXPORTING iv_doc_class  = zif_mdmdoc_types=>c_doc_class-w9
                                  iv_text       = `Form W-9 ...`
                                  it_candidates = lt_cand
                        IMPORTING et_fields     = lt_fields
                                  ev_doc_type   = lv_type
                                  ev_ok         = lv_ok
                                  ev_error      = lv_err ).

    cl_abap_unit_assert=>assert_equals( act = lv_ok exp = abap_true
      msg = `<think> wrapper stripped, JSON parsed` ).
    cl_abap_unit_assert=>assert_equals( act = lv_type exp = `w9` ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_fields[ name = `line1_name` ]-value exp = `John Smith` ).
  ENDMETHOD.

  METHOD extract_retry_then_ok.
    DATA lt_cand   TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_fields TYPE zif_mdmdoc_types=>tt_fields.
    DATA lv_type   TYPE string.
    DATA lv_ok     TYPE abap_bool.
    DATA lv_err    TYPE string.

    mo = make( ).
    " first content is not valid JSON -> triggers the single retry
    mo->queue( envelope( `sorry, I could not read the document` ) ).
    " second content is valid -> succeeds on retry
    mo->queue( envelope( `{"doc_type":"bank_letter","fields":{"bank_name":"Citibank"}}` ) ).

    mo->extract_fields( EXPORTING iv_doc_class  = zif_mdmdoc_types=>c_doc_class-bank
                                  iv_text       = `...`
                                  it_candidates = lt_cand
                        IMPORTING et_fields     = lt_fields
                                  ev_doc_type   = lv_type
                                  ev_ok         = lv_ok
                                  ev_error      = lv_err ).

    cl_abap_unit_assert=>assert_equals( act = lv_ok exp = abap_true
      msg = `invalid JSON then valid on retry -> ok` ).
    cl_abap_unit_assert=>assert_equals( act = lv_type exp = `bank_letter` ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_fields[ name = `bank_name` ]-value exp = `Citibank` ).
    cl_abap_unit_assert=>assert_equals( act = mo->mv_calls exp = 2
      msg = `exactly two /api/chat calls (initial + one retry)` ).
  ENDMETHOD.

  METHOD extract_http_failure.
    DATA lt_cand   TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_fields TYPE zif_mdmdoc_types=>tt_fields.
    DATA lv_type   TYPE string.
    DATA lv_ok     TYPE abap_bool.
    DATA lv_err    TYPE string.

    mo = make( ).
    mo->queue( iv_body = `` iv_ok = abap_false iv_err = `connection refused` ).

    mo->extract_fields( EXPORTING iv_doc_class  = zif_mdmdoc_types=>c_doc_class-bank
                                  iv_text       = `...`
                                  it_candidates = lt_cand
                        IMPORTING et_fields     = lt_fields
                                  ev_doc_type   = lv_type
                                  ev_ok         = lv_ok
                                  ev_error      = lv_err ).

    cl_abap_unit_assert=>assert_equals( act = lv_ok exp = abap_false
      msg = `transport failure -> ev_ok false` ).
    cl_abap_unit_assert=>assert_equals( act = lv_err exp = `connection refused` ).
    cl_abap_unit_assert=>assert_equals( act = mo->mv_calls exp = 1
      msg = `HTTP failure is not retried` ).
  ENDMETHOD.

  METHOD extract_skips_empty.
    " Empty string fields must be skipped (parity with tt_fields skip-empties).
    DATA lt_cand   TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_fields TYPE zif_mdmdoc_types=>tt_fields.
    DATA lv_type   TYPE string.
    DATA lv_ok     TYPE abap_bool.
    DATA lv_err    TYPE string.

    mo = make( ).
    mo->queue( envelope(
      `{"doc_type":"bank_letter","fields":{"bank_name":"HSBC","iban":"","swift_bic":""}}` ) ).

    mo->extract_fields( EXPORTING iv_doc_class  = zif_mdmdoc_types=>c_doc_class-bank
                                  iv_text       = `...`
                                  it_candidates = lt_cand
                        IMPORTING et_fields     = lt_fields
                                  ev_doc_type   = lv_type
                                  ev_ok         = lv_ok
                                  ev_error      = lv_err ).

    cl_abap_unit_assert=>assert_equals( act = lv_ok exp = abap_true ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_fields[ name = `bank_name` ]-value exp = `HSBC` ).
    cl_abap_unit_assert=>assert_equals(
      act = line_exists( lt_fields[ name = `iban` ] ) exp = abap_false
      msg = `empty iban is skipped` ).
    cl_abap_unit_assert=>assert_equals(
      act = line_exists( lt_fields[ name = `swift_bic` ] ) exp = abap_false ).
  ENDMETHOD.

  METHOD prompt_has_candidates.
    " The request body posted to /api/chat must carry the regex candidates block.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_fields TYPE zif_mdmdoc_types=>tt_fields.
    DATA lv_type TYPE string.
    DATA lv_ok   TYPE abap_bool.
    DATA lv_err  TYPE string.
    DATA lv_body TYPE string.

    mo = make( ).
    INSERT VALUE #( name = `routing_aba` value = `021000021` ) INTO TABLE lt_cand.
    mo->queue( envelope( `{"doc_type":"bank_letter","fields":{}}` ) ).

    mo->extract_fields( EXPORTING iv_doc_class  = zif_mdmdoc_types=>c_doc_class-bank
                                  iv_text       = `some document text`
                                  it_candidates = lt_cand
                        IMPORTING et_fields     = lt_fields
                                  ev_doc_type   = lv_type
                                  ev_ok         = lv_ok
                                  ev_error      = lv_err ).

    lv_body = mo->mt_seen_body[ 1 ].
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_body exp = `*REGEX-VERIFIED CANDIDATES*`
      msg = `prompt carries the regex-verified candidates block` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_body exp = `*021000021*`
      msg = `candidate value present in the prompt` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_body exp = `*routing_aba*`
      msg = `candidate name present in the prompt` ).
  ENDMETHOD.

  METHOD prompt_has_doc_text.
    " Body must include the DOCUMENT TEXT head and the JSON-only instruction.
    DATA lt_cand TYPE zif_mdmdoc_types=>tt_fields.
    DATA lt_fields TYPE zif_mdmdoc_types=>tt_fields.
    DATA lv_type TYPE string.
    DATA lv_ok   TYPE abap_bool.
    DATA lv_err  TYPE string.
    DATA lv_body TYPE string.

    mo = make( ).
    mo->queue( envelope( `{"doc_type":"w9","fields":{}}` ) ).

    mo->extract_fields( EXPORTING iv_doc_class  = zif_mdmdoc_types=>c_doc_class-w9
                                  iv_text       = `UNIQUE_MARKER_TEXT_42`
                                  it_candidates = lt_cand
                        IMPORTING et_fields     = lt_fields
                                  ev_doc_type   = lv_type
                                  ev_ok         = lv_ok
                                  ev_error      = lv_err ).

    lv_body = mo->mt_seen_body[ 1 ].
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_body exp = `*DOCUMENT TEXT*` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_body exp = `*UNIQUE_MARKER_TEXT_42*`
      msg = `document text head reaches the prompt` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_body exp = `*line1_name*`
      msg = `w9 key list present in the prompt` ).
    " and the request must be addressed to /api/chat
    cl_abap_unit_assert=>assert_equals(
      act = mo->mt_seen_path[ 1 ] exp = `/api/chat` ).
  ENDMETHOD.

  METHOD probe_up.
    mo = make( ).
    mo->queue( iv_body = `{"models":[]}` iv_ok = abap_true ).
    cl_abap_unit_assert=>assert_equals(
      act = mo->probe( ) exp = abap_true msg = `200 on /api/tags -> up` ).
    cl_abap_unit_assert=>assert_equals(
      act = mo->mt_seen_path[ 1 ] exp = `/api/tags` ).
  ENDMETHOD.

  METHOD probe_down.
    mo = make( ).
    mo->queue( iv_body = `` iv_ok = abap_false iv_err = `timeout` ).
    cl_abap_unit_assert=>assert_equals(
      act = mo->probe( ) exp = abap_false msg = `no response -> down` ).
  ENDMETHOD.

  METHOD transcribe_ok.
    DATA lv_text TYPE string.
    DATA lv_ok   TYPE abap_bool.
    DATA lv_err  TYPE string.
    DATA lv_img  TYPE xstring.

    mo = make( ).
    lv_img = '4749463839'.   " arbitrary bytes; base64-encoded by the class
    mo->queue( envelope( `BANK OF EXAMPLE\nAccount holder: ACME` ) ).

    mo->transcribe_image( EXPORTING iv_image = lv_img
                                    iv_mime  = `image/png`
                          IMPORTING ev_text  = lv_text
                                    ev_ok    = lv_ok
                                    ev_error = lv_err ).

    cl_abap_unit_assert=>assert_equals( act = lv_ok exp = abap_true ).
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_text exp = `*BANK OF EXAMPLE*`
      msg = `plain-text transcription returned as-is` ).
    cl_abap_unit_assert=>assert_equals(
      act = mo->mt_seen_path[ 1 ] exp = `/api/chat` ).
    " the request body must carry an images[] array
    cl_abap_unit_assert=>assert_char_cp(
      act = mo->mt_seen_body[ 1 ] exp = `*"images"*`
      msg = `vision request carries a base64 image` ).
    " the options must match the Python extractor — each one was earned the hard way:
    " 1536 predict tokens silently cut a dense form page in half; no repeat_penalty
    " let the model loop one table cell to the token limit (279 s, zero values).
    cl_abap_unit_assert=>assert_char_cp(
      act = mo->mt_seen_body[ 1 ] exp = `*"repeat_penalty":1.15*`
      msg = `repeat_penalty is sent as a bare number` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = mo->mt_seen_body[ 1 ] exp = `*"num_predict":4096*`
      msg = `a dense page needs 4096 tokens of output` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = mo->mt_seen_body[ 1 ] exp = `*"temperature":0,*`
      msg = `transcription is deterministic` ).
    " the shared prompt must be the one the Python extractor uses, not a local copy
    cl_abap_unit_assert=>assert_char_cp(
      act = mo->mt_seen_body[ 1 ] exp = `*Never translate, romanize*`
      msg = `system prompt comes from ZCL_MDMDOC_PROMPTS` ).
  ENDMETHOD.

  METHOD transcribe_http_failure.
    DATA lv_text TYPE string.
    DATA lv_ok   TYPE abap_bool.
    DATA lv_err  TYPE string.
    DATA lv_img  TYPE xstring.

    mo = make( ).
    lv_img = 'DEADBEEF'.
    mo->queue( iv_body = `` iv_ok = abap_false iv_err = `vision unreachable` ).

    mo->transcribe_image( EXPORTING iv_image = lv_img
                                    iv_mime  = `image/png`
                          IMPORTING ev_text  = lv_text
                                    ev_ok    = lv_ok
                                    ev_error = lv_err ).

    cl_abap_unit_assert=>assert_equals( act = lv_ok exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = lv_err exp = `vision unreachable` ).
  ENDMETHOD.

ENDCLASS.
