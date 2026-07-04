CLASS zcl_mdmdoc_mask DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Port of privacy.py — the single choke point for sensitive values.
    CLASS-METHODS mask
      IMPORTING iv_kind         TYPE string
                iv_value        TYPE string
      RETURNING VALUE(rv_masked) TYPE string.

    CLASS-METHODS display_value
      IMPORTING iv_kind      TYPE string
                iv_value     TYPE string
                iv_policy    TYPE string DEFAULT 'masked'
      RETURNING VALUE(rv_out) TYPE string.

    CLASS-METHODS kind_for_field
      IMPORTING iv_field       TYPE string
      RETURNING VALUE(rv_kind) TYPE string.

    CLASS-METHODS scrub_text
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS assert_no_leak
      IMPORTING iv_blob   TYPE string
                it_secrets TYPE string_table
                iv_policy TYPE string DEFAULT 'strict'
      EXPORTING et_hits   TYPE string_table
                ev_clean  TYPE abap_bool.

  PRIVATE SECTION.
    CLASS-DATA gv_ellipsis TYPE string.   " U+2026 HORIZONTAL ELLIPSIS
    CLASS-METHODS class_constructor.

    CLASS-METHODS shape_matches
      IMPORTING iv_value        TYPE string
                iv_pattern      TYPE string
      RETURNING VALUE(rv_yes)   TYPE abap_bool.

    CLASS-METHODS digits_only
      IMPORTING iv_value         TYPE string
      RETURNING VALUE(rv_digits) TYPE string.

    CLASS-METHODS last_n
      IMPORTING iv_value        TYPE string
                iv_n            TYPE i
      RETURNING VALUE(rv_tail)  TYPE string.

    CLASS-METHODS strip_spacing
      IMPORTING iv_value       TYPE string
      RETURNING VALUE(rv_out)  TYPE string.

    CLASS-METHODS rep
      IMPORTING iv_char        TYPE string
                iv_count       TYPE i
      RETURNING VALUE(rv_out)  TYPE string.

    CLASS-METHODS trim
      IMPORTING iv_value       TYPE string
      RETURNING VALUE(rv_out)  TYPE string.
ENDCLASS.


