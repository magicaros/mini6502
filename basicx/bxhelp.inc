; bxhelp.inc - !HELP for mini6502 BASIC extensions: the commands and
; functions of EVERY extension loaded (whichever one answers !HELP), read
; from their headers ("BX", 2: name at $E00C, keyword lists at $E014 /
; $E016) through port A (put back afterwards).
; Part of mini6502 BASIC, derived from EhBASIC (c) Lee Davison: free for
; personal, non-commercial use only (see basic/README.txt).
; mini6502 additions Copyright (C) 2026 Benoit Colson, with the help of Claude AI.
; Uses $F8-$FE.

XMASK   = $0310                 ; the extensions' banks (bit N: bank N)
HMASK   = $F8
HBANK   = $F9
HLO     = $FA                   ; an address in that bank
HHI     = $FB
HCH     = $FC
HVER    = $FD
HCOL    = $FE                   ; the column (words wrap before 70)

bxhelp: lda PADR                ; port A: kept
        pha
        lda PADR+1
        pha
        lda PADR+2
        pha
        lda PSTEP
        pha
        lda #1
        sta PSTEP
        lda XMASK
        sta HMASK
        lda #0
        sta HBANK
@bank:  lsr HMASK
        bcc @next
        lda #<$E000             ; "BX", version
        ldx #>$E000
        jsr hseek
        lda PDATA
        cmp #'B'
        bne @next
        lda PDATA
        cmp #'X'
        bne @next
        lda PDATA
        sta HVER                ; (version)
        lda #<$E00C             ; its name
        ldx #>$E00C
        jsr hseek
        ldx #8
@n:     lda PDATA
        beq @nd
        jsr XPRINT
        dex
        bne @n
@nd:    lda #':'
        jsr XPRINT
        jsr XCRLF
        lda HVER                ; version 1: just its name
        cmp #2
        bcc @next
        lda #<$E014             ; its commands
        ldx #>$E014
        jsr hlist
        lda #<$E016             ; its functions
        ldx #>$E016
        jsr hlist
@next:  inc HBANK
        lda HBANK
        cmp #8
        bne @bank
        pla
        sta PSTEP
        pla
        sta PADR+2
        pla
        sta PADR+1
        pla
        sta PADR
        clc
        rts

; The word list whose address is at XA in that bank: "  !WORD !WORD...",
; a new line (nothing if the address is 0)
hlist:  jsr hseek
        lda PDATA
        sta HLO
        lda PDATA
        sta HHI
        ora HLO
        beq @r
        lda HLO
        ldx HHI
        jsr hseek
        lda #' '
        jsr XPRINT
        lda #1
        sta HCOL
@w:     lda PDATA               ; a word: its last letter has bit 7
        beq @e
        sta HCH
        lda HCOL                ; the line is full: a new one
        cmp #70
        bcc @sp
        jsr XCRLF
        lda #' '
        jsr XPRINT
        lda #1
        sta HCOL
@sp:    lda #' '
        jsr XPRINT
        lda #'!'
        jsr XPRINT
        inc HCOL
        inc HCOL
        lda HCH
@c:     and #$7F
        jsr XPRINT
        inc HCOL
        lda HCH
        bmi @w
        lda PDATA
        sta HCH
        jmp @c
@e:     jsr XCRLF
@r:     rts

; Port A at XA (an address $E000-$EFFF) in bank HBANK
hseek:  sta PADR
        txa
        and #$0F
        sta HCH
        lda HBANK
        asl
        asl
        asl
        asl
        ora HCH
        sta PADR+1
        lda #0                  ; (banks 0-7: the top byte is 0)
        sta PADR+2
        rts
