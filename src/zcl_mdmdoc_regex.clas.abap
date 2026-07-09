CLASS zcl_mdmdoc_regex DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Deterministic ID extraction ported from ocr.regex_fields + fields.find_boxed_tin
    "! / fields.find_valid_ibans. Candidate names:
    "! iban, swift_bic, account_number, routing_aba, routing_aba_wires, ein, ssn,
    "! tin_boxed (9 digits), tin_boxed_type ('EIN'|'SSN').
    CLASS-METHODS extract_candidates
      IMPORTING iv_text              TYPE string
      RETURNING VALUE(rt_candidates) TYPE zif_mdmdoc_types=>tt_fields.

  PRIVATE SECTION.
    "! One captured submatch of one match.
    TYPES: BEGIN OF ty_match,
             g1 TYPE string,
             g2 TYPE string,
           END OF ty_match,
           tt_match TYPE STANDARD TABLE OF ty_match WITH EMPTY KEY.

    "! Newline-flattened working buffer (newlines/tabs -> single spaces) for the
    "! label-window regexes. `(?s)`/`(?m)` do not exist in classic ABAP regex, so
    "! we flatten so `.{0,N}` style windows can cross original line breaks.
    CLASS-METHODS flatten
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_flat) TYPE string.

    "! strip whitespace, upper-case (ocr._clean)
    CLASS-METHODS clean
      IMPORTING iv_value       TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    "! strip whitespace + dashes (account/fallback normalisation)
    CLASS-METHODS strip_sep
      IMPORTING iv_value       TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    "! keep digits only
    CLASS-METHODS digits
      IMPORTING iv_value        TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    "! at least one char is not A-Z (python `not c.isalpha()`)
    CLASS-METHODS has_non_alpha
      IMPORTING iv_value      TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    "! run a regex (optionally case-insensitive) and collect submatch group 1
    "! (and group 2 when iv_want_g2) of every match, in document order.
    CLASS-METHODS find_all
      IMPORTING iv_pattern        TYPE string
                iv_text           TYPE string
                iv_ignore_case    TYPE abap_bool DEFAULT abap_false
                iv_want_g2        TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rt_matches) TYPE tt_match.

    "! first submatch group 1 of a regex, '' when none.
    CLASS-METHODS find_first
      IMPORTING iv_pattern     TYPE string
                iv_text        TYPE string
                iv_ignore_case TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rv_g1)   TYPE string.

    CLASS-METHODS put
      IMPORTING iv_name  TYPE string
                iv_value TYPE string
      CHANGING  ct_out   TYPE zif_mdmdoc_types=>tt_fields.

    CLASS-METHODS get
      IMPORTING it_out         TYPE zif_mdmdoc_types=>tt_fields
                iv_name        TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS has
      IMPORTING it_out        TYPE zif_mdmdoc_types=>tt_fields
                iv_name       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    CLASS-METHODS extract_iban
      IMPORTING iv_flat TYPE string
      CHANGING  ct_out  TYPE zif_mdmdoc_types=>tt_fields.

    CLASS-METHODS extract_swift
      IMPORTING iv_flat TYPE string
      CHANGING  ct_out  TYPE zif_mdmdoc_types=>tt_fields.

    CLASS-METHODS extract_ein_ssn
      IMPORTING iv_flat TYPE string
      CHANGING  ct_out  TYPE zif_mdmdoc_types=>tt_fields.

    CLASS-METHODS extract_routing
      IMPORTING iv_flat TYPE string
      CHANGING  ct_out  TYPE zif_mdmdoc_types=>tt_fields.

    CLASS-METHODS extract_account
      IMPORTING iv_flat TYPE string
      CHANGING  ct_out  TYPE zif_mdmdoc_types=>tt_fields.

    "! fields.find_boxed_tin as an explicit line-table LOOP: count consecutive
    "! lines that are a single digit and/or a dash; a run totalling exactly 9
    "! digits is a boxed TIN. Type from the nearest PRECEDING box label.
    CLASS-METHODS extract_boxed_tin
      IMPORTING it_lines TYPE string_table
                iv_text  TYPE string
      CHANGING  ct_out   TYPE zif_mdmdoc_types=>tt_fields.

    "! true when a line consists only of an optional dash, one digit, another
    "! optional dash and whitespace, with at most one digit (a box row).
    CLASS-METHODS classify_box_line
      IMPORTING iv_line       TYPE string
      EXPORTING ev_is_box     TYPE abap_bool
                ev_digitcount TYPE i.

    "! assemble the 9 boxed digits from the run starting at iv_start_line, settle
    "! the type from the nearest preceding box label, and store both candidates.
    CLASS-METHODS set_boxed
      IMPORTING it_lines      TYPE string_table
                iv_start_line TYPE i
                iv_text       TYPE string
      CHANGING  ct_out        TYPE zif_mdmdoc_types=>tt_fields.
