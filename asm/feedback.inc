; Bounded, 79-column result messages and a compact save-name prompt.
feedback_ready:
        clc
        lda ORIGIN
        adc LENGTH
        sta FBEND
        lda ORIGIN+1
        adc LENGTH+1
        sta FBEND+1
        lda FBEND
        bne :+
        dec FBEND+1
:       dec FBEND
        lda #0
        sta FBINDEX
        lda #' '
        jsr fb_char
        jsr fb_range
        lda #' '
        jsr fb_char
        lda LENGTH
        ldx LENGTH+1
        jsr fb_number
        lda #<fb_prompt_bytes
        ldx #>fb_prompt_bytes
        jsr fb_string
        lda NSYM
        ldx NSYM+1
        jsr fb_number
        lda #<fb_prompt_save
        ldx #>fb_prompt_save
        jsr fb_string
        jsr fb_finish
        ldx #0
@copy: lda MESSAGE,x
        sta SUMMARY,x
        beq @result
        inx
        bne @copy
@result:
        lda #0
        jmp feedback_result

; 0 assembled / not saved, 1 saved, 3 disk error, 4 invalid save range.
feedback_result:
        sta FBSTATE
        tax
        lda #0
        sta FBINDEX
        lda fb_prefix_lo,x
        pha
        lda fb_prefix_hi,x
        tax
        pla
        jsr fb_string
        lda LENGTH
        ldx LENGTH+1
        jsr fb_number
        jsr fb_byte_units
        jsr fb_range
        lda #<fb_symbols
        ldx #>fb_symbols
        jsr fb_string
        lda NSYM
        ldx NSYM+1
        jsr fb_number
        lda FBSTATE
        bne @done
        lda #<fb_unsaved
        ldx #>fb_unsaved
        jsr fb_string
@done: jmp fb_finish

fb_byte_units:
        lda LENGTH+1
        bne @plural
        lda LENGTH
        cmp #1
        bne @plural
        lda #<fb_byte
        ldx #>fb_byte
        jmp fb_string
@plural:
        lda #<fb_bytes
        ldx #>fb_bytes
        jmp fb_string

fb_range:
        lda #'$'
        jsr fb_char
        lda ORIGIN+1
        jsr fb_hex
        lda ORIGIN
        jsr fb_hex
        lda #'-'
        jsr fb_char
        lda #'$'
        jsr fb_char
        lda FBEND+1
        jsr fb_hex
        lda FBEND
        jmp fb_hex
fb_hex: pha
        lsr
        lsr
        lsr
        lsr
        jsr @digit
        pla
        and #15
@digit: cmp #10
        bcc :+
        adc #6
:       adc #'0'
        jmp fb_char

; A/X = unsigned 16-bit number, rendered without leading zeroes.
fb_number:
        sta IPTR
        stx IPTR+1
        lda #0
        sta FBNONZERO
        ldy #0
@digit: lda #'0'
        sta FBDIGIT
@sub:  lda IPTR
        cmp i_tens_lo,y
        lda IPTR+1
        sbc i_tens_hi,y
        bcc @put
        sta IPTR+1
        lda IPTR
        sbc i_tens_lo,y
        sta IPTR
        inc FBDIGIT
        bne @sub
@put:  lda FBDIGIT
        cmp #'0'
        bne @show
        cpy #4
        beq @show
        lda FBNONZERO
        beq @next
        lda FBDIGIT
@show: jsr fb_char
        inc FBNONZERO
@next: iny
        cpy #5
        bcc @digit
        rts

fb_string:
        sta SPTR
        stx SPTR+1
        ldy #0
@copy: lda (SPTR),y
        beq @done
        jsr fb_char
        iny
        bne @copy
@done: rts
fb_char:
        ldx FBINDEX
        cpx #79
        bcs @done
        sta MESSAGE,x
        inc FBINDEX
@done: rts
fb_finish:
        ldx FBINDEX
        lda #0
        sta MESSAGE,x
        rts

; Known token errors identify the symbol/mnemonic and its starting column.
; Missing/oversized include errors identify the requested absolute path.
feedback_error_detail:
        ldx #0
@find: lda SPTR
        cmp fb_detail_lo,x
        bne @next
        lda SPTR+1
        cmp fb_detail_hi,x
        beq @found
@next: inx
        cpx #5
        bcc @find
        rts
@found: cpx #3
        bcs @path
        lda TOKSTART
        clc
        adc #1
        sta ERRCOL
        lda #<TOKEN
        ldx #>TOKEN
        jmp @append
@path: lda #<IPATH
        ldx #>IPATH
@append:
        sta IPTR2
        stx IPTR2+1
        ldx #0
@end:  lda MESSAGE,x
        beq @suffix
        inx
        cpx #79
        bcc @end
@suffix:
        stx FBINDEX
        lda #':'
        jsr fb_char
        lda #' '
        jsr fb_char
        lda IPTR2
        ldx IPTR2+1
        jsr fb_string
        jmp fb_finish

fb_prefix_lo: .lobytes fb_ok,fb_saved,fb_ok,fb_disk,fb_bad_range
fb_prefix_hi: .hibytes fb_ok,fb_saved,fb_ok,fb_disk,fb_bad_range
fb_ok: .byte " Assembled: ",0
fb_saved: .byte " Saved: ",0
fb_disk: .byte " Disk error; not saved: ",0
fb_bad_range: .byte " Invalid save range; not saved: ",0
fb_bytes: .byte " bytes at ",0
fb_byte: .byte " byte at ",0
fb_symbols: .byte " | symbols: ",0
fb_unsaved: .byte " | not saved",0
fb_prompt_bytes: .byte "B ",0
fb_prompt_save: .byte "sym Save: ",0
fb_detail_lo: .lobytes msg_undefined,msg_duplicate,msg_opcode,i_missing,i_size
fb_detail_hi: .hibytes msg_undefined,msg_duplicate,msg_opcode,i_missing,i_size
