" GENERATED from tools/golden/gen_plausibility_golden.py (Python reference:
" src/mdmdoc/extract/plausibility.py) — *** DO NOT EDIT BY HAND ***
" Re-run the generator instead; tools/check_parity.py fails when this file is stale.
" GEN-HASH f2d70a91bddcaa4b
"
" Text-layer plausibility parity corpus. Each case is a real text-layer shape with the
" score the Python reference produces (0..1000) and its usable verdict. ZCL_MDMDOC_PDF
" must reproduce both — an approximate port is exactly the failure this guards against
" (case C-2026-08-21-02: a Korean bankbook scan whose mojibake OCR layer was trusted
" because it was longer than 40 characters).
CLASS zcl_mdmdoc_plaus_golden DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_case,
             id     TYPE string,
             note   TYPE string,
             text   TYPE string,
             score  TYPE i,          " Python plausibility( ) * 1000, rounded
             usable TYPE abap_bool,  " Python layer_usable( )[0]
           END OF ty_case.
    TYPES tt_cases TYPE STANDARD TABLE OF ty_case WITH EMPTY KEY.

    CONSTANTS c_gen_hash    TYPE string VALUE `f2d70a91bddcaa4b`.
    CONSTANTS c_trust_layer TYPE i      VALUE 700.

    CLASS-DATA gt_cases TYPE tt_cases READ-ONLY.
    CLASS-METHODS class_constructor.
ENDCLASS.


