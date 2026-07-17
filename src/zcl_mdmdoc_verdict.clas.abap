" Port of src/mdmdoc/verdict.py — folds rule findings into a single verdict.
" The rule engine decides, never the model.
" Precedence: REJECT > NEED_MANUAL_REVIEW > WARNING > ACCEPT.
CLASS zcl_mdmdoc_verdict DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS decide
      IMPORTING it_findings     TYPE zif_mdmdoc_types=>tt_findings
      RETURNING VALUE(rv_verdict) TYPE string.

    CLASS-METHODS next_step
      IMPORTING iv_doc_class   TYPE string
                iv_verdict     TYPE string
                iv_lang        TYPE string DEFAULT 'EN'
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS message_type
      IMPORTING iv_verdict      TYPE string
      RETURNING VALUE(rv_msgty) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS next_step_en
      IMPORTING iv_doc_class   TYPE string
                iv_verdict     TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS next_step_ru
      IMPORTING iv_doc_class   TYPE string
                iv_verdict     TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS zcl_mdmdoc_verdict IMPLEMENTATION.

  METHOD decide.
    " Collect the set of non-empty verdict_effect values, then apply precedence.
    " Empty effects (and effect-less findings) are ignored; no effects -> ACCEPT.
    DATA lv_has_reject TYPE abap_bool.
    DATA lv_has_review TYPE abap_bool.
    DATA lv_has_warn   TYPE abap_bool.

    LOOP AT it_findings ASSIGNING FIELD-SYMBOL(<ls_f>).
      CASE <ls_f>-verdict_effect.
        WHEN zif_mdmdoc_types=>c_verdict-reject.
          lv_has_reject = abap_true.
        WHEN zif_mdmdoc_types=>c_verdict-review.
          lv_has_review = abap_true.
        WHEN zif_mdmdoc_types=>c_verdict-warning.
          lv_has_warn = abap_true.
        WHEN OTHERS.
          " '' or any unknown effect -> not a decision driver (parity with Python set filter)
      ENDCASE.
    ENDLOOP.

    IF lv_has_reject = abap_true.
      rv_verdict = zif_mdmdoc_types=>c_verdict-reject.
    ELSEIF lv_has_review = abap_true.
      rv_verdict = zif_mdmdoc_types=>c_verdict-review.
    ELSEIF lv_has_warn = abap_true.
      rv_verdict = zif_mdmdoc_types=>c_verdict-warning.
    ELSE.
      rv_verdict = zif_mdmdoc_types=>c_verdict-accept.
    ENDIF.
  ENDMETHOD.


  METHOD next_step.
    " Python: _NEXT_STEP.get(doc_class, _NEXT_STEP["bank"]).get(verdict, "")
    " Unknown doc_class falls back to bank texts; unknown verdict -> ''.
    IF iv_lang = 'RU'.
      rv_text = next_step_ru( iv_doc_class = iv_doc_class
                              iv_verdict   = iv_verdict ).
    ELSE.
      rv_text = next_step_en( iv_doc_class = iv_doc_class
                              iv_verdict   = iv_verdict ).
    ENDIF.
  ENDMETHOD.


  METHOD next_step_en.
    " Verbatim EN texts from verdict._NEXT_STEP. W9 only when doc_class = 'w9'; else bank.
    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9.
      CASE iv_verdict.
        WHEN zif_mdmdoc_types=>c_verdict-accept.
          rv_text = `use for SAP entry (Line 1 -> Name 1, Line 2 -> Name 2, TIN per type)`.
        WHEN zif_mdmdoc_types=>c_verdict-warning.
          rv_text = `usable with caution — note the warnings`.
        WHEN zif_mdmdoc_types=>c_verdict-review.
          rv_text = `hold — clarify with requestor or request an updated form`.
        WHEN zif_mdmdoc_types=>c_verdict-reject.
          rv_text = `kick back — request a corrected W-9`.
        WHEN OTHERS.
          rv_text = ``.
      ENDCASE.
    ELSE.
      CASE iv_verdict.
        WHEN zif_mdmdoc_types=>c_verdict-accept.
          rv_text = `use as banking support — compare against SAP/the request form before entry`.
        WHEN zif_mdmdoc_types=>c_verdict-warning.
          rv_text = `usable with caution — note the warnings for the Data Owner`.
        WHEN zif_mdmdoc_types=>c_verdict-review.
          rv_text = `hold — resolve the flagged items manually before use`.
        WHEN zif_mdmdoc_types=>c_verdict-reject.
          rv_text = `kick back — request a bank letter / bank statement / supplier letterhead`.
        WHEN OTHERS.
          rv_text = ``.
      ENDCASE.
    ENDIF.
  ENDMETHOD.


  METHOD next_step_ru.
    " Faithful Russian translations of the 8 EN next-step texts.
    IF iv_doc_class = zif_mdmdoc_types=>c_doc_class-w9.
      CASE iv_verdict.
        WHEN zif_mdmdoc_types=>c_verdict-accept.
          rv_text = `использовать для ввода в SAP (Line 1 -> Name 1, Line 2 -> Name 2, TIN по типу)`.
        WHEN zif_mdmdoc_types=>c_verdict-warning.
          rv_text = `можно использовать с осторожностью — учтите предупреждения`.
        WHEN zif_mdmdoc_types=>c_verdict-review.
          rv_text = `отложить — уточните у запросившего или запросите обновлённую форму`.
        WHEN zif_mdmdoc_types=>c_verdict-reject.
          rv_text = `вернуть — запросите исправленную форму W-9`.
        WHEN OTHERS.
          rv_text = ``.
      ENDCASE.
    ELSE.
      CASE iv_verdict.
        WHEN zif_mdmdoc_types=>c_verdict-accept.
          rv_text = `использовать как банковское подтверждение — сверьте с SAP/формой запроса перед вводом`.
        WHEN zif_mdmdoc_types=>c_verdict-warning.
          rv_text = `можно использовать с осторожностью — учтите предупреждения для Data Owner`.
        WHEN zif_mdmdoc_types=>c_verdict-review.
          rv_text = `отложить — устраните отмеченные пункты вручную перед использованием`.
        WHEN zif_mdmdoc_types=>c_verdict-reject.
          rv_text = `вернуть — запросите банковское письмо / выписку / письмо на бланке поставщика`.
        WHEN OTHERS.
          rv_text = ``.
      ENDCASE.
    ENDIF.
  ENDMETHOD.


  METHOD message_type.
    " ACCEPT->'S', WARNING/NEED_MANUAL_REVIEW->'W', REJECT->'E'.
    CASE iv_verdict.
      WHEN zif_mdmdoc_types=>c_verdict-accept.
        rv_msgty = 'S'.
      WHEN zif_mdmdoc_types=>c_verdict-warning.
        rv_msgty = 'W'.
      WHEN zif_mdmdoc_types=>c_verdict-review.
        rv_msgty = 'W'.
      WHEN zif_mdmdoc_types=>c_verdict-reject.
        rv_msgty = 'E'.
      WHEN OTHERS.
        rv_msgty = 'W'.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
