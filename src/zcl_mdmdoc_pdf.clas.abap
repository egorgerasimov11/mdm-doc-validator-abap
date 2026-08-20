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

ENDCLASS.
