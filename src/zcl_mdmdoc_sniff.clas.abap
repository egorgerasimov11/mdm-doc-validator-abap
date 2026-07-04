CLASS zcl_mdmdoc_sniff DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " port of stage_a.sniff_doc_class (filename + text keyword scoring)
    CLASS-METHODS sniff_doc_class
      IMPORTING iv_text         TYPE string
                iv_filename     TYPE string
      RETURNING VALUE(rv_class) TYPE string.

    " port of fields.type_hint (+ helper markers it uses)
    CLASS-METHODS type_hint
      IMPORTING iv_text        TYPE string
                iv_filename    TYPE string
                iv_doc_class   TYPE string
      RETURNING VALUE(rv_type) TYPE string.

  PRIVATE SECTION.
    CLASS-DATA gt_editable_exts TYPE string_table.
    CLASS-DATA gt_email_exts    TYPE string_table.
    CLASS-DATA gt_image_exts    TYPE string_table.
    CLASS-DATA gt_w9_sniff      TYPE string_table.
    CLASS-DATA gt_invoice_marks TYPE string_table.
    CLASS-DATA gt_remit_context TYPE string_table.

    CLASS-METHODS class_constructor.

    " lower-case suffix incl. dot, e.g. 'file.PDF' -> '.pdf'; '' when none
    CLASS-METHODS ext_of
      IMPORTING iv_filename   TYPE string
      RETURNING VALUE(rv_ext) TYPE string.

    CLASS-METHODS in_table
      IMPORTING it_table       TYPE string_table
                iv_value       TYPE string
      RETURNING VALUE(rv_found) TYPE abap_bool.

    " fields.invoice_marks: count invoice marks on lines OUTSIDE remit context
    CLASS-METHODS invoice_marks
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_n)   TYPE i.

    " fields._INVOICE_HEADER_RE.search : (?im)^\s*(invoice|rechnung|fattura|factura)\s*$
    CLASS-METHODS invoice_header
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    " fields.looks_like_printed_email
    CLASS-METHODS looks_like_printed_email
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    " fields.page_markers(...)['bank_letter']
    CLASS-METHODS page_marker_bank_letter
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.

    CLASS-METHODS split_lines
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rt_lines) TYPE string_table.
ENDCLASS.


