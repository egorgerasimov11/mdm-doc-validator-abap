" Pure-ABAP PDF text-layer extraction (no Python counterpart; spec = CONTRACT.md).
" Scans stream/endstream bodies + their preceding dict, inflates /FlateDecode via a
" strategy chain, tokenizes BT/ET content operators (Tf/Tj/TJ/'/"/Td/TD/T*), decodes
" literal + hex strings, and maps 2-byte CID codes through /ToUnicode CMaps.
" Robustness beats completeness: every malformed structure is skipped silently
" (TRY/CATCH, bounds checks) — it never dumps; worst case ev_text = ''.
CLASS zcl_mdmdoc_pdf DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS extract_text
      IMPORTING iv_pdf       TYPE xstring
      EXPORTING ev_text      TYPE string
                ev_pages     TYPE i
                ev_encrypted TYPE abap_bool
                et_warnings  TYPE string_table.

    " ---- text-layer plausibility (port of src/mdmdoc/extract/plausibility.py) --
    " Is this text LANGUAGE, or the soup a broken text layer produces? A scanned
    " document whose embedded OCR layer is mojibake used to pass the strlen( ) < 40
    " test and be trusted as the document (case C-2026-08-21-02: a Korean bankbook
    " whose 1304-character layer read `zt4fla q=€+ d€qql€ 7l'J`). The Python
    " reference and this port must agree — parity is asserted case by case by
    " ZCL_MDMDOC_PLAUS_GOLDEN, generated from the Python side.
    "! Plausibility of a text layer, 0..1000 (Python plausibility( ) * 1000).
    CLASS-METHODS plausibility
      IMPORTING iv_text         TYPE string
      RETURNING VALUE(rv_score) TYPE i.
    "! Should this text layer be used at all? Folds the former strlen( ) test in.
    CLASS-METHODS layer_usable
      IMPORTING iv_text      TYPE string
                iv_min_chars TYPE i DEFAULT 40
      EXPORTING ev_usable    TYPE abap_bool
                ev_reason    TYPE string
                ev_score     TYPE i.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_cmap_entry,
             code TYPE i,
             char TYPE string,
           END OF ty_cmap_entry,
           tt_cmap TYPE SORTED TABLE OF ty_cmap_entry WITH UNIQUE KEY code.

    TYPES: BEGIN OF ty_named_cmap,
             obj TYPE string,       " object id "12 0" owning this ToUnicode stream
             map TYPE tt_cmap,
           END OF ty_named_cmap,
           tt_named_cmap TYPE STANDARD TABLE OF ty_named_cmap WITH EMPTY KEY.

    " ---- byte <-> latin-1 string (1:1 code point 0..255) --------------------
    CLASS-METHODS bytes_to_latin1
      IMPORTING iv_x          TYPE xstring
      RETURNING VALUE(rv_str) TYPE string.
    CLASS-METHODS latin1_to_bytes
      IMPORTING iv_str      TYPE string
      RETURNING VALUE(rv_x) TYPE xstring.

    " ---- inflate strategy chain (never raises) ------------------------------
    CLASS-METHODS inflate
      IMPORTING iv_zlib TYPE xstring
      EXPORTING ev_raw  TYPE xstring
                ev_ok   TYPE abap_bool.

    " ---- structure helpers --------------------------------------------------
    CLASS-METHODS count_pages
      IMPORTING iv_all          TYPE string
      RETURNING VALUE(rv_count) TYPE i.
    CLASS-METHODS skip_stream_eol
      IMPORTING iv_all        TYPE string
                iv_pos        TYPE i
      RETURNING VALUE(rv_pos) TYPE i.
    CLASS-METHODS trim_body_eol
      IMPORTING iv_all        TYPE string
                iv_start      TYPE i
                iv_end        TYPE i
      RETURNING VALUE(rv_end) TYPE i.
    CLASS-METHODS preceding_dict
      IMPORTING iv_all         TYPE string
                iv_before      TYPE i
      RETURNING VALUE(rv_dict) TYPE string.
    CLASS-METHODS obj_id_before
      IMPORTING iv_all        TYPE string
                iv_before     TYPE i
      RETURNING VALUE(rv_obj) TYPE string.
    CLASS-METHODS collect_cmaps
      IMPORTING iv_all      TYPE string
      EXPORTING et_cmaps    TYPE tt_named_cmap
      CHANGING  ct_fail     TYPE i.

    " ---- CMap parsing -------------------------------------------------------
    CLASS-METHODS parse_cmap
      IMPORTING iv_body       TYPE string
      RETURNING VALUE(rt_map) TYPE tt_cmap.

    " ---- content tokenizer --------------------------------------------------
    CLASS-METHODS tokenize_content
      IMPORTING iv_buf   TYPE string
                it_cmaps TYPE tt_named_cmap
      CHANGING  cv_out   TYPE string.
    CLASS-METHODS decode_literal
      IMPORTING iv_body       TYPE string
      RETURNING VALUE(rv_str) TYPE string.
    CLASS-METHODS hex_to_string
      IMPORTING iv_hex        TYPE string
      RETURNING VALUE(rv_str) TYPE string.
    CLASS-METHODS process_tj_array
      IMPORTING iv_arr        TYPE string
                iv_have_cmap  TYPE abap_bool
                it_map        TYPE tt_cmap
      CHANGING  cv_block      TYPE string.
    CLASS-METHODS emit_string
      IMPORTING iv_dec       TYPE string
                iv_have_cmap TYPE abap_bool
                it_map       TYPE tt_cmap
      CHANGING  cv_block     TYPE string.
    CLASS-METHODS apply_cmap
      IMPORTING iv_bytes TYPE string
                it_map   TYPE tt_cmap
      RETURNING VALUE(rv_text) TYPE string.
    CLASS-METHODS append_block
      CHANGING cv_out   TYPE string
               cv_block TYPE string.
    CLASS-METHODS matches_op
      IMPORTING iv_buf        TYPE string
                iv_pos        TYPE i
                iv_op         TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS find_array_end
      IMPORTING iv_buf        TYPE string
                iv_start      TYPE i
      RETURNING VALUE(rv_end) TYPE i.
    CLASS-METHODS select_font
      IMPORTING iv_buf       TYPE string
                iv_pos       TYPE i
                it_cmaps     TYPE tt_named_cmap
      EXPORTING ev_have_cmap TYPE abap_bool
                et_map       TYPE tt_cmap.

    " ---- text-layer plausibility helpers (port of extract/plausibility.py) ---
    " Everything below classifies characters WITHOUT unicode category tables: a
    " character above U+007F that is not in c_symbols is a letter of some other
    " script. Verified over the whole benchmark corpus — the discriminating power
    " lives entirely in the ASCII range (the Korean mojibake carries exactly one
    " non-ASCII character: the euro sign).
    CONSTANTS c_trust_layer TYPE i VALUE 700.
    " the two sets are split only to stay inside abaplint's 140-char line limit
    CONSTANTS c_symbols_a TYPE string VALUE `{}[]<>|^~``=@#$%*\€£¥₩§©®™°`.
    CONSTANTS c_symbols_b TYPE string VALUE `±×÷•·●○■□▪▫◆★☆←→↑↓☑☐✓✔✗✘`.
    CONSTANTS c_weird     TYPE string VALUE `{}[]<>|^~``=@#$%*\€£¥₩§©®™°`.
    CONSTANTS c_edge      TYPE string VALUE `()[]{}<>"'«»„“”‘’.,;:!?…-–—_/\|*+=~^``·•●○■□▪`.
    CONSTANTS c_upper     TYPE string VALUE `ABCDEFGHIJKLMNOPQRSTUVWXYZ`.
    CONSTANTS c_lower     TYPE string VALUE `abcdefghijklmnopqrstuvwxyz`.
    CONSTANTS c_digits    TYPE string VALUE `0123456789`.
    CONSTANTS c_vowels    TYPE string VALUE `aeiouy`.
    " printable ASCII, split in two only to stay inside the 140-char line limit;
    " a character outside these (and not whitespace) is a letter of another script
    CONSTANTS c_ascii_a   TYPE string VALUE ` !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNO`.
    CONSTANTS c_ascii_b   TYPE string VALUE `PQRSTUVWXYZ[\]^_``abcdefghijklmnopqrstuvwxyz{|}~`.

    CLASS-METHODS plaus_tokens
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rt_toks) TYPE string_table.
    CLASS-METHODS plaus_strip_edges
      IMPORTING iv_tok         TYPE string
      RETURNING VALUE(rv_core) TYPE string.
    CLASS-METHODS plaus_other_script
      IMPORTING iv_s          TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_wellformed
      IMPORTING iv_tok        TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_short_junk
      IMPORTING iv_tok        TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_word_improbable
      IMPORTING iv_word       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_latin_word_ok
      IMPORTING iv_tok        TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_is_ascii_letters
      IMPORTING iv_s          TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_num_token
      IMPORTING iv_s          TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_mixed_ok
      IMPORTING iv_s          TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_upper_code
      IMPORTING iv_s          TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_mail_or_url
      IMPORTING iv_s          TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_short_ok
      IMPORTING iv_s          TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS plaus_count_any
      IMPORTING iv_s          TYPE string
                iv_set        TYPE string
      RETURNING VALUE(rv_n)   TYPE i.

    " ---- numeric / char helpers ---------------------------------------------
    CLASS-METHODS hex_str_to_int
      IMPORTING iv_hex        TYPE string
      RETURNING VALUE(rv_int) TYPE i.
    CLASS-METHODS oct_str_to_int
      IMPORTING iv_oct        TYPE string
      RETURNING VALUE(rv_int) TYPE i.
    CLASS-METHODS cp_to_char
      IMPORTING iv_cp          TYPE i
      RETURNING VALUE(rv_char) TYPE string.
    CLASS-METHODS int_to_hex4
      IMPORTING iv_int        TYPE i
      RETURNING VALUE(rv_hex) TYPE string.
    CLASS-METHODS char_cp
      IMPORTING iv_char      TYPE string
      RETURNING VALUE(rv_cp) TYPE i.
    CLASS-METHODS utf16be_hex_to_str
      IMPORTING iv_hex        TYPE string
      RETURNING VALUE(rv_str) TYPE string.

