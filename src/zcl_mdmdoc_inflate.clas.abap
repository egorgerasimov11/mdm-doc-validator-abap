" Pure-ABAP raw-DEFLATE (RFC 1951) decoder — no CRC/Adler verification, never dumps.
" Why it exists (case C-2026-08-20-01): a PDF /FlateDecode stream is a bare zlib member
" (RFC 1950), and the kernel classes refuse to finish without a valid checksum —
" cl_abap_gzip verifies the gzip CRC32 trailer, cl_abap_zip=>get verifies the ZIP CRC —
" so no checksum-checked container can be faked around an already-compressed stream.
" Algorithm follows Mark Adler's public-domain 'puff' reference inflater; the same
" approach abapGit takes in zcl_abapgit_zlib (MIT).
CLASS zcl_mdmdoc_inflate DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    " raw deflate bytes in -> plain bytes out; ev_ok = abap_false on any structural error
    CLASS-METHODS decompress
      IMPORTING iv_data TYPE xstring
      EXPORTING ev_raw  TYPE xstring
                ev_ok   TYPE abap_bool.

    " zlib envelope test (RFC 1950): CM=8, FCHECK consistent, FDICT off. ev_deflate is
    " the payload with the 2-byte header stripped; the Adler32 tail stays on — the
    " decoder stops at the final block and never reads it.
    CLASS-METHODS unwrap_zlib
      IMPORTING iv_data    TYPE xstring
      EXPORTING ev_deflate TYPE xstring
                ev_is_zlib TYPE abap_bool.

    CLASS-METHODS class_constructor.

  PRIVATE SECTION.
    TYPES tt_int TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    " canonical Huffman code: count = codes per bit-length (line L+1 = length L, 0..15),
    " sym = symbols ordered by (code length, symbol value)
    TYPES: BEGIN OF ty_huff,
             count TYPE tt_int,
             sym   TYPE tt_int,
           END OF ty_huff.

    " decode state (one instance per decompress call; static entry keeps callers simple)
    DATA mv_data   TYPE xstring.
    DATA mv_len    TYPE i.
    DATA mv_pos    TYPE i.
    DATA mv_bitbuf TYPE i.
    DATA mv_bitcnt TYPE i.
    DATA mv_out    TYPE xstring.
    DATA mv_buf    TYPE x LENGTH 4096.   " literal-byte staging, flushed before matches
    DATA mv_buflen TYPE i.
    DATA mv_err    TYPE abap_bool.

    CLASS-DATA gt_pow2       TYPE tt_int.   " line N+1 = 2^N, N = 0..16
    CLASS-DATA gt_lens_base  TYPE tt_int.
    CLASS-DATA gt_lens_extra TYPE tt_int.
    CLASS-DATA gt_dist_base  TYPE tt_int.
    CLASS-DATA gt_dist_extra TYPE tt_int.
    CLASS-DATA gt_cl_order   TYPE tt_int.
    CLASS-DATA gs_fixed_len  TYPE ty_huff.
    CLASS-DATA gs_fixed_dist TYPE ty_huff.

    CLASS-METHODS fill
      IMPORTING iv_csv        TYPE string
      RETURNING VALUE(rt_tab) TYPE tt_int.
    CLASS-METHODS construct
      IMPORTING it_lengths     TYPE tt_int
      RETURNING VALUE(rs_huff) TYPE ty_huff.

    METHODS run.
    METHODS bits
      IMPORTING iv_need       TYPE i
      RETURNING VALUE(rv_val) TYPE i.
    METHODS decode
      IMPORTING is_huff       TYPE ty_huff
      RETURNING VALUE(rv_sym) TYPE i.
    METHODS codes
      IMPORTING is_len  TYPE ty_huff
                is_dist TYPE ty_huff.
    METHODS block_stored.
    METHODS block_dynamic.
    METHODS put_byte
      IMPORTING iv_int TYPE i.
    METHODS flush_buf.
ENDCLASS.



