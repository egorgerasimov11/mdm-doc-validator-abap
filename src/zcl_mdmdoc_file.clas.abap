" File I/O + container unwrapping for the mdmdoc ABAP clone.
" Ports the read/hash/classify/unwrap/save behaviour that lives in
" src/mdmdoc/pipeline.py (_resolve_container / _extract_eml_attachments) and
" config.py (EDITABLE/EMAIL/IMAGE ext sets). Container selection mirrors the
" Python preference: pdf outranks image outranks eml; macOS junk is skipped;
" one recursion into an inner eml.
CLASS zcl_mdmdoc_file DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_doc,
             path    TYPE string,
             name    TYPE string,   " basename
             ext     TYPE string,   " lowercase, no dot
             content TYPE xstring,
             sha16   TYPE string,   " first 16 hex chars of SHA-256, lowercase
             source  TYPE string,   " 'pc' | 'server'
           END OF ty_doc.

    CLASS-METHODS read
      IMPORTING iv_path        TYPE string
                iv_from_server TYPE abap_bool
      EXPORTING es_doc         TYPE ty_doc
                ev_error       TYPE string.

    CLASS-METHODS classify_ext
      IMPORTING iv_ext         TYPE string
      RETURNING VALUE(rv_kind) TYPE string.
    " 'pdf'|'image'|'email'|'zip'|'editable'|'msg'|'other'

    CLASS-METHODS unwrap
      EXPORTING et_notes TYPE string_table
                ev_error TYPE string
      CHANGING  cs_doc   TYPE ty_doc.

    CLASS-METHODS save_text
      IMPORTING iv_path      TYPE string
                iv_text      TYPE string
                iv_to_server TYPE abap_bool
      EXPORTING ev_error     TYPE string.

    " Exposed for unit tests (pure, no GUI/dataset) --------------------------
    CLASS-METHODS sha16
      IMPORTING iv_data       TYPE xstring
      RETURNING VALUE(rv_hex) TYPE string.

    CLASS-METHODS basename
      IMPORTING iv_path        TYPE string
      RETURNING VALUE(rv_name) TYPE string.

    CLASS-METHODS ext_of
      IMPORTING iv_name       TYPE string
      RETURNING VALUE(rv_ext) TYPE string.

  PRIVATE SECTION.
    " candidate scoring for container selection (higher = better)
    CONSTANTS: BEGIN OF c_score,
                 pdf   TYPE i VALUE 4,
                 image TYPE i VALUE 2,
                 eml   TYPE i VALUE 1,
                 none  TYPE i VALUE 0,
               END OF c_score.

    TYPES: BEGIN OF ty_cand,
             name    TYPE string,
             ext     TYPE string,
             content TYPE xstring,
             score   TYPE i,
           END OF ty_cand,
           tt_cand TYPE STANDARD TABLE OF ty_cand WITH EMPTY KEY.

    CLASS-METHODS read_pc
      IMPORTING iv_path  TYPE string
      EXPORTING ev_data  TYPE xstring
                ev_error TYPE string.

    CLASS-METHODS read_server
      IMPORTING iv_path  TYPE string
      EXPORTING ev_data  TYPE xstring
                ev_error TYPE string.

    CLASS-METHODS candidate_score
      IMPORTING iv_ext          TYPE string
      RETURNING VALUE(rv_score) TYPE i.

    CLASS-METHODS pick_best
      IMPORTING it_cand        TYPE tt_cand
      RETURNING VALUE(rs_best) TYPE ty_cand.

    CLASS-METHODS unwrap_zip
      EXPORTING et_notes TYPE string_table
                ev_error TYPE string
      CHANGING  cs_doc   TYPE ty_doc.

    CLASS-METHODS unwrap_eml
      IMPORTING iv_depth TYPE i DEFAULT 0
      EXPORTING et_notes TYPE string_table
                ev_error TYPE string
      CHANGING  cs_doc   TYPE ty_doc.

    " eml -> list of decoded attachment candidates (pdf / image / eml)
    CLASS-METHODS eml_candidates
      IMPORTING iv_content TYPE xstring
      EXPORTING et_cand    TYPE tt_cand.

    CLASS-METHODS xstr_to_string
      IMPORTING iv_data       TYPE xstring
      RETURNING VALUE(rv_str) TYPE string.

    CLASS-METHODS is_junk_name
      IMPORTING iv_name       TYPE string
      RETURNING VALUE(rv_junk) TYPE abap_bool.

    CLASS-METHODS ext_kind_pref
      IMPORTING iv_ext         TYPE string
      RETURNING VALUE(rv_kind) TYPE string.  " 'pdf'|'image'|'eml'|''
