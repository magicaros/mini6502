;=============================================================================
; ctlgeo.inc - controls: geometry, lists, scroll bars, arithmetic; assembled
; into toolkit banks 3, 4 and 5
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
;=============================================================================


; Carry clear if X is a control in use (CI = X)
valid:  stx CI
        cpx #MAXALL
        bcs @no
        lda C_KIND,x
        beq @no
        clc
        rts
@no:    sec
        rts

;=============================================================================
; geometry
;=============================================================================

; OXW, OYW = the top left corner of control X's window contents
ctlorg: stx CI
        lda C_WIN,x
        cmp #DLGWIN
        bne @win
        lda DLGOX
        sta OXW
        lda DLGOX+1
        sta OXW+1
        lda DLGOY
        sta OYW
        lda DLGOY+1
        sta OYW+1
        ldx CI
        rts
@win:   tax
        jsr wincontent
        lda RX0
        sta OXW
        lda RX0+1
        sta OXW+1
        lda RY0
        sta OYW
        lda RY0+1
        sta OYW+1
        ldx CI
        rts

; RX0..RY1 = control X on the screen (CI = X)
ctlrect:
        jsr ctlorg
        clc
        lda OXW
        adc C_X0L,x
        sta RX0
        lda OXW+1
        adc C_X0H,x
        sta RX0+1
        clc
        lda OYW
        adc C_Y0L,x
        sta RY0
        lda OYW+1
        adc C_Y0H,x
        sta RY0+1
        clc
        lda OXW
        adc C_X1L,x
        sta RX1
        lda OXW+1
        adc C_X1H,x
        sta RX1+1
        clc
        lda OYW
        adc C_Y1L,x
        sta RY1
        lda OYW+1
        adc C_Y1H,x
        sta RY1+1
        rts

; ROWS = rows of list CI, SHOWSB = 1 if they do not all fit, TXR = the right
; edge of the rows; RX0..RY1 = the list
listgeom:
        ldx CI
        jsr ctlrect
        lda RY1                 ; rows = (height - 4) / 16
        sec
        sbc RY0
        sta T0
        lda RY1+1
        sbc RY0+1
        sta T0+1
        SUBW T0, T0, 3
        lsr T0+1
        ror T0
        lsr T0+1
        ror T0
        lsr T0+1
        ror T0
        lsr T0+1
        ror T0
        lda T0
        bne @r1
        lda #1
@r1:    sta ROWS
        ldx CI
        lda #0
        sta SHOWSB
        lda C_MAXL,x
        cmp ROWS
        beq @fit
        bcc @fit
        inc SHOWSB
@fit:   SUBW TXR, RX1, 2
        lda SHOWSB
        beq @r
        SUBW TXR, RX1, 17
@r:     rts

; Port B on item A of list CI (each item ends with 0)
listseek:
        sta TMPB
        ldx CI
        lda C_PTRL,x
        sta T0
        lda C_PTRH,x
        sta T0+1
        lda CBANK
        pha
        lda C_BANK,x
        sta CBANK
        jsr farptr
        pla
        sta CBANK
        lda #1
        sta PBSTEP
@s:     lda TMPB
        beq @r
@c:     lda PBDATA
        bne @c
        dec TMPB
        jmp @s
@r:     rts

;=============================================================================
; scroll bars (a SCROLL control, or the bar of a LIST)
;=============================================================================

; SBX0, SBY0, SBY1 / SBV, SBM, SBP for control CI (RX0..RY1 = it)
sbsetup:
        ldx CI
        lda C_KIND,x
        cmp #CK_LIST
        beq @list
        MOVW SBX0, RX0
        MOVW SBY0, RY0
        MOVW SBY1, RY1
        lda C_VALL,x
        sta SBV
        lda C_VALH,x
        sta SBV+1
        lda C_MAXL,x
        sta SBM
        lda C_MAXH,x
        sta SBM+1
        lda C_AUX,x
        sta SBP
        rts
@list:  jsr listgeom            ; the bar of a list: top 0 .. count - rows
        SUBW SBX0, RX1, 15
        MOVW SBY0, RY0
        MOVW SBY1, RY1
        ldx CI
        lda C_TOP,x
        sta SBV
        lda #0
        sta SBV+1
        sta SBM+1
        lda C_MAXL,x
        sec
        sbc ROWS
        bcs @m
        lda #0
@m:     sta SBM
        ldx ROWS                ; page: rows - 1 (1 at least)
        dex
        bne @p
        inx
@p:     stx SBP
        rts
.ifndef TK3

; SBV back into control CI (value, or a list's top row)
sbstore:
        ldx CI
        lda C_KIND,x
        cmp #CK_LIST
        beq @list
        lda SBV
        sta C_VALL,x
        lda SBV+1
        sta C_VALH,x
        rts
@list:  lda SBV
        sta C_TOP,x
        rts
.endif

; TRL = the track's length minus the thumb: (SBY1 - SBY0 + 1) - 32 - 16
sbtrack:
        lda SBY1
        sec
        sbc SBY0
        sta TRL
        lda SBY1+1
        sbc SBY0+1
        sta TRL+1
        SUBW TRL, TRL, 47
        bpl @r
        lda #0
        sta TRL
        sta TRL+1
@r:     rts

; THY = the thumb's top: SBY0 + 16 + SBV * TRL / SBM
sbthumb:
        jsr sbtrack
        lda #0
        sta THY
        sta THY+1
        lda SBM
        ora SBM+1
        beq @add
        lda SBV
        sta MA
        lda SBV+1
        sta MA+1
        lda TRL
        sta MB
        lda TRL+1
        sta MB+1
        jsr mul16
        lda SBM
        sta MD
        lda SBM+1
        sta MD+1
        jsr div32
        lda PR
        sta THY
        lda PR+1
        sta THY+1
@add:   lda THY
        clc
        adc SBY0
        sta THY
        lda THY+1
        adc SBY0+1
        sta THY+1
        ADDW THY, THY, 16
        rts

; The top row of list X moved so that its chosen item shows
showsel:
        stx CI
        lda C_VALH,x
        bne @r
        jsr listgeom
        ldx CI
        lda C_VALL,x
        cmp C_TOP,x             ; above the top: it becomes the top
        bcs @b
        sta C_TOP,x
        rts
@b:     sec                     ; below the last row: top = item - rows + 1
        sbc ROWS
        bcc @r
        clc
        adc #1
        cmp C_TOP,x
        bcc @r
        sta C_TOP,x
@r:     ldx CI
        rts

;=============================================================================
; arithmetic, lines
;=============================================================================

; PR (4 bytes) = MA * MB
mul16:  lda #0
        sta PR+2
        sta PR+3
        ldx #16
@l:     lsr MB+1
        ror MB
        bcc @n
        lda PR+2
        clc
        adc MA
        sta PR+2
        lda PR+3
        adc MA+1
        sta PR+3
@n:     ror PR+3
        ror PR+2
        ror PR+1
        ror PR
        dex
        bne @l
        rts

; PR = PR / MD (32 bits by 16)
div32:  lda #0
        sta REM
        sta REM+1
        ldx #32
@l:     asl PR
        rol PR+1
        rol PR+2
        rol PR+3
        rol REM
        rol REM+1
        lda REM
        sec
        sbc MD
        tay
        lda REM+1
        sbc MD+1
        bcc @n
        sta REM+1
        sty REM
        inc PR
@n:     dex
        bne @l
        rts
