" GENERATED from the Python reference prompts by tools/gen_prompts_abap.py
" *** DO NOT EDIT BY HAND — edit the prompt file and re-run the generator ***
" GEN-HASH 782c0819ec8edae9
"
" One prompt text, two callers. The Python extractor and ZMDMDOC must ask the vision
" model the same thing; the rules here are not decoration — "never translate or
" romanize" is what keeps a Korean or Japanese page from coming back in latin letters
" with every value on it lost.
CLASS zcl_mdmdoc_prompts DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CONSTANTS c_gen_hash TYPE string VALUE `782c0819ec8edae9`.
    "! Full-page transcription: verbatim, original script, tables as Markdown.
    "! Source of truth: prompts/vision/transcribe_md.v1.txt
    CLASS-METHODS vision_transcribe
      RETURNING VALUE(rv_text) TYPE string.
    "! CJK rescue: re-read a page the model came back from in latin letters.
    "! Source of truth: prompts/vision/transcribe_cjk.v1.txt
    CLASS-METHODS vision_transcribe_cjk
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS zcl_mdmdoc_prompts IMPLEMENTATION.
  METHOD vision_transcribe.
    rv_text =
      `You are a transcription engine. Transcribe EVERYTHING visibl` &&
      `e on this page image, exactly as printed or written, in natu` &&
      `ral reading order (top to bottom, left to right; vertical Ea` &&
      `st-Asian text column by column, right to left).` &&
      cl_abap_char_utilities=>newline &&
      cl_abap_char_utilities=>newline &&
      `Rules:` &&
      cl_abap_char_utilities=>newline &&
      `1. Verbatim. Keep the original language and script. Never tr` &&
      `anslate, romanize, transliterate, correct spelling, expand a` &&
      `bbreviations or normalise numbers. 漢字・かな・カナ・한글・汉字・кириллица・` &&
      `العربية stay exactly as written.` &&
      cl_abap_char_utilities=>newline &&
      `2. One printed line = one output line, in order. A label and` &&
      ` its value printed on the same line stay on the same line ("` &&
      `Account No.: 123-456").` &&
      cl_abap_char_utilities=>newline &&
      `3. Tables become Markdown tables (| a | b |), one row per pr` &&
      `inted row, header row included when there is one. Keep empty` &&
      ` cells empty.` &&
      cl_abap_char_utilities=>newline &&
      `4. Handwriting: transcribe it and wrap each handwritten pass` &&
      `age in [hw] … [/hw].` &&
      cl_abap_char_utilities=>newline &&
      `5. A glyph you cannot read: write 〓 (one per glyph). Never g` &&
      `uess a plausible word in its place.` &&
      cl_abap_char_utilities=>newline &&
      `6. Checkboxes: ☑ for a marked box, ☐ for an unmarked one, fo` &&
      `llowed by the box label.` &&
      cl_abap_char_utilities=>newline &&
      `7. Non-text elements: describe briefly in square brackets — ` &&
      `[stamp: red round seal, text "…"], [signature], [logo: …], [` &&
      `photo], [barcode], [QR code]. Transcribe any text inside a s` &&
      `tamp or logo.` &&
      cl_abap_char_utilities=>newline &&
      `8. Page furniture counts: headers, footers, page numbers, sm` &&
      `all print, margin notes, watermark text.` &&
      cl_abap_char_utilities=>newline &&
      `9. Output the transcript only — no introduction, no summary,` &&
      ` no commentary, no code fences.`.
  ENDMETHOD.

  METHOD vision_transcribe_cjk.
    rv_text =
      `This document contains Japanese, Chinese or Korean text (pri` &&
      `nted labels AND handwritten values). Transcribe EVERYTHING i` &&
      `n its ORIGINAL script — 漢字・ひらがな・カタカナ・한글 — line by line, exac` &&
      `tly as written. Do NOT romanize, translate or transliterate:` &&
      ` never turn 銀行 into 'bank' or ヨシダ into 'Yoshida'. Pay specia` &&
      `l attention to the handwritten answers next to each label: b` &&
      `ank name (銀行名), branch (支店名/店番号), account holder (口座名義人, oft` &&
      `en katakana), city/prefecture (都道府県). If a handwritten chara` &&
      `cter is unreadable, write 〓. Output plain text only — no com` &&
      `mentary.`.
  ENDMETHOD.
ENDCLASS.
