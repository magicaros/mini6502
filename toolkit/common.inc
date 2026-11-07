;=============================================================================
; common.inc - drawing helpers assembled into both toolkit banks
;=============================================================================

; Blitter X0,Y0-X1,Y1 = RX0,RY0-RX1,RY1
setrect:
        lda RX0
        sta BX0
        lda RX0+1
        sta BX0H
        lda RY0
        sta BY0
        lda RY0+1
        sta BY0H
        lda RX1
        sta BX1
        lda RX1+1
        sta BX1H
        lda RY1
        sta BY1
        lda RY1+1
        sta BY1H
        rts

; Filled box over RX0..RY1 with colour A (0 paper, 1 ink), plain SET
fillrect:
        ldx #R_SET
        stx ROP
        ldx #0
        stx PATON
fillr2: sta BCOL
        jsr setrect
        lda #C_BOXF
        sta BCMD
        rts

; Frame (BOX) around RX0..RY1 in ink
framerect:
        lda #R_SET
        sta ROP
        lda #0
        sta PATON
        lda #1
        sta BCOL
        jsr setrect
        lda #C_BOX
        sta BCMD
        rts

; RX0..RY1 filled with the current PATTERN
patrect:
        lda #R_SET
        sta ROP
        lda #1
        sta PATON
        jsr fillr2
        lda #0
        sta PATON
        rts

; RX0..RY1 inverted
invrect:
        lda #R_INV
        sta ROP
        lda #0
        sta PATON
        jsr fillr2
        lda #R_SET
        sta ROP
        rts

; Clip rectangle = RX0..RY1
clipset:
        ldx #7
@c:     lda RX0,x
        sta CLIPR,x
        dex
        bpl @c
        rts

; Clip rectangle = the whole screen
clipfull:
        lda #0
        sta CLIPR
        sta CLIPR+1
        sta CLIPR+2
        sta CLIPR+3
        lda #<639
        sta CLIPR+4
        lda #>639
        sta CLIPR+5
        lda #<399
        sta CLIPR+6
        lda #>399
        sta CLIPR+7
        rts

; Text position X0 = T0, Y0 = T1
moveto:
        lda T0
        sta BX0
        lda T0+1
        sta BX0H
        lda T1
        sta BY0
        lda T1+1
        sta BY0H
        rts

; Draws the 0-terminated string at TP (fixed RAM) at X0,Y0 in STYLE
drawstr:
        ldy #0
@l:     lda (TP),y
        beq @e
        sta CHOUT
        iny
        bne @l
@e:     rts

; A = length of the string at TP (up to 255)
strlen:
        ldy #0
@l:     lda (TP),y
        beq @e
        iny
        bne @l
@e:     tya
        rts

; PATTERN = 8 bytes at QP
setpat:
        ldy #7
@p:     lda (QP),y
        sta PATTERN,y
        dey
        bpl @p
        rts
patgrey:
        lda #<pgrey
        sta QP
        lda #>pgrey
        sta QP+1
        jmp setpat
patstripe:
        lda #<pstripe
        sta QP
        lda #>pstripe
        sta QP+1
        jmp setpat
pgrey:   .byte $AA, $55, $AA, $55, $AA, $55, $AA, $55
pstripe: .byte $00, $FF, $00, $FF, $00, $FF, $00, $FF

; COPY RX0..RY1 from page 0 to the same place on page 1 (save what is under)
saveunder:
        lda #1
        sta DRAW
        lda #0
        sta BSRC
        jmp copysame
; ... and back from page 1 to page 0
restunder:
        lda #0
        sta DRAW
        lda #1
        sta BSRC
copysame:
        lda #R_SET
        sta ROP
        jsr setrect
        lda RX0
        sta BDX
        lda RX0+1
        sta BDXH
        lda RY0
        sta BDY
        lda RY0+1
        sta BDYH
        jsr clipfull
        lda #C_COPY
        sta BCMD
        lda #0
        sta DRAW
        rts

; MX, MY = the mouse
readmouse:
        lda MOUSEX
        sta MX
        lda MOUSEX+1
        sta MX+1
        lda MOUSEY
        sta MY
        lda MOUSEY+1
        sta MY+1
        rts

; Carry set if MX,MY is inside RX0..RY1
inrect:
        lda MX                  ; MX >= RX0
        cmp RX0
        lda MX+1
        sbc RX0+1
        bcc @no
        lda RX1                 ; RX1 >= MX
        cmp MX
        lda RX1+1
        sbc MX+1
        bcc @no
        lda MY
        cmp RY0
        lda MY+1
        sbc RY0+1
        bcc @no
        lda RY1
        cmp MY
        lda RY1+1
        sbc MY+1
@no:    rts                     ; carry = the last comparison

; Waits for the next frame
waitframe:
        lda FRAME
@w:     cmp FRAME
        beq @w
        rts

; T0 = X position that centres A characters between RX0 and RX1:
; (RX0 + RX1) / 2 - A * 4
centrex:
        sta TMPB
        lda RX0
        clc
        adc RX1
        sta T0
        lda RX0+1
        adc RX1+1
        lsr
        sta T0+1
        ror T0
        lda #0
        sta TMPC
        lda TMPB                ; A * 4 -> TMPC:TMPB
        asl
        rol TMPC
        asl
        rol TMPC
        sta TMPB
        lda T0
        sec
        sbc TMPB
        sta T0
        lda T0+1
        sbc TMPC
        sta T0+1
        rts

; Port B = the caller's address T0: $E000-$EFFF is in the caller's bank
; (CBANK), anything else in the fixed RAM
farptr:
        lda T0
        sta PBADR
        lda T0+1
        and #$F0
        cmp #$E0
        bne @fixed
        lda T0+1
        and #$0F
        sta T3
        lda CBANK
        asl
        asl
        asl
        asl
        ora T3
        sta PBADR+1
        lda CBANK
        lsr
        lsr
        lsr
        lsr
        sta PBADR+2
        rts
@fixed: lda T0+1
        sta PBADR+1
        lda #$FF
        sta PBADR+2
        rts

; Copies the caller's string at T0 to QP (fixed RAM), at most A characters,
; always ending with 0
fetchstr:
        sta T3+1
        jsr farptr
        ldy #0
@l:     cpy T3+1
        beq @end
        lda PBDATA
        sta (QP),y
        beq @done
        iny
        bne @l
@end:   lda #0
        sta (QP),y
@done:  rts