ENDCLASS.



CLASS zcl_mdmdoc_pdf IMPLEMENTATION.

  METHOD extract_text.
    CLEAR: ev_text, ev_pages, ev_encrypted.
    CLEAR et_warnings.

    DATA lv_all        TYPE string.
    DATA lv_fail_count TYPE i VALUE 0.

    TRY.
        lv_all = bytes_to_latin1( iv_pdf ).
      CATCH cx_root.
        RETURN.       " undecodable bytes -> empty result, no dump
    ENDTRY.

    " ---- /Encrypt detection ----------------------------------------------
    FIND FIRST OCCURRENCE OF `/Encrypt` IN lv_all.
    IF sy-subrc = 0.
      ev_encrypted = abap_true.
    ENDIF.

    " ---- page count: /Type /Page (word-bounded, NOT /Pages) --------------
    ev_pages = count_pages( lv_all ).

    " ---- pre-pass: collect /ToUnicode CMaps -------------------------------
    DATA lt_cmaps TYPE tt_named_cmap.
    collect_cmaps( EXPORTING iv_all = lv_all
                   IMPORTING et_cmaps = lt_cmaps
                   CHANGING  ct_fail = lv_fail_count ).

    " A CID/Type0 font present without any collected ToUnicode CMap means 2-byte
    " codes cannot be decoded -> flag once (spec: 'cid-font-without-tounicode').
    IF lines( lt_cmaps ) = 0.
      IF lv_all CS `/Type0` OR lv_all CS `/CIDFontType0` OR lv_all CS `/CIDFontType2`.
        APPEND `cid-font-without-tounicode` TO et_warnings.
      ENDIF.
    ENDIF.

    " ---- main pass: walk streams, decode, tokenize -----------------------
    DATA lv_len  TYPE i.
    lv_len = strlen( lv_all ).
    DATA lv_pos  TYPE i VALUE 0.

    WHILE lv_pos < lv_len.
      DATA lv_sstart TYPE i.
      FIND FIRST OCCURRENCE OF `stream` IN SECTION OFFSET lv_pos OF lv_all
        MATCH OFFSET lv_sstart.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      " avoid the tail of 'endstream'
      IF lv_sstart >= 3
         AND substring( val = lv_all off = lv_sstart - 3 len = 3 ) = `end`.
        lv_pos = lv_sstart + 6.
        CONTINUE.
      ENDIF.

      DATA lv_bstart TYPE i.
      lv_bstart = skip_stream_eol( iv_all = lv_all iv_pos = lv_sstart + 6 ).

      DATA lv_estart TYPE i.
      FIND FIRST OCCURRENCE OF `endstream` IN SECTION OFFSET lv_bstart OF lv_all
        MATCH OFFSET lv_estart.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      DATA lv_bodyend TYPE i.
      lv_bodyend = trim_body_eol( iv_all = lv_all iv_start = lv_bstart iv_end = lv_estart ).

      DATA lv_dict TYPE string.
      lv_dict = preceding_dict( iv_all = lv_all iv_before = lv_sstart ).

      lv_pos = lv_estart + 9.

      " skip images / non-text streams
      IF lv_dict CS `/Subtype/Image` OR lv_dict CS `/Subtype /Image`
         OR lv_dict CS `/DCTDecode`
         OR lv_dict CS `/CCITTFaxCode` OR lv_dict CS `/CCITTFaxDecode`.
        CONTINUE.
      ENDIF.

      IF lv_bodyend <= lv_bstart.
        CONTINUE.
      ENDIF.
      DATA lv_body TYPE string.
      lv_body = substring( val = lv_all off = lv_bstart len = lv_bodyend - lv_bstart ).

      DATA lv_decoded TYPE string.
      CLEAR lv_decoded.
      IF lv_dict CS `/FlateDecode`.
        DATA lv_bufx TYPE xstring.
        DATA lv_raw  TYPE xstring.
        DATA lv_okinf TYPE abap_bool.
        TRY.
            lv_bufx = latin1_to_bytes( lv_body ).
          CATCH cx_root.
            lv_fail_count = lv_fail_count + 1.
            CONTINUE.
        ENDTRY.
        inflate( EXPORTING iv_zlib = lv_bufx IMPORTING ev_raw = lv_raw ev_ok = lv_okinf ).
        IF lv_okinf = abap_false.
          lv_fail_count = lv_fail_count + 1.
          CONTINUE.
        ENDIF.
        TRY.
            lv_decoded = bytes_to_latin1( lv_raw ).
          CATCH cx_root.
            lv_fail_count = lv_fail_count + 1.
            CONTINUE.
        ENDTRY.
      ELSE.
        lv_decoded = lv_body.
      ENDIF.

      tokenize_content( EXPORTING iv_buf = lv_decoded it_cmaps = lt_cmaps
                        CHANGING  cv_out = ev_text ).
    ENDWHILE.

    IF lv_fail_count > 0.
      APPEND |inflate-failed({ lv_fail_count })| TO et_warnings.
    ENDIF.
  ENDMETHOD.


  METHOD count_pages.
    " Count word-bounded '/Type /Page' occurrences, excluding '/Pages'.
    rv_count = 0.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_all ).
    DATA lv_off TYPE i VALUE 0.
    WHILE lv_off < lv_len.
      DATA lv_found TYPE i.
      FIND FIRST OCCURRENCE OF `/Type` IN SECTION OFFSET lv_off OF iv_all
        MATCH OFFSET lv_found.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      DATA lv_rest TYPE string.
      lv_rest = substring( val = iv_all off = lv_found + 5
                           len = nmin( val1 = 16 val2 = lv_len - ( lv_found + 5 ) ) ).
      SHIFT lv_rest LEFT DELETING LEADING ` `.
      SHIFT lv_rest LEFT DELETING LEADING cl_abap_char_utilities=>horizontal_tab.
      SHIFT lv_rest LEFT DELETING LEADING cl_abap_char_utilities=>cr_lf(1).
      SHIFT lv_rest LEFT DELETING LEADING cl_abap_char_utilities=>newline.
      IF lv_rest CP `/Page*`.
        DATA lv_after TYPE i.
        lv_after = strlen( `/Page` ).
        DATA lv_tail TYPE string.
        IF strlen( lv_rest ) > lv_after.
          lv_tail = substring( val = lv_rest off = lv_after len = 1 ).
        ELSE.
          lv_tail = ``.
        ENDIF.
        IF lv_tail NA `abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ`.
          rv_count = rv_count + 1.
        ENDIF.
      ENDIF.
      lv_off = lv_found + 5.
    ENDWHILE.
  ENDMETHOD.


  METHOD skip_stream_eol.
    " After the 'stream' keyword, skip an optional CRLF or LF to reach the body start.
    rv_pos = iv_pos.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_all ).
    IF rv_pos >= lv_len.
      RETURN.
    ENDIF.
    DATA lv_c1 TYPE string.
    lv_c1 = substring( val = iv_all off = rv_pos len = 1 ).
    IF lv_c1 = cl_abap_char_utilities=>cr_lf(1).
      rv_pos = rv_pos + 1.
      IF rv_pos < lv_len
         AND substring( val = iv_all off = rv_pos len = 1 ) = cl_abap_char_utilities=>newline.
        rv_pos = rv_pos + 1.
      ENDIF.
    ELSEIF lv_c1 = cl_abap_char_utilities=>newline.
      rv_pos = rv_pos + 1.
    ENDIF.
  ENDMETHOD.


  METHOD trim_body_eol.
    " Strip a single trailing EOL (LF or CRLF or CR) directly before 'endstream'.
    rv_end = iv_end.
    IF rv_end <= iv_start.
      RETURN.
    ENDIF.
    DATA lv_last TYPE string.
    lv_last = substring( val = iv_all off = rv_end - 1 len = 1 ).
    IF lv_last = cl_abap_char_utilities=>newline.
      rv_end = rv_end - 1.
      IF rv_end > iv_start.
        lv_last = substring( val = iv_all off = rv_end - 1 len = 1 ).
        IF lv_last = cl_abap_char_utilities=>cr_lf(1).
          rv_end = rv_end - 1.
        ENDIF.
      ENDIF.
    ELSEIF lv_last = cl_abap_char_utilities=>cr_lf(1).
      rv_end = rv_end - 1.
    ENDIF.
  ENDMETHOD.


  METHOD bytes_to_latin1.
    DATA lo_conv TYPE REF TO cl_abap_conv_in_ce.
    lo_conv = cl_abap_conv_in_ce=>create( encoding = '1100' ).
    lo_conv->convert( EXPORTING input = iv_x IMPORTING data = rv_str ).
  ENDMETHOD.


  METHOD latin1_to_bytes.
    DATA lo_conv TYPE REF TO cl_abap_conv_out_ce.
    lo_conv = cl_abap_conv_out_ce=>create( encoding = '1100' ).
    lo_conv->convert( EXPORTING data = iv_str IMPORTING buffer = rv_x ).
  ENDMETHOD.


  METHOD inflate.
    " The kernel classes verify checksums the caller cannot supply for a bare
    " /FlateDecode stream (gzip CRC32, ZIP CRC) — see C-2026-08-20-01. So: try the
    " kernel gzip path only for genuine gzip data, then decode the zlib envelope
    " with the checksum-free pure-ABAP inflater.
    CLEAR ev_raw.
    ev_ok = abap_false.

    " (a) the stream may genuinely be gzip — cheap to try
    TRY.
        cl_abap_gzip=>decompress_binary( EXPORTING gzip_in = iv_zlib
                                         IMPORTING raw_out = ev_raw ).
        ev_ok = abap_true.
        RETURN.
      CATCH cx_root.
        CLEAR ev_raw.
    ENDTRY.

    " (b) the normal case: a zlib envelope (RFC 1950) around raw deflate
    DATA lv_deflate TYPE xstring.
    DATA lv_is_zlib TYPE abap_bool.
    zcl_mdmdoc_inflate=>unwrap_zlib( EXPORTING iv_data    = iv_zlib
                                     IMPORTING ev_deflate = lv_deflate
                                               ev_is_zlib = lv_is_zlib ).
    IF lv_is_zlib = abap_true.
      zcl_mdmdoc_inflate=>decompress( EXPORTING iv_data = lv_deflate
                                      IMPORTING ev_raw  = ev_raw
                                                ev_ok   = ev_ok ).
      IF ev_ok = abap_true.
        RETURN.
      ENDIF.
      CLEAR ev_raw.
    ENDIF.

    " (c) last resort: treat the bytes as bare raw deflate
    zcl_mdmdoc_inflate=>decompress( EXPORTING iv_data = iv_zlib
                                    IMPORTING ev_raw  = ev_raw
                                              ev_ok   = ev_ok ).
    IF ev_ok = abap_false.
      CLEAR ev_raw.
    ENDIF.
  ENDMETHOD.


  METHOD preceding_dict.
    " Nearest '<<' ... (to end of window) before the stream keyword. Bounded window.
    CLEAR rv_dict.
    DATA lv_winstart TYPE i.
    lv_winstart = iv_before - 4000.
    IF lv_winstart < 0.
      lv_winstart = 0.
    ENDIF.
    DATA lv_window TYPE string.
    lv_window = substring( val = iv_all off = lv_winstart len = iv_before - lv_winstart ).
    FIND ALL OCCURRENCES OF `<<` IN lv_window RESULTS DATA(lt_op).
    IF lines( lt_op ) = 0.
      RETURN.
    ENDIF.
    DATA(ls_op) = lt_op[ lines( lt_op ) ].
    rv_dict = substring( val = lv_window off = ls_op-offset ).
  ENDMETHOD.


  METHOD obj_id_before.
    " Find the "<num> <gen> obj" header opening the object that contains iv_before.
    CLEAR rv_obj.
    DATA lv_winstart TYPE i.
    lv_winstart = iv_before - 6000.
    IF lv_winstart < 0.
      lv_winstart = 0.
    ENDIF.
    DATA lv_window TYPE string.
    lv_window = substring( val = iv_all off = lv_winstart len = iv_before - lv_winstart ).
    FIND ALL OCCURRENCES OF REGEX `(\d+)\s+(\d+)\s+obj` IN lv_window RESULTS DATA(lt_o).
    IF lines( lt_o ) = 0.
      RETURN.
    ENDIF.
    DATA(ls_o) = lt_o[ lines( lt_o ) ].
    DATA lv_sub TYPE string.
    lv_sub = substring( val = lv_window off = ls_o-offset len = ls_o-length ).
    FIND FIRST OCCURRENCE OF REGEX `(\d+)\s+(\d+)\s+obj` IN lv_sub
      SUBMATCHES DATA(lv_g1) DATA(lv_g2).
    IF sy-subrc = 0.
      CONCATENATE lv_g1 lv_g2 INTO rv_obj SEPARATED BY ` `.
    ENDIF.
  ENDMETHOD.


  METHOD collect_cmaps.
    " Walk streams; a CMap is detected by content markers. Inflate flate CMaps, parse
    " them, and store keyed by object id. Failures increment ct_fail.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_all ).
    DATA lv_pos TYPE i VALUE 0.

    WHILE lv_pos < lv_len.
      DATA lv_sstart TYPE i.
      FIND FIRST OCCURRENCE OF `stream` IN SECTION OFFSET lv_pos OF iv_all
        MATCH OFFSET lv_sstart.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      IF lv_sstart >= 3
         AND substring( val = iv_all off = lv_sstart - 3 len = 3 ) = `end`.
        lv_pos = lv_sstart + 6.
        CONTINUE.
      ENDIF.
      DATA lv_bstart TYPE i.
      lv_bstart = skip_stream_eol( iv_all = iv_all iv_pos = lv_sstart + 6 ).
      DATA lv_estart TYPE i.
      FIND FIRST OCCURRENCE OF `endstream` IN SECTION OFFSET lv_bstart OF iv_all
        MATCH OFFSET lv_estart.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      lv_pos = lv_estart + 9.

      IF lv_estart <= lv_bstart.
        CONTINUE.
      ENDIF.
      DATA lv_body TYPE string.
      lv_body = substring( val = iv_all off = lv_bstart len = lv_estart - lv_bstart ).

      DATA lv_dict TYPE string.
      lv_dict = preceding_dict( iv_all = iv_all iv_before = lv_sstart ).

      DATA lv_text TYPE string.
      CLEAR lv_text.
      IF lv_dict CS `/FlateDecode`.
        TRY.
            DATA lv_bx TYPE xstring.
            lv_bx = latin1_to_bytes( lv_body ).
            DATA lv_raw TYPE xstring.
            DATA lv_ok  TYPE abap_bool.
            inflate( EXPORTING iv_zlib = lv_bx IMPORTING ev_raw = lv_raw ev_ok = lv_ok ).
            IF lv_ok = abap_true.
              lv_text = bytes_to_latin1( lv_raw ).
            ENDIF.
          CATCH cx_root.
            CLEAR lv_text.
        ENDTRY.
      ELSE.
        lv_text = lv_body.
      ENDIF.

      IF lv_text IS INITIAL.
        CONTINUE.
      ENDIF.

      IF lv_text CS `beginbfchar` OR lv_text CS `beginbfrange` OR lv_text CS `begincmap`.
        DATA lt_map TYPE tt_cmap.
        lt_map = parse_cmap( lv_text ).
        IF lines( lt_map ) > 0.
          DATA lv_obj TYPE string.
          lv_obj = obj_id_before( iv_all = iv_all iv_before = lv_sstart ).
          APPEND VALUE #( obj = lv_obj map = lt_map ) TO et_cmaps.
        ENDIF.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.


  METHOD parse_cmap.
    " Parse beginbfchar / beginbfrange blocks into a code->char map.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_body ).

    " --- bfchar: <src> <dst> ---
    DATA lv_pos TYPE i VALUE 0.
    WHILE lv_pos < lv_len.
      DATA lv_bs TYPE i.
      FIND FIRST OCCURRENCE OF `beginbfchar` IN SECTION OFFSET lv_pos OF iv_body
        MATCH OFFSET lv_bs.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      lv_bs = lv_bs + strlen( `beginbfchar` ).
      DATA lv_be TYPE i.
      FIND FIRST OCCURRENCE OF `endbfchar` IN SECTION OFFSET lv_bs OF iv_body
        MATCH OFFSET lv_be.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      DATA lv_block TYPE string.
      lv_block = substring( val = iv_body off = lv_bs len = lv_be - lv_bs ).
      FIND ALL OCCURRENCES OF REGEX `<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>`
        IN lv_block RESULTS DATA(lt_ch).
      LOOP AT lt_ch INTO DATA(ls_ch).
        DATA lv_seg TYPE string.
        lv_seg = substring( val = lv_block off = ls_ch-offset len = ls_ch-length ).
        FIND FIRST OCCURRENCE OF REGEX `<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>`
          IN lv_seg SUBMATCHES DATA(lv_src) DATA(lv_dst).
        IF sy-subrc = 0.
          INSERT VALUE #( code = hex_str_to_int( lv_src )
                          char = utf16be_hex_to_str( lv_dst ) ) INTO TABLE rt_map.
        ENDIF.
      ENDLOOP.
      lv_pos = lv_be + strlen( `endbfchar` ).
    ENDWHILE.

    " --- bfrange: <lo> <hi> <dst> (simple form only) ---
    lv_pos = 0.
    WHILE lv_pos < lv_len.
      DATA lv_rbs TYPE i.
      FIND FIRST OCCURRENCE OF `beginbfrange` IN SECTION OFFSET lv_pos OF iv_body
        MATCH OFFSET lv_rbs.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      lv_rbs = lv_rbs + strlen( `beginbfrange` ).
      DATA lv_rbe TYPE i.
      FIND FIRST OCCURRENCE OF `endbfrange` IN SECTION OFFSET lv_rbs OF iv_body
        MATCH OFFSET lv_rbe.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      DATA lv_rblock TYPE string.
      lv_rblock = substring( val = iv_body off = lv_rbs len = lv_rbe - lv_rbs ).
      FIND ALL OCCURRENCES OF
        REGEX `<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>`
        IN lv_rblock RESULTS DATA(lt_rg).
      LOOP AT lt_rg INTO DATA(ls_rg).
        DATA lv_rseg TYPE string.
        lv_rseg = substring( val = lv_rblock off = ls_rg-offset len = ls_rg-length ).
        FIND FIRST OCCURRENCE OF
          REGEX `<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>`
          IN lv_rseg SUBMATCHES DATA(lv_lo) DATA(lv_hi) DATA(lv_rdst).
        IF sy-subrc = 0.
          DATA lv_ilo TYPE i.
          DATA lv_ihi TYPE i.
          DATA lv_idst TYPE i.
          lv_ilo  = hex_str_to_int( lv_lo ).
          lv_ihi  = hex_str_to_int( lv_hi ).
          lv_idst = hex_str_to_int( lv_rdst ).
          IF lv_ihi >= lv_ilo AND ( lv_ihi - lv_ilo ) < 65536.
            DATA lv_i TYPE i.
            lv_i = lv_ilo.
            WHILE lv_i <= lv_ihi.
              INSERT VALUE #( code = lv_i
                              char = cp_to_char( lv_idst + ( lv_i - lv_ilo ) ) )
                     INTO TABLE rt_map.
              lv_i = lv_i + 1.
            ENDWHILE.
          ENDIF.
        ENDIF.
      ENDLOOP.
      lv_pos = lv_rbe + strlen( `endbfrange` ).
    ENDWHILE.
  ENDMETHOD.


  METHOD hex_str_to_int.
    rv_int = 0.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_hex ).
    DATA lv_i TYPE i VALUE 0.
    WHILE lv_i < lv_len.
      DATA lv_ch TYPE string.
      lv_ch = substring( val = iv_hex off = lv_i len = 1 ).
      TRANSLATE lv_ch TO UPPER CASE.
      DATA lv_d TYPE i.
      CASE lv_ch.
        WHEN '0'. lv_d = 0.
        WHEN '1'. lv_d = 1.
        WHEN '2'. lv_d = 2.
        WHEN '3'. lv_d = 3.
        WHEN '4'. lv_d = 4.
        WHEN '5'. lv_d = 5.
        WHEN '6'. lv_d = 6.
        WHEN '7'. lv_d = 7.
        WHEN '8'. lv_d = 8.
        WHEN '9'. lv_d = 9.
        WHEN 'A'. lv_d = 10.
        WHEN 'B'. lv_d = 11.
        WHEN 'C'. lv_d = 12.
        WHEN 'D'. lv_d = 13.
        WHEN 'E'. lv_d = 14.
        WHEN 'F'. lv_d = 15.
        WHEN OTHERS. lv_d = 0.
      ENDCASE.
      rv_int = rv_int * 16 + lv_d.
      lv_i = lv_i + 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD oct_str_to_int.
    rv_int = 0.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_oct ).
    DATA lv_i TYPE i VALUE 0.
    WHILE lv_i < lv_len.
      DATA lv_ch TYPE string.
      lv_ch = substring( val = iv_oct off = lv_i len = 1 ).
      DATA lv_d TYPE i.
      lv_d = lv_ch.
      rv_int = rv_int * 8 + lv_d.
      lv_i = lv_i + 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD int_to_hex4.
    DATA lv_v TYPE i.
    lv_v = iv_int.
    DATA lv_out TYPE string.
    lv_out = ``.
    DATA lv_i TYPE i VALUE 0.
    WHILE lv_i < 4.
      DATA lv_nib TYPE i.
      lv_nib = lv_v MOD 16.
      lv_v = lv_v DIV 16.
      DATA lv_ch TYPE string.
      CASE lv_nib.
        WHEN 0.  lv_ch = '0'.
        WHEN 1.  lv_ch = '1'.
        WHEN 2.  lv_ch = '2'.
        WHEN 3.  lv_ch = '3'.
        WHEN 4.  lv_ch = '4'.
        WHEN 5.  lv_ch = '5'.
        WHEN 6.  lv_ch = '6'.
        WHEN 7.  lv_ch = '7'.
        WHEN 8.  lv_ch = '8'.
        WHEN 9.  lv_ch = '9'.
        WHEN 10. lv_ch = 'A'.
        WHEN 11. lv_ch = 'B'.
        WHEN 12. lv_ch = 'C'.
        WHEN 13. lv_ch = 'D'.
        WHEN 14. lv_ch = 'E'.
        WHEN 15. lv_ch = 'F'.
      ENDCASE.
      CONCATENATE lv_ch lv_out INTO lv_out.
      lv_i = lv_i + 1.
    ENDWHILE.
    rv_hex = lv_out.
  ENDMETHOD.


  METHOD cp_to_char.
    " Unicode BMP code point -> string char (via UCCP). Non-BMP -> ''.
    IF iv_cp >= 0 AND iv_cp <= 65535.
      DATA lv_hex TYPE c LENGTH 4.
      lv_hex = int_to_hex4( iv_cp ).
      TRY.
          rv_char = cl_abap_conv_in_ce=>uccp( uccp = lv_hex ).
        CATCH cx_root.
          rv_char = ``.
      ENDTRY.
    ELSE.
      rv_char = ``.
    ENDIF.
  ENDMETHOD.


  METHOD char_cp.
    " Code point of a single latin-1 char (0..255) via its byte value.
    rv_cp = 0.
    IF strlen( iv_char ) = 0.
      RETURN.
    ENDIF.
    DATA lv_one TYPE string.
    lv_one = substring( val = iv_char off = 0 len = 1 ).
    DATA lv_x TYPE xstring.
    TRY.
        lv_x = latin1_to_bytes( lv_one ).
        IF xstrlen( lv_x ) >= 1.
          DATA lv_b TYPE x LENGTH 1.
          lv_b = lv_x(1).
          rv_cp = lv_b.
        ENDIF.
      CATCH cx_root.
        rv_cp = 0.
    ENDTRY.
  ENDMETHOD.


  METHOD utf16be_hex_to_str.
    " bfchar dst = UTF-16BE hex; decode each 4-hex group to a BMP char.
    CLEAR rv_str.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_hex ).
    DATA lv_pos TYPE i VALUE 0.
    WHILE lv_pos + 4 <= lv_len.
      DATA lv_grp TYPE string.
      lv_grp = substring( val = iv_hex off = lv_pos len = 4 ).
      rv_str = rv_str && cp_to_char( hex_str_to_int( lv_grp ) ).
      lv_pos = lv_pos + 4.
    ENDWHILE.
    IF lv_pos < lv_len.
      DATA lv_tail TYPE string.
      lv_tail = substring( val = iv_hex off = lv_pos len = lv_len - lv_pos ).
      rv_str = rv_str && cp_to_char( hex_str_to_int( lv_tail ) ).
    ENDIF.
  ENDMETHOD.


  METHOD hex_to_string.
    " hex-string body (whitespace allowed) -> latin-1 byte-run.
    CLEAR rv_str.
    DATA lv_clean TYPE string.
    lv_clean = iv_hex.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_clean WITH ``.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1) IN lv_clean WITH ``.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_clean WITH ``.
    REPLACE ALL OCCURRENCES OF ` ` IN lv_clean WITH ``.
    DATA lv_len TYPE i.
    lv_len = strlen( lv_clean ).
    IF lv_len MOD 2 = 1.
      CONCATENATE lv_clean `0` INTO lv_clean.
      lv_len = lv_len + 1.
    ENDIF.
    DATA lv_pos TYPE i VALUE 0.
    WHILE lv_pos + 2 <= lv_len.
      DATA lv_pair TYPE string.
      lv_pair = substring( val = lv_clean off = lv_pos len = 2 ).
      rv_str = rv_str && cp_to_char( hex_str_to_int( lv_pair ) ).
      lv_pos = lv_pos + 2.
    ENDWHILE.
  ENDMETHOD.


  METHOD decode_literal.
    CLEAR rv_str.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_body ).
    DATA lv_i TYPE i VALUE 0.
    WHILE lv_i < lv_len.
      DATA lv_ch TYPE string.
      lv_ch = substring( val = iv_body off = lv_i len = 1 ).
      IF lv_ch = `\`.
        lv_i = lv_i + 1.
        IF lv_i >= lv_len.
          EXIT.
        ENDIF.
        DATA lv_e TYPE string.
        lv_e = substring( val = iv_body off = lv_i len = 1 ).
        CASE lv_e.
          WHEN `n`.
            CONCATENATE rv_str cl_abap_char_utilities=>newline INTO rv_str RESPECTING BLANKS.
            lv_i = lv_i + 1.
          WHEN `r`.
            CONCATENATE rv_str cl_abap_char_utilities=>cr_lf(1) INTO rv_str RESPECTING BLANKS.
            lv_i = lv_i + 1.
          WHEN `t`.
            CONCATENATE rv_str cl_abap_char_utilities=>horizontal_tab INTO rv_str RESPECTING BLANKS.
            lv_i = lv_i + 1.
          WHEN `b`.
            lv_i = lv_i + 1.
          WHEN `f`.
            lv_i = lv_i + 1.
          WHEN `(`.
            CONCATENATE rv_str `(` INTO rv_str RESPECTING BLANKS.
            lv_i = lv_i + 1.
          WHEN `)`.
            CONCATENATE rv_str `)` INTO rv_str RESPECTING BLANKS.
            lv_i = lv_i + 1.
          WHEN `\`.
            CONCATENATE rv_str `\` INTO rv_str RESPECTING BLANKS.
            lv_i = lv_i + 1.
          WHEN cl_abap_char_utilities=>newline.
            lv_i = lv_i + 1.
          WHEN cl_abap_char_utilities=>cr_lf(1).
            lv_i = lv_i + 1.
            IF lv_i < lv_len
               AND substring( val = iv_body off = lv_i len = 1 ) = cl_abap_char_utilities=>newline.
              lv_i = lv_i + 1.
            ENDIF.
          WHEN OTHERS.
            IF lv_e CA `01234567`.
              DATA lv_oct TYPE string.
              lv_oct = ``.
              DATA lv_cnt TYPE i VALUE 0.
              WHILE lv_cnt < 3 AND lv_i < lv_len.
                DATA lv_od TYPE string.
                lv_od = substring( val = iv_body off = lv_i len = 1 ).
                IF lv_od CA `01234567`.
                  CONCATENATE lv_oct lv_od INTO lv_oct.
                  lv_i = lv_i + 1.
                  lv_cnt = lv_cnt + 1.
                ELSE.
                  EXIT.
                ENDIF.
              ENDWHILE.
              rv_str = rv_str && cp_to_char( oct_str_to_int( lv_oct ) ).
            ELSE.
              CONCATENATE rv_str lv_e INTO rv_str RESPECTING BLANKS.
              lv_i = lv_i + 1.
            ENDIF.
        ENDCASE.
      ELSE.
        CONCATENATE rv_str lv_ch INTO rv_str RESPECTING BLANKS.
        lv_i = lv_i + 1.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.


  METHOD apply_cmap.
    " Map a byte-run through the CMap treating codes as 2-byte big-endian CIDs.
    CLEAR rv_text.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_bytes ).
    DATA lv_i TYPE i VALUE 0.
    WHILE lv_i + 2 <= lv_len.
      DATA lv_hi TYPE i.
      DATA lv_lo TYPE i.
      lv_hi = char_cp( substring( val = iv_bytes off = lv_i len = 1 ) ).
      lv_lo = char_cp( substring( val = iv_bytes off = lv_i + 1 len = 1 ) ).
      DATA lv_code TYPE i.
      lv_code = lv_hi * 256 + lv_lo.
      READ TABLE it_map INTO DATA(ls_m) WITH KEY code = lv_code.
      IF sy-subrc = 0.
        CONCATENATE rv_text ls_m-char INTO rv_text RESPECTING BLANKS.
      ENDIF.
      lv_i = lv_i + 2.
    ENDWHILE.
  ENDMETHOD.


  METHOD emit_string.
    IF iv_have_cmap = abap_true.
      cv_block = cv_block && apply_cmap( iv_bytes = iv_dec it_map = it_map ).
    ELSE.
      cv_block = cv_block && iv_dec.
    ENDIF.
  ENDMETHOD.


  METHOD append_block.
    IF cv_block IS INITIAL.
      RETURN.
    ENDIF.
    IF cv_out IS NOT INITIAL.
      CONCATENATE cv_out cl_abap_char_utilities=>newline cv_block INTO cv_out RESPECTING BLANKS.
    ELSE.
      cv_out = cv_block.
    ENDIF.
    CLEAR cv_block.
  ENDMETHOD.


  METHOD matches_op.
    " True when the 2-char operator iv_op is a standalone token at iv_pos.
    rv_yes = abap_false.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_buf ).
    IF iv_pos + 2 > lv_len.
      RETURN.
    ENDIF.
    IF substring( val = iv_buf off = iv_pos len = 2 ) <> iv_op.
      RETURN.
    ENDIF.
    IF iv_pos > 0.
      DATA lv_prev TYPE string.
      lv_prev = substring( val = iv_buf off = iv_pos - 1 len = 1 ).
      IF lv_prev CA `abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ`.
        RETURN.
      ENDIF.
    ENDIF.
    IF iv_pos + 2 = lv_len.
      rv_yes = abap_true.
      RETURN.
    ENDIF.
    DATA lv_nx TYPE string.
    lv_nx = substring( val = iv_buf off = iv_pos + 2 len = 1 ).
    IF lv_nx CA `abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789`.
      RETURN.
    ENDIF.
    rv_yes = abap_true.
  ENDMETHOD.


  METHOD find_array_end.
    " Offset of the ']' closing the array, respecting ( ) literals. -1 if none.
    rv_end = -1.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_buf ).
    DATA lv_i TYPE i.
    lv_i = iv_start.
    WHILE lv_i < lv_len.
      DATA lv_ch TYPE string.
      lv_ch = substring( val = iv_buf off = lv_i len = 1 ).
      IF lv_ch = `(`.
        DATA lv_depth TYPE i.
        lv_depth = 1.          " assignment, not DATA..VALUE: a declaration
                               " initializes once per call, not per iteration
        lv_i = lv_i + 1.
        WHILE lv_i < lv_len AND lv_depth > 0.
          DATA lv_cj TYPE string.
          lv_cj = substring( val = iv_buf off = lv_i len = 1 ).
          IF lv_cj = `\`.
            lv_i = lv_i + 2.
            CONTINUE.
          ELSEIF lv_cj = `(`.
            lv_depth = lv_depth + 1.
          ELSEIF lv_cj = `)`.
            lv_depth = lv_depth - 1.
          ENDIF.
          lv_i = lv_i + 1.
        ENDWHILE.
        CONTINUE.
      ELSEIF lv_ch = `]`.
        rv_end = lv_i.
        RETURN.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD process_tj_array.
    " Parse a TJ array body: strings + numeric kerns. Emit strings; kern < -150 -> space.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_arr ).
    DATA lv_i TYPE i VALUE 0.
    WHILE lv_i < lv_len.
      DATA lv_ch TYPE string.
      lv_ch = substring( val = iv_arr off = lv_i len = 1 ).
      IF lv_ch = `(`.
        DATA lv_depth TYPE i.
        lv_depth = 1.          " assignment, not DATA..VALUE: a declaration
                               " initializes once per call, not per iteration
        DATA lv_j TYPE i.
        lv_j = lv_i + 1.
        DATA lv_start TYPE i.
        lv_start = lv_j.
        WHILE lv_j < lv_len AND lv_depth > 0.
          DATA lv_cj TYPE string.
          lv_cj = substring( val = iv_arr off = lv_j len = 1 ).
          IF lv_cj = `\`.
            lv_j = lv_j + 2.
            CONTINUE.
          ELSEIF lv_cj = `(`.
            lv_depth = lv_depth + 1.
          ELSEIF lv_cj = `)`.
            lv_depth = lv_depth - 1.
            IF lv_depth = 0.
              EXIT.
            ENDIF.
          ENDIF.
          lv_j = lv_j + 1.
        ENDWHILE.
        DATA lv_body TYPE string.
        IF lv_j > lv_start.
          lv_body = substring( val = iv_arr off = lv_start len = lv_j - lv_start ).
        ELSE.
          lv_body = ``.
        ENDIF.
        emit_string( EXPORTING iv_dec = decode_literal( lv_body )
                               iv_have_cmap = iv_have_cmap it_map = it_map
                     CHANGING  cv_block = cv_block ).
        lv_i = lv_j + 1.
        CONTINUE.
      ELSEIF lv_ch = `<`.
        DATA lv_he TYPE i.
        FIND FIRST OCCURRENCE OF `>` IN SECTION OFFSET lv_i + 1 OF iv_arr
          MATCH OFFSET lv_he.
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.
        DATA lv_hb TYPE string.
        lv_hb = substring( val = iv_arr off = lv_i + 1 len = lv_he - ( lv_i + 1 ) ).
        emit_string( EXPORTING iv_dec = hex_to_string( lv_hb )
                               iv_have_cmap = iv_have_cmap it_map = it_map
                     CHANGING  cv_block = cv_block ).
        lv_i = lv_he + 1.
        CONTINUE.
      ELSEIF lv_ch CA `-+0123456789.`.
        DATA lv_numtxt TYPE string.
        lv_numtxt = ``.
        WHILE lv_i < lv_len.
          DATA lv_nc TYPE string.
          lv_nc = substring( val = iv_arr off = lv_i len = 1 ).
          IF lv_nc CA `-+0123456789.eE`.
            CONCATENATE lv_numtxt lv_nc INTO lv_numtxt.
            lv_i = lv_i + 1.
          ELSE.
            EXIT.
          ENDIF.
        ENDWHILE.
        TRY.
            DATA lv_num TYPE f.
            lv_num = lv_numtxt.
            IF lv_num < -150.
              CONCATENATE cv_block ` ` INTO cv_block RESPECTING BLANKS.
            ENDIF.
          CATCH cx_root.
        ENDTRY.
        CONTINUE.
      ELSE.
        lv_i = lv_i + 1.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.


  METHOD select_font.
    " On Tf, decide whether the active font has a ToUnicode CMap. Flat-scan model:
    " if ANY CMap was collected, treat the current font as CID+ToUnicode and use the
    " first map; otherwise single-byte latin-1. (Full per-font xref wiring is out of
    " scope for a flat byte scan; robustness beats completeness.)
    CLEAR: ev_have_cmap, et_map.
    IF lines( it_cmaps ) > 0.
      ev_have_cmap = abap_true.
      et_map = it_cmaps[ 1 ]-map.
    ENDIF.
  ENDMETHOD.


  METHOD tokenize_content.
    " Walk the buffer, decode ( ) literals and < > hex strings, honour BT/ET/Tf/Td/
    " TD/T*/TJ. A BT flushes the prior block (newline separation). CID-without-CMap is
    " flagged at file level in extract_text, so no warning is emitted here.
    DATA lv_len TYPE i.
    lv_len = strlen( iv_buf ).
    DATA lv_i TYPE i VALUE 0.

    DATA lv_have_cmap TYPE abap_bool VALUE abap_false.
    DATA lt_map       TYPE tt_cmap.
    DATA lv_block     TYPE string.

    WHILE lv_i < lv_len.
      DATA lv_ch TYPE string.
      lv_ch = substring( val = iv_buf off = lv_i len = 1 ).

      " literal string ( ... )
      IF lv_ch = `(`.
        DATA lv_depth TYPE i.
        lv_depth = 1.          " assignment, not DATA..VALUE: a declaration
                               " initializes once per call, not per iteration
        DATA lv_j TYPE i.
        lv_j = lv_i + 1.
        DATA lv_start TYPE i.
        lv_start = lv_j.
        WHILE lv_j < lv_len AND lv_depth > 0.
          DATA lv_cj TYPE string.
          lv_cj = substring( val = iv_buf off = lv_j len = 1 ).
          IF lv_cj = `\`.
            lv_j = lv_j + 2.
            CONTINUE.
          ELSEIF lv_cj = `(`.
            lv_depth = lv_depth + 1.
          ELSEIF lv_cj = `)`.
            lv_depth = lv_depth - 1.
            IF lv_depth = 0.
              EXIT.
            ENDIF.
          ENDIF.
          lv_j = lv_j + 1.
        ENDWHILE.
        DATA lv_litbody TYPE string.
        IF lv_j > lv_start AND lv_j <= lv_len.
          lv_litbody = substring( val = iv_buf off = lv_start len = lv_j - lv_start ).
        ELSE.
          lv_litbody = ``.
        ENDIF.
        emit_string( EXPORTING iv_dec = decode_literal( lv_litbody )
                               iv_have_cmap = lv_have_cmap it_map = lt_map
                     CHANGING  cv_block = lv_block ).
        lv_i = lv_j + 1.
        CONTINUE.
      ENDIF.

      " hex string < ... > (but skip << dict opener)
      IF lv_ch = `<`.
        IF lv_i + 1 < lv_len
           AND substring( val = iv_buf off = lv_i + 1 len = 1 ) = `<`.
          lv_i = lv_i + 2.
          CONTINUE.
        ENDIF.
        DATA lv_he TYPE i.
        FIND FIRST OCCURRENCE OF `>` IN SECTION OFFSET lv_i + 1 OF iv_buf
          MATCH OFFSET lv_he.
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.
        DATA lv_hexbody TYPE string.
        lv_hexbody = substring( val = iv_buf off = lv_i + 1 len = lv_he - ( lv_i + 1 ) ).
        emit_string( EXPORTING iv_dec = hex_to_string( lv_hexbody )
                               iv_have_cmap = lv_have_cmap it_map = lt_map
                     CHANGING  cv_block = lv_block ).
        lv_i = lv_he + 1.
        CONTINUE.
      ENDIF.

      " TJ array [ ... ]
      IF lv_ch = `[`.
        DATA lv_ae TYPE i.
        lv_ae = find_array_end( iv_buf = iv_buf iv_start = lv_i + 1 ).
        IF lv_ae < 0.
          lv_i = lv_i + 1.
          CONTINUE.
        ENDIF.
        DATA lv_arrbody TYPE string.
        lv_arrbody = substring( val = iv_buf off = lv_i + 1 len = lv_ae - ( lv_i + 1 ) ).
        process_tj_array( EXPORTING iv_arr = lv_arrbody
                                    iv_have_cmap = lv_have_cmap it_map = lt_map
                          CHANGING  cv_block = lv_block ).
        lv_i = lv_ae + 1.
        CONTINUE.
      ENDIF.

      " operators
      IF matches_op( iv_buf = iv_buf iv_pos = lv_i iv_op = `BT` ).
        append_block( CHANGING cv_out = cv_out cv_block = lv_block ).
        lv_i = lv_i + 2.
        CONTINUE.
      ENDIF.
      IF matches_op( iv_buf = iv_buf iv_pos = lv_i iv_op = `ET` ).
        append_block( CHANGING cv_out = cv_out cv_block = lv_block ).
        lv_i = lv_i + 2.
        CONTINUE.
      ENDIF.
      IF matches_op( iv_buf = iv_buf iv_pos = lv_i iv_op = `T*` ).
        CONCATENATE lv_block cl_abap_char_utilities=>newline INTO lv_block RESPECTING BLANKS.
        lv_i = lv_i + 2.
        CONTINUE.
      ENDIF.
      IF matches_op( iv_buf = iv_buf iv_pos = lv_i iv_op = `Td` )
         OR matches_op( iv_buf = iv_buf iv_pos = lv_i iv_op = `TD` ).
        CONCATENATE lv_block cl_abap_char_utilities=>newline INTO lv_block RESPECTING BLANKS.
        lv_i = lv_i + 2.
        CONTINUE.
      ENDIF.
      IF matches_op( iv_buf = iv_buf iv_pos = lv_i iv_op = `Tf` ).
        select_font( EXPORTING iv_buf = iv_buf iv_pos = lv_i it_cmaps = it_cmaps
                     IMPORTING ev_have_cmap = lv_have_cmap et_map = lt_map ).
        lv_i = lv_i + 2.
        CONTINUE.
      ENDIF.

      lv_i = lv_i + 1.
    ENDWHILE.

    IF lv_block IS NOT INITIAL.
      append_block( CHANGING cv_out = cv_out cv_block = lv_block ).
    ENDIF.
  ENDMETHOD.


  " ---- text-layer plausibility (port of src/mdmdoc/extract/plausibility.py) --
  " Parity with the Python reference is asserted case by case by
  " ZCL_MDMDOC_PLAUS_GOLDEN (generated). Arithmetic is integer per-mille: the
  " package has no floating-point API and exact float parity across two languages
  " is not worth chasing — the golden test allows +/- 5 per mille.

  METHOD plaus_count_any.
    DATA lv_off TYPE i.
    DATA(lv_len) = strlen( iv_s ).
    WHILE lv_off < lv_len.
      DATA(lv_ch) = iv_s+lv_off(1).
      IF lv_ch CA iv_set.
        rv_n = rv_n + 1.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD plaus_tokens.
    " Python's str.split(): split on ANY run of whitespace. SPLIT ... AT space only
    " cuts on the blank, so flatten CR/LF/tab first (same trick as zcl_mdmdoc_regex).
    DATA(lv_flat) = iv_text.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_flat WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_flat WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_flat WITH ` `.
    SPLIT lv_flat AT space INTO TABLE rt_toks.
    DELETE rt_toks WHERE table_line IS INITIAL.
  ENDMETHOD.

  METHOD plaus_strip_edges.
    " Python str.strip(_EDGE_PUNCT): drop leading and trailing edge punctuation.
    rv_core = iv_tok.
    WHILE strlen( rv_core ) > 0.
      DATA(lv_first) = rv_core(1).
      IF lv_first CA c_edge.
        rv_core = rv_core+1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    WHILE strlen( rv_core ) > 0.
      DATA(lv_last_off) = strlen( rv_core ) - 1.
      DATA(lv_last) = rv_core+lv_last_off(1).
      IF lv_last CA c_edge.
        rv_core = rv_core(lv_last_off).
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.

  METHOD plaus_other_script.
    " A character above U+007F that is not one of our symbols = a letter of some
    " other script (CJK, Cyrillic, Arabic, accented Latin). This is what keeps the
    " gate free of unicode category tables, which 7.50 does not have.
    " No code points: cl_abap_conv_in_ce=>uccpi is not available in the local
    " transpiler harness, and it is not needed — "above U+007F" is exactly "outside
    " printable ASCII, and not whitespace".
    DATA lv_off TYPE i.
    DATA(lv_ws) = cl_abap_char_utilities=>newline && cl_abap_char_utilities=>cr_lf
               && cl_abap_char_utilities=>horizontal_tab.
    DATA(lv_len) = strlen( iv_s ).
    WHILE lv_off < lv_len.
      DATA(lv_ch) = iv_s+lv_off(1).
      IF lv_ch NA c_ascii_a AND lv_ch NA c_ascii_b AND lv_ch NA lv_ws
         AND lv_ch NA c_symbols_a AND lv_ch NA c_symbols_b.
        rv_yes = abap_true.
        RETURN.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD plaus_is_ascii_letters.
    " All characters are ASCII letters (apostrophe and hyphen allowed as joiners)
    " and at least one is a letter.
    DATA lv_off TYPE i.
    DATA lv_has TYPE abap_bool.
    DATA(lv_len) = strlen( iv_s ).
    WHILE lv_off < lv_len.
      DATA(lv_ch) = iv_s+lv_off(1).
      IF lv_ch CA c_upper OR lv_ch CA c_lower.
        lv_has = abap_true.
      ELSEIF lv_ch = `'` OR lv_ch = `-`.
        " joiner: allowed, but does not make the token a word on its own
      ELSE.
        RETURN.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
    rv_yes = lv_has.
  ENDMETHOD.

  METHOD plaus_latin_word_ok.
    " A letters-only Latin token: needs a vowel, unless it is a short acronym;
    " a mid-word case flip (aB) is the signature of OCR junk.
    DATA lv_off TYPE i.
    DATA(lv_letters) = plaus_count_any( iv_s = iv_tok iv_set = c_upper ) +
                       plaus_count_any( iv_s = iv_tok iv_set = c_lower ).
    IF lv_letters < 3.
      rv_yes = abap_true.
      RETURN.
    ENDIF.
    IF plaus_word_improbable( iv_tok ) = abap_true.
      RETURN.
    ENDIF.
    DATA(lv_upper_n) = plaus_count_any( iv_s = iv_tok iv_set = c_upper ).
    IF lv_upper_n = lv_letters AND lv_letters <= 6.
      rv_yes = abap_true.               " HSBC, BBVA, IBAN, SWIFT
      RETURN.
    ENDIF.
    DATA(lv_low) = to_lower( iv_tok ).
    IF plaus_count_any( iv_s = lv_low iv_set = c_vowels ) >= 1.
      rv_yes = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD plaus_word_improbable.
    " Port of ocr._word_improbable: a mid-word case flip, or an implausibly long
    " vowel-poor token. All-caps short tokens are acronyms, never improbable.
    DATA lv_off TYPE i.
    DATA(lv_n) = plaus_count_any( iv_s = iv_word iv_set = c_upper ) +
                 plaus_count_any( iv_s = iv_word iv_set = c_lower ).
    IF lv_n < 3.
      RETURN.
    ENDIF.
    DATA(lv_upper_n) = plaus_count_any( iv_s = iv_word iv_set = c_upper ).
    IF lv_upper_n = lv_n AND lv_n <= 6.
      RETURN.
    ENDIF.
    " mid-word case flip: a lowercase letter immediately followed by an uppercase one
    DATA(lv_len) = strlen( iv_word ).
    WHILE lv_off < lv_len - 1.
      DATA(lv_a) = iv_word+lv_off(1).
      DATA(lv_b) = iv_word+lv_off(1).
      DATA(lv_next_off) = lv_off + 1.
      lv_b = iv_word+lv_next_off(1).
      IF lv_a CA c_lower AND lv_b CA c_upper.
        rv_yes = abap_true.
        RETURN.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
    IF lv_n >= 13.
      DATA(lv_low) = to_lower( iv_word ).
      DATA(lv_v) = plaus_count_any( iv_s = lv_low iv_set = c_vowels ).
      " vowel ratio below 0.42 -> compare 100*v < 42*n to stay in integers
      IF 100 * lv_v < 42 * lv_n.
        rv_yes = abap_true.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD plaus_num_token.
    " Python _NUM_TOKEN, two alternatives, expressed as character walks so that no
    " regex dialect difference can creep in between the two implementations:
    "   a) [+-]? digit ( [digit.,-/:'] * digit )? %?
    "   b) \(? digit{2,4} \)? [digit-.]{3,}
    DATA lv_off TYPE i.
    DATA(lv_len) = strlen( iv_s ).
    IF lv_len = 0.
      RETURN.
    ENDIF.
    " --- alternative (a)
    DATA(lv_i) = 0.
    DATA(lv_ok) = abap_true.
    DATA(lv_ch) = iv_s(1).
    IF lv_ch = `+` OR lv_ch = `-`.
      lv_i = 1.
    ENDIF.
    IF lv_i >= lv_len.
      lv_ok = abap_false.
    ELSE.
      lv_ch = iv_s+lv_i(1).
      IF lv_ch NA c_digits.
        lv_ok = abap_false.
      ENDIF.
    ENDIF.
    IF lv_ok = abap_true.
      DATA(lv_end) = lv_len - 1.
      DATA(lv_tail) = iv_s+lv_end(1).
      IF lv_tail = `%`.
        lv_end = lv_end - 1.
        IF lv_end < lv_i.
          lv_ok = abap_false.
        ELSE.
          lv_tail = iv_s+lv_end(1).
        ENDIF.
      ENDIF.
      IF lv_ok = abap_true AND lv_tail NA c_digits.
        lv_ok = abap_false.
      ENDIF.
    ENDIF.
    IF lv_ok = abap_true.
      lv_off = lv_i.
      WHILE lv_off <= lv_end.
        lv_ch = iv_s+lv_off(1).
        IF lv_ch NA c_digits AND lv_ch <> `.` AND lv_ch <> `,` AND lv_ch <> `-`
           AND lv_ch <> `/` AND lv_ch <> `:` AND lv_ch <> `'` AND lv_ch <> `′` AND lv_ch <> `″`.
          lv_ok = abap_false.
          EXIT.
        ENDIF.
        lv_off = lv_off + 1.
      ENDWHILE.
    ENDIF.
    IF lv_ok = abap_true.
      rv_yes = abap_true.
      RETURN.
    ENDIF.
    " --- alternative (b)
    lv_i = 0.
    IF iv_s(1) = `(`.
      lv_i = 1.
    ENDIF.
    DATA(lv_digits) = 0.
    WHILE lv_i + lv_digits < lv_len.
      DATA(lv_at) = lv_i + lv_digits.
      lv_ch = iv_s+lv_at(1).
      IF lv_ch CA c_digits.
        lv_digits = lv_digits + 1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    IF lv_digits < 2 OR lv_digits > 4.
      RETURN.
    ENDIF.
    lv_off = lv_i + lv_digits.
    IF lv_off < lv_len.
      lv_ch = iv_s+lv_off(1).
      IF lv_ch = `)`.
        lv_off = lv_off + 1.
      ENDIF.
    ENDIF.
    DATA(lv_rest) = lv_len - lv_off.
    IF lv_rest < 3.
      RETURN.
    ENDIF.
    WHILE lv_off < lv_len.
      lv_ch = iv_s+lv_off(1).
      IF lv_ch NA c_digits AND lv_ch <> `-` AND lv_ch <> `.`.
        RETURN.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
    rv_yes = abap_true.
  ENDMETHOD.

  METHOD plaus_mixed_ok.
    " Python _MIXED_OK: W9, 3a, C24, A4, 1st, 12th — a short letter/digit mix.
    DATA lv_off TYPE i.
    DATA(lv_len) = strlen( iv_s ).
    IF lv_len = 0.
      RETURN.
    ENDIF.
    " shape 1: 1-3 letters, 1-6 digits, optional trailing letter
    DATA(lv_i) = 0.
    DATA(lv_a) = 0.
    WHILE lv_i < lv_len.
      DATA(lv_ch) = iv_s+lv_i(1).
      IF ( lv_ch CA c_upper OR lv_ch CA c_lower ) AND lv_a < 3.
        lv_a = lv_a + 1.
        lv_i = lv_i + 1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    IF lv_a >= 1.
      DATA(lv_d) = 0.
      WHILE lv_i < lv_len.
        lv_ch = iv_s+lv_i(1).
        IF lv_ch CA c_digits AND lv_d < 6.
          lv_d = lv_d + 1.
          lv_i = lv_i + 1.
        ELSE.
          EXIT.
        ENDIF.
      ENDWHILE.
      IF lv_d >= 1.
        IF lv_i = lv_len.
          rv_yes = abap_true.
          RETURN.
        ENDIF.
        IF lv_i = lv_len - 1.
          lv_ch = iv_s+lv_i(1).
          IF lv_ch CA c_upper OR lv_ch CA c_lower.
            rv_yes = abap_true.
            RETURN.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
    " shape 2: 1-6 digits followed by st/nd/rd/th/er/re, a masculine/feminine
    " ordinal sign, or one letter
    lv_i = 0.
    lv_d = 0.
    WHILE lv_i < lv_len.
      lv_ch = iv_s+lv_i(1).
      IF lv_ch CA c_digits AND lv_d < 6.
        lv_d = lv_d + 1.
        lv_i = lv_i + 1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    IF lv_d < 1 OR lv_i = lv_len.
      RETURN.
    ENDIF.
    DATA(lv_suffix) = iv_s+lv_i.
    IF lv_suffix = `st` OR lv_suffix = `nd` OR lv_suffix = `rd` OR lv_suffix = `th`
       OR lv_suffix = `er` OR lv_suffix = `re` OR lv_suffix = `ª` OR lv_suffix = `º`.
      rv_yes = abap_true.
      RETURN.
    ENDIF.
    IF strlen( lv_suffix ) = 1 AND ( lv_suffix CA c_upper OR lv_suffix CA c_lower ).
      rv_yes = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD plaus_upper_code.
    " Python _UPPER_CODE plus the >=2 digits condition: IBAN chunks, SWIFT codes,
    " invoice ids — uppercase and digits with . / - separators.
    DATA lv_off TYPE i.
    DATA(lv_len) = strlen( iv_s ).
    IF lv_len < 3.
      RETURN.
    ENDIF.
    DATA(lv_first) = iv_s(1).
    IF lv_first NA c_upper AND lv_first NA c_digits.
      RETURN.
    ENDIF.
    lv_off = 1.
    WHILE lv_off < lv_len.
      DATA(lv_ch) = iv_s+lv_off(1).
      IF lv_ch NA c_upper AND lv_ch NA c_digits AND lv_ch <> `.` AND lv_ch <> `/` AND lv_ch <> `-`.
        RETURN.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
    IF plaus_count_any( iv_s = iv_s iv_set = c_digits ) >= 2.
      rv_yes = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD plaus_mail_or_url.
    DATA lv_off TYPE i.
    DATA(lv_len) = strlen( iv_s ).
    IF lv_len = 0.
      RETURN.
    ENDIF.
    IF iv_s CS `@`.
      " exactly one @, non-empty both sides, only word characters and . + -
      DATA(lv_at_n) = plaus_count_any( iv_s = iv_s iv_set = `@` ).
      IF lv_at_n <> 1.
        RETURN.
      ENDIF.
      FIND FIRST OCCURRENCE OF `@` IN iv_s MATCH OFFSET DATA(lv_at).
      IF lv_at = 0 OR lv_at = lv_len - 1.
        RETURN.
      ENDIF.
      WHILE lv_off < lv_len.
        DATA(lv_ch) = iv_s+lv_off(1).
        IF lv_ch NA c_upper AND lv_ch NA c_lower AND lv_ch NA c_digits
           AND lv_ch <> `@` AND lv_ch <> `.` AND lv_ch <> `_` AND lv_ch <> `+` AND lv_ch <> `-`.
          RETURN.
        ENDIF.
        lv_off = lv_off + 1.
      ENDWHILE.
      rv_yes = abap_true.
      RETURN.
    ENDIF.
    DATA(lv_low) = to_lower( iv_s ).
    IF lv_low CP `http://*` OR lv_low CP `https://*` OR lv_low CP `www.*`.
      rv_yes = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD plaus_wellformed.
    DATA(lv_core) = plaus_strip_edges( iv_tok ).
    IF lv_core IS INITIAL.
      rv_yes = abap_true.               " pure punctuation (bullets, dashes, brackets)
      RETURN.
    ENDIF.
    IF plaus_other_script( lv_core ) = abap_true.
      rv_yes = abap_true.               " 第3条, 〒123, ул.5 — letters of another script
      RETURN.
    ENDIF.
    DATA(lv_weird) = plaus_count_any( iv_s = lv_core iv_set = c_weird ).
    IF lv_weird > 0.
      " a symbol is fine as the whole token (currency signs, ©) — never mid-word
      IF strlen( lv_core ) = 1.
        rv_yes = abap_true.
      ENDIF.
      RETURN.
    ENDIF.
    IF plaus_is_ascii_letters( lv_core ) = abap_true.
      rv_yes = plaus_latin_word_ok( lv_core ).
      RETURN.
    ENDIF.
    IF plaus_num_token( lv_core ) = abap_true
       OR plaus_mixed_ok( lv_core ) = abap_true
       OR plaus_mail_or_url( lv_core ) = abap_true
       OR plaus_upper_code( lv_core ) = abap_true.
      rv_yes = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD plaus_short_ok.
    " Two-letter words that are real in the languages this corpus contains.
    " Kept as one literal per line to stay inside the 140-char limit.
    CONSTANTS lc_lat1 TYPE string VALUE `a ab ag al am an as at au be bv by cc ce cf ch cm cn co da de di do`.
    CONSTANTS lc_lat1b TYPE string VALUE `du el en er es et eu`.
    CONSTANTS lc_lat2 TYPE string VALUE `fw gm go he hr i id if il im in is it ja je jp kg kr la le lo lt me ml mm my ne no nr`.
    CONSTANTS lc_lat3 TYPE string VALUE `nv o of ok on or ou ph pm pp re rm rs ru sa se so su te to tr tu tv tx tz uk um un up`.
    CONSTANTS lc_lat4 TYPE string VALUE `us vs we wo y zu`.
    CONSTANTS lc_cyr1 TYPE string VALUE `в во да до же за и из к ко ли мы на не ни но о об он от по с со то ты у я`.
    DATA(lv_probe) = | { iv_s } |.
        " pad both sides so that `a` cannot match inside `ab`
    IF | { lc_lat1 } | CS lv_probe OR | { lc_lat1b } | CS lv_probe OR | { lc_lat2 } | CS lv_probe
       OR | { lc_lat3 } | CS lv_probe OR | { lc_lat4 } | CS lv_probe OR | { lc_cyr1 } | CS lv_probe.
      rv_yes = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD plaus_short_junk.
    " A 1-2 character token that is neither a word, a number, punctuation nor another
    " script. Mojibake is full of them: zt, q=, ;H, LI, 'J.
    DATA(lv_core) = plaus_strip_edges( iv_tok ).
    DATA(lv_len) = strlen( lv_core ).
    IF lv_len = 0 OR lv_len > 2.
      RETURN.
    ENDIF.
    IF plaus_count_any( iv_s = lv_core iv_set = c_digits ) = lv_len.
      RETURN.                            " pure digits
    ENDIF.
    IF plaus_other_script( lv_core ) = abap_true.
      RETURN.
    ENDIF.
    IF lv_len = 1.
      IF lv_core NA c_upper AND lv_core NA c_lower.
        rv_yes = abap_true.              " a single LETTER is fine (initials, list markers)
      ENDIF.
      RETURN.
    ENDIF.
    DATA(lv_low) = to_lower( lv_core ).
    IF plaus_short_ok( lv_low ) = abap_true.
      RETURN.
    ENDIF.
    IF plaus_count_any( iv_s = lv_core iv_set = c_upper ) = lv_len.
      RETURN.                            " two-letter caps = acronym / state code
    ENDIF.
    rv_yes = abap_true.
  ENDMETHOD.

  METHOD plausibility.
    DATA lv_off TYPE i.
    DATA(lt_toks) = plaus_tokens( iv_text ).
    DATA(lv_n) = lines( lt_toks ).
    IF lv_n = 0.
      RETURN.
    ENDIF.

    " --- well-formed share and short-junk share, per mille
    DATA lv_wf_c TYPE i.
    DATA lv_sj_c TYPE i.
    LOOP AT lt_toks INTO DATA(lv_tok).
      IF plaus_wellformed( lv_tok ) = abap_true.
        lv_wf_c = lv_wf_c + 1.
      ENDIF.
      IF plaus_short_junk( lv_tok ) = abap_true.
        lv_sj_c = lv_sj_c + 1.
      ENDIF.
    ENDLOOP.
    DATA(lv_wf_m) = 1000 * lv_wf_c / lv_n.
    DATA(lv_sj_m) = 1000 * lv_sj_c / lv_n.

    " --- improbable share over Latin words of 3+ letters
    DATA lt_words TYPE string_table.
    DATA lv_cur TYPE string.
    DATA(lv_len) = strlen( iv_text ).
    lv_off = 0.
    WHILE lv_off < lv_len.
      DATA(lv_ch) = iv_text+lv_off(1).
      IF lv_ch CA c_upper OR lv_ch CA c_lower.
        lv_cur = lv_cur && lv_ch.
      ELSE.
        IF strlen( lv_cur ) >= 3.
          APPEND lv_cur TO lt_words.
        ENDIF.
        CLEAR lv_cur.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
    IF strlen( lv_cur ) >= 3.
      APPEND lv_cur TO lt_words.
    ENDIF.
    DATA lv_imp_m TYPE i.
    DATA(lv_words) = lines( lt_words ).
    IF lv_words > 0.
      DATA lv_imp_c TYPE i.
      LOOP AT lt_words INTO DATA(lv_word).
        IF plaus_word_improbable( lv_word ) = abap_true.
          lv_imp_c = lv_imp_c + 1.
        ENDIF.
      ENDLOOP.
      lv_imp_m = 1000 * lv_imp_c / lv_words.
    ENDIF.

    " --- symbol density over non-space characters, and the Latin vowel ratio
    DATA lv_nonspace TYPE i.
    DATA lv_sym TYPE i.
    DATA lv_lat TYPE i.
    DATA lv_vow TYPE i.
    lv_off = 0.
    WHILE lv_off < lv_len.
      lv_ch = iv_text+lv_off(1).
      IF lv_ch <> ` ` AND lv_ch <> cl_abap_char_utilities=>newline
         AND lv_ch <> cl_abap_char_utilities=>horizontal_tab.
        lv_nonspace = lv_nonspace + 1.
        IF lv_ch CA c_symbols_a OR lv_ch CA c_symbols_b.
          lv_sym = lv_sym + 1.
        ENDIF.
      ENDIF.
      IF lv_ch CA c_upper OR lv_ch CA c_lower.
        lv_lat = lv_lat + 1.
        DATA(lv_low_ch) = to_lower( lv_ch ).
        IF lv_low_ch CA c_vowels.
          lv_vow = lv_vow + 1.
        ENDIF.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
    IF lv_nonspace = 0.
      lv_nonspace = 1.
    ENDIF.
    DATA(lv_sym_m) = 10000 * lv_sym / lv_nonspace.     " density * 10, per mille
    IF lv_sym_m > 1000.
      lv_sym_m = 1000.
    ENDIF.
    DATA(lv_vok_m) = 1000.
    IF lv_lat >= 20.
      DATA(lv_vr_m) = 1000 * lv_vow / lv_lat.
      IF lv_vr_m < 280 OR lv_vr_m > 620.
        DATA(lv_delta) = lv_vr_m - 450.
        IF lv_delta < 0.
          lv_delta = -1 * lv_delta.
        ENDIF.
        lv_vok_m = 1000 - 4 * lv_delta.
        IF lv_vok_m < 0.
          lv_vok_m = 0.
        ENDIF.
      ENDIF.
    ENDIF.
    DATA(lv_sj_term) = 4 * lv_sj_m.
    IF lv_sj_term > 1000.
      lv_sj_term = 1000.
    ENDIF.

    " --- the same five weights as the Python reference
    rv_score = ( 400 * lv_wf_m
               + 200 * ( 1000 - lv_imp_m )
               + 150 * ( 1000 - lv_sym_m )
               + 100 * lv_vok_m
               + 150 * ( 1000 - lv_sj_term ) ) / 1000.
    IF rv_score > 1000.
      rv_score = 1000.
    ELSEIF rv_score < 0.
      rv_score = 0.
    ENDIF.
  ENDMETHOD.

  METHOD layer_usable.
    CLEAR: ev_usable, ev_reason, ev_score.
    DATA(lv_trimmed) = condense( val = iv_text ).
    ev_score = plausibility( iv_text ).
    IF strlen( lv_trimmed ) < iv_min_chars.
      ev_reason = |text layer has { strlen( lv_trimmed ) } chars|.
      RETURN.
    ENDIF.
    IF ev_score < c_trust_layer.
      ev_reason = |text layer implausible: score { ev_score } of 1000|.
      RETURN.
    ENDIF.
    ev_usable = abap_true.
    ev_reason = |text layer plausible: score { ev_score } of 1000|.
  ENDMETHOD.

ENDCLASS.