CLASS zcl_mdmdoc_mask IMPLEMENTATION.

  METHOD class_constructor.
    gv_ellipsis = cl_abap_conv_in_ce=>uccp( uccp = '2026' ).
  ENDMETHOD.

  METHOD shape_matches.
    " anchored full-string classic-regex match (Python re.match with trailing $)
    DATA lo_rx TYPE REF TO cl_abap_regex.
    DATA lo_m  TYPE REF TO cl_abap_matcher.
    lo_rx = cl_abap_regex=>create( pattern = iv_pattern ).
    lo_m  = lo_rx->create_matcher( text = iv_value ).
    rv_yes = lo_m->match( ).      " match() requires the whole string to match
  ENDMETHOD.

  METHOD digits_only.
    " re.sub(r"\D", "", s) — keep only 0-9
    DATA lv_off TYPE i.
    DATA lv_len TYPE i.
    DATA lv_ch TYPE c LENGTH 1.
    lv_len = strlen( iv_value ).
    WHILE lv_off < lv_len.
      lv_ch = iv_value+lv_off(1).
      IF lv_ch CA '0123456789'.
        CONCATENATE rv_digits lv_ch INTO rv_digits RESPECTING BLANKS.
      ENDIF.
      lv_off = lv_off + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD last_n.
    DATA lv_len TYPE i.
    DATA lv_off TYPE i.
    lv_len = strlen( iv_value ).
    IF lv_len <= iv_n.
      rv_tail = iv_value.
    ELSE.
      lv_off = lv_len - iv_n.
      rv_tail = iv_value+lv_off(iv_n).
    ENDIF.
  ENDMETHOD.

  METHOD strip_spacing.
    " remove spaces, hyphen, en-dash, em-dash, tabs, CR/LF
    rv_out = iv_value.
    REPLACE ALL OCCURRENCES OF ` ` IN rv_out WITH ``.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_out WITH ``.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_out WITH ``.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_out WITH ``.
    REPLACE ALL OCCURRENCES OF `-` IN rv_out WITH ``.
    REPLACE ALL OCCURRENCES OF cl_abap_conv_in_ce=>uccp( '2013' ) IN rv_out WITH ``. " en dash
    REPLACE ALL OCCURRENCES OF cl_abap_conv_in_ce=>uccp( '2014' ) IN rv_out WITH ``. " em dash
  ENDMETHOD.

  METHOD rep.
    DATA lv_i TYPE i.
    WHILE lv_i < iv_count.
      CONCATENATE rv_out iv_char INTO rv_out RESPECTING BLANKS.
      lv_i = lv_i + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD trim.
    " Python str.strip() — remove leading/trailing ASCII whitespace only,
    " preserving internal spacing (unlike CONDENSE).
    rv_out = iv_value.
    " leading
    DATA lv_ch TYPE c LENGTH 1.
    WHILE strlen( rv_out ) > 0.
      lv_ch = rv_out(1).
      IF lv_ch = ` ` OR lv_ch = cl_abap_char_utilities=>horizontal_tab
         OR lv_ch = cl_abap_char_utilities=>newline OR lv_ch = cl_abap_char_utilities=>cr_lf.
        rv_out = rv_out+1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    " trailing
    DATA lv_len TYPE i.
    DATA lv_off TYPE i.
    WHILE strlen( rv_out ) > 0.
      lv_len = strlen( rv_out ).
      lv_off = lv_len - 1.
      lv_ch  = rv_out+lv_off(1).
      IF lv_ch = ` ` OR lv_ch = cl_abap_char_utilities=>horizontal_tab
         OR lv_ch = cl_abap_char_utilities=>newline OR lv_ch = cl_abap_char_utilities=>cr_lf.
        rv_out = rv_out(lv_off).
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.

  METHOD mask.
    DATA lv_v TYPE string.
    DATA lv_d TYPE string.
    DATA lv_dl TYPE i.
    DATA lv_c TYPE string.
    DATA lv_cl TYPE i.
    DATA lv_head2 TYPE string.
    DATA lv_stars TYPE i.

    lv_v = trim( iv_value ).     " Python .strip()
    IF lv_v IS INITIAL.
      RETURN.
    ENDIF.
    lv_d  = digits_only( lv_v ).
    lv_dl = strlen( lv_d ).

    DATA lv_tail4 TYPE string.
    lv_tail4 = last_n( iv_value = lv_d iv_n = 4 ).

    CASE iv_kind.
      WHEN 'ssn'.
        IF lv_dl >= 4.
          rv_masked = |XXX-XX-{ lv_tail4 }|.
        ELSE.
          rv_masked = `XXX-XX-????`.
        ENDIF.

      WHEN 'ein'.
        IF lv_dl >= 4.
          rv_masked = |XX-XXX{ lv_tail4 }|.
        ELSE.
          rv_masked = `XX-XXX????`.
        ENDIF.

      WHEN 'tin'.
        " route by shape: 3-2-4 = SSN style, 2-7 = EIN style
        IF shape_matches( iv_value = lv_v iv_pattern = '\d{3}-\d{2}-\d{4}' ) = abap_true.
          rv_masked = mask( iv_kind = 'ssn' iv_value = lv_v ).
        ELSEIF shape_matches( iv_value = lv_v iv_pattern = '\d{2}-\d{7}' ) = abap_true.
          rv_masked = mask( iv_kind = 'ein' iv_value = lv_v ).
        ELSEIF lv_dl >= 5.
          lv_stars = lv_dl - 4.
          IF lv_stars < 2.
            lv_stars = 2.
          ENDIF.
          rv_masked = |{ rep( iv_char = `*` iv_count = lv_stars ) }{ lv_tail4 }|.
        ELSE.
          rv_masked = `****`.
        ENDIF.

      WHEN 'iban'.
        " strip whitespace + uppercase
        lv_c = lv_v.
        REPLACE ALL OCCURRENCES OF ` ` IN lv_c WITH ``.
        REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_c WITH ``.
        REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_c WITH ``.
        REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_c WITH ``.
        TRANSLATE lv_c TO UPPER CASE.
        lv_cl = strlen( lv_c ).
        IF lv_cl >= 2.
          lv_head2 = lv_c(2).
        ELSE.
          lv_head2 = lv_c.
        ENDIF.
        IF lv_cl >= 8.
          rv_masked = |{ lv_head2 }**{ gv_ellipsis }{ last_n( iv_value = lv_c iv_n = 4 ) }|.
        ELSE.
          rv_masked = |{ lv_head2 }**{ gv_ellipsis }|.
        ENDIF.

      WHEN 'account_number' OR 'routing_aba'.
        IF lv_dl >= 4.
          rv_masked = |{ gv_ellipsis }{ lv_tail4 }|.
        ELSE.
          rv_masked = |{ gv_ellipsis }{ lv_d }|.
        ENDIF.

      WHEN OTHERS.
        " unknown kind: safest generic
        IF lv_dl >= 5.
          lv_stars = lv_dl - 4.
          IF lv_stars < 2.
            lv_stars = 2.
          ENDIF.
          rv_masked = |{ rep( iv_char = `*` iv_count = lv_stars ) }{ lv_tail4 }|.
        ELSE.
          rv_masked = `****`.
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD display_value.
    DATA lv_v TYPE string.
    lv_v = trim( iv_value ).
    IF lv_v IS INITIAL.
      RETURN.
    ENDIF.
    " TIN kinds masked BEFORE the policy is consulted; bank kinds full only when 'full'
    IF iv_kind = 'ssn' OR iv_kind = 'ein' OR iv_kind = 'tin' OR iv_policy <> 'full'.
      rv_out = mask( iv_kind = iv_kind iv_value = lv_v ).
    ELSE.
      rv_out = lv_v.
    ENDIF.
  ENDMETHOD.

  METHOD kind_for_field.
    " parse zif_mdmdoc_types=>c_field_kind ('field:kind' comma-separated pairs)
    DATA lt_pairs TYPE string_table.
    DATA lv_pair TYPE string.
    DATA lv_name TYPE string.
    DATA lv_kind TYPE string.
    SPLIT zif_mdmdoc_types=>c_field_kind AT `,` INTO TABLE lt_pairs.
    LOOP AT lt_pairs INTO lv_pair.
      SPLIT lv_pair AT `:` INTO lv_name lv_kind.
      IF lv_name = iv_field.
        rv_kind = lv_kind.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD scrub_text.
    " Free-text scrubbing, policy 'strict' (the contract signature has no vault/policy).
    " SSN_RE, EIN_RE, SSN_SPACED_RE, EIN_SPACED_RE, then IBAN_RE, _ACCT_NEAR_RE,
    " _LONG_DIGITS_RE.  Classic regex only.
    DATA lo_ssn   TYPE REF TO cl_abap_regex.
    DATA lo_ein   TYPE REF TO cl_abap_regex.
    DATA lo_ssn_s TYPE REF TO cl_abap_regex.
    DATA lo_ein_s TYPE REF TO cl_abap_regex.
    DATA lo_iban  TYPE REF TO cl_abap_regex.
    DATA lo_acct  TYPE REF TO cl_abap_regex.
    DATA lo_long  TYPE REF TO cl_abap_regex.
    DATA lo_m     TYPE REF TO cl_abap_matcher.
    DATA lv_match TYPE string.
    DATA lv_g1    TYPE string.

    rv_text = iv_text.

    " ocr.SSN_RE = \b(\d{3}-\d{2}-\d{4})\b  -> \<...\>
    lo_ssn = cl_abap_regex=>create( pattern = '\<\d{3}-\d{2}-\d{4}\>' ).
    lo_m   = lo_ssn->create_matcher( text = rv_text ).
    WHILE lo_m->find_next( ) = abap_true.
      lv_match = lo_m->get_submatch( 0 ).
      lo_m->replace_found( mask( iv_kind = 'ssn' iv_value = lv_match ) ).
      rv_text = lo_m->text.
      lo_m = lo_ssn->create_matcher( text = rv_text ).
    ENDWHILE.

    " ocr.EIN_RE = \b(\d{2}-\d{7})\b
    lo_ein = cl_abap_regex=>create( pattern = '\<\d{2}-\d{7}\>' ).
    lo_m   = lo_ein->create_matcher( text = rv_text ).
    WHILE lo_m->find_next( ) = abap_true.
      lv_match = lo_m->get_submatch( 0 ).
      lo_m->replace_found( mask( iv_kind = 'ein' iv_value = lv_match ) ).
      rv_text = lo_m->text.
      lo_m = lo_ein->create_matcher( text = rv_text ).
    ENDWHILE.

    " SSN_SPACED_RE = \b\d{3}[ ]\d{2}[ ]\d{4}\b
    lo_ssn_s = cl_abap_regex=>create( pattern = '\<\d{3} \d{2} \d{4}\>' ).
    lo_m     = lo_ssn_s->create_matcher( text = rv_text ).
    WHILE lo_m->find_next( ) = abap_true.
      lv_match = lo_m->get_submatch( 0 ).
      lo_m->replace_found( mask( iv_kind = 'ssn' iv_value = lv_match ) ).
      rv_text = lo_m->text.
      lo_m = lo_ssn_s->create_matcher( text = rv_text ).
    ENDWHILE.

    " EIN_SPACED_RE second branch \b\d{2}[ ]\d{7}\b (first hyphen branch is covered
    " by EIN_RE / hyphen handling; classic-regex-safe subset)
    lo_ein_s = cl_abap_regex=>create( pattern = '\<\d{2} \d{7}\>' ).
    lo_m     = lo_ein_s->create_matcher( text = rv_text ).
    WHILE lo_m->find_next( ) = abap_true.
      lv_match = lo_m->get_submatch( 0 ).
      lo_m->replace_found( mask( iv_kind = 'ein' iv_value = lv_match ) ).
      rv_text = lo_m->text.
      lo_m = lo_ein_s->create_matcher( text = rv_text ).
    ENDWHILE.

    " ocr.IBAN_RE = \b([A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]){10,30})\b
    " classic-regex form of (?:[ ]?[A-Z0-9]){10,30}
    lo_iban = cl_abap_regex=>create( pattern = '\<[A-Z]{2}\d{2}( ?[A-Z0-9]){10,30}\>' ).
    lo_m    = lo_iban->create_matcher( text = rv_text ).
    WHILE lo_m->find_next( ) = abap_true.
      lv_match = lo_m->get_match( ).
      lo_m->replace_found( mask( iv_kind = 'iban' iv_value = lv_match ) ).
      rv_text = lo_m->text.
      lo_m = lo_iban->create_matcher( text = rv_text ).
    ENDWHILE.

    " _ACCT_NEAR_RE: group1 = (label + up-to-14 non-digits), group2 = the digit run.
    " Replace with group1 + mask(group2).  (?i) -> ignore_case; non-capturing label alt.
    lo_acct = cl_abap_regex=>create(
      pattern = '((?:acc(?:oun)?t|iban|cuenta|cta\.?|konto(?:nummer)?|kto\.?|compte|conta)[^0-9]{0,14})([0-9][0-9 \-]{5,20}[0-9])'
      ignore_case = abap_true ).
    lo_m = lo_acct->create_matcher( text = rv_text ).
    WHILE lo_m->find_next( ) = abap_true.
      lv_match = lo_m->get_match( ).
      lv_g1    = lo_m->get_submatch( 2 ).            " the digit run
      DATA lv_repl TYPE string.
      DATA lv_prefix TYPE string.
      DATA lv_plen TYPE i.
      lv_plen   = strlen( lv_match ) - strlen( lv_g1 ).
      lv_prefix = lv_match(lv_plen).
      lv_repl   = |{ lv_prefix }{ mask( iv_kind = 'account_number' iv_value = lv_g1 ) }|.
      lo_m->replace_found( lv_repl ).
      rv_text = lo_m->text.
      lo_m = lo_acct->create_matcher( text = rv_text ).
    ENDWHILE.

    " _LONG_DIGITS_RE = \b\d[\d \-]{9,20}\d\b
    lo_long = cl_abap_regex=>create( pattern = '\<\d[\d \-]{9,20}\d\>' ).
    lo_m    = lo_long->create_matcher( text = rv_text ).
    WHILE lo_m->find_next( ) = abap_true.
      lv_match = lo_m->get_match( ).
      lo_m->replace_found( mask( iv_kind = 'account_number' iv_value = lv_match ) ).
      rv_text = lo_m->text.
      lo_m = lo_long->create_matcher( text = rv_text ).
    ENDWHILE.
  ENDMETHOD.

  METHOD assert_no_leak.
    " policy 'strict': TIN + banking patterns + known secrets
    " policy 'tin-only': TIN patterns + TIN secrets (caller passes TIN secrets only)
    DATA lv_b       TYPE string.
    DATA lv_b_norm  TYPE string.
    DATA lv_secret  TYPE string.
    DATA lv_s_norm  TYPE string.
    DATA lv_hit     TYPE string.
    DATA lt_pat     TYPE string_table.
    DATA lv_pat     TYPE string.
    DATA lo_rx      TYPE REF TO cl_abap_regex.
    DATA lo_m       TYPE REF TO cl_abap_matcher.
    DATA lv_g0      TYPE string.

    CLEAR et_hits.
    lv_b = iv_blob.

    " b_norm = strip [\s\-–] for digit-normalized secret compare
    lv_b_norm = strip_spacing( lv_b ).

    " --- known-secret pass (exact + digit-normalized) ---
    LOOP AT it_secrets INTO lv_secret.
      lv_s_norm = strip_spacing( lv_secret ).
      IF strlen( digits_only( lv_s_norm ) ) < 6.
        CONTINUE.
      ENDIF.
      " case-sensitive substring test (ABAP CS is case-insensitive, so use find())
      IF find( val = lv_b sub = lv_secret ) >= 0
         OR ( lv_s_norm IS NOT INITIAL AND find( val = lv_b_norm sub = lv_s_norm ) >= 0 ).
        lv_hit = |known-secret:{ mask( iv_kind = 'tin' iv_value = lv_secret ) }|.
        APPEND lv_hit TO et_hits.
      ENDIF.
    ENDLOOP.

    " --- pattern pass ---
    " TIN patterns (always). SSN/EIN hyphenated + spaced shapes.
    APPEND '\<\d{3}-\d{2}-\d{4}\>' TO lt_pat.
    APPEND '\<\d{2}-\d{7}\>' TO lt_pat.
    APPEND '\<\d{3} \d{2} \d{4}\>' TO lt_pat.
    APPEND '\<\d{2} \d{7}\>' TO lt_pat.
    IF iv_policy <> 'tin-only'.
      " banking patterns: full unmasked IBAN + long bare digit run
      APPEND '\<[A-Z]{2}\d{2}[A-Z0-9]{11,30}\>' TO lt_pat.
      APPEND '\<\d{11,18}\>' TO lt_pat.
    ENDIF.

    LOOP AT lt_pat INTO lv_pat.
      lo_rx = cl_abap_regex=>create( pattern = lv_pat ).
      lo_m  = lo_rx->create_matcher( text = lv_b ).
      IF lo_m->find_next( ) = abap_true.
        lv_g0 = lo_m->get_match( ).
        DATA lv_short TYPE string.
        lv_short = lv_pat.
        IF strlen( lv_short ) > 40.
          lv_short = lv_short(40).
        ENDIF.
        lv_hit = |pattern:{ lv_short }:{ mask( iv_kind = 'account_number' iv_value = lv_g0 ) }|.
        APPEND lv_hit TO et_hits.
      ENDIF.
    ENDLOOP.

    IF et_hits IS INITIAL.
      ev_clean = abap_true.
    ELSE.
      ev_clean = abap_false.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
