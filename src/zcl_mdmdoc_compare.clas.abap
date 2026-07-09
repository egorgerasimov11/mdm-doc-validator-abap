CLASS zcl_mdmdoc_compare DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Source-independent port of sap_compare.py: deterministic field-by-field
    " comparison of the extracted document against a SAP-side field set
    " (SAP_KEYS). Produces findings (SAP-000..008) + display rows. Both sides
    " are masked via zcl_mdmdoc_mask; full sensitive values never leave here.
    CLASS-METHODS compare
      IMPORTING is_ext      TYPE zif_mdmdoc_types=>ty_extraction
                it_sap      TYPE zif_mdmdoc_types=>tt_sap_fields
                iv_policy   TYPE string DEFAULT 'masked'
      EXPORTING et_findings TYPE zif_mdmdoc_types=>tt_findings
                et_rows     TYPE zif_mdmdoc_types=>tt_compare_row.

  PRIVATE SECTION.
    CLASS-METHODS doc
      IMPORTING is_ext          TYPE zif_mdmdoc_types=>ty_extraction
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS sap
      IMPORTING it_sap          TYPE zif_mdmdoc_types=>tt_sap_fields
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS norm_name
      IMPORTING iv_value        TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS first_diff
      IMPORTING iv_a          TYPE string
                iv_b          TYPE string
      RETURNING VALUE(rv_pos) TYPE i.

    CLASS-METHODS dv
      IMPORTING iv_kind      TYPE string
                iv_value     TYPE string
                iv_policy    TYPE string
      RETURNING VALUE(rv_out) TYPE string.

    CLASS-METHODS add_row
      IMPORTING iv_field  TYPE string
                iv_doc    TYPE string
                iv_sap    TYPE string
                iv_status TYPE string
                iv_note   TYPE string DEFAULT ''
      CHANGING  ct_rows   TYPE zif_mdmdoc_types=>tt_compare_row.

    CLASS-METHODS finding
      IMPORTING iv_id     TYPE string
                iv_sev    TYPE string
                iv_effect TYPE string
                iv_msg    TYPE string
                iv_field  TYPE string DEFAULT ''
      CHANGING  ct_find   TYPE zif_mdmdoc_types=>tt_findings.

    CLASS-METHODS cmp_iban
      IMPORTING is_ext    TYPE zif_mdmdoc_types=>ty_extraction
                it_sap    TYPE zif_mdmdoc_types=>tt_sap_fields
                iv_policy TYPE string
      CHANGING  ct_find   TYPE zif_mdmdoc_types=>tt_findings
                ct_rows   TYPE zif_mdmdoc_types=>tt_compare_row.

    CLASS-METHODS cmp_account
      IMPORTING is_ext    TYPE zif_mdmdoc_types=>ty_extraction
                it_sap    TYPE zif_mdmdoc_types=>tt_sap_fields
                iv_policy TYPE string
      CHANGING  ct_find   TYPE zif_mdmdoc_types=>tt_findings
                ct_rows   TYPE zif_mdmdoc_types=>tt_compare_row.

    CLASS-METHODS cmp_swift
      IMPORTING is_ext  TYPE zif_mdmdoc_types=>ty_extraction
                it_sap  TYPE zif_mdmdoc_types=>tt_sap_fields
      CHANGING  ct_find TYPE zif_mdmdoc_types=>tt_findings
                ct_rows TYPE zif_mdmdoc_types=>tt_compare_row.

    CLASS-METHODS cmp_country
      IMPORTING is_ext  TYPE zif_mdmdoc_types=>ty_extraction
                it_sap  TYPE zif_mdmdoc_types=>tt_sap_fields
      CHANGING  ct_find TYPE zif_mdmdoc_types=>tt_findings
                ct_rows TYPE zif_mdmdoc_types=>tt_compare_row.

    CLASS-METHODS cmp_bank_key
      IMPORTING is_ext    TYPE zif_mdmdoc_types=>ty_extraction
                it_sap    TYPE zif_mdmdoc_types=>tt_sap_fields
                iv_policy TYPE string
      CHANGING  ct_find   TYPE zif_mdmdoc_types=>tt_findings
                ct_rows   TYPE zif_mdmdoc_types=>tt_compare_row.

    CLASS-METHODS cmp_name
      IMPORTING iv_field  TYPE string
                iv_id     TYPE string
                iv_sev    TYPE string
                iv_effect TYPE string
                iv_doc    TYPE string
                iv_sap    TYPE string
      CHANGING  ct_find   TYPE zif_mdmdoc_types=>tt_findings
                ct_rows   TYPE zif_mdmdoc_types=>tt_compare_row.
