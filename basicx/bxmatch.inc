; bxmatch.inc - the keyword matcher for mini6502 BASIC extensions.
; Part of mini6502 BASIC, derived from EhBASIC (c) Lee Davison: free for
; personal, non-commercial use only (see basic/README.txt).
; mini6502 additions Copyright (C) 2026 Benoit Colson, with the help of Claude AI.
; .include it after bx.inc. Uses zero page $F0-$F7.
;
; XMATCH: X/Y = a keyword list:
;     .byte "PLO", 'T'+$80, "LIN", 'E'+$80, 0
; Spaces between "!" and the keyword are fine.
KWP     = $F0           ; 2: the keyword list
TOKP    = $F2           ; 2: the text of a token being spelled out
TOKN    = $F4           ; characters of it still to come
TOKO    = $F5           ; where in it
INOFF   = $F6           ; offset in the BASIC line
KOFF    = $F7           ; offset in the keyword list

; which keyword of the list at X/Y comes next in the line? The list:
; each keyword in capitals, its last character + $80, then 0. Words BASIC
; turned into tokens are spelled out (COLOR is stored as C O L and OR). The
; keyword must not run on into a letter. Found: carry clear, A = its number
; (0 = the first), the line moved on past it (and to the next non-space).
; Not found: carry set, the line as it was.
XMATCH: stx KWP
        sty KWP+1
        lda #0
        sta KIDX
@kw:    ldy #0
        lda (KWP),y
        bne @try
        sec                     ; the end of the list
        rts
@try:   lda #0
        sta INOFF
        sta TOKN
        sta KOFF
@ch:    jsr @next               ; the next character of the line
        sta KCH
        ldy KOFF
        lda (KWP),y
        and #$7F
        cmp KCH
        bne @fail
        lda (KWP),y
        inc KOFF
        asl                     ; its last character?
        bcc @ch
        lda TOKN                ; not in the middle of a token
        bne @fail
        ldy INOFF               ; and no letter right after it (a token
        lda (Bpntrl),y          ; is fine: + - * / and so on)
        cmp #'A'
        bcc @ok
        cmp #'Z'+1
        bcc @fail
@ok:    clc                     ; found: the line moves on
        lda Bpntrl
        adc INOFF
        sta Bpntrl
        bcc @nc
        inc Bpntrh
@nc:    jsr XCHRGOT
        lda KIDX
        clc
        rts
@fail:  ldy #0                  ; on to the next keyword in the list
@sk:    lda (KWP),y
        iny
        asl
        bcc @sk
        tya
        clc
        adc KWP
        sta KWP
        bcc @nc2
        inc KWP+1
@nc2:   inc KIDX
        jmp @kw
; the next character of the line, tokens spelled out, in capitals
@next:  lda TOKN
        beq @raw
        dec TOKN
        ldy TOKO
        inc TOKO
        lda (TOKP),y
        and #$7F
        rts
@raw:   ldy INOFF
        inc INOFF
        lda (Bpntrl),y
        bmi @tok
        cmp #'a'
        bcc @r
        cmp #'z'+1
        bcs @r
        and #$DF
@r:     rts
@tok:   asl                     ; its keyword table entry: length, first
        asl                     ; character, address of the rest
        ldx XKEYT+1
        bcc @t1
        inx
        clc
@t1:    adc XKEYT
        bcc @t2
        inx
@t2:    sta TOKP
        stx TOKP+1
        ldy #0
        lda (TOKP),y            ; length
        sec
        sbc #1
        sta TOKN
        iny
        lda (TOKP),y            ; first character
        pha
        iny
        lda (TOKP),y
        tax
        iny
        lda (TOKP),y
        stx TOKP
        sta TOKP+1
        lda #0
        sta TOKO
        pla
        rts

KIDX:   .byte 0             ; the keyword's number
KCH:    .byte 0             ; the line's character being compared