CLASS zcl_mdmdoc_inflate IMPLEMENTATION.

  METHOD class_constructor.
    DATA lv_v TYPE i.
    lv_v = 1.
    DO 17 TIMES.
      APPEND lv_v TO gt_pow2.
      lv_v = lv_v * 2.
    ENDDO.

    gt_lens_base  = fill( `3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,` &&
                          `67,83,99,115,131,163,195,227,258` ).
    gt_lens_extra = fill( `0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0` ).
    gt_dist_base  = fill( `1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,` &&
                          `1025,1537,2049,3073,4097,6145,8193,12289,16385,24577` ).
    gt_dist_extra = fill( `0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13` ).
    gt_cl_order   = fill( `16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15` ).

    " fixed literal/length code: 0-143 -> 8 bits, 144-255 -> 9, 256-279 -> 7, 280-287 -> 8
    DATA lt_l TYPE tt_int.
    DATA lv_s TYPE i.
    DO 288 TIMES.
      lv_s = sy-index - 1.
      IF lv_s <= 143.
        APPEND 8 TO lt_l.
      ELSEIF lv_s <= 255.
        APPEND 9 TO lt_l.
      ELSEIF lv_s <= 279.
        APPEND 7 TO lt_l.
      ELSE.
        APPEND 8 TO lt_l.
      ENDIF.
    ENDDO.
    gs_fixed_len = construct( lt_l ).

    DATA lt_d TYPE tt_int.
    DO 30 TIMES.
      APPEND 5 TO lt_d.
    ENDDO.
    gs_fixed_dist = construct( lt_d ).
  ENDMETHOD.


  METHOD fill.
    DATA lt_parts TYPE string_table.
    SPLIT iv_csv AT ',' INTO TABLE lt_parts.
    DATA lv_part TYPE string.
    DATA lv_int  TYPE i.
    LOOP AT lt_parts INTO lv_part.
      lv_int = lv_part.
      APPEND lv_int TO rt_tab.
    ENDLOOP.
  ENDMETHOD.


  METHOD decompress.
    CLEAR ev_raw.
    ev_ok = abap_false.
    DATA lo TYPE REF TO zcl_mdmdoc_inflate.
    CREATE OBJECT lo.
    lo->mv_data = iv_data.
    lo->mv_len  = xstrlen( iv_data ).
    TRY.
        lo->run( ).
      CATCH cx_root.
        lo->mv_err = abap_true.   " hostile input must degrade, never dump
    ENDTRY.
    IF lo->mv_err = abap_false.
      ev_raw = lo->mv_out.
      ev_ok  = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD unwrap_zlib.
    CLEAR ev_deflate.
    ev_is_zlib = abap_false.
    DATA lv_len TYPE i.
    lv_len = xstrlen( iv_data ).
    IF lv_len < 7.                       " 2 header + 1 minimal deflate + 4 adler
      RETURN.
    ENDIF.
    DATA lv_cmf TYPE i.
    DATA lv_flg TYPE i.
    lv_cmf = iv_data+0(1).
    lv_flg = iv_data+1(1).
    IF lv_cmf MOD 16 <> 8.               " CM must be 'deflate'
      RETURN.
    ENDIF.
    IF ( lv_cmf * 256 + lv_flg ) MOD 31 <> 0.
      RETURN.
    ENDIF.
    IF ( lv_flg DIV 32 ) MOD 2 = 1.      " FDICT: preset dictionary — undecodable
      RETURN.
    ENDIF.
    DATA lv_plen TYPE i.
    lv_plen = lv_len - 2.
    ev_deflate = iv_data+2(lv_plen).
    ev_is_zlib = abap_true.
  ENDMETHOD.


  METHOD run.
    DATA lv_final TYPE i.
    DATA lv_type  TYPE i.
    DO.
      lv_final = bits( 1 ).
      lv_type  = bits( 2 ).
      IF mv_err = abap_true.
        RETURN.
      ENDIF.
      CASE lv_type.
        WHEN 0.
          block_stored( ).
        WHEN 1.
          codes( is_len = gs_fixed_len is_dist = gs_fixed_dist ).
        WHEN 2.
          block_dynamic( ).
        WHEN OTHERS.
          mv_err = abap_true.
      ENDCASE.
      IF mv_err = abap_true.
        RETURN.
      ENDIF.
      IF lv_final = 1.
        flush_buf( ).
        RETURN.
      ENDIF.
    ENDDO.
  ENDMETHOD.


  METHOD bits.
    " LSB-first bit reader; arithmetic only (values stay far below int4 range)
    rv_val = 0.
    DATA lv_byte TYPE i.
    WHILE mv_bitcnt < iv_need.
      IF mv_pos >= mv_len.
        mv_err = abap_true.
        RETURN.
      ENDIF.
      lv_byte = mv_data+mv_pos(1).
      mv_bitbuf = mv_bitbuf + lv_byte * gt_pow2[ mv_bitcnt + 1 ].
      mv_bitcnt = mv_bitcnt + 8.
      mv_pos = mv_pos + 1.
    ENDWHILE.
    DATA lv_p TYPE i.
    lv_p = gt_pow2[ iv_need + 1 ].
    rv_val = mv_bitbuf MOD lv_p.
    mv_bitbuf = mv_bitbuf DIV lv_p.
    mv_bitcnt = mv_bitcnt - iv_need.
  ENDMETHOD.


  METHOD construct.
    " canonical-Huffman bookkeeping ('puff'): per-length counts + sorted symbol list
    DATA lt_count TYPE tt_int.
    DO 16 TIMES.
      APPEND 0 TO lt_count.
    ENDDO.
    DATA lv_len TYPE i.
    LOOP AT it_lengths INTO lv_len.
      lt_count[ lv_len + 1 ] = lt_count[ lv_len + 1 ] + 1.
    ENDLOOP.
    lt_count[ 1 ] = 0.                   " length 0 = unused symbol

    DATA lt_offs TYPE tt_int.
    DO 17 TIMES.
      APPEND 0 TO lt_offs.
    ENDDO.
    DATA lv_l TYPE i.
    DO 15 TIMES.
      lv_l = sy-index.
      lt_offs[ lv_l + 2 ] = lt_offs[ lv_l + 1 ] + lt_count[ lv_l + 1 ].
    ENDDO.

    DATA lt_sym TYPE tt_int.
    DATA lv_total TYPE i.
    lv_total = lt_offs[ 17 ].
    DO lv_total TIMES.
      APPEND 0 TO lt_sym.
    ENDDO.
    DATA lv_symno TYPE i.
    LOOP AT it_lengths INTO lv_len.
      lv_symno = sy-tabix - 1.
      IF lv_len <> 0.
        lt_sym[ lt_offs[ lv_len + 1 ] + 1 ] = lv_symno.
        lt_offs[ lv_len + 1 ] = lt_offs[ lv_len + 1 ] + 1.
      ENDIF.
    ENDLOOP.

    rs_huff-count = lt_count.
    rs_huff-sym   = lt_sym.
  ENDMETHOD.


  METHOD decode.
    rv_sym = -1.
    DATA lv_code  TYPE i.
    DATA lv_first TYPE i.
    DATA lv_index TYPE i.
    DATA lv_cnt   TYPE i.
    DATA lv_len   TYPE i.
    DO 15 TIMES.
      lv_len = sy-index.
      lv_code = lv_code + bits( 1 ).
      IF mv_err = abap_true.
        RETURN.
      ENDIF.
      lv_cnt = is_huff-count[ lv_len + 1 ].
      IF lv_code - lv_first < lv_cnt.
        rv_sym = is_huff-sym[ lv_index + lv_code - lv_first + 1 ].
        RETURN.
      ENDIF.
      lv_index = lv_index + lv_cnt.
      lv_first = ( lv_first + lv_cnt ) * 2.
      lv_code  = lv_code * 2.
    ENDDO.
    mv_err = abap_true.                  " over-long code: corrupt table
  ENDMETHOD.


  METHOD codes.
    DATA lv_sym    TYPE i.
    DATA lv_length TYPE i.
    DATA lv_dsym   TYPE i.
    DATA lv_dist   TYPE i.
    DATA lv_outlen TYPE i.
    DATA lv_src    TYPE i.
    DATA lv_x1     TYPE x LENGTH 1.
    DATA lv_slice  TYPE xstring.
    DO.
      lv_sym = decode( is_len ).
      IF mv_err = abap_true.
        RETURN.
      ENDIF.
      IF lv_sym < 256.
        put_byte( lv_sym ).
      ELSEIF lv_sym = 256.
        flush_buf( ).
        RETURN.
      ELSE.
        lv_sym = lv_sym - 257.
        IF lv_sym >= 29.
          mv_err = abap_true.
          RETURN.
        ENDIF.
        lv_length = gt_lens_base[ lv_sym + 1 ] + bits( gt_lens_extra[ lv_sym + 1 ] ).
        lv_dsym = decode( is_dist ).
        IF mv_err = abap_true.
          RETURN.
        ENDIF.
        IF lv_dsym < 0 OR lv_dsym >= 30.
          mv_err = abap_true.
          RETURN.
        ENDIF.
        lv_dist = gt_dist_base[ lv_dsym + 1 ] + bits( gt_dist_extra[ lv_dsym + 1 ] ).
        IF mv_err = abap_true.
          RETURN.
        ENDIF.
        flush_buf( ).                    " matches read finished output only
        lv_outlen = xstrlen( mv_out ).
        IF lv_dist <= 0 OR lv_dist > lv_outlen.
          mv_err = abap_true.
          RETURN.
        ENDIF.
        lv_src = lv_outlen - lv_dist.
        IF lv_dist >= lv_length.
          " no overlap: one slice copy
          lv_slice = mv_out+lv_src(lv_length).
          CONCATENATE mv_out lv_slice INTO mv_out IN BYTE MODE.
        ELSE.
          " overlapping match (e.g. run-length): byte-wise, reading as we grow
          DO lv_length TIMES.
            lv_x1 = mv_out+lv_src(1).
            CONCATENATE mv_out lv_x1 INTO mv_out IN BYTE MODE.
            lv_src = lv_src + 1.
          ENDDO.
        ENDIF.
      ENDIF.
    ENDDO.
  ENDMETHOD.


  METHOD block_stored.
    " byte-aligned raw copy: LEN(2, LE) + NLEN(2, tolerated unchecked) + LEN bytes
    mv_bitbuf = 0.
    mv_bitcnt = 0.
    IF mv_pos + 4 > mv_len.
      mv_err = abap_true.
      RETURN.
    ENDIF.
    DATA lv_b0 TYPE i.
    DATA lv_b1 TYPE i.
    DATA lv_p1 TYPE i.
    lv_b0 = mv_data+mv_pos(1).
    lv_p1 = mv_pos + 1.
    lv_b1 = mv_data+lv_p1(1).
    DATA lv_ln TYPE i.
    lv_ln = lv_b0 + lv_b1 * 256.
    mv_pos = mv_pos + 4.
    IF mv_pos + lv_ln > mv_len.
      mv_err = abap_true.
      RETURN.
    ENDIF.
    IF lv_ln > 0.
      flush_buf( ).
      DATA lv_chunk TYPE xstring.
      lv_chunk = mv_data+mv_pos(lv_ln).
      CONCATENATE mv_out lv_chunk INTO mv_out IN BYTE MODE.
      mv_pos = mv_pos + lv_ln.
    ENDIF.
  ENDMETHOD.


  METHOD block_dynamic.
    DATA lv_nlen  TYPE i.
    DATA lv_ndist TYPE i.
    DATA lv_ncode TYPE i.
    lv_nlen  = bits( 5 ) + 257.
    lv_ndist = bits( 5 ) + 1.
    lv_ncode = bits( 4 ) + 4.
    IF mv_err = abap_true OR lv_nlen > 286 OR lv_ndist > 30.
      mv_err = abap_true.
      RETURN.
    ENDIF.

    " code-length code: 3-bit lengths in the fixed permutation order
    DATA lt_cl TYPE tt_int.
    DO 19 TIMES.
      APPEND 0 TO lt_cl.
    ENDDO.
    DATA lv_i TYPE i.
    DO lv_ncode TIMES.
      lv_i = sy-index.
      lt_cl[ gt_cl_order[ lv_i ] + 1 ] = bits( 3 ).
    ENDDO.
    IF mv_err = abap_true.
      RETURN.
    ENDIF.
    DATA ls_cl TYPE ty_huff.
    ls_cl = construct( lt_cl ).

    " literal/length + distance code lengths, with 16/17/18 repeat operators
    DATA lt_lengths TYPE tt_int.
    DATA lv_want TYPE i.
    lv_want = lv_nlen + lv_ndist.
    DATA lv_sym  TYPE i.
    DATA lv_prev TYPE i.
    DATA lv_rep  TYPE i.
    WHILE lines( lt_lengths ) < lv_want.
      lv_sym = decode( ls_cl ).
      IF mv_err = abap_true.
        RETURN.
      ENDIF.
      IF lv_sym < 0.
        mv_err = abap_true.
        RETURN.
      ELSEIF lv_sym < 16.
        APPEND lv_sym TO lt_lengths.
      ELSEIF lv_sym = 16.
        IF lines( lt_lengths ) = 0.
          mv_err = abap_true.
          RETURN.
        ENDIF.
        lv_prev = lt_lengths[ lines( lt_lengths ) ].
        lv_rep = 3 + bits( 2 ).
        DO lv_rep TIMES.
          APPEND lv_prev TO lt_lengths.
        ENDDO.
      ELSEIF lv_sym = 17.
        lv_rep = 3 + bits( 3 ).
        DO lv_rep TIMES.
          APPEND 0 TO lt_lengths.
        ENDDO.
      ELSEIF lv_sym = 18.
        lv_rep = 11 + bits( 7 ).
        DO lv_rep TIMES.
          APPEND 0 TO lt_lengths.
        ENDDO.
      ELSE.
        mv_err = abap_true.
        RETURN.
      ENDIF.
      IF mv_err = abap_true.
        RETURN.
      ENDIF.
    ENDWHILE.
    IF lines( lt_lengths ) > lv_want.
      mv_err = abap_true.
      RETURN.
    ENDIF.

    DATA lt_ll TYPE tt_int.
    DATA lt_dd TYPE tt_int.
    LOOP AT lt_lengths INTO lv_sym.
      IF sy-tabix <= lv_nlen.
        APPEND lv_sym TO lt_ll.
      ELSE.
        APPEND lv_sym TO lt_dd.
      ENDIF.
    ENDLOOP.
    DATA ls_len  TYPE ty_huff.
    DATA ls_dist TYPE ty_huff.
    ls_len  = construct( lt_ll ).
    ls_dist = construct( lt_dd ).
    codes( is_len = ls_len is_dist = ls_dist ).
  ENDMETHOD.


  METHOD put_byte.
    DATA lv_x1 TYPE x LENGTH 1.
    lv_x1 = iv_int.
    mv_buf+mv_buflen(1) = lv_x1.
    mv_buflen = mv_buflen + 1.
    IF mv_buflen = 4096.
      flush_buf( ).
    ENDIF.
  ENDMETHOD.


  METHOD flush_buf.
    IF mv_buflen > 0.
      DATA lv_part TYPE xstring.
      lv_part = mv_buf(mv_buflen).
      CONCATENATE mv_out lv_part INTO mv_out IN BYTE MODE.
      mv_buflen = 0.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