ENDCLASS.


CLASS zcl_mdmdoc_compare IMPLEMENTATION.

  METHOD doc.
    rv_value = zcl_mdmdoc_norm=>field_value( it_fields = is_ext-fields iv_name = iv_name ).
  ENDMETHOD.

  METHOD sap.
    READ TABLE it_sap WITH KEY name = iv_name INTO DATA(ls).
    IF sy-subrc = 0.
      rv_value = ls-value.
    ENDIF.
  ENDMETHOD.

  METHOD norm_name.
    " _norm_name: casefold, punctuation -> space, collapse whitespace, trim
    rv_value = to_lower( iv_value ).
    REPLACE ALL OCCURRENCES OF REGEX `[^\w\s]` IN rv_value WITH ` `.
    REPLACE ALL OCCURRENCES OF REGEX `\s+` IN rv_value WITH ` `.
    CONDENSE rv_value.
  ENDMETHOD.

  METHOD first_diff.
    " 1-based position of the first differing char; if one is a prefix of the
    " other, the position just past the shorter string; 0 when equal.
    DATA(lv_la) = strlen( iv_a ).
    DATA(lv_lb) = strlen( iv_b ).
    DATA(lv_min) = COND i( WHEN lv_la < lv_lb THEN lv_la ELSE lv_lb ).
    DATA lv_i TYPE i.
    WHILE lv_i < lv_min.
      IF iv_a+lv_i(1) <> iv_b+lv_i(1).
        rv_pos = lv_i + 1.
        RETURN.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.
    IF lv_la <> lv_lb.
      rv_pos = lv_min + 1.
    ENDIF.
  ENDMETHOD.

  METHOD dv.
    IF iv_kind IS INITIAL.
      rv_out = iv_value.
    ELSE.
      rv_out = zcl_mdmdoc_mask=>display_value( iv_kind = iv_kind iv_value = iv_value iv_policy = iv_policy ).
    ENDIF.
  ENDMETHOD.

  METHOD add_row.
    APPEND VALUE #( field = iv_field doc = iv_doc sap = iv_sap status = iv_status note = iv_note ) TO ct_rows.
  ENDMETHOD.

  METHOD finding.
    APPEND VALUE #( rule_id = iv_id severity = iv_sev verdict_effect = iv_effect
                    message = iv_msg field = iv_field ) TO ct_find.
  ENDMETHOD.

  METHOD compare.
    CLEAR: et_findings, et_rows.

    cmp_iban(     EXPORTING is_ext = is_ext it_sap = it_sap iv_policy = iv_policy
                  CHANGING ct_find = et_findings ct_rows = et_rows ).
    cmp_account(  EXPORTING is_ext = is_ext it_sap = it_sap iv_policy = iv_policy
                  CHANGING ct_find = et_findings ct_rows = et_rows ).
    cmp_swift(    EXPORTING is_ext = is_ext it_sap = it_sap
                  CHANGING ct_find = et_findings ct_rows = et_rows ).
    cmp_country(  EXPORTING is_ext = is_ext it_sap = it_sap
                  CHANGING ct_find = et_findings ct_rows = et_rows ).
    cmp_bank_key( EXPORTING is_ext = is_ext it_sap = it_sap iv_policy = iv_policy
                  CHANGING ct_find = et_findings ct_rows = et_rows ).

    " bank name (WARNING) + account holder (CRITICAL), via _norm_name substring
    cmp_name( EXPORTING iv_field = 'Bank Name' iv_id = 'SAP-007'
                        iv_sev = zif_mdmdoc_types=>c_severity-warning
                        iv_effect = zif_mdmdoc_types=>c_verdict-warning
                        iv_doc = doc( is_ext = is_ext iv_name = 'bank_name' )
                        iv_sap = sap( it_sap = it_sap iv_name = 'bank_name' )
              CHANGING ct_find = et_findings ct_rows = et_rows ).
    DATA(lv_sap_holder) = sap( it_sap = it_sap iv_name = 'account_holder' ).
    IF lv_sap_holder IS INITIAL.
      lv_sap_holder = sap( it_sap = it_sap iv_name = 'account_name' ).
    ENDIF.
    cmp_name( EXPORTING iv_field = 'Account Holder' iv_id = 'SAP-008'
                        iv_sev = zif_mdmdoc_types=>c_severity-critical
                        iv_effect = zif_mdmdoc_types=>c_verdict-review
                        iv_doc = doc( is_ext = is_ext iv_name = 'account_holder' )
                        iv_sap = lv_sap_holder
              CHANGING ct_find = et_findings ct_rows = et_rows ).

    " SAP-only informational rows (no findings)
    DATA: BEGIN OF ls_info,
            key   TYPE string,
            label TYPE string,
          END OF ls_info.
    DATA lt_info LIKE STANDARD TABLE OF ls_info.
    lt_info = VALUE #( ( key = 'bank_details_id'   label = 'Bank Details ID' )
                       ( key = 'control_key'       label = 'Control Key' )
                       ( key = 'reference_details' label = 'Reference Details' )
                       ( key = 'city'              label = 'City' ) ).
    LOOP AT lt_info INTO ls_info.
      DATA(lv_iv) = sap( it_sap = it_sap iv_name = ls_info-key ).
      IF lv_iv IS NOT INITIAL.
        add_row( EXPORTING iv_field = ls_info-label iv_doc = `` iv_sap = lv_iv
                           iv_status = zif_mdmdoc_types=>c_cmp_status-sap_only
                 CHANGING ct_rows = et_rows ).
      ENDIF.
    ENDLOOP.

    " summary NOTE when nothing mismatched
    IF et_rows IS NOT INITIAL.
      DATA lv_has_mismatch TYPE abap_bool.
      LOOP AT et_rows TRANSPORTING NO FIELDS WHERE status = zif_mdmdoc_types=>c_cmp_status-mismatch.
        lv_has_mismatch = abap_true.
        EXIT.
      ENDLOOP.
      IF lv_has_mismatch = abap_false.
        finding( EXPORTING iv_id = 'SAP-000' iv_sev = zif_mdmdoc_types=>c_severity-note iv_effect = ``
                           iv_msg = 'SAP comparison: all comparable fields match.'
                 CHANGING ct_find = et_findings ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD cmp_iban.
    DATA(lv_d) = zcl_mdmdoc_norm=>norm_id( doc( is_ext = is_ext iv_name = 'iban' ) ).
    DATA(lv_s) = zcl_mdmdoc_norm=>norm_id( sap( it_sap = it_sap iv_name = 'iban' ) ).
    DATA(lv_dd) = dv( iv_kind = zif_mdmdoc_types=>c_kind-iban iv_value = lv_d iv_policy = iv_policy ).
    DATA(lv_sd) = dv( iv_kind = zif_mdmdoc_types=>c_kind-iban iv_value = lv_s iv_policy = iv_policy ).
    IF lv_d IS NOT INITIAL AND lv_s IS NOT INITIAL.
      IF lv_d = lv_s.
        add_row( EXPORTING iv_field = 'IBAN' iv_doc = lv_dd iv_sap = lv_sd
                           iv_status = zif_mdmdoc_types=>c_cmp_status-match CHANGING ct_rows = ct_rows ).
      ELSE.
        DATA(lv_pos) = first_diff( iv_a = lv_d iv_b = lv_s ).
        add_row( EXPORTING iv_field = 'IBAN' iv_doc = lv_dd iv_sap = lv_sd
                           iv_status = zif_mdmdoc_types=>c_cmp_status-mismatch
                           iv_note = |differs from position { lv_pos }| CHANGING ct_rows = ct_rows ).
        finding( EXPORTING iv_id = 'SAP-001' iv_sev = zif_mdmdoc_types=>c_severity-critical
                           iv_effect = zif_mdmdoc_types=>c_verdict-review iv_field = 'iban'
                           iv_msg = |IBAN mismatch: document { lv_dd } vs SAP { lv_sd } | &&
                                    |(differs from position { lv_pos }). Do not process — request corrected form or banking support.|
                 CHANGING ct_find = ct_find ).
      ENDIF.
    ELSEIF lv_d IS NOT INITIAL OR lv_s IS NOT INITIAL.
      add_row( EXPORTING iv_field = 'IBAN' iv_doc = lv_dd iv_sap = lv_sd
                         iv_status = zif_mdmdoc_types=>c_cmp_status-one_side CHANGING ct_rows = ct_rows ).
      finding( EXPORTING iv_id = 'SAP-002' iv_sev = zif_mdmdoc_types=>c_severity-warning
                         iv_effect = zif_mdmdoc_types=>c_verdict-warning iv_field = 'iban'
                         iv_msg = 'IBAN present on only one side (document vs SAP).'
               CHANGING ct_find = ct_find ).
    ENDIF.
  ENDMETHOD.

  METHOD cmp_account.
    DATA(lv_d) = zcl_mdmdoc_norm=>norm_id( doc( is_ext = is_ext iv_name = 'account_number' ) ).
    DATA(lv_s) = zcl_mdmdoc_norm=>norm_id( sap( it_sap = it_sap iv_name = 'bank_account' ) ).
    DATA(lv_iban) = zcl_mdmdoc_norm=>norm_id( sap( it_sap = it_sap iv_name = 'iban' ) ).
    DATA(lv_dd) = dv( iv_kind = zif_mdmdoc_types=>c_kind-account iv_value = lv_d iv_policy = iv_policy ).
    DATA(lv_sd) = dv( iv_kind = zif_mdmdoc_types=>c_kind-account iv_value = lv_s iv_policy = iv_policy ).
    DATA(lv_field) = `Bank Account`.
    IF lv_d IS NOT INITIAL AND lv_s IS NOT INITIAL.
      DATA(lv_dz) = lv_d.
      DATA(lv_sz) = lv_s.
      SHIFT lv_dz LEFT DELETING LEADING '0'.
      SHIFT lv_sz LEFT DELETING LEADING '0'.
      IF lv_d = lv_s.
        add_row( EXPORTING iv_field = lv_field iv_doc = lv_dd iv_sap = lv_sd
                           iv_status = zif_mdmdoc_types=>c_cmp_status-match CHANGING ct_rows = ct_rows ).
      ELSEIF lv_dz = lv_sz.
        add_row( EXPORTING iv_field = lv_field iv_doc = lv_dd iv_sap = lv_sd
                           iv_status = zif_mdmdoc_types=>c_cmp_status-match
                           iv_note = `leading zeros differ (SAP padding)` CHANGING ct_rows = ct_rows ).
      ELSE.
        " Anchored to the IBAN's ACCOUNT TAIL (>=6 significant digits) — the
        " old unanchored CS declared "match" and silenced SAP-003 (audit C9).
        DATA(lv_tail_ok) = abap_false.
        DATA(lv_len_i) = strlen( lv_iban ).
        DATA(lv_len_d) = strlen( lv_dz ).
        IF lv_iban IS NOT INITIAL AND lv_dz IS NOT INITIAL
           AND lv_len_d >= 6 AND lv_len_i >= lv_len_d
           AND substring( val = lv_iban off = lv_len_i - lv_len_d len = lv_len_d ) = lv_dz.
          lv_tail_ok = abap_true.
        ENDIF.
        IF lv_tail_ok = abap_true.
          " is SAP's own BANKN consistent with its IBAN tail too?
          DATA(lv_s_ok) = abap_false.
          DATA(lv_len_s) = strlen( lv_sz ).
          IF lv_sz IS NOT INITIAL AND lv_len_i >= lv_len_s
             AND substring( val = lv_iban off = lv_len_i - lv_len_s len = lv_len_s ) = lv_sz.
            lv_s_ok = abap_true.
          ENDIF.
          IF lv_s_ok = abap_true.
            DATA(lv_note_ok) = `document account matches the SAP IBAN account tail ` &&
              `(SAP stores a different decomposition of the same account)`.
            add_row( EXPORTING iv_field = lv_field iv_doc = lv_dd iv_sap = lv_sd
                               iv_status = zif_mdmdoc_types=>c_cmp_status-match
                               iv_note = lv_note_ok CHANGING ct_rows = ct_rows ).
          ELSE.
            add_row( EXPORTING iv_field = lv_field iv_doc = lv_dd iv_sap = lv_sd
                               iv_status = zif_mdmdoc_types=>c_cmp_status-mismatch
                               iv_note = `document matches the SAP IBAN tail but SAP's stored account number differs`
                     CHANGING ct_rows = ct_rows ).
            DATA(lv_msg9) = `Document account matches the SAP IBAN account tail, but SAP's stored ` &&
              `bank account (BANKN) differs - verify the decomposition before processing.`.
            finding( EXPORTING iv_id = 'SAP-009' iv_sev = zif_mdmdoc_types=>c_severity-warning
                               iv_effect = zif_mdmdoc_types=>c_verdict-warning iv_field = 'account_number'
                               iv_msg = lv_msg9
                     CHANGING ct_find = ct_find ).
          ENDIF.
        ELSE.
          DATA(lv_pos) = first_diff( iv_a = lv_dz iv_b = lv_sz ).
          add_row( EXPORTING iv_field = lv_field iv_doc = lv_dd iv_sap = lv_sd
                             iv_status = zif_mdmdoc_types=>c_cmp_status-mismatch
                             iv_note = |differs from position { lv_pos }| CHANGING ct_rows = ct_rows ).
          finding( EXPORTING iv_id = 'SAP-003' iv_sev = zif_mdmdoc_types=>c_severity-critical
                             iv_effect = zif_mdmdoc_types=>c_verdict-review iv_field = 'account_number'
                             iv_msg = |Account number mismatch: document { lv_dd } vs SAP { lv_sd }. Do not process.|
                   CHANGING ct_find = ct_find ).
        ENDIF.
      ENDIF.
    ELSEIF lv_d IS NOT INITIAL OR lv_s IS NOT INITIAL.
      add_row( EXPORTING iv_field = lv_field iv_doc = lv_dd iv_sap = lv_sd
                         iv_status = zif_mdmdoc_types=>c_cmp_status-one_side CHANGING ct_rows = ct_rows ).
    ENDIF.
  ENDMETHOD.

  METHOD cmp_swift.
    DATA(lv_d) = zcl_mdmdoc_norm=>norm_id( doc( is_ext = is_ext iv_name = 'swift_bic' ) ).
    DATA(lv_s) = zcl_mdmdoc_norm=>norm_id( sap( it_sap = it_sap iv_name = 'swift_bic' ) ).
    IF lv_d IS NOT INITIAL AND lv_s IS NOT INITIAL.
      DATA(lv_eq) = boolc( lv_d = lv_s OR lv_d && `XXX` = lv_s OR lv_d = lv_s && `XXX` ).
      DATA(lv_note) = COND string( WHEN lv_eq = abap_true AND lv_d <> lv_s THEN `XXX head-office suffix` ELSE `` ).
      add_row( EXPORTING iv_field = 'SWIFT/BIC' iv_doc = lv_d iv_sap = lv_s
                         iv_status = COND #( WHEN lv_eq = abap_true THEN zif_mdmdoc_types=>c_cmp_status-match
                                             ELSE zif_mdmdoc_types=>c_cmp_status-mismatch )
                         iv_note = lv_note CHANGING ct_rows = ct_rows ).
      IF lv_eq = abap_false.
        finding( EXPORTING iv_id = 'SAP-004' iv_sev = zif_mdmdoc_types=>c_severity-critical
                           iv_effect = zif_mdmdoc_types=>c_verdict-review iv_field = 'swift_bic'
                           iv_msg = |SWIFT/BIC mismatch: document { lv_d } vs SAP { lv_s }.|
                 CHANGING ct_find = ct_find ).
      ENDIF.
    ELSEIF lv_d IS NOT INITIAL OR lv_s IS NOT INITIAL.
      add_row( EXPORTING iv_field = 'SWIFT/BIC' iv_doc = lv_d iv_sap = lv_s
                         iv_status = zif_mdmdoc_types=>c_cmp_status-one_side CHANGING ct_rows = ct_rows ).
    ENDIF.
  ENDMETHOD.

  METHOD cmp_country.
    DATA(lv_d) = zcl_mdmdoc_norm=>to_iso2( doc( is_ext = is_ext iv_name = 'bank_country' ) ).
    DATA(lv_s) = zcl_mdmdoc_norm=>to_iso2( sap( it_sap = it_sap iv_name = 'bank_country' ) ).
    IF lv_d IS NOT INITIAL AND lv_s IS NOT INITIAL.
      add_row( EXPORTING iv_field = 'Bank Country' iv_doc = lv_d iv_sap = lv_s
                         iv_status = COND #( WHEN lv_d = lv_s THEN zif_mdmdoc_types=>c_cmp_status-match
                                             ELSE zif_mdmdoc_types=>c_cmp_status-mismatch ) CHANGING ct_rows = ct_rows ).
      IF lv_d <> lv_s.
        finding( EXPORTING iv_id = 'SAP-005' iv_sev = zif_mdmdoc_types=>c_severity-critical
                           iv_effect = zif_mdmdoc_types=>c_verdict-review iv_field = 'bank_country'
                           iv_msg = |Bank country mismatch: document { lv_d } vs SAP { lv_s }.|
                 CHANGING ct_find = ct_find ).
      ENDIF.
    ELSEIF lv_d IS NOT INITIAL OR lv_s IS NOT INITIAL.
      add_row( EXPORTING iv_field = 'Bank Country' iv_doc = lv_d iv_sap = lv_s
                         iv_status = zif_mdmdoc_types=>c_cmp_status-one_side CHANGING ct_rows = ct_rows ).
    ENDIF.
  ENDMETHOD.

  METHOD cmp_bank_key.
    DATA(lv_key) = zcl_mdmdoc_norm=>norm_id( sap( it_sap = it_sap iv_name = 'bank_key' ) ).
    IF lv_key IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_iban)  = zcl_mdmdoc_norm=>norm_id( doc( is_ext = is_ext iv_name = 'iban' ) ).
    DATA(lv_rout)  = zcl_mdmdoc_norm=>norm_id( doc( is_ext = is_ext iv_name = 'routing_aba' ) ).
    DATA(lv_wires) = zcl_mdmdoc_norm=>norm_id( doc( is_ext = is_ext iv_name = 'routing_aba_wires' ) ).

    " bank code sits after the 4-char country+check-digit prefix of the IBAN
    DATA lv_in_iban TYPE abap_bool.
    IF lv_iban IS NOT INITIAL AND strlen( lv_iban ) > 4.
      DATA(lv_len) = COND i( WHEN strlen( lv_key ) > 10 THEN strlen( lv_key ) ELSE 10 ).
      DATA(lv_avail) = strlen( lv_iban ) - 4.
      IF lv_avail < lv_len.
        lv_len = lv_avail.
      ENDIF.
      DATA(lv_window) = lv_iban+4(lv_len).
      lv_in_iban = boolc( lv_window CS lv_key ).
    ENDIF.
    DATA(lv_eq_rout) = boolc( ( lv_rout IS NOT INITIAL AND lv_rout = lv_key )
                           OR ( lv_wires IS NOT INITIAL AND lv_wires = lv_key ) ).

    DATA(lv_doc_side) = COND string(
      WHEN lv_rout IS NOT INITIAL OR lv_wires IS NOT INITIAL
        THEN dv( iv_kind = zif_mdmdoc_types=>c_kind-routing
                 iv_value = COND #( WHEN lv_rout IS NOT INITIAL THEN lv_rout ELSE lv_wires ) iv_policy = iv_policy )
      WHEN lv_iban IS NOT INITIAL THEN `from IBAN`
      ELSE `` ).

    IF lv_in_iban = abap_true OR lv_eq_rout = abap_true.
      DATA(lv_note) = COND string( WHEN lv_in_iban = abap_true THEN `confirmed by document IBAN` ELSE `matches document routing` ).
      add_row( EXPORTING iv_field = 'Bank Key' iv_doc = lv_doc_side iv_sap = lv_key
                         iv_status = zif_mdmdoc_types=>c_cmp_status-match iv_note = lv_note CHANGING ct_rows = ct_rows ).
    ELSEIF lv_rout IS NOT INITIAL OR lv_iban IS NOT INITIAL.
      add_row( EXPORTING iv_field = 'Bank Key' iv_doc = lv_doc_side iv_sap = lv_key
                         iv_status = zif_mdmdoc_types=>c_cmp_status-mismatch
                         iv_note = `no document-side confirmation` CHANGING ct_rows = ct_rows ).
      finding( EXPORTING iv_id = 'SAP-006' iv_sev = zif_mdmdoc_types=>c_severity-warning
                         iv_effect = zif_mdmdoc_types=>c_verdict-warning iv_field = 'bank_key'
                         iv_msg = |SAP Bank Key { lv_key } is not confirmed by the document | &&
                                  |(not in the IBAN bank-code position, routing differs).|
               CHANGING ct_find = ct_find ).
    ELSE.
      add_row( EXPORTING iv_field = 'Bank Key' iv_doc = lv_doc_side iv_sap = lv_key
                         iv_status = zif_mdmdoc_types=>c_cmp_status-sap_only
                         iv_note = `document shows no routing/IBAN to compare` CHANGING ct_rows = ct_rows ).
    ENDIF.
  ENDMETHOD.

  METHOD cmp_name.
    DATA(lv_dn) = norm_name( iv_doc ).
    DATA(lv_sn) = norm_name( iv_sap ).
    IF lv_dn IS NOT INITIAL AND lv_sn IS NOT INITIAL.
      DATA(lv_eq) = boolc( lv_dn CS lv_sn OR lv_sn CS lv_dn ).
      add_row( EXPORTING iv_field = iv_field iv_doc = iv_doc iv_sap = iv_sap
                         iv_status = COND #( WHEN lv_eq = abap_true THEN zif_mdmdoc_types=>c_cmp_status-match
                                             ELSE zif_mdmdoc_types=>c_cmp_status-mismatch ) CHANGING ct_rows = ct_rows ).
      IF lv_eq = abap_false.
        finding( EXPORTING iv_id = iv_id iv_sev = iv_sev iv_effect = iv_effect
                           iv_msg = |{ iv_field } differs: document '{ iv_doc }' vs SAP '{ iv_sap }'.|
                 CHANGING ct_find = ct_find ).
      ENDIF.
    ELSEIF lv_dn IS NOT INITIAL OR lv_sn IS NOT INITIAL.
      add_row( EXPORTING iv_field = iv_field iv_doc = iv_doc iv_sap = iv_sap
                         iv_status = zif_mdmdoc_types=>c_cmp_status-one_side CHANGING ct_rows = ct_rows ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
