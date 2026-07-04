CLASS zcl_mdmdoc_report DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Port of report.py: the human report blocks (report_bank/w9.md.j2) + the
    " machine JSON (schema mdmdoc.v1 subset). Every sensitive value is masked here
    " via zcl_mdmdoc_mask=>display_value; the program still runs the leak gate on
    " the final JSON before writing it.

    CLASS-METHODS build_list
      IMPORTING is_ext          TYPE zif_mdmdoc_types=>ty_extraction
                it_findings     TYPE zif_mdmdoc_types=>tt_findings
                iv_verdict      TYPE string
                iv_lang         TYPE string   DEFAULT 'EN'
                iv_policy       TYPE string   DEFAULT 'masked'
      RETURNING VALUE(rt_lines) TYPE string_table.

    CLASS-METHODS build_json
      IMPORTING is_ext         TYPE zif_mdmdoc_types=>ty_extraction
                it_findings    TYPE zif_mdmdoc_types=>tt_findings
                iv_verdict     TYPE string
                iv_doc_path    TYPE string
                iv_run_id      TYPE string
                iv_lang        TYPE string DEFAULT 'EN'
                iv_policy      TYPE string DEFAULT 'masked'
      RETURNING VALUE(rv_json) TYPE string.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_row,
             label TYPE string,
             value TYPE string,
             hint  TYPE string,
           END OF ty_row,
           tt_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    CONSTANTS c_ru TYPE string VALUE 'RU'.

    CLASS-METHODS get
      IMPORTING is_ext          TYPE zif_mdmdoc_types=>ty_extraction
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS shown
      IMPORTING is_ext          TYPE zif_mdmdoc_types=>ty_extraction
                iv_name         TYPE string
                iv_policy       TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS fmt
      IMPORTING iv_value        TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS data_rows
      IMPORTING is_ext        TYPE zif_mdmdoc_types=>ty_extraction
                iv_policy     TYPE string
                iv_lang       TYPE string
      RETURNING VALUE(rt_rows) TYPE tt_row.

    CLASS-METHODS frow
      IMPORTING is_ext        TYPE zif_mdmdoc_types=>ty_extraction
                iv_name       TYPE string
                iv_en         TYPE string
                iv_ru         TYPE string
                iv_lang       TYPE string
                iv_policy     TYPE string
                iv_hint       TYPE string DEFAULT ''
      RETURNING VALUE(rs_row) TYPE ty_row.

    CLASS-METHODS evidence
      IMPORTING is_ext         TYPE zif_mdmdoc_types=>ty_extraction
                iv_policy      TYPE string
      RETURNING VALUE(rt_ev)   TYPE string_table.

    CLASS-METHODS why_line
      IMPORTING it_findings   TYPE zif_mdmdoc_types=>tt_findings
                iv_doc_class  TYPE string
      RETURNING VALUE(rv_why) TYPE string.

    CLASS-METHODS lbl
      IMPORTING iv_en         TYPE string
                iv_ru         TYPE string
                iv_lang       TYPE string
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS iban_country
      IMPORTING iv_value      TYPE string
      RETURNING VALUE(rv_cc)  TYPE string.

    CLASS-METHODS iban_len
      IMPORTING iv_value      TYPE string
      RETURNING VALUE(rv_len) TYPE i.

    CLASS-METHODS jesc
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS jstr
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS json_fields
      IMPORTING is_ext         TYPE zif_mdmdoc_types=>ty_extraction
                iv_policy      TYPE string
      RETURNING VALUE(rv_json) TYPE string.

    CLASS-METHODS append_group
      IMPORTING it_findings TYPE zif_mdmdoc_types=>tt_findings
                iv_sev      TYPE string
                iv_title    TYPE string
      CHANGING  ct_lines    TYPE string_table.
ENDCLASS.