CLASS zcl_mdmdoc_plaus_golden IMPLEMENTATION.

  METHOD class_constructor.
    DATA ls_c TYPE ty_case.

    " Korean NH bankbook scan: embedded OCR layer turned Hangul into latin/symbol soup. 1304 chars in the real
    " file; ABAP trusted it because strlen >= 40. C-2026-08-21-02.
    ls_c-id     = `ko_mojibake`.
    ls_c-note   = `Korean NH bankbook scan: embedded OCR layer turned Hangul in` &&
      `to latin/symbol soup. 1304 chars in the real`.
    ls_c-text   = `   zt4fla  5()2-()655*    1994-A   1         d€qql€` &&
      cl_abap_char_utilities=>newline &&
      `  q=€+    ;&l @..-{l   *` &&
      cl_abap_char_utilities=>newline &&
      `           <<t 1.4€.ei>>` &&
      cl_abap_char_utilities=>newline &&
      `                      r*+F_*                                ` &&
      `g` &&
      cl_abap_char_utilities=>newline &&
      `    7l'J 6t{] 'J  201.5H 0t e 22 "J                   rll€tE` &&
      `J+drHlEEtNo.1Account` &&
      cl_abap_char_utilities=>newline &&
      `      E I       ; H       ; I    L I        = 6 t  l =      ` &&
      `2015 Ll 01 C 22";` &&
      cl_abap_char_utilities=>newline &&
      `    7t'Jdru         (e) 055-566-7201                        ` &&
      `58'J;flA   o` &&
      cl_abap_char_utilities=>newline &&
      `    'JBEs *t!$t!'{B-fl<S>` &&
      cl_abap_char_utilities=>newline &&
      `    drffi         ol8PlLtl      ol/trltL{l/Al/rl      u-t   ` &&
      `  Aoo`.
    ls_c-score  = 537.
    ls_c-usable = abap_false.
    APPEND ls_c TO gt_cases.

    " Custom font without a ToUnicode CMap (Colombian bank certificate): every glyph extracts as punctuation.
    " ABAP's ZCL_MDMDOC_PDF hits this whenever CMaps are missing.
    ls_c-id     = `font_soup`.
    ls_c-note   = `Custom font without a ToUnicode CMap (Colombian bank certifi` &&
      `cate): every glyph extracts as punctuation.`.
    ls_c-text   = `! " # $ "% &        '            #$(%` &&
      cl_abap_char_utilities=>newline &&
      `)%*( +, -+ .,/%0%$(1%   2! (3  4 #%( #$(%(3 /# ( 0 % ( 0 5 #` &&
      cl_abap_char_utilities=>newline &&
      `6789:;<8           =8>6789:;<8    ?@;AB>CD@7<:7B   EF<B98` &&
      cl_abap_char_utilities=>newline &&
      `#%  %1            ,+..G        HGHI     (#J%` &&
      cl_abap_char_utilities=>newline &&
      `KLMD87<BN<@O> #%(  #% (% 30 1%( $ (%%0 !  (# " ( % % # " #`.
    ls_c-score  = 467.
    ls_c-usable = abap_false.
    APPEND ls_c TO gt_cases.

    " Clean English bank confirmation letter — the baseline 'good' shape.
    ls_c-id     = `en_bank_letter`.
    ls_c-note   = `Clean English bank confirmation letter — the baseline 'good'` &&
      ` shape.`.
    ls_c-text   = `Bank of America, N.A.` &&
      cl_abap_char_utilities=>newline &&
      `222 Broadway, New York, NY 10038` &&
      cl_abap_char_utilities=>newline &&
      cl_abap_char_utilities=>newline &&
      `To whom it may concern,` &&
      cl_abap_char_utilities=>newline &&
      cl_abap_char_utilities=>newline &&
      `This letter confirms that Acme Industrial Supplies LLC` &&
      cl_abap_char_utilities=>newline &&
      `maintains checking account number 4830 2291 0077 with Bank o` &&
      `f America.` &&
      cl_abap_char_utilities=>newline &&
      `ABA routing (wires): 026009593   SWIFT: BOFAUS3N` &&
      cl_abap_char_utilities=>newline &&
      `Account opened: 12 March 2019` &&
      cl_abap_char_utilities=>newline &&
      `Sincerely,` &&
      cl_abap_char_utilities=>newline &&
      `Jane Doe, Relationship Manager`.
    ls_c-score  = 984.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " German Kontobestaetigung: umlauts and eszett must count as letters.
    ls_c-id     = `de_kontobestaetigung`.
    ls_c-note   = `German Kontobestaetigung: umlauts and eszett must count as l` &&
      `etters.`.
    ls_c-text   = `Kontobestätigung` &&
      cl_abap_char_utilities=>newline &&
      cl_abap_char_utilities=>newline &&
      `Sehr geehrte Damen und Herren,` &&
      cl_abap_char_utilities=>newline &&
      `hiermit bestätigen wir, dass die Firma Müller & Söhne GmbH b` &&
      `ei uns` &&
      cl_abap_char_utilities=>newline &&
      `folgendes Konto unterhält:` &&
      cl_abap_char_utilities=>newline &&
      `IBAN: DE89 3704 0044 0532 0130 00` &&
      cl_abap_char_utilities=>newline &&
      `BIC: COBADEFFXXX` &&
      cl_abap_char_utilities=>newline &&
      `Kontoinhaber: Müller & Söhne GmbH` &&
      cl_abap_char_utilities=>newline &&
      `Mit freundlichen Grüßen`.
    ls_c-score  = 913.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " Spanish certificacion bancaria (accents, long numbers with dots).
    ls_c-id     = `es_certificado`.
    ls_c-note   = `Spanish certificacion bancaria (accents, long numbers with d` &&
      `ots).`.
    ls_c-text   = `CERTIFICACIÓN BANCARIA` &&
      cl_abap_char_utilities=>newline &&
      `Bancolombia S.A. certifica que el señor JUAN PÉREZ GÓMEZ,` &&
      cl_abap_char_utilities=>newline &&
      `identificado con cédula de ciudadanía No. 1.020.345.678, es ` &&
      `titular de la` &&
      cl_abap_char_utilities=>newline &&
      `cuenta de ahorros No. 032-456789-01, activa desde el 03 de m` &&
      `ayo de 2018.`.
    ls_c-score  = 989.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " French RIB — short lines, many codes.
    ls_c-id     = `fr_rib`.
    ls_c-note   = `French RIB — short lines, many codes.`.
    ls_c-text   = `RELEVÉ D'IDENTITÉ BANCAIRE` &&
      cl_abap_char_utilities=>newline &&
      `Titulaire: SARL ATREEC` &&
      cl_abap_char_utilities=>newline &&
      `IBAN: FR76 3000 4008 2800 0102 4567 890` &&
      cl_abap_char_utilities=>newline &&
      `BIC: BNPAFRPPXXX` &&
      cl_abap_char_utilities=>newline &&
      `Domiciliation: BNP PARIBAS PARIS OPERA` &&
      cl_abap_char_utilities=>newline &&
      `Code banque 30004  Code guichet 00828`.
    ls_c-score  = 1000.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " The SAME Korean bankbook, but read correctly (Hangul) — must pass.
    ls_c-id     = `ko_bankbook_real`.
    ls_c-note   = `The SAME Korean bankbook, but read correctly (Hangul) — must` &&
      ` pass.`.
    ls_c-text   = `계좌번호 302-0653-1998-81` &&
      cl_abap_char_utilities=>newline &&
      `예금종류 저축예금` &&
      cl_abap_char_utilities=>newline &&
      `<<매직트리>>` &&
      cl_abap_char_utilities=>newline &&
      `남상욕 님` &&
      cl_abap_char_utilities=>newline &&
      `가입하신날 2013 년 01 월 22 일` &&
      cl_abap_char_utilities=>newline &&
      `NH농협은행` &&
      cl_abap_char_utilities=>newline &&
      `SWIFT CODE : NACFKRSE` &&
      cl_abap_char_utilities=>newline &&
      `가입하신 점포 양산부산대병원<출>` &&
      cl_abap_char_utilities=>newline &&
      `(☎) 055-366-7201`.
    ls_c-score  = 919.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " Japanese bank-account form: kanji + katakana + latin labels.
    ls_c-id     = `ja_form`.
    ls_c-note   = `Japanese bank-account form: kanji + katakana + latin labels.`.
    ls_c-text   = `銀行口座認証` &&
      cl_abap_char_utilities=>newline &&
      `銀行名: 三井住友銀行` &&
      cl_abap_char_utilities=>newline &&
      `支店名: 神戸支店 (店番号 412)` &&
      cl_abap_char_utilities=>newline &&
      `口座種別: 普通` &&
      cl_abap_char_utilities=>newline &&
      `口座番号: 1234567` &&
      cl_abap_char_utilities=>newline &&
      `口座名義人: カ）リリカラー`.
    ls_c-score  = 1000.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " Chinese bank information sheet with a company seal.
    ls_c-id     = `zh_seal`.
    ls_c-note   = `Chinese bank information sheet with a company seal.`.
    ls_c-text   = `中国银行账户信息` &&
      cl_abap_char_utilities=>newline &&
      `开户名称：四川省国际医学交流促进会` &&
      cl_abap_char_utilities=>newline &&
      `开户银行：中国银行成都高新支行` &&
      cl_abap_char_utilities=>newline &&
      `账号：1234 5678 9012 3456 789` &&
      cl_abap_char_utilities=>newline &&
      `联行号：104651003456`.
    ls_c-score  = 1000.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " Russian payment receipt — Cyrillic plus long account numbers.
    ls_c-id     = `ru_receipt`.
    ls_c-note   = `Russian payment receipt — Cyrillic plus long account numbers` &&
      `.`.
    ls_c-text   = `КВИТАНЦИЯ № 000123` &&
      cl_abap_char_utilities=>newline &&
      `Получатель: ООО «Ромашка»` &&
      cl_abap_char_utilities=>newline &&
      `ИНН 7701234567 КПП 770101001` &&
      cl_abap_char_utilities=>newline &&
      `Р/с 40702810400000001234 в ПАО Сбербанк` &&
      cl_abap_char_utilities=>newline &&
      `БИК 044525225`.
    ls_c-score  = 1000.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " Arabic VAT certificate (RTL script must not be penalised).
    ls_c-id     = `ar_cert`.
    ls_c-note   = `Arabic VAT certificate (RTL script must not be penalised).`.
    ls_c-text   = `شهادة تسجيل ضريبة القيمة المضافة` &&
      cl_abap_char_utilities=>newline &&
      `اسم المكلف: شركة أطلس للسفر والسياحة` &&
      cl_abap_char_utilities=>newline &&
      `الرقم الضريبي: 300123456700003` &&
      cl_abap_char_utilities=>newline &&
      `VAT Registration Certificate`.
    ls_c-score  = 1000.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " IRS W-9 digital fill — checkbox glyphs and a boxed EIN.
    ls_c-id     = `w9_digital`.
    ls_c-note   = `IRS W-9 digital fill — checkbox glyphs and a boxed EIN.`.
    ls_c-text   = `Form W-9 (Rev. March 2024) Request for Taxpayer Identificati` &&
      `on Number and Certification` &&
      cl_abap_char_utilities=>newline &&
      `1 Name of entity/individual: Qwest Corporation` &&
      cl_abap_char_utilities=>newline &&
      `2 Business name: dba CenturyLink QC` &&
      cl_abap_char_utilities=>newline &&
      `3a C corporation` &&
      cl_abap_char_utilities=>newline &&
      `5 Address: 931 14th Street` &&
      cl_abap_char_utilities=>newline &&
      `6 Denver, CO 80202` &&
      cl_abap_char_utilities=>newline &&
      `Employer identification number 84-0273800` &&
      cl_abap_char_utilities=>newline &&
      `Sign Here  Date 1-6-26`.
    ls_c-score  = 952.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " A page that is mostly a table — pipes and dashes must not read as symbols.
    ls_c-id     = `markdown_table`.
    ls_c-note   = `A page that is mostly a table — pipes and dashes must not re` &&
      `ad as symbols.`.
    ls_c-text   = `| Field | Value |` &&
      cl_abap_char_utilities=>newline &&
      `|---|---|` &&
      cl_abap_char_utilities=>newline &&
      `| Bank | JPMorgan Chase |` &&
      cl_abap_char_utilities=>newline &&
      `| ABA | 071000013 |` &&
      cl_abap_char_utilities=>newline &&
      `| Account | 2908805789 |` &&
      cl_abap_char_utilities=>newline &&
      `| Name on the account | AECNS, PLLC |`.
    ls_c-score  = 850.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " Almost no prose: IBAN, SWIFT, e-mail and a URL. The gate must still pass it.
    ls_c-id     = `codes_only`.
    ls_c-note   = `Almost no prose: IBAN, SWIFT, e-mail and a URL. The gate mus` &&
      `t still pass it.`.
    ls_c-text   = `IBAN DE89370400440532013000` &&
      cl_abap_char_utilities=>newline &&
      `BIC COBADEFFXXX` &&
      cl_abap_char_utilities=>newline &&
      `EIN 84-0273800` &&
      cl_abap_char_utilities=>newline &&
      `kundenservice@c24.de` &&
      cl_abap_char_utilities=>newline &&
      `www.c24.de` &&
      cl_abap_char_utilities=>newline &&
      `069 24 24 69 000`.
    ls_c-score  = 920.
    ls_c-usable = abap_true.
    APPEND ls_c TO gt_cases.

    " Below the minimum character count — the pre-existing strlen gate.
    ls_c-id     = `too_short`.
    ls_c-note   = `Below the minimum character count — the pre-existing strlen ` &&
      `gate.`.
    ls_c-text   = `02/01/2026`.
    ls_c-score  = 1000.
    ls_c-usable = abap_false.
    APPEND ls_c TO gt_cases.

    " No text layer at all.
    ls_c-id     = `empty`.
    ls_c-note   = `No text layer at all.`.
    ls_c-text   = ``.
    ls_c-score  = 0.
    ls_c-usable = abap_false.
    APPEND ls_c TO gt_cases.
  ENDMETHOD.

ENDCLASS.
