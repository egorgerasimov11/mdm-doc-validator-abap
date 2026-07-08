CLASS zcl_mdmdoc_extract DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Port of fields.crosscheck_ids + the field normalization applied in stage_b.
    " Builds a ty_extraction from the LLM-read fields and the regex candidates,
    " overlaying deterministic (regex) IDs on top of the model reads.
    CLASS-METHODS build
      IMPORTING iv_doc_class    TYPE string
                iv_doc_type     TYPE string
                it_llm_fields   TYPE zif_mdmdoc_types=>tt_fields
                it_candidates   TYPE zif_mdmdoc_types=>tt_fields
                iv_llm_used     TYPE abap_bool
                iv_raw_text     TYPE string OPTIONAL
                iv_filename     TYPE string OPTIONAL
      RETURNING VALUE(rs_ext)   TYPE zif_mdmdoc_types=>ty_extraction.

  PRIVATE SECTION.
    " ID_FIELDS (fields.py) — bank IDs cross-checked against regex candidates
    CONSTANTS c_id_fields TYPE string VALUE
      `iban,swift_bic,account_number,routing_aba,routing_aba_wires`.

    " sensitive field names whose full values are registered as secrets
    CONSTANTS c_secret_bank TYPE string VALUE
      `iban,account_number,routing_aba,routing_aba_wires`.
    CONSTANTS c_secret_w9 TYPE string VALUE `tin_raw`.

    " upsert (or clear) a field value in the field table
    CLASS-METHODS set_field
      IMPORTING iv_name   TYPE string
                iv_value  TYPE string
      CHANGING  ct_fields TYPE zif_mdmdoc_types=>tt_fields.

    " strip leading '0' characters (python str.lstrip("0"))
    CLASS-METHODS lstrip_zeros
      IMPORTING iv_value      TYPE string
      RETURNING VALUE(rv_out) TYPE string.

    " masked display for a field, using its kind (bank kinds honour policy 'masked')
    CLASS-METHODS masked
      IMPORTING iv_field       TYPE string
                iv_value       TYPE string
      RETURNING VALUE(rv_out)  TYPE string.

    CLASS-METHODS crosscheck_bank
      IMPORTING it_candidates TYPE zif_mdmdoc_types=>tt_fields
      CHANGING  cs_ext        TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS crosscheck_w9
      IMPORTING it_candidates TYPE zif_mdmdoc_types=>tt_fields
      CHANGING  cs_ext        TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS normalize_fields
      CHANGING cs_ext TYPE zif_mdmdoc_types=>ty_extraction.

    " deterministic audit guards — ports of Python stage_b guards; each carries
    " a [GUARD:<name>] marker that tools/check_parity.py verifies against Python
    CLASS-METHODS audit_bank_ids
      IMPORTING iv_raw_text TYPE string
      CHANGING  cs_ext      TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS fix_jp_form
      IMPORTING iv_raw_text TYPE string
      CHANGING  cs_ext      TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS esignature_guard
      IMPORTING iv_raw_text TYPE string
      CHANGING  cs_ext      TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS fix_statement_period
      IMPORTING iv_raw_text TYPE string
      CHANGING  cs_ext      TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS drop_regulator_noise
      CHANGING  cs_ext TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS drop_filename_echo
      IMPORTING iv_filename TYPE string
                iv_raw_text TYPE string
      CHANGING  cs_ext      TYPE zif_mdmdoc_types=>ty_extraction.

    CLASS-METHODS normalize_tin
      CHANGING  cs_ext TYPE zif_mdmdoc_types=>ty_extraction.

    " append a crosscheck note once (guards are idempotent)
    CLASS-METHODS cross_note
      IMPORTING iv_note TYPE string
      CHANGING  cs_ext  TYPE zif_mdmdoc_types=>ty_extraction.

    " mod-97-valid IBAN candidates from raw text (fields.find_valid_ibans)
    CLASS-METHODS find_valid_ibans
      IMPORTING iv_text         TYPE string
      RETURNING VALUE(rt_ibans) TYPE string_table.

    CLASS-METHODS register_secrets
      CHANGING cs_ext TYPE zif_mdmdoc_types=>ty_extraction.
ENDCLASS.