CLASS zcl_mdmdoc_report IMPLEMENTATION.

  METHOD get.
    rv_value = zcl_mdmdoc_norm=>field_value( it_fields = is_ext-fields iv_name = iv_name ).
  ENDMETHOD.

  METHOD shown.
    " masked/full display of a (possibly sensitive) field
    DATA(lv_raw) = get( is_ext = is_ext iv_name = iv_name ).
    DATA(lv_kind) = zcl_mdmdoc_mask=>kind_for_field( iv_name ).
    IF lv_kind IS INITIAL.
      rv_value = lv_raw.
    ELSE.
      rv_value = zcl_mdmdoc_mask=>display_value( iv_kind = lv_kind iv_value = lv_raw iv_policy = iv_policy ).
    ENDIF.
  ENDMETHOD.

  METHOD fmt.
    rv_value = iv_value.
    CONDENSE rv_value.
    IF rv_value IS INITIAL.
      rv_value = |—|.
    ENDIF.
  ENDMETHOD.

  METHOD lbl.
    rv_txt = COND #( WHEN iv_lang = c_ru THEN iv_ru ELSE iv_en ).
  ENDMETHOD.

  METHOD iban_country.
    DATA(lv_id) = zcl_mdmdoc_norm=>norm_id( iv_value ).
    IF strlen( lv_id ) >= 2.
      rv_cc = lv_id(2).
    ENDIF.
  ENDMETHOD.

  METHOD iban_len.
    rv_len = strlen( zcl_mdmdoc_norm=>norm_id( iv_value ) ).
  ENDMETHOD.

  METHOD why_line.
    LOOP AT it_findings ASSIGNING FIELD-SYMBOL(<f>) WHERE severity = zif_mdmdoc_types=>c_severity-critical.
      rv_why = <f>-message.
      RETURN.
    ENDLOOP.
    LOOP AT it_findings ASSIGNING <f> WHERE severity = zif_mdmdoc_types=>c_severity-warning.
      rv_why = <f>-message.
      RETURN.
    ENDLOOP.
    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-bank.
      rv_why = |Document shows sufficient banking identity for support.|.
    ELSE.
      rv_why = |Form is complete and internally consistent.|.
    ENDIF.
  ENDMETHOD.

  METHOD frow.
    rs_row-label = lbl( iv_en = iv_en iv_ru = iv_ru iv_lang = iv_lang ).
    rs_row-value = fmt( shown( is_ext = is_ext iv_name = iv_name iv_policy = iv_policy ) ).
    rs_row-hint  = iv_hint.
  ENDMETHOD.

  METHOD data_rows.
    IF is_ext-doc_class = zif_mdmdoc_types=>c_doc_class-bank.
      APPEND frow( is_ext = is_ext iv_name = 'account_holder'
                   iv_en = |Account holder| iv_ru = |Владелец счёта| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'account_type'
                   iv_en = |Account type| iv_ru = |Тип счёта| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'bank_name'
                   iv_en = |Bank name| iv_ru = |Банк| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'bank_country'
                   iv_en = |Bank country| iv_ru = |Страна банка| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'bank_address'
                   iv_en = |Bank address| iv_ru = |Адрес банка| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.

      " IBAN gets a country/length annotation appended to the masked value
      DATA(lv_iban_raw) = get( is_ext = is_ext iv_name = 'iban' ).
      DATA(lv_iban_val) = |—|.
      IF lv_iban_raw IS NOT INITIAL.
        lv_iban_val = shown( is_ext = is_ext iv_name = 'iban' iv_policy = iv_policy ).
        IF iban_country( lv_iban_raw ) IS NOT INITIAL.
          lv_iban_val = |{ lv_iban_val } (country { iban_country( lv_iban_raw ) }, len { iban_len( lv_iban_raw ) })|.
        ENDIF.
      ENDIF.
      APPEND VALUE #( label = |IBAN| value = lv_iban_val ) TO rt_rows.

      APPEND frow( is_ext = is_ext iv_name = 'swift_bic'
                   iv_en = |SWIFT/BIC| iv_ru = |SWIFT/BIC| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'account_number'
                   iv_en = |Account number| iv_ru = |Номер счёта| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'routing_aba'
                   iv_en = |Routing/ABA (standard)| iv_ru = |Routing/ABA (осн.)| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'routing_aba_wires'
                   iv_en = |Routing/ABA (wires)| iv_ru = |Routing/ABA (wire)| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'branch_code'
                   iv_en = |Branch code| iv_ru = |Код отделения| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'currency'
                   iv_en = |Currency| iv_ru = |Валюта| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'doc_date'
                   iv_en = |Document date| iv_ru = |Дата документа| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.

      " signed/stamped: yes | no (evidence)
      DATA(lv_signed) = COND string(
        WHEN zcl_mdmdoc_norm=>field_is_true( it_fields = is_ext-fields iv_name = 'signed' ) THEN |yes| ELSE |no| ).
      DATA(lv_sig_ev) = get( is_ext = is_ext iv_name = 'signature_evidence' ).
      IF lv_signed = |no| AND lv_sig_ev IS NOT INITIAL.
        lv_signed = |no ({ lv_sig_ev })|.
      ENDIF.
      APPEND VALUE #( label = lbl( iv_en = |Signed/stamped| iv_ru = |Подпись/печать| iv_lang = iv_lang )
                      value = lv_signed ) TO rt_rows.
    ELSE.
      DATA(lv_tin_type) = get( is_ext = is_ext iv_name = 'tin_type' ).
      DATA(lv_tin_target) = COND string( WHEN lv_tin_type = 'SSN' THEN |Tax Number 1|
                                         WHEN lv_tin_type = 'EIN' THEN |Tax Number 2| ELSE || ).
      APPEND frow( is_ext = is_ext iv_name = 'line1_name' iv_hint = |SAP Name 1|
                   iv_en = |Line 1 — taxpayer name| iv_ru = |Строка 1 — имя налогопл.| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'line2_business_name' iv_hint = |SAP Name 2|
                   iv_en = |Line 2 — business name| iv_ru = |Строка 2 — бизнес-имя| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'line3_classification'
                   iv_en = |Classification (Line 3)| iv_ru = |Классификация (строка 3)|
                   iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND VALUE #( label = |TIN type| hint = lv_tin_target
                      value = COND #( WHEN lv_tin_type IS INITIAL THEN |—| ELSE lv_tin_type ) ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'tin_raw'
                   iv_en = |TIN (masked)| iv_ru = |ИНН (маска)| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'address_street'
                   iv_en = |Address — street| iv_ru = |Адрес — улица| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.
      APPEND frow( is_ext = is_ext iv_name = 'address_city_state_zip'
                   iv_en = |Address — city/state/ZIP| iv_ru = |Адрес — город/штат/ZIP| iv_lang = iv_lang iv_policy = iv_policy ) TO rt_rows.

      DATA(lv_w9_signed) = COND string(
        WHEN zcl_mdmdoc_norm=>field_is_true( it_fields = is_ext-fields iv_name = 'signed' ) THEN |yes| ELSE |no| ).
      DATA(lv_sign_date) = get( is_ext = is_ext iv_name = 'sign_date' ).
      IF lv_sign_date IS NOT INITIAL.
        lv_w9_signed = |{ lv_w9_signed } ({ lv_sign_date })|.
      ENDIF.
      APPEND VALUE #( label = lbl( iv_en = |Signed| iv_ru = |Подпись| iv_lang = iv_lang )
                      value = lv_w9_signed ) TO rt_rows.
    ENDIF.
  ENDMETHOD.

  METHOD evidence.
    IF is_ext-doc_class = zif_mdmdoc_types=>c_doc_class-bank.
      DATA(lv) = get( is_ext = is_ext iv_name = 'bank_name' ).
      IF lv IS NOT INITIAL.
        APPEND |bank: { lv }| TO rt_ev.
      ENDIF.
      lv = get( is_ext = is_ext iv_name = 'account_holder' ).
      IF lv IS NOT INITIAL.
        APPEND |holder: { lv }| TO rt_ev.
      ENDIF.
      lv = shown( is_ext = is_ext iv_name = 'iban' iv_policy = iv_policy ).
      IF get( is_ext = is_ext iv_name = 'iban' ) IS NOT INITIAL.
        APPEND |IBAN: { lv }| TO rt_ev.
      ENDIF.
      lv = shown( is_ext = is_ext iv_name = 'account_number' iv_policy = iv_policy ).
      IF get( is_ext = is_ext iv_name = 'account_number' ) IS NOT INITIAL.
        APPEND |account: { lv }| TO rt_ev.
      ENDIF.
      lv = shown( is_ext = is_ext iv_name = 'routing_aba' iv_policy = iv_policy ).
      IF get( is_ext = is_ext iv_name = 'routing_aba' ) IS NOT INITIAL.
        APPEND |routing: { lv }| TO rt_ev.
      ENDIF.
      lv = get( is_ext = is_ext iv_name = 'swift_bic' ).
      IF lv IS NOT INITIAL.
        APPEND |SWIFT: { lv }| TO rt_ev.
      ENDIF.
    ELSE.
      lv = get( is_ext = is_ext iv_name = 'line1_name' ).
      IF lv IS NOT INITIAL.
        APPEND |Line 1: { lv }| TO rt_ev.
      ENDIF.
      lv = get( is_ext = is_ext iv_name = 'line2_business_name' ).
      IF lv IS NOT INITIAL.
        APPEND |Line 2: { lv }| TO rt_ev.
      ENDIF.
      DATA(lv_tin) = shown( is_ext = is_ext iv_name = 'tin_raw' iv_policy = iv_policy ).
      IF get( is_ext = is_ext iv_name = 'tin_raw' ) IS NOT INITIAL.
        APPEND |TIN ({ get( is_ext = is_ext iv_name = 'tin_type' ) }): { lv_tin }| TO rt_ev.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD build_list.
    DATA(lv_head) = COND string( WHEN is_ext-doc_class = zif_mdmdoc_types=>c_doc_class-bank
                                 THEN |[BANK DOC VERDICT]| ELSE |[W-9 VERDICT]| ).
    APPEND lv_head TO rt_lines.
    APPEND |{ lbl( iv_en = |Document | iv_ru = |Документ | iv_lang = iv_lang ) }: { is_ext-doc_class }| TO rt_lines.
    APPEND |{ lbl( iv_en = |Doc type | iv_ru = |Тип      | iv_lang = iv_lang ) }: { is_ext-doc_type }| TO rt_lines.
    APPEND |{ lbl( iv_en = |Verdict  | iv_ru = |Вердикт  | iv_lang = iv_lang ) }: { iv_verdict }| TO rt_lines.
    DATA(lv_why) = why_line( it_findings = it_findings iv_doc_class = is_ext-doc_class ).
    APPEND |{ lbl( iv_en = |Why      | iv_ru = |Причина  | iv_lang = iv_lang ) }: { lv_why }| TO rt_lines.

    DATA(lt_ev) = evidence( is_ext = is_ext iv_policy = iv_policy ).
    IF lt_ev IS NOT INITIAL.
      DATA(lv_ev) = concat_lines_of( table = lt_ev sep = |; | ).
      APPEND |{ lbl( iv_en = |Evidence | iv_ru = |Реквизиты| iv_lang = iv_lang ) }: { lv_ev }| TO rt_lines.
    ENDIF.
    DATA(lv_next) = zcl_mdmdoc_verdict=>next_step( iv_doc_class = is_ext-doc_class iv_verdict = iv_verdict iv_lang = iv_lang ).
    APPEND |{ lbl( iv_en = |Next step| iv_ru = |Далее    | iv_lang = iv_lang ) }: { lv_next }| TO rt_lines.
    APPEND || TO rt_lines.

    " findings grouped by severity
    append_group( EXPORTING it_findings = it_findings
                            iv_sev      = zif_mdmdoc_types=>c_severity-critical
                            iv_title    = lbl( iv_en = |Critical issues| iv_ru = |Критично| iv_lang = iv_lang )
                  CHANGING  ct_lines    = rt_lines ).
    append_group( EXPORTING it_findings = it_findings
                            iv_sev      = zif_mdmdoc_types=>c_severity-warning
                            iv_title    = lbl( iv_en = |Warnings| iv_ru = |Предупреждения| iv_lang = iv_lang )
                  CHANGING  ct_lines    = rt_lines ).
    append_group( EXPORTING it_findings = it_findings
                            iv_sev      = zif_mdmdoc_types=>c_severity-note
                            iv_title    = lbl( iv_en = |Notes| iv_ru = |Заметки| iv_lang = iv_lang )
                  CHANGING  ct_lines    = rt_lines ).

    " EXTRACTED DATA block (aligned)
    DATA(lt_rows) = data_rows( is_ext = is_ext iv_policy = iv_policy iv_lang = iv_lang ).
    DATA lv_w TYPE i.
    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<r>).
      IF strlen( <r>-label ) > lv_w.
        lv_w = strlen( <r>-label ).
      ENDIF.
    ENDLOOP.
    APPEND || TO rt_lines.
    DATA(lv_dhdr) = lbl( iv_en = |EXTRACTED DATA| iv_ru = |ИЗВЛЕЧЁННЫЕ ДАННЫЕ| iv_lang = iv_lang ).
    APPEND |------------------ { lv_dhdr } ------------------| TO rt_lines.
    LOOP AT lt_rows ASSIGNING <r>.
      DATA(lv_line) = |{ <r>-label WIDTH = lv_w ALIGN = LEFT } : { <r>-value }|.
      IF <r>-hint IS NOT INITIAL AND <r>-value <> |—|.
        lv_line = |{ lv_line }   -> { <r>-hint }|.
      ENDIF.
      APPEND lv_line TO rt_lines.
    ENDLOOP.

    " cross-check notes
    IF is_ext-crosscheck IS NOT INITIAL.
      APPEND || TO rt_lines.
      APPEND |{ lbl( iv_en = |Cross-check| iv_ru = |Сверка| iv_lang = iv_lang ) }:| TO rt_lines.
      LOOP AT is_ext-crosscheck INTO DATA(lv_cc).
        APPEND |  { lv_cc }| TO rt_lines.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD jesc.
    rv_text = iv_text.
    REPLACE ALL OCCURRENCES OF `\` IN rv_text WITH `\\`.
    REPLACE ALL OCCURRENCES OF `"` IN rv_text WITH `\"`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_text WITH `\n`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_text WITH `\n`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_text WITH `\t`.
  ENDMETHOD.

  METHOD jstr.
    rv_text = |"{ jesc( iv_text ) }"|.
  ENDMETHOD.

  METHOD json_fields.
    DATA lt_parts TYPE string_table.
    DATA(lt_keys) = COND string( WHEN is_ext-doc_class = zif_mdmdoc_types=>c_doc_class-bank
                                 THEN zif_mdmdoc_types=>c_bank_keys ELSE zif_mdmdoc_types=>c_w9_keys ).
    SPLIT lt_keys AT |,| INTO TABLE DATA(lt_name).
    LOOP AT lt_name INTO DATA(lv_name).
      DATA(lv_raw) = get( is_ext = is_ext iv_name = lv_name ).
      DATA(lv_kind) = zcl_mdmdoc_mask=>kind_for_field( lv_name ).
      DATA(lv_msk) = shown( is_ext = is_ext iv_name = lv_name iv_policy = iv_policy ).
      DATA(lv_pres) = COND string( WHEN lv_raw IS INITIAL THEN |false| ELSE |true| ).
      IF lv_name = 'iban'.
        DATA(lv_cc) = iban_country( lv_raw ).
        APPEND |{ jstr( lv_name ) }: \{ "masked": { jstr( lv_msk ) }, "country": { jstr( lv_cc ) }, | &&
               |"length": { iban_len( lv_raw ) }, "present": { lv_pres } \}| TO lt_parts.
      ELSEIF lv_name = 'tin_raw' AND is_ext-doc_class = zif_mdmdoc_types=>c_doc_class-w9.
        DATA(lv_tp) = get( is_ext = is_ext iv_name = 'tin_type' ).
        DATA(lv_dig) = strlen( zcl_mdmdoc_norm=>digits_only( lv_raw ) ).
        APPEND |"tin": \{ "type": { jstr( lv_tp ) }, "masked": { jstr( lv_msk ) }, | &&
               |"digits": { lv_dig }, "present": { lv_pres } \}| TO lt_parts.
      ELSEIF lv_name = 'signed' OR lv_name = 'partial_capture'.
        DATA(lv_b) = COND string(
          WHEN zcl_mdmdoc_norm=>field_is_true( it_fields = is_ext-fields iv_name = lv_name ) THEN |true| ELSE |false| ).
        APPEND |{ jstr( lv_name ) }: { lv_b }| TO lt_parts.
      ELSEIF lv_kind IS NOT INITIAL.
        APPEND |{ jstr( lv_name ) }: { jstr( lv_msk ) }| TO lt_parts.
      ELSE.
        APPEND |{ jstr( lv_name ) }: { jstr( lv_raw ) }| TO lt_parts.
      ENDIF.
    ENDLOOP.
    rv_json = |\{ { concat_lines_of( table = lt_parts sep = |, | ) } \}|.
  ENDMETHOD.

  METHOD build_json.
    DATA lt_find TYPE string_table.
    LOOP AT it_findings ASSIGNING FIELD-SYMBOL(<f>).
      APPEND |\{ "rule_id": { jstr( <f>-rule_id ) }, "severity": { jstr( <f>-severity ) }, | &&
             |"verdict_effect": { jstr( <f>-verdict_effect ) }, "message": { jstr( <f>-message ) }, | &&
             |"detail": { jstr( <f>-detail ) }, "field": { jstr( <f>-field ) } \}| TO lt_find.
    ENDLOOP.

    DATA lt_cc TYPE string_table.
    LOOP AT is_ext-crosscheck INTO DATA(lv_cc).
      APPEND jstr( lv_cc ) TO lt_cc.
    ENDLOOP.
    DATA lt_wn TYPE string_table.
    LOOP AT is_ext-warnings INTO DATA(lv_wn).
      APPEND jstr( lv_wn ) TO lt_wn.
    ENDLOOP.

    DATA(lv_ts) = |{ sy-datum+0(4) }-{ sy-datum+4(2) }-{ sy-datum+6(2) }T{ sy-uzeit+0(2) }:{ sy-uzeit+2(2) }:{ sy-uzeit+4(2) }Z|.
    DATA(lv_next) = zcl_mdmdoc_verdict=>next_step( iv_doc_class = is_ext-doc_class iv_verdict = iv_verdict iv_lang = iv_lang ).

    rv_json =
      |\{\n| &&
      |  "schema": "mdmdoc.v1",\n| &&
      |  "doc": { jstr( iv_doc_path ) },\n| &&
      |  "run_id": { jstr( iv_run_id ) },\n| &&
      |  "doc_class": { jstr( is_ext-doc_class ) },\n| &&
      |  "doc_type": { jstr( is_ext-doc_type ) },\n| &&
      |  "verdict": { jstr( iv_verdict ) },\n| &&
      |  "next_step": { jstr( lv_next ) },\n| &&
      |  "findings": [{ concat_lines_of( table = lt_find sep = |, | ) }],\n| &&
      |  "fields": { json_fields( is_ext = is_ext iv_policy = iv_policy ) },\n| &&
      |  "crosscheck": [{ concat_lines_of( table = lt_cc sep = |, | ) }],\n| &&
      |  "warnings": [{ concat_lines_of( table = lt_wn sep = |, | ) }],\n| &&
      |  "model": { jstr( is_ext-model_id ) },\n| &&
      |  "ts": { jstr( lv_ts ) }\n| &&
      |\}|.
  ENDMETHOD.

  METHOD append_group.
    DATA lt TYPE zif_mdmdoc_types=>tt_findings.
    LOOP AT it_findings INTO DATA(ls_f) WHERE severity = iv_sev.
      APPEND ls_f TO lt.
    ENDLOOP.
    IF lt IS INITIAL.
      RETURN.
    ENDIF.
    APPEND |{ iv_title } ({ lines( lt ) }):| TO ct_lines.
    LOOP AT lt INTO ls_f.
      APPEND |- [{ ls_f-rule_id }] { ls_f-message }| TO ct_lines.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