ENDCLASS.


CLASS zcl_mdmdoc_regex IMPLEMENTATION.

  METHOD extract_candidates.
    " 1) full-width -> ASCII (translate_fullwidth), matching Python NFKC intent.
    DATA(lv_text) = zcl_mdmdoc_norm=>translate_fullwidth( iv_text ).

    " 2) flattened buffer for label-window regexes (newlines -> spaces)
    DATA(lv_flat) = flatten( lv_text ).

    " 3) line table for boxed-TIN / per-line logic
    DATA lt_lines TYPE string_table.
    SPLIT lv_text AT |{ cl_abap_char_utilities=>newline }| INTO TABLE lt_lines.

    extract_iban( EXPORTING iv_flat = lv_flat CHANGING ct_out = rt_candidates ).
    extract_swift( EXPORTING iv_flat = lv_flat CHANGING ct_out = rt_candidates ).
    extract_ein_ssn( EXPORTING iv_flat = lv_flat CHANGING ct_out = rt_candidates ).
    extract_routing( EXPORTING iv_flat = lv_flat CHANGING ct_out = rt_candidates ).
    extract_account( EXPORTING iv_flat = lv_flat CHANGING ct_out = rt_candidates ).
    extract_boxed_tin( EXPORTING it_lines = lt_lines iv_text = lv_text
                       CHANGING  ct_out = rt_candidates ).
  ENDMETHOD.


  METHOD flatten.
    rv_flat = iv_text.
    " CR, LF and tab -> single space; the label windows use `[^0-9]{0,N}` style
    " spans that must be able to cross original line breaks.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_flat WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_flat WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_flat WITH ` `.
  ENDMETHOD.


  METHOD clean.
    " ocr._clean: remove all whitespace, upper-case
    rv_text = iv_value.
    REPLACE ALL OCCURRENCES OF REGEX `[[:space:]]` IN rv_text WITH ``.
    TRANSLATE rv_text TO UPPER CASE.
  ENDMETHOD.


  METHOD strip_sep.
    rv_text = iv_value.
    REPLACE ALL OCCURRENCES OF REGEX `[[:space:]-]` IN rv_text WITH ``.
  ENDMETHOD.


  METHOD digits.
    rv_value = iv_value.
    REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN rv_value WITH ``.
  ENDMETHOD.


  METHOD has_non_alpha.
    DATA lv_off TYPE i.
    DATA(lv_len) = strlen( iv_value ).
    rv_yes = abap_false.
    WHILE lv_off < lv_len.
      DATA(lv_ch) = iv_value+lv_off(1).
      IF NOT lv_ch CA 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'.
        rv_yes = abap_true.
        RETURN.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD find_all.
    DATA lo_regex   TYPE REF TO cl_abap_regex.
    DATA lo_matcher TYPE REF TO cl_abap_matcher.

    CREATE OBJECT lo_regex
      EXPORTING pattern     = iv_pattern
                ignore_case = iv_ignore_case.
    lo_matcher = lo_regex->create_matcher( text = iv_text ).

    WHILE lo_matcher->find_next( ) = abap_true.
      DATA ls TYPE ty_match.
      CLEAR ls.
      TRY.
          ls-g1 = lo_matcher->get_submatch( 1 ).
          IF iv_want_g2 = abap_true.
            ls-g2 = lo_matcher->get_submatch( 2 ).
          ENDIF.
        CATCH cx_sy_matcher.
          " a submatch group did not participate -> leave it empty
      ENDTRY.
      APPEND ls TO rt_matches.
    ENDWHILE.
  ENDMETHOD.


  METHOD find_first.
    DATA(lt) = find_all( iv_pattern     = iv_pattern
                         iv_text        = iv_text
                         iv_ignore_case = iv_ignore_case ).
    IF lines( lt ) > 0.
      rv_g1 = lt[ 1 ]-g1.
    ELSE.
      rv_g1 = ``.
    ENDIF.
  ENDMETHOD.


  METHOD put.
    " setdefault semantics: never overwrite an already-present candidate.
    IF has( it_out = ct_out iv_name = iv_name ) = abap_true.
      RETURN.
    ENDIF.
    INSERT VALUE #( name = iv_name value = iv_value ) INTO TABLE ct_out.
  ENDMETHOD.


  METHOD get.
    READ TABLE it_out ASSIGNING FIELD-SYMBOL(<f>) WITH KEY name = iv_name.
    IF sy-subrc = 0.
      rv_value = <f>-value.
    ELSE.
      rv_value = ``.
    ENDIF.
  ENDMETHOD.


  METHOD has.
    READ TABLE it_out TRANSPORTING NO FIELDS WITH KEY name = iv_name.
    rv_yes = boolc( sy-subrc = 0 ).
  ENDMETHOD.


  METHOD extract_iban.
    " [CONST:ocr_iban_regex]
    " IBAN_RE = \b([A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]){10,30})\b   (\b -> \< \>)
    " NOTE: case-sensitive (Python IBAN_RE has no (?i)) -> upper-case letters only.
    DATA(lv_raw) = find_first(
      iv_pattern = `\<([A-Z][A-Z]\d\d(?:[ ]?[A-Z0-9]){10,30})\>`
      iv_text    = iv_flat ).
    IF lv_raw IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_iban) = clean( lv_raw ).
    DATA(lv_len) = strlen( lv_iban ).
    IF lv_len >= 15 AND lv_len <= 34.
      put( EXPORTING iv_name = `iban` iv_value = lv_iban CHANGING ct_out = ct_out ).
    ENDIF.
  ENDMETHOD.


  METHOD extract_swift.
    " [CONST:ocr_swift_regex]
    " prefer a BIC near a 'bic'/'swift' label (case-insensitive):
    "   (?i)(?:bic|swift)[^A-Z0-9]{0,8}([A-Z]{6}[A-Z0-9]{2}(?:[A-Z0-9]{3})?)
    " NOTE: the capturing group is case-sensitive in Python (only [A-Z] literal
    " inside is affected by the (?i) flag -> becomes case-insensitive). To keep
    " parity we run ignore_case = abap_true for the whole pattern, then upper().
    DATA(lv_near) = find_first(
      iv_pattern     = `(?:bic|swift)[^A-Za-z0-9]{0,8}([A-Z]{6}[A-Z0-9][A-Z0-9](?:[A-Z0-9][A-Z0-9][A-Z0-9])?)`
      iv_text        = iv_flat
      iv_ignore_case = abap_true ).
    DATA lv_sw TYPE string.
    IF lv_near IS NOT INITIAL.
      lv_sw = to_upper( lv_near ).
    ELSE.
      " SWIFT_RE = \b([A-Z]{6}[A-Z0-9]{2}(?:[A-Z0-9]{3})?)\b ; case-SENSITIVE.
      " Take the first candidate that is not all-alpha (real BIC carries a digit).
      DATA(lt) = find_all(
        iv_pattern = `\<([A-Z][A-Z][A-Z][A-Z][A-Z][A-Z][A-Z0-9][A-Z0-9](?:[A-Z0-9][A-Z0-9][A-Z0-9])?)\>`
        iv_text    = iv_flat ).
      LOOP AT lt ASSIGNING FIELD-SYMBOL(<c>).
        IF has_non_alpha( <c>-g1 ) = abap_true.
          lv_sw = to_upper( <c>-g1 ).
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
    IF lv_sw IS NOT INITIAL.
      put( EXPORTING iv_name = `swift_bic` iv_value = lv_sw CHANGING ct_out = ct_out ).
    ENDIF.
  ENDMETHOD.


  METHOD extract_ein_ssn.
    " [CONST:ocr_ein_regex] [CONST:ocr_ssn_regex]
    " EIN_RE = \b(\d{2}-\d{7})\b
    DATA(lv_ein) = find_first( iv_pattern = `\<(\d\d-\d{7})\>` iv_text = iv_flat ).
    IF lv_ein IS NOT INITIAL.
      put( EXPORTING iv_name = `ein` iv_value = lv_ein CHANGING ct_out = ct_out ).
    ELSE.
      " scanned W-9 boxes near the EIN label flatten to separated digits:
      "   (?is)employer\s+identification\s+number.{0,120}?((?:\d[ \t]*[\-–—]?[ \t]*){8}\d)
      " (?s) is handled because iv_flat has newlines already flattened to spaces.
      " Non-greedy .{0,120}? -> greedy-safe here because the digit block is anchored;
      " classic ABAP regex supports lazy quantifiers via `?`.
      DATA(lv_blk) = find_first(
        iv_pattern     = `employer\s+identification\s+number.{0,120}?`
                      && `((?:\d[ \t]*[-–—]?[ \t]*){8}\d)`
        iv_text        = iv_flat
        iv_ignore_case = abap_true ).
      IF lv_blk IS NOT INITIAL.
        DATA(lv_d) = digits( lv_blk ).
        IF strlen( lv_d ) = 9.
          put( EXPORTING iv_name = `ein`
                         iv_value = |{ lv_d(2) }-{ lv_d+2(7) }|
               CHANGING ct_out = ct_out ).
        ENDIF.
      ENDIF.
    ENDIF.

    " SSN_RE = \b(\d{3}-\d{2}-\d{4})\b -> store MASKED only (never full SSN).
    DATA(lv_ssn) = find_first( iv_pattern = `\<(\d{3}-\d\d-\d{4})\>` iv_text = iv_flat ).
    IF lv_ssn IS NOT INITIAL.
      DATA(lv_l4) = lv_ssn+7(4).   " last 4 digits of NNN-NN-NNNN
      put( EXPORTING iv_name = `ssn` iv_value = |***-**-{ lv_l4 }|
           CHANGING ct_out = ct_out ).
    ENDIF.
  ENDMETHOD.


  METHOD extract_routing.
    " routing/ABA: 9 digits near a routing keyword. US bank letters often carry
    " TWO values (standard/ACH vs domestic wires). ALL matches kept; qualifier
    " words ('wire'/'domestic' in the label) route to routing_aba_wires.
    "   (?i)((?:bank\s+)?(?:routing|aba|ach|rtn|wire[s]?)
    "        (?:[ /]*(?:aba|routing|number|no\.?|#))?[^0-9]{0,28})(\d{9})\b
    DATA(lt) = find_all(
      iv_pattern     = `((?:bank\s+)?(?:routing|aba|ach|rtn|wires?)`
                    && `(?:[ /]*(?:aba|routing|number|no\.?|#))?[^0-9]{0,28})(\d{9})\>`
      iv_text        = iv_flat
      iv_ignore_case = abap_true
      iv_want_g2     = abap_true ).

    DATA lt_seen TYPE string_table.
    LOOP AT lt ASSIGNING FIELD-SYMBOL(<m>).
      DATA(lv_label) = to_lower( <m>-g1 ).
      DATA(lv_val)   = <m>-g2.
      READ TABLE lt_seen TRANSPORTING NO FIELDS WITH KEY table_line = lv_val.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      APPEND lv_val TO lt_seen.
      IF lv_label CS `wire` OR lv_label CS `domestic`.
        put( EXPORTING iv_name = `routing_aba_wires` iv_value = lv_val CHANGING ct_out = ct_out ).
      ELSE.
        put( EXPORTING iv_name = `routing_aba` iv_value = lv_val CHANGING ct_out = ct_out ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD extract_account.
    " account number: digits near an 'account' keyword (EN/ES/DE/FR/PT/RU/CJK):
    "   (?i)(?:acct labels)[^0-9]{0,14}([0-9][0-9 \-]{5,20}[0-9])
    DATA(lt) = find_all(
      iv_pattern     = `(?:acc(?:oun)?t|cuenta|cta\.?|konto(?:nummer)?|kto\.?|`
                    && `compte|conta|сч[её]т|계좌|口座|账[户戶号號]|帐[户戶号號])`
                    && `[^0-9]{0,14}([0-9][0-9 -]{5,20}[0-9])`
      iv_text        = iv_flat
      iv_ignore_case = abap_true ).

    DATA(lv_routing) = get( it_out = ct_out iv_name = `routing_aba` ).
    LOOP AT lt ASSIGNING FIELD-SYMBOL(<m>).
      DATA(lv_acct) = strip_sep( <m>-g1 ).
      DATA(lv_len) = strlen( lv_acct ).
      IF lv_len >= 6 AND lv_len <= 18 AND lv_acct <> lv_routing.
        put( EXPORTING iv_name = `account_number` iv_value = lv_acct CHANGING ct_out = ct_out ).
        EXIT.
      ENDIF.
    ENDLOOP.

    " fallback: a long standalone digit run (11-18 digits) -> longest candidate.
    "   \b\d[\d \-]{9,20}\d\b
    IF has( it_out = ct_out iv_name = `account_number` ) = abap_false.
      DATA(lt2) = find_all( iv_pattern = `\<(\d[\d -]{9,20}\d)\>` iv_text = iv_flat ).
      DATA lv_best TYPE string.
      DATA lv_bestlen TYPE i VALUE 0.
      LOOP AT lt2 ASSIGNING FIELD-SYMBOL(<c>).
        DATA(lv_c) = strip_sep( <c>-g1 ).
        DATA(lv_cl) = strlen( lv_c ).
        IF lv_cl >= 11 AND lv_cl <= 18 AND lv_c <> lv_routing.
          " max(...,key=len): keep the longest; ties keep the first seen.
          IF lv_cl > lv_bestlen.
            lv_bestlen = lv_cl.
            lv_best = lv_c.
          ENDIF.
        ENDIF.
      ENDLOOP.
      IF lv_best IS NOT INITIAL.
        put( EXPORTING iv_name = `account_number` iv_value = lv_best CHANGING ct_out = ct_out ).
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD classify_box_line.
    " A box row is: optional leading dash(es)/spaces, at most ONE digit,
    " optional trailing dash(es)/spaces -- nothing else. Mirrors the per-line
    " alternative of _BOXED_TIN_RE:
    "   ^[ \t]*(?:[–\-—][ \t]*)?(?:\d[ \t]*(?:[–\-—][ \t]*)?|[–\-—][ \t]*)$
    ev_is_box = abap_false.
    ev_digitcount = 0.

    DATA(lv) = iv_line.
    " strip trailing CR left by a CRLF split, if any
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv WITH ``.

    DATA lv_off TYPE i.
    DATA(lv_len) = strlen( lv ).
    DATA lv_digits TYPE i VALUE 0.
    DATA lv_nonbox TYPE abap_bool VALUE abap_false.
    DATA lv_any    TYPE abap_bool VALUE abap_false.

    WHILE lv_off < lv_len.
      DATA(lv_ch) = lv+lv_off(1).
      IF lv_ch CA '0123456789'.
        lv_digits = lv_digits + 1.
        lv_any = abap_true.
      ELSEIF lv_ch = '-' OR lv_ch = '–' OR lv_ch = '—'.
        lv_any = abap_true.
      ELSEIF lv_ch = ` ` OR lv_ch = cl_abap_char_utilities=>horizontal_tab.
        " whitespace allowed
      ELSE.
        lv_nonbox = abap_true.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.

    " the regex allows AT MOST one digit per line and requires the line to hold
    " at least one box glyph (digit or dash); a blank line breaks the run.
    IF lv_nonbox = abap_false AND lv_any = abap_true AND lv_digits <= 1.
      ev_is_box = abap_true.
      ev_digitcount = lv_digits.
    ENDIF.
  ENDMETHOD.


  METHOD extract_boxed_tin.
    " fields.find_boxed_tin ported as an explicit line-table scan that mirrors the
    " NON-OVERLAPPING, GREEDY {9,13} finditer of _BOXED_TIN_RE:
    "   - a match starts on a box line and greedily consumes box lines, capped at
    "     13 (the {9,13} upper bound) and by the current maximal run;
    "   - a match needs >= 9 box lines; on success its digit total must be exactly
    "     9 -> accepted, type settled by the nearest preceding box label.
    "   - finditer then continues AFTER the consumed block (non-overlapping).
    DATA(lv_total) = lines( it_lines ).
    DATA lv_i TYPE i VALUE 1.

    WHILE lv_i <= lv_total.
      classify_box_line( EXPORTING iv_line = it_lines[ lv_i ]
                         IMPORTING ev_is_box = DATA(lv_is_box) ).
      IF lv_is_box = abap_false.
        lv_i = lv_i + 1.
        CONTINUE.
      ENDIF.

      " greedily consume up to 13 consecutive box lines from lv_i
      DATA lv_j       TYPE i.
      DATA lv_count   TYPE i VALUE 0.
      DATA lv_digsum  TYPE i VALUE 0.
      lv_j = lv_i.
      WHILE lv_j <= lv_total AND lv_count < 13.
        classify_box_line( EXPORTING iv_line = it_lines[ lv_j ]
                           IMPORTING ev_is_box = DATA(lv_box2) ev_digitcount = DATA(lv_dc) ).
        IF lv_box2 = abap_false.
          EXIT.
        ENDIF.
        lv_count  = lv_count + 1.
        lv_digsum = lv_digsum + lv_dc.
        lv_j = lv_j + 1.
      ENDWHILE.

      IF lv_count >= 9.
        " a {9,13} block was consumed [lv_i .. lv_i+lv_count-1]
        IF lv_digsum = 9.
          set_boxed( EXPORTING it_lines = it_lines iv_start_line = lv_i iv_text = iv_text
                     CHANGING ct_out = ct_out ).
          RETURN.
        ENDIF.
        " consumed but rejected -> continue non-overlapping, after the block
        lv_i = lv_i + lv_count.
      ELSE.
        " fewer than 9 box lines here: no match can start at lv_i, step by one
        lv_i = lv_i + 1.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.


  METHOD set_boxed.
    " assemble the 9 digits of the boxed run and settle its type from the nearest
    " PRECEDING box label within the 800 chars before the run start (fields.find_boxed_tin).
    DATA lv_digits TYPE string.
    DATA lv_i TYPE i.
    lv_i = iv_start_line.
    DATA(lv_total) = lines( it_lines ).
    DATA lv_count TYPE i VALUE 0.
    WHILE lv_i <= lv_total AND lv_count < 13.
      classify_box_line( EXPORTING iv_line = it_lines[ lv_i ]
                         IMPORTING ev_is_box = DATA(lv_box) ev_digitcount = DATA(lv_dc) ).
      IF lv_box = abap_false.
        EXIT.
      ENDIF.
      lv_digits = lv_digits && digits( it_lines[ lv_i ] ).
      lv_count = lv_count + 1.
      lv_i = lv_i + 1.
    ENDWHILE.

    IF strlen( lv_digits ) <> 9.
      RETURN.
    ENDIF.

    " character offset of the run start = length of all preceding lines + newlines.
    DATA lv_offset TYPE i VALUE 0.
    DATA lv_k TYPE i VALUE 1.
    WHILE lv_k < iv_start_line.
      lv_offset = lv_offset + strlen( it_lines[ lv_k ] ) + 1.   " +1 for the split newline
      lv_k = lv_k + 1.
    ENDWHILE.

    DATA(lv_from) = lv_offset - 800.
    IF lv_from < 0.
      lv_from = 0.
    ENDIF.
    DATA(lv_win) = lv_offset - lv_from.
    DATA(lv_textlen) = strlen( iv_text ).
    IF lv_from + lv_win > lv_textlen.
      lv_win = lv_textlen - lv_from.       " clamp: split-offset may exceed text length
    ENDIF.
    DATA lv_before TYPE string.
    IF lv_win > 0.
      lv_before = to_lower( substring( val = iv_text off = lv_from len = lv_win ) ).
    ELSE.
      lv_before = ``.
    ENDIF.

    " nearest preceding label: rfind of each phrase, larger offset wins.
    DATA lv_ei TYPE i.
    DATA lv_ss TYPE i.
    FIND ALL OCCURRENCES OF `employer identification` IN lv_before
         RESULTS DATA(lt_ei).
    FIND ALL OCCURRENCES OF `social security` IN lv_before
         RESULTS DATA(lt_ss).
    IF lines( lt_ei ) > 0.
      lv_ei = lt_ei[ lines( lt_ei ) ]-offset.
    ELSE.
      lv_ei = -1.
    ENDIF.
    IF lines( lt_ss ) > 0.
      lv_ss = lt_ss[ lines( lt_ss ) ]-offset.
    ELSE.
      lv_ss = -1.
    ENDIF.

    DATA lv_type TYPE string.
    IF lv_ei > lv_ss.
      lv_type = `EIN`.
    ELSEIF lv_ss > lv_ei.
      lv_type = `SSN`.
    ELSE.
      lv_type = ``.
    ENDIF.

    put( EXPORTING iv_name = `tin_boxed` iv_value = lv_digits CHANGING ct_out = ct_out ).
    put( EXPORTING iv_name = `tin_boxed_type` iv_value = lv_type CHANGING ct_out = ct_out ).
  ENDMETHOD.

ENDCLASS.