CLASS zcl_mdmdoc_sniff IMPLEMENTATION.

  METHOD class_constructor.
    " config.EDITABLE_EXTS
    gt_editable_exts = VALUE #(
      ( `.docx` ) ( `.doc` ) ( `.xlsx` ) ( `.xlsm` ) ( `.xls` )
      ( `.txt` ) ( `.rtf` ) ( `.csv` ) ( `.odt` ) ).
    " config.EMAIL_EXTS
    gt_email_exts = VALUE #( ( `.eml` ) ( `.msg` ) ).
    " config.IMAGE_EXTS
    gt_image_exts = VALUE #(
      ( `.png` ) ( `.jpg` ) ( `.jpeg` ) ( `.bmp` )
      ( `.tif` ) ( `.tiff` ) ( `.gif` ) ( `.webp` ) ).
    " stage_a._W9_SNIFF (lower-case markers)
    gt_w9_sniff = VALUE #(
      ( `form w-9` ) ( `request for taxpayer` )
      ( `taxpayer identification number` )
      ( `w-8ben` ) ( `w-8ben-e` )
      ( `certificate of foreign status` )
      ( `substitute w-9` ) ( `substitute form w-9` ) ).
    " fields._INVOICE_MARKS
    gt_invoice_marks = VALUE #(
      ( `invoice number` ) ( `invoice no` ) ( `invoice date` )
      ( `amount due` ) ( `subtotal` ) ( `payment terms` )
      ( `purchase order number` ) ( `pro forma` )
      ( `rechnungsnummer` ) ( `rechnungsdatum` )
      ( `numero fattura` ) ( `número de factura` ) ).
    " fields._REMIT_CONTEXT
    gt_remit_context = VALUE #(
      ( `remit` ) ( `being paid` ) ( `must include` )
      ( `must be accompanied` ) ( `when making payment` )
      ( `payments received without` ) ( `amt:` )
      ( `payment amount per invoice` ) ( `ach payment` )
      ( `payment instruction` ) ( `wire transfer` )
      ( `include the following` ) ).
  ENDMETHOD.


  METHOD ext_of.
    DATA lv_off TYPE i.
    rv_ext = ``.
    " find last '.'; python Path.suffix takes the final dotted segment
    FIND ALL OCCURRENCES OF '.' IN iv_filename RESULTS DATA(lt_dots).
    IF lt_dots IS INITIAL.
      RETURN.
    ENDIF.
    DATA(ls_last) = lt_dots[ lines( lt_dots ) ].
    lv_off = ls_last-offset.
    rv_ext = iv_filename+lv_off.
    rv_ext = to_lower( rv_ext ).
  ENDMETHOD.


  METHOD in_table.
    READ TABLE it_table TRANSPORTING NO FIELDS WITH KEY table_line = iv_value.
    rv_found = boolc( sy-subrc = 0 ).
  ENDMETHOD.


  METHOD split_lines.
    " normalise CRLF/CR to LF, then split on LF (python str.splitlines-ish)
    DATA(lv) = iv_text.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv WITH cl_abap_char_utilities=>newline.
    REPLACE ALL OCCURRENCES OF |{ cl_abap_char_utilities=>cr_lf(1) }| IN lv WITH cl_abap_char_utilities=>newline.
    SPLIT lv AT cl_abap_char_utilities=>newline INTO TABLE rt_lines.
  ENDMETHOD.


  METHOD sniff_doc_class.
    " 1) filename first: (?i)\bw[-_ ]?(9|8(ben)?)\b -> w9
    IF cl_abap_matcher=>contains(
         pattern     = `\<w[-_ ]?(9|8(ben)?)\>`
         text        = iv_filename
         ignore_case = abap_true ).
      rv_class = zif_mdmdoc_types=>c_doc_class-w9.
      RETURN.
    ENDIF.

    " 2) text markers (case-insensitive). No PDF/OCR here — caller supplies text.
    DATA(lv_t) = to_lower( iv_text ).
    LOOP AT gt_w9_sniff ASSIGNING FIELD-SYMBOL(<k>).
      IF lv_t CS <k>.
        rv_class = zif_mdmdoc_types=>c_doc_class-w9.
        RETURN.
      ENDIF.
    ENDLOOP.

    " 3) default: bank
    rv_class = zif_mdmdoc_types=>c_doc_class-bank.
  ENDMETHOD.


  METHOD invoice_header.
    " (?im)^\s*(invoice|rechnung|fattura|factura)\s*$  — per line, case-insensitive
    rv_yes = abap_false.
    LOOP AT split_lines( iv_text ) ASSIGNING FIELD-SYMBOL(<line>).
      IF cl_abap_matcher=>matches(
           pattern     = `\s*(invoice|rechnung|fattura|factura)\s*`
           text        = <line>
           ignore_case = abap_true ).
        rv_yes = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD invoice_marks.
    rv_n = 0.
    LOOP AT split_lines( iv_text ) ASSIGNING FIELD-SYMBOL(<line>).
      DATA(lv_line) = to_lower( <line> ).
      " skip lines that carry remittance-instruction context
      DATA(lv_skip) = abap_false.
      LOOP AT gt_remit_context ASSIGNING FIELD-SYMBOL(<c>).
        IF lv_line CS <c>.
          lv_skip = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF lv_skip = abap_true.
        CONTINUE.
      ENDIF.
      LOOP AT gt_invoice_marks ASSIGNING FIELD-SYMBOL(<m>).
        IF lv_line CS <m>.
          rv_n = rv_n + 1.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD looks_like_printed_email.
    " head = text[:2000].lower(); count of (?m)^\s*{h}:\s?\S for from/sent/to/subject
    DATA(lv_head) = iv_text.
    IF strlen( lv_head ) > 2000.
      lv_head = lv_head(2000).
    ENDIF.
    lv_head = to_lower( lv_head ).

    DATA lt_hdrs TYPE string_table.
    lt_hdrs = VALUE #( ( `from` ) ( `sent` ) ( `to` ) ( `subject` ) ).

    " Per header, count 1 if ANY line matches ^\s*<h>:\s?\S (python: sum of
    " per-header booleans over the whole head). matches() anchors both ends, so
    " strip leading whitespace and test the header as a line prefix.
    DATA lv_hits TYPE i VALUE 0.
    DATA(lt_lines) = split_lines( lv_head ).
    LOOP AT lt_hdrs ASSIGNING FIELD-SYMBOL(<h>).
      LOOP AT lt_lines ASSIGNING FIELD-SYMBOL(<line>).
        DATA(lv_trim) = <line>.
        SHIFT lv_trim LEFT DELETING LEADING ` `.
        SHIFT lv_trim LEFT DELETING LEADING cl_abap_char_utilities=>horizontal_tab.
        IF cl_abap_matcher=>contains(
             pattern     = |^{ <h> }:\\s?\\S|
             text        = lv_trim
             ignore_case = abap_true ).
          lv_hits = lv_hits + 1.
          EXIT.  " count each header at most once
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    rv_yes = boolc( lv_hits >= 3 ).
  ENDMETHOD.


  METHOD page_marker_bank_letter.
    " fields.page_markers(...)['bank_letter']:
    "   letter_hits >= 2  OR 'account confirmation' in t
    "   OR 'please accept this letter' in t OR 'this letter is to confirm' in t
    DATA(t) = to_lower( iv_text ).

    DATA lt_phrases TYPE string_table.
    lt_phrases = VALUE #(
      ( `please accept this letter` ) ( `account confirmation` )
      ( `confirmation that` ) ( `we confirm that` )
      ( `maintained at` ) ( `routing instructions` )
      ( `letter as confirmation` ) ( `bank confirmation` )
      ( `treasury analyst` ) ( `to whom it may concern` )
      ( `this letter is to confirm` )
      ( `account confirmation certificate` )
      ( `conferma coordinate bancarie` ) ( `coordinate bancarie` )
      ( `vi confermiamo` ) ( `certificación bancaria` )
      ( `certificacion bancaria` ) ( `certificado bancario` )
      ( `bankbestätigung` ) ( `kontobestätigung` ) ).

    DATA lv_hits TYPE i VALUE 0.
    LOOP AT lt_phrases ASSIGNING FIELD-SYMBOL(<p>).
      IF t CS <p>.
        lv_hits = lv_hits + 1.
      ENDIF.
    ENDLOOP.

    rv_yes = boolc( lv_hits >= 2
                 OR t CS `account confirmation`
                 OR t CS `please accept this letter`
                 OR t CS `this letter is to confirm` ).
  ENDMETHOD.


  METHOD type_hint.
    DATA(lv_ext) = ext_of( iv_filename ).

    " editable / email short-circuits (config.EDITABLE_EXTS / EMAIL_EXTS)
    IF in_table( it_table = gt_editable_exts iv_value = lv_ext ) = abap_true.
      rv_type = `editable_source`.
      RETURN.
    ENDIF.
    IF in_table( it_table = gt_email_exts iv_value = lv_ext ) = abap_true.
      rv_type = `email`.
      RETURN.
    ENDIF.

    DATA(f) = to_lower( iv_filename ).
    DATA(t) = to_lower( iv_text ).
    " blob = f + " " + t[:4000]
    DATA(lv_t4000) = t.
    IF strlen( lv_t4000 ) > 4000.
      lv_t4000 = lv_t4000(4000).
    ENDIF.
    DATA(blob) = f && ` ` && lv_t4000.

    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9.
      IF blob CS `w-9` OR blob CS `w9`
         OR blob CS `request for taxpayer identification`.
        rv_type = `w9`.
        RETURN.
      ENDIF.
      IF blob CS `w-8` OR blob CS `w8ben` OR blob CS `w-8ben`
         OR blob CS `w8-ben` OR blob CS `certificate of foreign status`.
        rv_type = `w8`.
        RETURN.
      ENDIF.
      rv_type = ``.
      RETURN.
    ENDIF.

    " banking branch --------------------------------------------------------
    " a printed-out email thread is email evidence regardless of embeds
    IF looks_like_printed_email( iv_text ) = abap_true.
      rv_type = `email`.
      RETURN.
    ENDIF.

    " filename-based invoice hint
    IF f CS `invoice` OR f CS `rechnung` OR f CS `fattura`.
      rv_type = `invoice`.
      RETURN.
    ENDIF.

    " STRUCTURAL invoice hint: own header / >=2 marks AND not a bank letter
    IF ( invoice_header( iv_text ) = abap_true OR invoice_marks( iv_text ) >= 2 )
       AND page_marker_bank_letter( t ) = abap_false.
      rv_type = `invoice`.
      RETURN.
    ENDIF.

    IF blob CS `voided check` OR blob CS `void check`.
      rv_type = `voided_check`.
      RETURN.
    ENDIF.

    IF blob CS `account statement` OR blob CS `e-statement`
       OR blob CS `estatement` OR blob CS `statement period`
       OR blob CS `statement of account` OR blob CS `kontoauszug`
       OR blob CS `extracto bancario` OR blob CS `estado de cuenta`.
      rv_type = `bank_statement`.
      RETURN.
    ENDIF.

    IF blob CS `certificación bancaria` OR blob CS `certificacion bancaria`
       OR blob CS `bankbestätigung` OR blob CS `bank confirmation`
       OR blob CS `bank letter` OR blob CS `开户许可证` OR blob CS `开户银行`.
      rv_type = `bank_letter`.
      RETURN.
    ENDIF.

    IF blob CS `bank account information`
       AND ( blob CS `docusign` OR blob CS `for sap` OR blob CS `s/4hana` ).
      rv_type = `ap_document`.
      RETURN.
    ENDIF.

    IF blob CS `payment instruction` OR blob CS `ach payments only`
       OR blob CS `for ach payments` OR blob CS `remittance advice`
       OR blob CS `remittance sent` OR blob CS `email remittance`
       OR blob CS `banking details are confidential`
       OR blob CS `ach payment type`.
      rv_type = `payment_instructions`.
      RETURN.
    ENDIF.

    rv_type = ``.
  ENDMETHOD.

ENDCLASS.