ENDCLASS.


CLASS zcl_mdmdoc_file IMPLEMENTATION.

  METHOD read.
    CLEAR: es_doc, ev_error.
    DATA lv_data TYPE xstring.

    IF iv_from_server = abap_true.
      read_server( EXPORTING iv_path = iv_path
                   IMPORTING ev_data = lv_data ev_error = ev_error ).
      es_doc-source = 'server'.
    ELSE.
      read_pc( EXPORTING iv_path = iv_path
               IMPORTING ev_data = lv_data ev_error = ev_error ).
      es_doc-source = 'pc'.
    ENDIF.
    IF ev_error IS NOT INITIAL.
      RETURN.
    ENDIF.

    es_doc-path    = iv_path.
    es_doc-name    = basename( iv_path ).
    es_doc-ext     = ext_of( es_doc-name ).
    es_doc-content = lv_data.
    es_doc-sha16   = sha16( lv_data ).
  ENDMETHOD.


  METHOD read_pc.
    CLEAR: ev_data, ev_error.
    DATA lt_bin    TYPE solix_tab.
    DATA lv_length TYPE i.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING filename   = iv_path
                filetype   = 'BIN'
      IMPORTING filelength = lv_length
      CHANGING  data_tab   = lt_bin
      EXCEPTIONS OTHERS    = 1 ).
    IF sy-subrc <> 0.
      ev_error = |cannot read PC file: { iv_path }|.
      RETURN.
    ENDIF.

    ev_data = cl_bcs_convert=>solix_to_xstring( it_solix  = lt_bin
                                                iv_size   = lv_length ).
  ENDMETHOD.


  METHOD read_server.
    CLEAR: ev_data, ev_error.
    DATA lv_chunk TYPE xstring.

    OPEN DATASET iv_path FOR INPUT IN BINARY MODE.
    IF sy-subrc <> 0.
      ev_error = |cannot open server file: { iv_path }|.
      RETURN.
    ENDIF.

    DO.
      READ DATASET iv_path INTO lv_chunk.
      IF lv_chunk IS NOT INITIAL.
        CONCATENATE ev_data lv_chunk INTO ev_data IN BYTE MODE.
      ENDIF.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
    ENDDO.

    CLOSE DATASET iv_path.
  ENDMETHOD.


  METHOD classify_ext.
    " Mirrors config.py ext sets. Bare lowercase ext, no dot.
    DATA lv_ext TYPE string.
    lv_ext = to_lower( iv_ext ).
    " tolerate a leading dot if a caller passes one
    IF lv_ext CP '.*'.
      lv_ext = lv_ext+1.
    ENDIF.

    CASE lv_ext.
      WHEN 'pdf'.
        rv_kind = 'pdf'.
      WHEN 'png' OR 'jpg' OR 'jpeg' OR 'bmp' OR 'tif' OR 'tiff' OR 'gif' OR 'webp'.
        rv_kind = 'image'.
      WHEN 'eml'.
        rv_kind = 'email'.
      WHEN 'msg'.
        rv_kind = 'msg'.
      WHEN 'zip'.
        rv_kind = 'zip'.
      WHEN 'docx' OR 'doc' OR 'xlsx' OR 'xlsm' OR 'xls' OR 'txt' OR 'rtf' OR 'csv' OR 'odt'.
        rv_kind = 'editable'.
      WHEN OTHERS.
        rv_kind = 'other'.
    ENDCASE.
  ENDMETHOD.


  METHOD unwrap.
    CLEAR: et_notes, ev_error.
    DATA lv_kind TYPE string.
    lv_kind = classify_ext( cs_doc-ext ).

    CASE lv_kind.
      WHEN 'zip'.
        unwrap_zip( IMPORTING et_notes = et_notes ev_error = ev_error
                    CHANGING  cs_doc   = cs_doc ).
      WHEN 'email'.
        unwrap_eml( EXPORTING iv_depth = 0
                    IMPORTING et_notes = et_notes ev_error = ev_error
                    CHANGING  cs_doc   = cs_doc ).
      WHEN OTHERS.
        " nothing to unwrap; leave the document as-is
    ENDCASE.
  ENDMETHOD.


  METHOD unwrap_zip.
    CLEAR: et_notes, ev_error.
    DATA lo_zip  TYPE REF TO cl_abap_zip.
    DATA lt_cand TYPE tt_cand.

    lo_zip = NEW cl_abap_zip( ).
    lo_zip->load( EXPORTING zip = cs_doc-content
                  EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0.
      ev_error = |cannot open zip: { cs_doc-name }|.
      RETURN.
    ENDIF.

    LOOP AT lo_zip->files ASSIGNING FIELD-SYMBOL(<ls_f>).
      DATA(lv_member) = CONV string( <ls_f>-name ).
      IF is_junk_name( lv_member ) = abap_true.
        CONTINUE.
      ENDIF.
      DATA(lv_ext)  = ext_of( basename( lv_member ) ).
      DATA(lv_pref) = ext_kind_pref( lv_ext ).
      IF lv_pref IS INITIAL.
        CONTINUE.  " not a pdf/image/eml document
      ENDIF.

      DATA lv_bin TYPE xstring.
      CLEAR lv_bin.
      lo_zip->get( EXPORTING name = <ls_f>-name
                   IMPORTING content = lv_bin
                   EXCEPTIONS OTHERS = 1 ).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      APPEND VALUE ty_cand( name    = basename( lv_member )
                            ext     = lv_ext
                            content = lv_bin
                            score   = candidate_score( lv_ext ) ) TO lt_cand.
    ENDLOOP.

    IF lt_cand IS INITIAL.
      ev_error = |zip contains no readable document (pdf/image/eml): { cs_doc-name }|.
      RETURN.
    ENDIF.

    DATA(ls_best) = pick_best( lt_cand ).

    " note what was chosen and what was skipped (parity with pipeline note)
    DATA lv_rest TYPE string.
    LOOP AT lt_cand ASSIGNING FIELD-SYMBOL(<ls_c>).
      IF <ls_c>-name = ls_best-name AND <ls_c>-content = ls_best-content.
        CONTINUE.
      ENDIF.
      IF lv_rest IS INITIAL.
        lv_rest = <ls_c>-name.
      ELSE.
        lv_rest = |{ lv_rest }, { <ls_c>-name }|.
      ENDIF.
    ENDLOOP.
    DATA(lv_note) = |packet ({ cs_doc-name }): analysed '{ ls_best-name }'|.
    IF lv_rest IS NOT INITIAL.
      lv_note = |{ lv_note }; other documents inside NOT analysed: { lv_rest }|.
    ENDIF.
    APPEND lv_note TO et_notes.

    " rewrite the doc to the chosen inner member
    cs_doc-name    = ls_best-name.
    cs_doc-ext     = ls_best-ext.
    cs_doc-content = ls_best-content.
    cs_doc-sha16   = sha16( ls_best-content ).

    " recurse ONCE into an inner eml
    IF classify_ext( cs_doc-ext ) = 'email'.
      DATA lt_more TYPE string_table.
      unwrap_eml( EXPORTING iv_depth = 1
                  IMPORTING et_notes = lt_more ev_error = ev_error
                  CHANGING  cs_doc   = cs_doc ).
      APPEND LINES OF lt_more TO et_notes.
    ENDIF.
  ENDMETHOD.


  METHOD unwrap_eml.
    CLEAR: et_notes, ev_error.
    DATA lt_cand TYPE tt_cand.

    eml_candidates( EXPORTING iv_content = cs_doc-content
                    IMPORTING et_cand    = lt_cand ).

    IF lt_cand IS INITIAL.
      ev_error = |email has no pdf/image/eml attachment: { cs_doc-name }|.
      RETURN.
    ENDIF.

    DATA(ls_best) = pick_best( lt_cand ).
    APPEND |email ({ cs_doc-name }): unwrapped attachment '{ ls_best-name }'| TO et_notes.

    cs_doc-name    = ls_best-name.
    cs_doc-ext     = ls_best-ext.
    cs_doc-content = ls_best-content.
    cs_doc-sha16   = sha16( ls_best-content ).

    " one recursion into an inner eml (respect depth ceiling of 2)
    IF classify_ext( cs_doc-ext ) = 'email' AND iv_depth < 2.
      DATA lt_more TYPE string_table.
      unwrap_eml( EXPORTING iv_depth = iv_depth + 1
                  IMPORTING et_notes = lt_more ev_error = ev_error
                  CHANGING  cs_doc   = cs_doc ).
      APPEND LINES OF lt_more TO et_notes.
    ENDIF.
  ENDMETHOD.


  METHOD eml_candidates.
    CLEAR et_cand.
    DATA lv_text TYPE string.
    lv_text = xstr_to_string( iv_content ).
    IF lv_text IS INITIAL.
      RETURN.
    ENDIF.

    " Find the multipart boundary in the Content-Type header.
    " boundary="xxx" or boundary=xxx (classic regex; case-insensitive).
    DATA lv_boundary TYPE string.
    FIND FIRST OCCURRENCE OF REGEX `boundary="?([^";\r\n]+)"?`
         IN lv_text IGNORING CASE SUBMATCHES lv_boundary.
    IF sy-subrc <> 0 OR lv_boundary IS INITIAL.
      RETURN.
    ENDIF.
    " strip a trailing quote if the greedy class swallowed one
    IF lv_boundary CP `*"`.
      DATA(lv_len) = strlen( lv_boundary ) - 1.
      lv_boundary = lv_boundary(lv_len).
    ENDIF.

    " Split into parts on --boundary. Normalise CRLF to LF first.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_text WITH cl_abap_char_utilities=>newline.
    DATA(lv_sep) = |--{ lv_boundary }|.
    DATA lt_parts TYPE string_table.
    SPLIT lv_text AT lv_sep INTO TABLE lt_parts.

    DATA(lv_nl) = cl_abap_char_utilities=>newline.
    LOOP AT lt_parts ASSIGNING FIELD-SYMBOL(<lv_part>).
      " Split each part into headers (before first blank line) and body.
      DATA lv_headers TYPE string.
      DATA lv_body    TYPE string.
      DATA(lv_blank)  = |{ lv_nl }{ lv_nl }|.
      DATA lv_off TYPE i.
      FIND FIRST OCCURRENCE OF lv_blank IN <lv_part> MATCH OFFSET lv_off.
      IF sy-subrc <> 0.
        CONTINUE.  " no header/body split -> not an attachment part
      ENDIF.
      lv_headers = <lv_part>(lv_off).
      DATA(lv_body_off) = lv_off + strlen( lv_blank ).
      lv_body = <lv_part>+lv_body_off.

      DATA(lv_hlow) = to_lower( lv_headers ).

      " Must be a document part: attachment disposition OR pdf/image content type.
      DATA lv_is_attach TYPE abap_bool.
      IF lv_hlow CS `content-disposition:` AND lv_hlow CS `attachment`.
        lv_is_attach = abap_true.
      ELSEIF lv_hlow CS `application/pdf` OR lv_hlow CS `image/`.
        lv_is_attach = abap_true.
      ENDIF.
      IF lv_is_attach = abap_false.
        CONTINUE.
      ENDIF.

      " Require base64 transfer encoding.
      IF NOT ( lv_hlow CS `content-transfer-encoding:` AND lv_hlow CS `base64` ).
        CONTINUE.
      ENDIF.

      " Derive a filename + extension.
      DATA lv_fn TYPE string.
      FIND FIRST OCCURRENCE OF REGEX `filename="?([^";\r\n]+)"?`
           IN lv_headers IGNORING CASE SUBMATCHES lv_fn.
      IF sy-subrc <> 0.
        FIND FIRST OCCURRENCE OF REGEX `name="?([^";\r\n]+)"?`
             IN lv_headers IGNORING CASE SUBMATCHES lv_fn.
      ENDIF.
      IF lv_fn CP `*"`.
        DATA(lv_fl) = strlen( lv_fn ) - 1.
        lv_fn = lv_fn(lv_fl).
      ENDIF.

      DATA(lv_ext) = ext_of( basename( lv_fn ) ).
      IF lv_ext IS INITIAL.
        " no usable filename ext -> infer from content type
        IF lv_hlow CS `application/pdf`.
          lv_ext = 'pdf'.
        ELSEIF lv_hlow CS `image/png`.
          lv_ext = 'png'.
        ELSEIF lv_hlow CS `image/jpeg` OR lv_hlow CS `image/jpg`.
          lv_ext = 'jpg'.
        ENDIF.
      ENDIF.

      DATA(lv_pref) = ext_kind_pref( lv_ext ).
      IF lv_pref IS INITIAL.
        CONTINUE.  " keep only pdf/image/eml attachments
      ENDIF.

      " Decode base64 body -> xstring. Base64 is line-wrapped; strip ALL
      " whitespace (newlines, CR, tabs, spaces) — CONDENSE would leave newlines.
      DATA lv_b64 TYPE string.
      lv_b64 = lv_body.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline        IN lv_b64 WITH ``.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf          IN lv_b64 WITH ``.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_b64 WITH ``.
      REPLACE ALL OCCURRENCES OF ` ` IN lv_b64 WITH ``.
      IF lv_b64 IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA lv_bin TYPE xstring.
      TRY.
          lv_bin = cl_http_utility=>decode_x_base64( lv_b64 ).
        CATCH cx_root.
          CONTINUE.
      ENDTRY.
      IF lv_bin IS INITIAL.
        CONTINUE.
      ENDIF.

      IF lv_fn IS INITIAL.
        lv_fn = |attachment.{ lv_ext }|.
      ENDIF.
      APPEND VALUE ty_cand( name    = basename( lv_fn )
                            ext     = lv_ext
                            content = lv_bin
                            score   = candidate_score( lv_ext ) ) TO et_cand.
    ENDLOOP.
  ENDMETHOD.


  METHOD pick_best.
    " Highest score wins; ties keep first-seen order (stable).
    CLEAR rs_best.
    LOOP AT it_cand ASSIGNING FIELD-SYMBOL(<ls_c>).
      IF sy-tabix = 1 OR <ls_c>-score > rs_best-score.
        rs_best = <ls_c>.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD candidate_score.
    CASE ext_kind_pref( iv_ext ).
      WHEN 'pdf'.
        rv_score = c_score-pdf.
      WHEN 'image'.
        rv_score = c_score-image.
      WHEN 'eml'.
        rv_score = c_score-eml.
      WHEN OTHERS.
        rv_score = c_score-none.
    ENDCASE.
  ENDMETHOD.


  METHOD ext_kind_pref.
    " Collapse classify_ext to the three container-relevant buckets.
    CASE classify_ext( iv_ext ).
      WHEN 'pdf'.
        rv_kind = 'pdf'.
      WHEN 'image'.
        rv_kind = 'image'.
      WHEN 'email'.
        rv_kind = 'eml'.
      WHEN OTHERS.
        rv_kind = ``.
    ENDCASE.
  ENDMETHOD.


  METHOD is_junk_name.
    " Skip macOS resource-fork junk and dotfiles.
    DATA(lv_base) = basename( iv_name ).
    IF iv_name CS `__MACOSX`
       OR lv_base CP `.*`          " dotfile (e.g. .DS_Store, ._foo)
       OR lv_base CP `._*`.
      rv_junk = abap_true.
    ELSE.
      rv_junk = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD save_text.
    CLEAR ev_error.

    IF iv_to_server = abap_true.
      DATA lv_x TYPE xstring.
      TRY.
          lv_x = cl_abap_conv_out_ce=>create( encoding = 'UTF-8' )->convert( iv_text ).
        CATCH cx_root.
          ev_error = |cannot encode text for { iv_path }|.
          RETURN.
      ENDTRY.
      OPEN DATASET iv_path FOR OUTPUT IN BINARY MODE.
      IF sy-subrc <> 0.
        ev_error = |cannot open server file for write: { iv_path }|.
        RETURN.
      ENDIF.
      TRANSFER lv_x TO iv_path.
      CLOSE DATASET iv_path.
    ELSE.
      " PC: write UTF-8 bytes via BIN so non-ASCII survives regardless of codepage.
      DATA lv_bin TYPE xstring.
      TRY.
          lv_bin = cl_abap_conv_out_ce=>create( encoding = 'UTF-8' )->convert( iv_text ).
        CATCH cx_root.
          ev_error = |cannot encode text for { iv_path }|.
          RETURN.
      ENDTRY.
      DATA lt_bin TYPE solix_tab.
      DATA lv_len TYPE i.
      lt_bin = cl_bcs_convert=>xstring_to_solix( lv_bin ).
      lv_len = xstrlen( lv_bin ).
      cl_gui_frontend_services=>gui_download(
        EXPORTING bin_filesize = lv_len
                  filename     = iv_path
                  filetype     = 'BIN'
        CHANGING  data_tab     = lt_bin
        EXCEPTIONS OTHERS      = 1 ).
      IF sy-subrc <> 0.
        ev_error = |cannot write PC file: { iv_path }|.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD sha16.
    " First 16 hex chars of SHA-256, lowercase.
    " EF_HASHSTRING returns the digest already rendered as an uppercase hex string
    " (unlike a raw xstring->string move, which is codepage-ambiguous); lower-case it.
    DATA lv_hex TYPE string.
    cl_abap_message_digest=>calculate_hash_for_raw(
      EXPORTING if_algorithm  = if_abap_message_digest=>c_sha256
                if_data       = iv_data
      IMPORTING ef_hashstring = lv_hex ).
    lv_hex = to_lower( lv_hex ).
    IF strlen( lv_hex ) >= 16.
      rv_hex = lv_hex(16).
    ELSE.
      rv_hex = lv_hex.
    ENDIF.
  ENDMETHOD.


  METHOD basename.
    " Last path segment, splitting on both / and \.
    DATA lv_p TYPE string.
    lv_p = iv_path.
    REPLACE ALL OCCURRENCES OF `\` IN lv_p WITH `/`.
    DATA lt TYPE string_table.
    SPLIT lv_p AT `/` INTO TABLE lt.
    IF lt IS NOT INITIAL.
      rv_name = lt[ lines( lt ) ].
    ELSE.
      rv_name = lv_p.
    ENDIF.
  ENDMETHOD.


  METHOD ext_of.
    " Lowercase extension after the LAST dot; '' when there is none (or the dot
    " is the final character, e.g. 'foo.').
    DATA(lv_name) = basename( iv_name ).
    DATA lv_last TYPE i.
    lv_last = -1.
    DATA lv_i TYPE i.
    lv_i = 0.
    DATA(lv_n) = strlen( lv_name ).
    WHILE lv_i < lv_n.
      IF lv_name+lv_i(1) = `.`.
        lv_last = lv_i.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.
    IF lv_last < 0 OR lv_last = lv_n - 1.
      rv_ext = ``.
      RETURN.
    ENDIF.
    DATA(lv_start) = lv_last + 1.
    rv_ext = to_lower( lv_name+lv_start ).
  ENDMETHOD.


  METHOD xstr_to_string.
    " UTF-8 first; on any failure fall back to Latin-1 (ISO-8859-1).
    CLEAR rv_str.
    TRY.
        DATA(lo_in) = cl_abap_conv_in_ce=>create( encoding = 'UTF-8'
                                                  input    = iv_data ).
        lo_in->read( IMPORTING data = rv_str ).
      CATCH cx_root.
        CLEAR rv_str.
    ENDTRY.
    IF rv_str IS NOT INITIAL.
      RETURN.
    ENDIF.
    TRY.
        DATA(lo_l1) = cl_abap_conv_in_ce=>create( encoding = '1100'   " ISO-8859-1
                                                  input    = iv_data ).
        lo_l1->read( IMPORTING data = rv_str ).
      CATCH cx_root.
        CLEAR rv_str.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
