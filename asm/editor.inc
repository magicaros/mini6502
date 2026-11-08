; Included only in ASM's version of EDIT. No effect on the EDIT binary.
; Persistent private image is allocated in the documents zone, independently
; of EDIT's $E0 image. The caller still occupies the standard $F0 swap area.
ASMIMAGE = $EF70
ASMBANK = $EF71
ASMSTAT = $EF72
ASMTAG = $EF73
ASMMODE = $EFF9                ; caller display state, outside swapped RAM
ASMPTR = $EFFA
ASMNAME = $EF00

asm_image:
        lda ASMTAG
        cmp #$5A
        bne @allocate
        lda ASMIMAGE
        cmp #$80
        bcc @allocate
        cmp #$B4
        bcs @allocate
        ldy #0
@owner: tya
        clc
        adc ASMIMAGE
        jsr BOWNER
        cmp BANK
        bne @allocate
        iny
        cpy #13
        bcc @owner
        lda ASMIMAGE
        bne @patch
@allocate:
        lda BANK
        ldx #13
        ldy #1
        jsr BALLOC
        bcc @got
        ; enter's own caller remains on the stack: return to the application
        pla
        pla
        pla
        pla
        lda #1
        sta BEEP
        rts
@got:   sta ASMIMAGE
        pha
        lda #$5A
        sta ASMTAG
        lda #0
        sta INSIDE
        pla
@patch: pha
        and #$0F
        asl
        asl
        asl
        asl
        sta d_load+1
        sta d_keep+4
        pla
        lsr
        lsr
        lsr
        lsr
        sta d_load+2
        sta d_keep+5
        rts

k_assemble:
        lda #<asm_work
        ldx #>asm_work
        jsr prompt
        lda #<asm_core_name
        sta DNAME
        lda #>asm_core_name
        sta DNAME+1
        lda #0
        sta DNLEN
        sta DSTART
        sta DEND
        lda #$84
        sta DSTART+1
        lda #$B0
        sta DEND+1
        lda #3
        sta DCMD
        lda DSTAT
        beq @loaded
        lda #<asm_missing
        ldx #>asm_missing
        jmp setmsg
@loaded:
        lda ASMIMAGE
        sta $C407
        jsr $8400
        lda $C400
        beq @save
        ; Move to the first column of the offending line, preserving text.
@home:  jsr left1
        bcc @home
@line:  clc
        lda CURLINE
        adc #1
        sta T
        lda CURLINE+1
        adc #0
        sta T+1
        lda T
        cmp $C401
        lda T+1
        sbc $C402
        bcs @atline
        jsr right1
        bcc @line
@atline:
        ldx $C412               ; core's 1-based error column in the root buffer
        beq @positioned
        dex
        beq @positioned
@column:
        jsr charafter
        bcs @positioned
        cmp #CR
        beq @positioned
        jsr right1
        dex
        bne @column
@positioned:
        jsr setwant
        lda #2
        sta REDRAW
        lda #<$C500
        ldx #>$C500
        jmp setmsg
@save:  lda #<$C480             ; address/size/symbol summary + filename prompt
        ldx #>$C480
        pha
        lda NAMELEN
        sta ASMBANK
        lda #0                  ; binary prompt starts empty, source name kept
        sta NAMELEN
        pla
        jsr askname
        php
        lda ASMBANK
        sta NAMELEN
        plp
        bcs @cancel
        ; Never overwrite the currently edited source with machine code.
        lda INLEN
        cmp NAMELEN
        bne @write
        ldx #0
@same:  lda INBUF,x
        eor NAME,x
        and #$DF
        bne @write
        inx
        cpx INLEN
        bcc @same
        lda #<asm_samename
        ldx #>asm_samename
        jmp setmsg
@write: jsr $8403
        lda #2
        sta REDRAW
        lda #<$C500
        ldx #>$C500
        jmp setmsg
@cancel:
        lda #<$C500
        ldx #>$C500
        jmp setmsg

; Called by core at $E009. All live fixed RAM, including the core, its
; stack and the source, is restored even if the disk SAVE fails.
asm_save_fixed:
        ldx #0
@name:  lda INBUF,x
        sta ASMNAME,x
        inx
        cpx INLEN
        bcc @name
        lda #0
        sta ASMNAME,x
        lda $C403
        sta asm_stage+3
        sta DSTART
        lda $C404
        sta asm_stage+4
        sta DSTART+1
        clc
        lda $C403
        adc $C405
        sta DEND
        lda $C404
        adc $C406
        sta DEND+1
        lda $C405
        sta asm_stage+6
        lda $C406
        sta asm_stage+7
        lda #<ASMNAME
        sta DNAME
        lda #>ASMNAME
        sta DNAME+1
        lda #0
        sta DNLEN
        DMACOPY d_keep
        DMACOPY asm_stage
        lda #2
        sta DCMD
        lda DSTAT
        sta ASMSTAT
        DMACOPY d_load
        lda ASMSTAT
        rts
asm_stage: .byte $00,$44,$FF, 0,0,$FF, 0,0,0
asm_core_name: .byte "/ASM/ASMCORE",0
asm_missing: .byte " Cannot load /ASM/ASMCORE (missing or too large)",0
asm_work: .byte " Assembling...",0
asm_samename: .byte " Binary name must differ from source name",0
asm_error_line: .byte " Line ",0
asm_error_col: .byte " col ",0
        .assert * <= $EF00, error, "ASM code overlaps its save-name buffer"