CLASS zcl_mdmdoc_extract IMPLEMENTATION.

  METHOD build.
    " doc_class passthrough
    rs_ext-doc_class = iv_doc_class.

    " doc_type: explicit iv_doc_type wins over the LLM value; fall back to
    " the LLM field '_model'/'doc_type'? — the task fixes iv_doc_type as the
    " override, else the LLM-provided doc_type field if present.
    IF iv_doc_type IS NOT INITIAL.
      rs_ext-doc_type = iv_doc_type.
    ELSE.
      rs_ext-doc_type = zcl_mdmdoc_norm=>field_value(
        it_fields = it_llm_fields iv_name = `doc_type` ).
    ENDIF.

    " llm_used passthrough; model_id from '_model' candidate/field entry
    rs_ext-llm_used = iv_llm_used.
    rs_ext-model_id = zcl_mdmdoc_norm=>field_value(
      it_fields = it_llm_fields iv_name = `_model` ).

    " start from the LLM fields (minus the meta '_model'/'doc_type' entries)
    rs_ext-fields = it_llm_fields.
    DELETE rs_ext-fields WHERE name = `_model`.
    DELETE rs_ext-fields WHERE name = `doc_type`.

    " echo/noise guards BEFORE the ID crosscheck (Python stage_b order: a
    " dropped echo/date-shaped TIN leaves a gap the detectors then refill)
    drop_filename_echo( EXPORTING iv_filename = iv_filename
                                  iv_raw_text = iv_raw_text
                        CHANGING  cs_ext = rs_ext ).
    drop_regulator_noise( CHANGING cs_ext = rs_ext ).
    normalize_tin( CHANGING cs_ext = rs_ext ).

    " deterministic ID overlay, scoped by doc class
    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank.
      crosscheck_bank( EXPORTING it_candidates = it_candidates
                       CHANGING  cs_ext = rs_ext ).
    ELSEIF iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9.
      crosscheck_w9( EXPORTING it_candidates = it_candidates
                     CHANGING  cs_ext = rs_ext ).
    ENDIF.

    " field normalization (bank_country -> ISO2, flags -> 'true'/'false', trim)
    normalize_fields( CHANGING cs_ext = rs_ext ).

    " deterministic audit guards (mirror of Python stage_b — see PARITY.md GUARDS);
    " run AFTER crosscheck+normalize and BEFORE secret registration, Python order
    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank.
      audit_bank_ids(       EXPORTING iv_raw_text = iv_raw_text CHANGING cs_ext = rs_ext ).
      fix_jp_form(          EXPORTING iv_raw_text = iv_raw_text CHANGING cs_ext = rs_ext ).
      fix_statement_period( EXPORTING iv_raw_text = iv_raw_text CHANGING cs_ext = rs_ext ).
      esignature_guard(     EXPORTING iv_raw_text = iv_raw_text CHANGING cs_ext = rs_ext ).
    ENDIF.

    " secrets = full values of every sensitive field present
    register_secrets( CHANGING cs_ext = rs_ext ).
  ENDMETHOD.


  METHOD cross_note.
    READ TABLE cs_ext-crosscheck TRANSPORTING NO FIELDS
         WITH KEY table_line = iv_note.
    IF sy-subrc <> 0.
      APPEND iv_note TO cs_ext-crosscheck.
    ENDIF.
  ENDMETHOD.


  METHOD audit_bank_ids.
    " [GUARD:audit_bank_ids] mirror of Python stage_b._audit_bank_ids:
    " - a value in the iban field that is NOT IBAN-shaped (2 letters + 2 digits)
    "   is a plain account number (US etc. print account numbers under an
    "   'IBAN account no.' label) -> relocate/clear, never BNK-011;
    " - a checksum-failing IBAN is REPAIRED from the raw text when the text
    "   holds exactly one valid same-country (same-tail preferred) IBAN;
    " - the IBAN mod-97 checksum is stated out loud (audit fact, not silence);
    " - routing fields hold 9-digit US ABA numbers ONLY; Italian ABI/CAB move
    "   into a crosscheck note, verified against the IBAN structure, and CAB
    "   doubles as branch_code;
    " - the printed account number wins over the zero-padded IBAN part.
    DATA(lv_iban) = to_upper(
      zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields iv_name = `iban` ) ).
    REPLACE ALL OCCURRENCES OF REGEX `[[:space:]]` IN lv_iban WITH ``.

    " not-IBAN-shaped relocation (no IBAN in this country)
    IF lv_iban IS NOT INITIAL.
      FIND REGEX `^[A-Z]{2}[0-9]{2}` IN lv_iban.
      IF sy-subrc <> 0.
        DATA(lv_digits) = zcl_mdmdoc_norm=>digits_only( lv_iban ).
        DATA(lv_acct0) = zcl_mdmdoc_norm=>digits_only(
          zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields iv_name = `account_number` ) ).
        IF lv_digits IS NOT INITIAL AND lv_acct0 IS INITIAL.
          set_field( EXPORTING iv_name = `account_number` iv_value = lv_digits
                     CHANGING  ct_fields = cs_ext-fields ).
          cross_note( EXPORTING iv_note = `the IBAN-field value is a plain account number `
                                       && `(this country has no IBAN) — moved to account number`
                      CHANGING  cs_ext = cs_ext ).
        ELSEIF lv_digits IS NOT INITIAL AND lv_digits = lv_acct0.
          cross_note( EXPORTING iv_note = `the IBAN field duplicated the account number (no IBAN in this country) — cleared`
                      CHANGING  cs_ext = cs_ext ).
        ELSE.
          cross_note( EXPORTING iv_note = `the IBAN-field value is a plain account number (this country has no IBAN), not a malformed IBAN`
                      CHANGING  cs_ext = cs_ext ).
        ENDIF.
        set_field( EXPORTING iv_name = `iban` iv_value = ``
                   CHANGING  ct_fields = cs_ext-fields ).
        CLEAR lv_iban.
      ENDIF.
    ENDIF.

    " repair a checksum-failing IBAN from the document text (the DOCUMENT is
    " the authority): same country code, same last-4 tail preferred, and only
    " when the text yields exactly ONE such candidate
    IF lv_iban IS NOT INITIAL
       AND zcl_mdmdoc_norm=>iban_mod97_ok( lv_iban ) = abap_false.
      DATA(lt_cands) = find_valid_ibans( iv_raw_text ).
      DATA lt_pick TYPE string_table.
      DATA lt_tail TYPE string_table.
      DATA(lv_cc) = lv_iban(2).
      DATA(lv_tail4) = COND string(
        WHEN strlen( lv_iban ) >= 4
        THEN substring( val = lv_iban off = strlen( lv_iban ) - 4 len = 4 ) ).
      LOOP AT lt_cands INTO DATA(lv_cand).
        IF strlen( lv_cand ) >= 4 AND lv_cand(2) = lv_cc.
          APPEND lv_cand TO lt_pick.
          IF substring( val = lv_cand off = strlen( lv_cand ) - 4 len = 4 ) = lv_tail4.
            APPEND lv_cand TO lt_tail.
          ENDIF.
        ENDIF.
      ENDLOOP.
      IF lines( lt_tail ) > 0.
        lt_pick = lt_tail.
      ENDIF.
      IF lines( lt_pick ) = 1.
        READ TABLE lt_pick INDEX 1 INTO DATA(lv_fixed).
        IF lv_fixed <> lv_iban.
          set_field( EXPORTING iv_name = `iban` iv_value = lv_fixed
                     CHANGING  ct_fields = cs_ext-fields ).
          cross_note( EXPORTING iv_note = `iban repaired from the document text (model read failed the mod-97 checksum)`
                      CHANGING  cs_ext = cs_ext ).
          lv_iban = lv_fixed.
        ENDIF.
      ENDIF.
    ENDIF.

    " checksum stated out loud
    IF lv_iban IS NOT INITIAL.
      IF zcl_mdmdoc_norm=>iban_mod97_ok( lv_iban ) = abap_true.
        cross_note( EXPORTING iv_note = `iban checksum (ISO 13616 mod-97): valid`
                    CHANGING  cs_ext = cs_ext ).
      ELSE.
        cross_note( EXPORTING iv_note = `iban checksum (ISO 13616 mod-97): INVALID`
                    CHANGING  cs_ext = cs_ext ).
      ENDIF.
    ENDIF.

    " routing fields: 9-digit US ABA only; ABI/CAB -> note + branch_code
    DATA lt_domestic TYPE string_table.
    DATA lt_rkeys TYPE string_table.
    SPLIT `routing_aba,routing_aba_wires` AT `,` INTO TABLE lt_rkeys.
    LOOP AT lt_rkeys INTO DATA(lv_rk).
      DATA(lv_rv) = zcl_mdmdoc_norm=>digits_only(
        zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields iv_name = lv_rk ) ).
      IF lv_rv IS NOT INITIAL AND strlen( lv_rv ) <> 9.
        APPEND lv_rv TO lt_domestic.
        set_field( EXPORTING iv_name = lv_rk iv_value = ``
                   CHANGING  ct_fields = cs_ext-fields ).
      ENDIF.
    ENDLOOP.
    IF lines( lt_domestic ) > 0.
      DATA(lv_codes) = concat_lines_of( table = lt_domestic sep = `/` ).
      IF lv_iban IS NOT INITIAL AND strlen( lv_iban ) >= 15 AND lv_iban(2) = `IT`.
        DATA(lv_abi) = lv_iban+5(5).
        DATA(lv_cab) = lv_iban+10(5).
        DATA(lv_all_match) = abap_true.
        LOOP AT lt_domestic INTO DATA(lv_d).
          IF lv_d <> lv_abi AND lv_d <> lv_cab.
            lv_all_match = abap_false.
          ENDIF.
        ENDLOOP.
        IF lv_all_match = abap_true.
          cross_note( EXPORTING iv_note = |domestic bank codes { lv_codes } (ABI/CAB, not ABA): match the IBAN structure|
                      CHANGING  cs_ext = cs_ext ).
        ELSE.
          cross_note( EXPORTING iv_note = |domestic bank codes { lv_codes } (ABI/CAB, not ABA): |
                                       && |do NOT match the IBAN structure (ABI { lv_abi } / CAB { lv_cab })|
                      CHANGING  cs_ext = cs_ext ).
        ENDIF.
        IF zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields
                                         iv_name = `branch_code` ) IS INITIAL.
          set_field( EXPORTING iv_name = `branch_code` iv_value = lv_cab
                     CHANGING  ct_fields = cs_ext-fields ).
        ENDIF.
      ELSE.
        cross_note( EXPORTING iv_note = |domestic bank code(s) (not a US ABA), removed from routing fields: { lv_codes }|
                    CHANGING  cs_ext = cs_ext ).
      ENDIF.
    ENDIF.

    " printed account number beats the zero-padded IBAN account part
    DATA(lv_acct) = zcl_mdmdoc_norm=>digits_only(
      zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields iv_name = `account_number` ) ).
    IF lv_iban IS NOT INITIAL AND lv_acct IS NOT INITIAL.
      DATA(lv_stripped) = lstrip_zeros( lv_acct ).
      DATA(lv_alen) = strlen( lv_acct ).
      DATA(lv_ilen) = strlen( lv_iban ).
      IF lv_stripped <> lv_acct AND lv_stripped IS NOT INITIAL
         AND lv_ilen >= lv_alen
         AND substring( val = lv_iban off = lv_ilen - lv_alen len = lv_alen ) = lv_acct
         AND iv_raw_text CS lv_stripped.
        set_field( EXPORTING iv_name = `account_number` iv_value = lv_stripped
                   CHANGING  ct_fields = cs_ext-fields ).
        cross_note( EXPORTING iv_note = |account number: printed form { lv_stripped } (IBAN account part is the zero-padded { lv_acct })|
                    CHANGING  cs_ext = cs_ext ).
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD find_valid_ibans.
    " fields.find_valid_ibans: spaced/full-width prints tolerated, mod-97-valid
    " only, unique, document order.
    DATA(lv_text) = to_upper( zcl_mdmdoc_norm=>translate_fullwidth( iv_text ) ).
    DATA(lv_off) = 0.
    DATA(lv_len) = strlen( lv_text ).
    WHILE lv_off < lv_len.
      FIND REGEX `\b[A-Z]{2}[[:space:]]?[0-9]{2}([[:space:]]?[A-Z0-9]){10,32}\b`
           IN SECTION OFFSET lv_off OF lv_text
           MATCH OFFSET DATA(lv_mo) MATCH LENGTH DATA(lv_ml).
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      DATA(lv_cand) = lv_text+lv_mo(lv_ml).
      REPLACE ALL OCCURRENCES OF REGEX `[[:space:]]` IN lv_cand WITH ``.
      IF zcl_mdmdoc_norm=>iban_mod97_ok( lv_cand ) = abap_true.
        READ TABLE rt_ibans TRANSPORTING NO FIELDS WITH KEY table_line = lv_cand.
        IF sy-subrc <> 0.
          APPEND lv_cand TO rt_ibans.
        ENDIF.
      ENDIF.
      lv_off = lv_mo + lv_ml.
    ENDWHILE.
  ENDMETHOD.


  METHOD fix_jp_form.
    " [GUARD:fix_jp_form] mirror of Python stage_b._fix_jp_form: JP documents
    " print digits full-width; a 〒NNN-NNNN value is a POSTAL CODE, not an
    " account; labeled 口座番号/支店 fields rescue the real values; country is
    " inferable; on split-stream forms the account value precedes the bank name.
    IF iv_raw_text IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_text) = zcl_mdmdoc_norm=>translate_fullwidth( iv_raw_text ).
    IF NOT ( lv_text CS `〒` OR lv_text CS `口座` ).
      RETURN.
    ENDIF.

    " postal-code guard: account equal to the 〒 postal code is wrong
    DATA(lv_acct) = zcl_mdmdoc_norm=>digits_only(
      zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields iv_name = `account_number` ) ).
    IF strlen( lv_acct ) = 7.
      DATA(lv_pat) = `〒[[:space:]]*` && lv_acct(3) && `[-‐−–]?[[:space:]]*` && lv_acct+3(4).
      FIND REGEX lv_pat IN lv_text.
      IF sy-subrc = 0.
        APPEND |account_number …{ lv_acct+3(4) } equalled the postal code (〒) — dropped|
               TO cs_ext-warnings.
        set_field( EXPORTING iv_name = `account_number` iv_value = ``
                   CHANGING  ct_fields = cs_ext-fields ).
        CLEAR lv_acct.
      ENDIF.
    ENDIF.

    " labeled 口座番号 / Account Number rescue
    IF zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields
                                     iv_name = `account_number` ) IS INITIAL.
      FIND REGEX `(口座番号|Account[[:space:]]*Number)[^0-9]{0,20}([0-9]{4,10})`
           IN lv_text SUBMATCHES DATA(lv_lbl) DATA(lv_num).
      IF sy-subrc = 0.
        set_field( EXPORTING iv_name = `account_number` iv_value = lv_num
                   CHANGING  ct_fields = cs_ext-fields ).
        cross_note( EXPORTING iv_note = `account number taken from the labeled 口座番号/Account Number field`
                    CHANGING  cs_ext = cs_ext ).
      ENDIF.
    ENDIF.

    " split-stream forms: the account value precedes the bank-name token; a
    " postal-like token AFTER the bank name must not win
    DATA(lv_cur) = zcl_mdmdoc_norm=>digits_only(
      zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields iv_name = `account_number` ) ).
    DATA(lv_bank_pos) = find( val = lv_text sub = `銀行` ).
    IF lv_cur IS NOT INITIAL AND strlen( lv_cur ) BETWEEN 6 AND 8 AND lv_bank_pos > 0.
      DATA(lv_cur_pos) = find( val = lv_text sub = lv_cur ).
      IF lv_cur_pos > lv_bank_pos.
        DATA(lv_head) = substring( val = lv_text off = 0 len = lv_bank_pos ).
        DATA lt_cands TYPE string_table.
        DATA(lv_hoff) = 0.
        DO.
          FIND REGEX `\b[0-9]{6,8}\b` IN SECTION OFFSET lv_hoff OF lv_head
               MATCH OFFSET DATA(lv_ho) MATCH LENGTH DATA(lv_hl).
          IF sy-subrc <> 0.
            EXIT.
          ENDIF.
          DATA(lv_tok) = lv_head+lv_ho(lv_hl).
          IF lv_tok <> lv_cur.
            READ TABLE lt_cands TRANSPORTING NO FIELDS WITH KEY table_line = lv_tok.
            IF sy-subrc <> 0.
              APPEND lv_tok TO lt_cands.
            ENDIF.
          ENDIF.
          lv_hoff = lv_ho + lv_hl.
        ENDDO.
        IF lines( lt_cands ) = 1.
          READ TABLE lt_cands INDEX 1 INTO DATA(lv_new).
          DATA(lv_new_t4) = substring( val = lv_new off = strlen( lv_new ) - 4 len = 4 ).
          DATA(lv_cur_t4) = substring( val = lv_cur off = strlen( lv_cur ) - 4 len = 4 ).
          APPEND |account_number …{ lv_cur_t4 } sits after the bank name (address zone) — |
              && |took …{ lv_new_t4 } from the form-value stream instead; verify|
                 TO cs_ext-warnings.
          set_field( EXPORTING iv_name = `account_number` iv_value = lv_new
                     CHANGING  ct_fields = cs_ext-fields ).
        ENDIF.
      ENDIF.
    ENDIF.

    " branch number (支店 / Branch)
    IF zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields
                                     iv_name = `branch_code` ) IS INITIAL.
      FIND REGEX `(支店番号|支店コード|支店名|支店|Branch[[:space:]]*(Name/number|Number|No\.?|Code)?)[[:space:]]*[:：]?[[:space:]]*0?([0-9]{3})\b`
           IN lv_text SUBMATCHES DATA(lv_b1) DATA(lv_b2) DATA(lv_bnum).
      IF sy-subrc = 0.
        set_field( EXPORTING iv_name = `branch_code` iv_value = lv_bnum
                   CHANGING  ct_fields = cs_ext-fields ).
      ENDIF.
    ENDIF.

    " 普通 (ordinary account) + JP country inference
    IF lv_text CS `普通`
       AND zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields
                                         iv_name = `account_type` ) IS INITIAL.
      set_field( EXPORTING iv_name = `account_type` iv_value = `普通口座 (ordinary account)`
                 CHANGING  ct_fields = cs_ext-fields ).
    ENDIF.
    IF zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields
                                     iv_name = `bank_country` ) IS INITIAL.
      set_field( EXPORTING iv_name = `bank_country` iv_value = `JP`
                 CHANGING  ct_fields = cs_ext-fields ).
      cross_note( EXPORTING iv_note = `bank country inferred: JP (Japanese domestic form markers)`
                  CHANGING  cs_ext = cs_ext ).
    ENDIF.
  ENDMETHOD.


  METHOD esignature_guard.
    " [GUARD:esignature_guard] mirror of Python stage_b._esignature_guard:
    " a DocuSign/Adobe-Sign envelope IS a signature (electronic) — 'unsigned'
    " would be wrong; the timestamp near it is the signing date.
    IF iv_raw_text IS INITIAL.
      RETURN.
    ENDIF.
    IF zcl_mdmdoc_norm=>field_is_true( it_fields = cs_ext-fields
                                       iv_name = `signed` ) = abap_true.
      RETURN.
    ENDIF.
    DATA(lv_low) = to_lower( iv_raw_text ).
    IF lv_low CS `docusign envelope` OR lv_low CS `docusigned by`
       OR lv_low CS `adobe sign`.
      set_field( EXPORTING iv_name = `signed` iv_value = `true`
                 CHANGING  ct_fields = cs_ext-fields ).
      set_field( EXPORTING iv_name = `signature_evidence`
                 iv_value = `electronically signed (DocuSign/e-signature envelope present)`
                 CHANGING  ct_fields = cs_ext-fields ).
      IF zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields
                                       iv_name = `doc_date` ) IS INITIAL.
        FIND REGEX `([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]*\|[[:space:]]*[0-9]{1,2}:[0-9]{2}`
             IN iv_raw_text SUBMATCHES DATA(lv_date).
        IF sy-subrc = 0.
          set_field( EXPORTING iv_name = `doc_date` iv_value = lv_date
                     CHANGING  ct_fields = cs_ext-fields ).
        ENDIF.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD fix_statement_period.
    " [GUARD:fix_statement_period] mirror of Python stage_b._fix_statement_period:
    " a statement's date IS its period — rescue it when doc_date came back empty.
    IF iv_raw_text IS INITIAL OR cs_ext-doc_type <> `bank_statement`.
      RETURN.
    ENDIF.
    IF zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields
                                     iv_name = `doc_date` ) IS NOT INITIAL.
      RETURN.
    ENDIF.
    FIND REGEX `([0-9]{1,2}[- ]?[A-Za-z]{3}[- ]?[0-9]{4})[[:space:]]*`
            && `(to|through|–|—|-)[[:space:]]*([0-9]{1,2}[- ]?[A-Za-z]{3}[- ]?[0-9]{4})`
         IN iv_raw_text SUBMATCHES DATA(lv_from) DATA(lv_sep) DATA(lv_to).
    IF sy-subrc = 0.
      set_field( EXPORTING iv_name = `doc_date` iv_value = |{ lv_from } to { lv_to }|
                 CHANGING  ct_fields = cs_ext-fields ).
      cross_note( EXPORTING iv_note = `document date = statement period`
                  CHANGING  cs_ext = cs_ext ).
    ENDIF.
  ENDMETHOD.


  METHOD drop_regulator_noise.
    " [GUARD:drop_regulator_noise] mirror of Python stage_b._drop_regulator_noise:
    " regulator watermarks (e.g. Colombia's margin stamp 'VIGILADO
    " Superintendencia Financiera') get read as the bank name — drop them.
    DATA(lv_bank) = zcl_mdmdoc_norm=>field_value(
      it_fields = cs_ext-fields iv_name = `bank_name` ).
    IF lv_bank IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_low) = to_lower( lv_bank ).
    IF lv_low CS `vigilado` OR lv_low CS `superintendencia`
       OR lv_low CS `supervised by` OR lv_low CS `regulated by`.
      APPEND |bank_name '{ lv_bank }' looks like a regulator watermark — dropped|
             TO cs_ext-warnings.
      set_field( EXPORTING iv_name = `bank_name` iv_value = ``
                 CHANGING  ct_fields = cs_ext-fields ).
    ENDIF.
  ENDMETHOD.


  METHOD drop_filename_echo.
    " [GUARD:drop_filename_echo] mirror of Python stage_b._drop_filename_echo:
    " a NAME value that occurs in the file name but nowhere in the document
    " text was lifted from the filename, not read from the form — drop it.
    " (basename split covers both / and \ — SAP GUI uploads carry Windows paths)
    IF iv_filename IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_base) = iv_filename.
    REPLACE ALL OCCURRENCES OF `\` IN lv_base WITH `/`.
    SPLIT lv_base AT `/` INTO TABLE DATA(lt_seg).
    READ TABLE lt_seg INDEX lines( lt_seg ) INTO lv_base.
    DATA(lv_fname) = to_lower( lv_base ).
    DATA(lv_text)  = to_lower( iv_raw_text ).
    DATA lt_names TYPE string_table.
    SPLIT `line1_name,line2_business_name,account_holder,bank_name` AT `,`
          INTO TABLE lt_names.
    LOOP AT lt_names INTO DATA(lv_k).
      DATA(lv_s) = zcl_mdmdoc_norm=>field_value(
        it_fields = cs_ext-fields iv_name = lv_k ).
      SHIFT lv_s LEFT DELETING LEADING ` `.
      SHIFT lv_s RIGHT DELETING TRAILING ` `.
      SHIFT lv_s LEFT DELETING LEADING ` `.
      DATA(lv_low) = to_lower( lv_s ).
      IF strlen( lv_s ) >= 4 AND lv_fname CS lv_low AND NOT lv_text CS lv_low.
        set_field( EXPORTING iv_name = lv_k iv_value = ``
                   CHANGING  ct_fields = cs_ext-fields ).
        APPEND |{ lv_k }: dropped filename echo ('{ lv_s }' appears in the file name but not in the document)|
               TO cs_ext-warnings.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD normalize_tin.
    " [GUARD:normalize_tin] mirror of Python stage_b._normalize_tin: tin_type
    " to canonical SSN/EIN/''; a DATE can never be a TIN (the model kept
    " grabbing the signature date as a tax number) — a slash-date moves to
    " sign_date when that is empty.
    IF cs_ext-doc_class <> zif_mdmdoc_types=>c_doc_class-w9.
      RETURN.
    ENDIF.
    DATA(lv_tt) = to_lower( zcl_mdmdoc_norm=>field_value(
      it_fields = cs_ext-fields iv_name = `tin_type` ) ).
    IF lv_tt CS `ssn` OR lv_tt CS `social`.
      set_field( EXPORTING iv_name = `tin_type` iv_value = `SSN`
                 CHANGING  ct_fields = cs_ext-fields ).
    ELSEIF lv_tt CS `ein` OR lv_tt CS `employer`.
      set_field( EXPORTING iv_name = `tin_type` iv_value = `EIN`
                 CHANGING  ct_fields = cs_ext-fields ).
    ELSE.
      set_field( EXPORTING iv_name = `tin_type` iv_value = ``
                 CHANGING  ct_fields = cs_ext-fields ).
    ENDIF.
    DATA(lv_tin) = zcl_mdmdoc_norm=>field_value(
      it_fields = cs_ext-fields iv_name = `tin_raw` ).
    SHIFT lv_tin LEFT DELETING LEADING ` `.
    SHIFT lv_tin RIGHT DELETING TRAILING ` `.
    SHIFT lv_tin LEFT DELETING LEADING ` `.
    IF lv_tin IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_datey) = abap_false.
    IF lv_tin CS `/`.
      lv_datey = abap_true.
    ELSE.
      FIND REGEX `^[[:space:]]*[0-9]{1,2}[/.\-][0-9]{1,2}[/.\-][0-9]{2,4}[[:space:]]*$`
           IN lv_tin.
      IF sy-subrc = 0.
        lv_datey = abap_true.
      ENDIF.
    ENDIF.
    IF lv_datey = abap_true.
      APPEND `model put a date-shaped value into tin_raw — discarded`
             TO cs_ext-warnings.
      IF zcl_mdmdoc_norm=>field_value( it_fields = cs_ext-fields
                                       iv_name = `sign_date` ) IS INITIAL
         AND lv_tin CS `/`.
        set_field( EXPORTING iv_name = `sign_date` iv_value = lv_tin
                   CHANGING  ct_fields = cs_ext-fields ).
      ENDIF.
      set_field( EXPORTING iv_name = `tin_raw` iv_value = ``
                 CHANGING  ct_fields = cs_ext-fields ).
    ENDIF.
  ENDMETHOD.


  METHOD set_field.
    READ TABLE ct_fields ASSIGNING FIELD-SYMBOL(<f>) WITH KEY name = iv_name.
    IF sy-subrc = 0.
      <f>-value = iv_value.
    ELSE.
      INSERT VALUE #( name = iv_name value = iv_value ) INTO TABLE ct_fields.
    ENDIF.
  ENDMETHOD.


  METHOD lstrip_zeros.
    rv_out = iv_value.
    WHILE strlen( rv_out ) > 0 AND rv_out(1) = `0`.
      rv_out = rv_out+1.
    ENDWHILE.
  ENDMETHOD.


  METHOD masked.
    DATA(lv_kind) = zcl_mdmdoc_mask=>kind_for_field( iv_field ).
    " policy 'masked': bank kinds masked, TIN kinds masked regardless
    rv_out = zcl_mdmdoc_mask=>display_value(
      iv_kind  = lv_kind
      iv_value = iv_value
      iv_policy = zif_mdmdoc_types=>c_policy-masked ).
  ENDMETHOD.


  METHOD crosscheck_bank.
    DATA lt_ids TYPE string_table.
    SPLIT c_id_fields AT `,` INTO TABLE lt_ids.

    LOOP AT lt_ids INTO DATA(lv_k).
      " regex candidate value for this ID field
      DATA(lv_dv) = zcl_mdmdoc_norm=>field_value(
        it_fields = it_candidates iv_name = lv_k ).
      IF lv_dv IS INITIAL.
        CONTINUE.
      ENDIF.

      " model-read value (already in cs_ext-fields)
      DATA(lv_mv) = zcl_mdmdoc_norm=>field_value(
        it_fields = cs_ext-fields iv_name = lv_k ).

      DATA(lv_note) = ``.
      IF lv_mv IS INITIAL.
        " blank model field + candidate -> fill from regex
        set_field( EXPORTING iv_name = lv_k iv_value = lv_dv
                   CHANGING  ct_fields = cs_ext-fields ).
        lv_note = |{ lv_k }=filled-from-regex({ masked( iv_field = lv_k iv_value = lv_dv ) })|.
        APPEND lv_note TO cs_ext-crosscheck.

      ELSEIF zcl_mdmdoc_norm=>norm_id( lv_mv ) = zcl_mdmdoc_norm=>norm_id( lv_dv ).
        " both present and norm_id-equal -> confirmed
        lv_note = |{ lv_k }=confirmed|.
        APPEND lv_note TO cs_ext-crosscheck.

      ELSEIF lv_k = `account_number`
             AND lstrip_zeros( zcl_mdmdoc_norm=>norm_id( lv_mv ) ) IS NOT INITIAL
             AND lstrip_zeros( zcl_mdmdoc_norm=>norm_id( lv_mv ) )
                 = lstrip_zeros( zcl_mdmdoc_norm=>norm_id( lv_dv ) ).
        " printed account vs zero-padded variant — same account
        lv_note = |{ lv_k }=confirmed (zero-padded variant)|.
        APPEND lv_note TO cs_ext-crosscheck.

      ELSE.
        " different -> candidate (regex) WINS + mismatch note + warning line
        DATA(lv_masked_m) = masked( iv_field = lv_k iv_value = lv_mv ).
        DATA(lv_masked_d) = masked( iv_field = lv_k iv_value = lv_dv ).
        set_field( EXPORTING iv_name = lv_k iv_value = lv_dv
                   CHANGING  ct_fields = cs_ext-fields ).
        lv_note = |{ lv_k }=MISMATCH(model={ lv_masked_m } vs regex={ lv_masked_d })|.
        APPEND lv_note TO cs_ext-crosscheck.
        APPEND |{ lv_k }: regex overrode model read ({ lv_note })| TO cs_ext-warnings.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD crosscheck_w9.
    " EIN candidate settles the TIN (deterministic, label/format anchored)
    DATA(lv_ein) = zcl_mdmdoc_norm=>field_value(
      it_fields = it_candidates iv_name = `ein` ).
    IF lv_ein IS NOT INITIAL.
      DATA(lv_tin) = zcl_mdmdoc_norm=>field_value(
        it_fields = cs_ext-fields iv_name = `tin_raw` ).
      IF lv_tin IS INITIAL.
        set_field( EXPORTING iv_name = `tin_raw` iv_value = lv_ein
                   CHANGING  ct_fields = cs_ext-fields ).
        APPEND |tin=filled-from-regex({ zcl_mdmdoc_mask=>mask( iv_kind = zif_mdmdoc_types=>c_kind-ein iv_value = lv_ein ) })|
               TO cs_ext-crosscheck.
        lv_tin = lv_ein.
      ENDIF.
      IF zcl_mdmdoc_norm=>norm_id( lv_tin ) = zcl_mdmdoc_norm=>norm_id( lv_ein ).
        DATA(lv_tt) = to_upper( zcl_mdmdoc_norm=>field_value(
          it_fields = cs_ext-fields iv_name = `tin_type` ) ).
        IF lv_tt <> `EIN`.
          APPEND `tin_type=EIN (settled by the EIN detector)` TO cs_ext-crosscheck.
        ENDIF.
        set_field( EXPORTING iv_name = `tin_type` iv_value = `EIN`
                   CHANGING  ct_fields = cs_ext-fields ).
      ENDIF.
    ENDIF.

    " W-9 digit boxes (one digit per line in the text layer)
    DATA(lv_boxed) = zcl_mdmdoc_norm=>field_value(
      it_fields = it_candidates iv_name = `tin_boxed` ).
    IF lv_boxed IS NOT INITIAL.
      DATA(lv_tin2) = zcl_mdmdoc_norm=>field_value(
        it_fields = cs_ext-fields iv_name = `tin_raw` ).
      IF lv_tin2 IS INITIAL.
        set_field( EXPORTING iv_name = `tin_raw` iv_value = lv_boxed
                   CHANGING  ct_fields = cs_ext-fields ).
        APPEND |tin=filled-from-boxed-digits({ zcl_mdmdoc_mask=>mask( iv_kind = zif_mdmdoc_types=>c_kind-tin iv_value = lv_boxed ) })|
               TO cs_ext-crosscheck.
        lv_tin2 = lv_boxed.
      ENDIF.
      DATA(lv_boxed_type) = zcl_mdmdoc_norm=>field_value(
        it_fields = it_candidates iv_name = `tin_boxed_type` ).
      IF lv_boxed_type IS NOT INITIAL
         AND zcl_mdmdoc_norm=>norm_id( lv_tin2 ) = zcl_mdmdoc_norm=>norm_id( lv_boxed ).
        DATA(lv_tt2) = to_upper( zcl_mdmdoc_norm=>field_value(
          it_fields = cs_ext-fields iv_name = `tin_type` ) ).
        IF lv_tt2 <> to_upper( lv_boxed_type ).
          APPEND |tin_type={ lv_boxed_type } (settled by the { lv_boxed_type } box label)|
                 TO cs_ext-crosscheck.
        ENDIF.
        set_field( EXPORTING iv_name = `tin_type` iv_value = lv_boxed_type
                   CHANGING  ct_fields = cs_ext-fields ).
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD normalize_fields.
    " trim all values; bank_country -> ISO2; signed/partial_capture -> 'true'/'false'
    LOOP AT cs_ext-fields ASSIGNING FIELD-SYMBOL(<f>).
      " Python .strip() — leading/trailing ASCII whitespace only
      DATA(lv_v) = <f>-value.
      SHIFT lv_v LEFT  DELETING LEADING ` `.
      SHIFT lv_v RIGHT DELETING TRAILING ` `.
      SHIFT lv_v LEFT  DELETING LEADING ` `.
      <f>-value = lv_v.
    ENDLOOP.

    " bank_country -> ISO2 (only when it resolves; keep raw otherwise)
    READ TABLE cs_ext-fields ASSIGNING <f> WITH KEY name = `bank_country`.
    IF sy-subrc = 0 AND <f>-value IS NOT INITIAL.
      DATA(lv_iso2) = zcl_mdmdoc_norm=>to_iso2( <f>-value ).
      IF lv_iso2 IS NOT INITIAL.
        <f>-value = lv_iso2.
      ENDIF.
    ENDIF.

    " signed / partial_capture -> canonical 'true'/'false' strings
    READ TABLE cs_ext-fields ASSIGNING <f> WITH KEY name = `signed`.
    IF sy-subrc = 0.
      <f>-value = COND string(
        WHEN zcl_mdmdoc_norm=>norm_flag( <f>-value ) = abap_true THEN `true` ELSE `false` ).
    ENDIF.
    READ TABLE cs_ext-fields ASSIGNING <f> WITH KEY name = `partial_capture`.
    IF sy-subrc = 0.
      <f>-value = COND string(
        WHEN zcl_mdmdoc_norm=>norm_flag( <f>-value ) = abap_true THEN `true` ELSE `false` ).
    ENDIF.
  ENDMETHOD.


  METHOD register_secrets.
    DATA lt_keys TYPE string_table.
    IF cs_ext-doc_class = zif_mdmdoc_types=>c_doc_class-bank.
      SPLIT c_secret_bank AT `,` INTO TABLE lt_keys.
    ELSE.
      SPLIT c_secret_w9 AT `,` INTO TABLE lt_keys.
    ENDIF.

    LOOP AT lt_keys INTO DATA(lv_key).
      DATA(lv_val) = zcl_mdmdoc_norm=>field_value(
        it_fields = cs_ext-fields iv_name = lv_key ).
      IF lv_val IS NOT INITIAL.
        APPEND lv_val TO cs_ext-secrets.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
