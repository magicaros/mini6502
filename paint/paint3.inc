;=============================================================================
; paint3.inc - PAINT2 (main RAM), continued: ovals, the selection and the
; Edit menu, text, the paint bucket, FatBits. Part of paint.asm.
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
;=============================================================================

; The port on our window, the clip on the canvas
pcan:   jsr setport
        jmp canclip

; --- ovals ----------------------------------------------------------------------
; The oval in X0..Y1, row by row: CNT2 = 0 its outline (every pixel once, so
; it can be XORed), 1 filled. ROP, PATON, COLOR as the caller set them.
ovalspans:
        lda X1                  ; RXO = (X1 - X0) / 2, CXC = X0 + RXO
        sec
        sbc X0
        sta RXO
        lda X1+1
        sbc X0+1
        lsr
        sta RXO+1
        ror RXO
        lda X0
        clc
        adc RXO
        sta CXC
        lda X0+1
        adc RXO+1
        sta CXC+1
        lda Y1                  ; RYO = (Y1 - Y0) / 2 (< 256), CYC
        sec
        sbc Y0
        sta U0
        lda Y1+1
        sbc Y0+1
        lsr
        ror U0
        lda U0
        sta RYO
        clc
        adc Y0
        sta CYC
        lda Y0+1
        adc #0
        sta CYC+1
        lda #0
        sta TACC
        sta TACC+1
        sta DYC
        MOVW PDX, RXO
        lda RYO                 ; TSTEP = 65535 / RYO
        beq @row
        LDW N0, $FFFF
        lda RYO
        jsr div16
        MOVW TSTEP, N0
@row:   lda DYC                 ; this row's half width
        cmp RYO
        bne @w
        lda #0
        sta CDX
        sta CDX+1
        lda RYO
        bne @have
        MOVW CDX, RXO           ; (a flat oval: one row)
        jmp @have
@w:     ldx TACC+1              ; CDX = RXO - RXO * shrink[t] / 256
        lda shrink,x
        jsr mulrx               ; N1 = RXO * A / 256
        lda RXO
        sec
        sbc N1
        sta CDX
        lda RXO+1
        sbc N1+1
        sta CDX+1
@have:  lda CYC                 ; the row below the middle
        clc
        adc DYC
        sta HY
        lda CYC+1
        adc #0
        sta HY+1
        jsr ospan
        lda DYC                 ; and above it
        beq @next
        lda CYC
        sec
        sbc DYC
        sta HY
        lda CYC+1
        sbc #0
        sta HY+1
        jsr ospan
@next:  MOVW PDX, CDX
        lda TACC
        clc
        adc TSTEP
        sta TACC
        lda TACC+1
        adc TSTEP+1
        sta TACC+1
        lda DYC
        cmp RYO
        beq @r
        inc DYC
        jmp @row
@r:     rts

; Row HY of the oval: filled -CDX..CDX; the outline CDX..max(CDX, PDX - 1)
; on each side (the middle pixel once)
ospan:  lda CNT2
        beq @o
        lda CXC                 ; filled
        sec
        sbc CDX
        sta HA
        lda CXC+1
        sbc CDX+1
        sta HA+1
        lda CXC
        clc
        adc CDX
        sta HB
        lda CXC+1
        adc CDX+1
        sta HB+1
        jmp hspan
@o:     MOVW OA, CDX            ; OA..OB: the run on the right side
        MOVW OB, CDX
        lda DYC
        beq @s
        lda PDX
        sec
        sbc #1
        sta U0
        lda PDX+1
        sbc #0
        sta U0+1
        bmi @s
        lda OB
        cmp U0
        lda OB+1
        sbc U0+1
        bcs @s
        MOVW OB, U0
@s:     lda CXC                 ; right: CXC + OA .. CXC + OB
        clc
        adc OA
        sta HA
        lda CXC+1
        adc OA+1
        sta HA+1
        lda CXC
        clc
        adc OB
        sta HB
        lda CXC+1
        adc OB+1
        sta HB+1
        jsr hspan
        lda OA                  ; left: CXC - OB .. CXC - OA (or - 1)
        ora OA+1
        bne @l
        lda OB
        ora OB+1
        beq @r
        LDW OA, 1
@l:     lda CXC
        sec
        sbc OB
        sta HA
        lda CXC+1
        sbc OB+1
        sta HA+1
        lda CXC
        sec
        sbc OA
        sta HB
        lda CXC+1
        sbc OA+1
        sta HB+1
        jmp hspan
@r:     rts
; A filled box HA..HB on row HY (negative x: from 0)
hspan:  lda HB+1
        bmi @r
        lda HA+1
        bpl @a
        lda #0
        sta HA
        sta HA+1
@a:     lda HA
        sta BX0
        lda HA+1
        sta BX0H
        lda HB
        sta BX1
        lda HB+1
        sta BX1H
        lda HY
        sta BY0
        sta BY1
        lda HY+1
        sta BY0H
        sta BY1H
        lda #C_BOXF
        sta BCMD
@r:     rts

; N0 = N0 / A (16 by 8 bits)
div16:  sta U1
        lda #0
        ldx #16
@l:     asl N0
        rol N0+1
        rol a
        bcs @s
        cmp U1
        bcc @n
@s:     sbc U1
        inc N0
@n:     dex
        bne @l
        rts
; N1 = RXO * A / 256 (rounded)
mulrx:  sta U1
        lda #0
        sta N1
        sta N1+1
        sta N2                  ; N2: the low byte
        sta U3
        MOVW U2, RXO
        ldx #8
@l:     lsr U1
        bcc @n
        lda N2
        clc
        adc U2
        sta N2
        lda N1
        adc U2+1
        sta N1
        lda N1+1
        adc U3
        sta N1+1
@n:     asl U2
        rol U2+1
        rol U3
        dex
        bne @l
        lda N2                  ; rounded
        bpl @r
        inc N1
        bne @r
        inc N1+1
@r:     rts

; --- the selection ---------------------------------------------------------------
; Its marching frame (XOR) on / off
selxor: lda #R_XOR
        sta ROP
        lda #0
        sta PATON
        lda #1
        sta BCOL
        ldx #SX0
        ldy #SY0
        jsr bxy0
        ldx #SX1
        ldy #SY1
        jsr bxy1
        lda #C_BOX
        sta BCMD
        lda #R_SET
        sta ROP
        rts
; No selection
selnone:
        lda SEL
        beq @r
        jsr pcan
        jsr selxor
        lda #0
        sta SEL
@r:     rts

; The selection tool: inside the selection, it is dragged (with Shift: a
; copy of it); elsewhere a new one is drawn
t_sel:  lda SEL
        beq @new
        lda PMX
        cmp SX0
        lda PMX+1
        sbc SX0+1
        bcc @out
        lda SX1
        cmp PMX
        lda SX1+1
        sbc PMX+1
        bcc @out
        lda PMY
        cmp SY0
        lda PMY+1
        sbc SY0+1
        bcc @out
        lda SY1
        cmp PMY
        lda SY1+1
        sbc PMY+1
        bcc @out
        jmp seldrag
@out:   jsr selnone
@new:   MOVW SX, PMX
        MOVW SY, PMY
        jsr mtol
        lda #1
        sta SHAPE
        jsr xorshape
@l:     jsr wait1
        bcs @up
        jsr mclamp
        jsr moved
        bcs @l
        jsr xorshape
        jsr mtol
        jsr xorshape
        jmp @l
@up:    jsr xorshape
        lda CLICKS
        jsr order
        lda X0                  ; a point is no selection
        cmp X1
        bne @ok
        lda X0+1
        cmp X1+1
        beq @r
@ok:    lda Y0
        cmp Y1
        bne @set
        lda Y0+1
        cmp Y1+1
        beq @r
@set:   ldx #7
@c:     lda X0,x
        sta SX0,x
        dex
        bpl @c
        lda #1
        sta SEL
        jmp selxor
@r:     rts

; The selection dragged: a copy of it on VRAM page 1 is drawn where the
; mouse takes it, over the picture as it is without it
seldrag:
        jsr snapshot
        jsr selxor
        lda #140                ; Shift held: a copy
        sta KEYSEL
        lda KEYHELD
        sta CNT
        lda #R_SET              ; the selection -> page 1, same place
        sta ROP
        lda #0
        sta PATON
        sta BSRC
        lda #1
        sta DRAW
        jsr selsrc
        lda SX0
        sta BDX
        lda SX0+1
        sta BDXH
        lda SY0
        sta BDY
        lda SY0+1
        sta BDYH
        lda #C_COPY
        sta BCMD
        lda #0
        sta DRAW
        lda CNT
        bne @k
        lda #0                  ; moving: a white hole where it was
        sta BCOL
        ldx #SX0
        ldy #SY0
        jsr bxy0
        ldx #SX1
        ldy #SY1
        jsr bxy1
        lda #C_BOXF
        sta BCMD
@k:     jsr commit              ; (the picture without it)
        MOVW SX, PMX
        MOVW SY, PMY
        jsr mtol
        ldx #7                  ; Q: where it is now
@q:     lda SX0,x
        sta QX0,x
        dex
        bpl @q
@l:     jsr wait1
        jcs @up
        jsr moved
        bcs @l
        jsr mtol
        ldx #7                  ; the old place from the picture
@o:     lda QX0,x
        sta X0,x
        dex
        bpl @o
        jsr showrect
        lda PMX                  ; the new place: SX0 + PMX - SX
        sec
        sbc SX
        sta U0
        lda PMX+1
        sbc SX+1
        sta U0+1
        lda SX0
        clc
        adc U0
        sta QX0
        lda SX0+1
        adc U0+1
        sta QX0+1
        bpl @x
        lda #0
        sta QX0
        sta QX0+1
@x:     lda PMY
        sec
        sbc SY
        sta U0
        lda PMY+1
        sbc SY+1
        sta U0+1
        lda SY0
        clc
        adc U0
        sta QY0
        lda SY0+1
        adc U0+1
        sta QY0+1
        bpl @y
        lda #0
        sta QY0
        sta QY0+1
@y:     lda SX1                 ; the same size
        sec
        sbc SX0
        sta U0
        lda SX1+1
        sbc SX0+1
        sta U0+1
        lda QX0
        clc
        adc U0
        sta QX1
        lda QX0+1
        adc U0+1
        sta QX1+1
        lda SY1
        sec
        sbc SY0
        sta U0
        lda SY1+1
        sbc SY0+1
        sta U0+1
        lda QY0
        clc
        adc U0
        sta QY1
        lda QY0+1
        adc U0+1
        sta QY1+1
        jsr selsrc              ; page 1 -> there
        lda QX0
        sta BDX
        lda QX0+1
        sta BDXH
        lda QY0
        sta BDY
        lda QY0+1
        sta BDYH
        lda #1
        sta BSRC
        lda #R_SET
        sta ROP
        lda #C_COPY
        sta BCMD
        lda #0
        sta BSRC
        jmp @l
@up:    lda CLICKS
        jsr commit
        jsr changed
        ldx #7
@s:     lda QX0,x
        sta SX0,x
        dex
        bpl @s
        jmp selxor
; The blitter's source rectangle: the selection
selsrc: ldx #SX0
        ldy #SY0
        jsr bxy0
        ldx #SX1
        ldy #SY1
        jmp bxy1

; GX, GY, GW, H = the selection's left, top, width, height
selgeo: MOVW GX, SX0
        MOVW GY, SY0
        lda SX1
        sec
        sbc SX0
        sta GW
        lda SX1+1
        sbc SX0+1
        sta GW+1
        inc GW
        bne @h
        inc GW+1
@h:     lda SY1
        sec
        sbc SY0
        sta HH
        lda SY1+1
        sbc SY0+1
        sta HH+1
        inc HH
        bne @r
        inc HH+1
@r:     rts

; Before an Edit command on the selection: carry set if there is none;
; else the undo copy taken, the frame off
selop:  lda SEL
        bne @y
        lda #1
        sta BEEP
        sec
        rts
@y:     jsr pcan
        jsr snapshot
        jsr selxor
        clc
        rts
; After it: the picture, the frame back
selend: jsr commit
        jsr changed
        jsr pcan
        jmp selxor

m_cut:  jsr m_copy
m_clear:
        jsr selop
        bcs @r
        jsr ink
        lda #0
        sta BCOL
        jsr selsrc
        lda #C_BOXF
        sta BCMD
        jmp selend
@r:     rts

m_invert:
        jsr selop
        bcs @r
        jsr selsrc
        lda #R_INV
        sta ROP
        lda #C_BOXF
        sta BCMD
        lda #R_SET
        sta ROP
        jmp selend
@r:     rts

; Copy: the selection -> the clipboard banks: width, height (2 bytes
; each), then its rows, (width + 7) / 8 bytes each, bit 7 = the left pixel
m_copy: lda SEL
        beq @r
        lda CLPB
        cmp #$FF
        beq @r
        jsr pcan
        jsr selxor
        jsr selgeo
        lda #0
        sta N0
        sta N0+1
        ldx #DD
        jsr ofclp
        jsr padrdd              ; the header
        lda GW
        sta PDATA
        lda GW+1
        sta PDATA
        lda HH
        sta PDATA
        lda HH+1
        sta PDATA
        LDW CLOFF, 4
        jsr rowbytes            ; DL = (GW + 7) / 8
@row:   jsr getrow
        MOVW N0, CLOFF
        ldx #DD
        jsr ofclp
        LDW N0, RB
        ldx #DS
        jsr ofram
        jsr dma
        lda CLOFF
        clc
        adc DL
        sta CLOFF
        bcc @n
        inc CLOFF+1
@n:     jsr nextrow
        bne @row
        jsr selxor
@r:     rts
; DL = (GW + 7) / 8
rowbytes:
        lda GW
        clc
        adc #7
        sta DL
        lda GW+1
        adc #0
        lsr
        ror DL
        lsr
        ror DL
        lsr
        ror DL
        lda #0
        sta DL+1
        rts
; GY one row on, HH one less; Z set when HH is 0
nextrow:
        inc GY
        bne @a
        inc GY+1
@a:     lda HH
        bne @b
        dec HH+1
@b:     dec HH
        lda HH
        ora HH+1
        rts
; Port A on the address in DD
padrdd: lda DD
        sta PADR
        lda DD+1
        sta PADR+1
        lda DD+2
        sta PADR+2
        lda #1
        sta PSTEP
        rts

; Paste: the clipboard at the canvas' top left (as much as fits), then
; selected (the selection tool chosen)
m_paste:
        lda CLPB
        cmp #$FF
        beq @r
        lda #0
        sta N0
        sta N0+1
        ldx #DD
        jsr ofclp
        jsr padrdd
        lda PDATA
        sta CLW
        lda PDATA
        sta CLW+1
        lda PDATA
        sta HH
        lda PDATA
        sta HH+1
        lda CLW
        ora CLW+1
        beq @r
        lda HH
        ora HH+1
        bne @go
@r:     rts
@go:    jsr pcan
        jsr endall
        jsr snapshot
        MOVW GW, CLW            ; the clipboard's row length
        jsr rowbytes
        lda DL
        sta CLRB
        lda CLW                 ; GW = as much as the canvas shows
        cmp CWP
        lda CLW+1
        sbc CWP+1
        bcc @w
        MOVW GW, CWP
@w:     lda HH
        cmp CH
        lda HH+1
        sbc CH+1
        bcc @h
        MOVW HH, CH
@h:     MOVW GX, CANX
        MOVW GY, CANY
        MOVW SX0, CANX          ; it will be the selection
        MOVW SY0, CANY
        lda GX
        clc
        adc GW
        sta SX1
        lda GX+1
        adc GW+1
        sta SX1+1
        lda GY
        clc
        adc HH
        sta SY1
        lda GY+1
        adc HH+1
        sta SY1+1
        lda SX1
        bne @s1
        dec SX1+1
@s1:    dec SX1
        lda SY1
        bne @s2
        dec SY1+1
@s2:    dec SY1
        LDW CLOFF, 4
@row:   MOVW N0, CLOFF
        ldx #DS
        jsr ofclp
        LDW N0, RB
        ldx #DD
        jsr ofram
        lda CLRB
        sta DL
        lda #0
        sta DL+1
        jsr dma
        jsr putrow
        lda CLOFF
        clc
        adc CLRB
        sta CLOFF
        bcc @n
        inc CLOFF+1
@n:     jsr nextrow
        bne @row
        jsr commit
        jsr changed
        lda #1
        sta SEL
        lda #T_SEL
        sta TOOL_
        jsr setport
        jsr drawpal
        jsr canclip
        jmp selxor

; Select all: the whole canvas
m_selall:
        jsr pcan
        jsr endall
        jsr pcan
        MOVW SX0, CANX
        MOVW SY0, CANY
        lda CANX
        clc
        adc CWP
        sta SX1
        lda CANX+1
        adc CWP+1
        sta SX1+1
        lda CANY
        clc
        adc CH
        sta SY1
        lda CANY+1
        adc CH+1
        sta SY1+1
        lda SX1
        bne @a
        dec SX1+1
@a:     dec SX1
        lda SY1
        bne @b
        dec SY1+1
@b:     dec SY1
        lda #1
        sta SEL
        lda #T_SEL
        sta TOOL_
        jsr setport
        jsr drawpal
        jsr canclip
        jmp selxor

; Flip horizontal: each row of the selection the other way round
m_fliph:
        jsr selop
        bcs @r
        jsr selgeo
        jsr rowbytes            ; DL = bytes, pad = DL * 8 - GW
        lda DL
        asl
        asl
        asl
        sec
        sbc GW
        and #7
        sta CNT
@row:   jsr getrow
        ldx DL                  ; RB3 = RB's bytes backwards, each reversed
        ldy #0
@rv:    dex
        lda RB,x
        stx TMP
        tax
        lda REV,x
        sta RB3,y
        ldx TMP
        iny
        cpy DL
        bne @rv
        lda CNT                 ; then shifted left by pad
        beq @cp
        sta CNT2
@sh:    ldx DL
        dex
        asl RB3,x
@sb:    dex
        bmi @sn
        rol RB3,x
        jmp @sb
@sn:    dec CNT2
        bne @sh
@cp:    ldy DL
@c:     dey
        lda RB3,y
        sta RB,y
        tya
        bne @c
        jsr putrow
        jsr nextrow
        bne @row
        jmp selend
@r:     rts

; Flip vertical: the rows swapped, top with bottom
m_flipv:
        jsr selop
        jcs @r
        jsr selgeo
        MOVW GB, SY1            ; GB: the bottom row
        lda HH+1                ; HH = height / 2 pairs
        lsr
        sta HH+1
        ror HH
        lda HH
        ora HH+1
        beq @e
        jsr rowbytes
@p:     jsr getrow              ; top -> RB3
        ldy DL
@c1:    lda RB,y
        sta RB3,y
        dey
        bpl @c1
        MOVW U2, GY             ; bottom -> RB, put at the top
        MOVW GY, GB
        jsr getrow
        MOVW GY, U2
        jsr putrow
        ldy DL                  ; RB3 at the bottom
@c2:    lda RB3,y
        sta RB,y
        dey
        bpl @c2
        MOVW GY, GB
        jsr putrow
        MOVW GY, U2
        lda GB
        bne @d
        dec GB+1
@d:     dec GB
        jsr nextrow
        bne @p
@e:     jmp selend
@r:     rts

; --- rows of the screen, bit by bit -------------------------------------------------
; GS = GX AND 7; GNB = (GS + GW + 7) / 8; N0 = GY * 80 + GX / 8
rowsetup:
        lda GX
        and #7
        sta GS
        clc
        adc GW
        sta U1
        lda GW+1
        adc #0
        sta U1+1
        lda U1
        clc
        adc #7
        sta U1
        bcc @a
        inc U1+1
@a:     lsr U1+1
        ror U1
        lsr U1+1
        ror U1
        lsr U1+1
        ror U1
        lda U1
        sta GNB
        MOVW U0, GY
        lda GX+1
        sta U1
        lda GX
        lsr U1
        ror
        lsr U1
        ror
        lsr U1
        ror
        jsr mul80
        ldx #DS
        jsr ofvram
        LDW N0, RB2
        ldx #DD
        jsr ofram
        lda GNB
        sta DL
        lda #0
        sta DL+1
        jsr dma                 ; RB2 = the screen's bytes there
        lda #0
        ldx GNB
        sta RB2,x
        rts

; RB = GW pixels of screen row GY from GX, from bit 7 of RB on
getrow: lda DL                  ; (DL kept)
        pha
        jsr rowsetup
        ldx #0
@l:     lda RB2+1,x
        sta TMP
        lda RB2,x
        ldy GS
        beq @s
@sh:    asl TMP
        rol a
        dey
        bne @sh
@s:     sta RB,x
        inx
        cpx GNB
        bne @l
        lda #0
        sta RB,x
        pla
        sta DL
        rts

; RB (GW pixels) -> screen row GY from GX; the pixels around kept
putrow: lda DL
        pha
        jsr rowsetup            ; RB2 = what is there now
        jsr rowbytes2           ; RB beyond its bytes: 0
        lda #0
        sta TMP2                ; the byte before
        ldx #0
@l:     lda RB,x
        ldy GS
        beq @s
        sta TMP
        lda TMP2
        sta U1
        lda TMP
@sh:    lsr U1
        ror a
        dey
        bne @sh
@s:     sta RB4,x
        lda RB,x
        sta TMP2
        inx
        cpx GNB
        bne @l
        ldx GS                  ; the edges: the first byte keeps the
        lda lkeep,x             ; pixels before GX, the last those after
        sta SKL                 ; the end
        lda GS
        clc
        adc GW
        sec
        sbc #1
        and #7
        tax
        lda rkeep,x
        sta SKR
        ldx GNB
        dex
        bne @two
        lda SKL
        ora SKR
        sta SKL
        sta SKR
@two:   lda SKL
        eor #$FF
        and RB4
        sta TMP
        lda SKL
        and RB2
        ora TMP
        sta RB4
        lda SKR
        eor #$FF
        and RB4,x
        sta TMP
        lda SKR
        and RB2,x
        ora TMP
        sta RB4,x
        lda DS                  ; back where RB2 came from
        sta DD
        lda DS+1
        sta DD+1
        lda DS+2
        sta DD+2
        LDW N0, RB4
        ldx #DS
        jsr ofram
        jsr dma
        pla
        sta DL
        rts
; RB's byte after the GW pixels: 0
rowbytes2:
        lda DL
        pha
        jsr rowbytes
        ldx DL
        lda #0
        sta RB,x
        pla
        sta DL
        rts

; --- text ----------------------------------------------------------------------
t_text: jsr textend
        jsr snapshot
        lda #1
        sta TXON
        MOVW TXX, PMX
        MOVW TXL, PMX
        lda PMY                  ; the click in the middle of the line
        sec
        sbc #11
        sta TXY
        lda PMY+1
        sbc #0
        sta TXY+1
        lda TXY
        cmp CANY
        lda TXY+1
        sbc CANY+1
        bcs @y
        MOVW TXY, CANY
@y:     lda #0
        sta TXN
        lda CLICKS
        jmp caret

; The caret (XOR, a line left of the next character)
caret:  lda #R_XOR
        sta ROP
        lda #0
        sta PATON
        lda #1
        sta BCOL
        ldx #TXX
        ldy #TXY
        jsr bxy0
        lda TXY
        clc
        adc #15
        sta BY1
        lda TXY+1
        adc #0
        sta BY1H
        lda TXX
        sta BX1
        lda TXX+1
        sta BX1H
        lda #C_LINE
        sta BCMD
        lda #R_SET
        sta ROP
        rts

; No more typing
textend:
        lda TXON
        beq @r
        jsr pcan
        jsr caret
        lda #0
        sta TXON
@r:     rts

; A key while typing (port and clip set)
textkey:
        lda KCH
        jeq @r
        cmp #27
        beq textend
        cmp #CR
        bne @n1
        jsr caret               ; Enter: the next line
        MOVW TXX, TXL
        lda TXY
        clc
        adc #16
        sta TXY
        bcc @e
        inc TXY+1
@e:     lda #0
        sta TXN
        jmp caret
@n1:    cmp #8
        beq @bs
        cmp #127
        beq @bs
        cmp #' '
        bcc @r
        lda TXX                 ; room on the canvas?
        clc
        adc #8
        sta U0
        lda TXX+1
        adc #0
        sta U0+1
        lda CANX
        clc
        adc CWP
        sta U1
        lda CANX+1
        adc CWP+1
        sta U1+1
        lda U1
        cmp U0
        lda U1+1
        sbc U0+1
        bcc @full
        jsr caret
        jsr ink
        ldx #TXX
        ldy #TXY
        jsr bxy0
        lda TSTYLE
        sta STYLE
        lda KCH
        sta CHOUT
        lda #0
        sta STYLE
        lda U0
        sta TXX
        lda U0+1
        sta TXX+1
        inc TXN
        jsr commit
        jsr changed
        jmp caret
@full:  lda #1
        sta BEEP
@r:     rts
@bs:    lda TXN                 ; Backspace: the last character rubbed out
        beq @r
        jsr caret
        lda TXX
        sec
        sbc #8
        sta TXX
        sta X0
        lda TXX+1
        sbc #0
        sta TXX+1
        sta X0+1
        MOVW Y0, TXY
        lda X0
        clc
        adc #7
        sta X1
        lda X0+1
        adc #0
        sta X1+1
        lda Y0
        clc
        adc #15
        sta Y1
        lda Y0+1
        adc #0
        sta Y1+1
        jsr ink
        lda #0
        sta BCOL
        lda #C_BOXF
        jsr brect
        dec TXN
        jsr commit
        jmp caret

m_plain:
        lda #0
        sta TSTYLE
        rts
m_bold: lda #1
        bne style
m_under:
        lda #2
        bne style
m_italic:
        lda #4
style:  eor TSTYLE
        sta TSTYLE
        rts

; --- the paint bucket ------------------------------------------------------------
; The area of the clicked pixel's colour, as far as the canvas goes, filled
; with the pattern. Worked out on a copy of the canvas in WORK (a span at a
; time, seeds on a stack), then the pattern put where the copy changed.
t_fill: jsr snapshot
        lda PMX
        sec
        sbc CANX
        sta FX
        lda PMX+1
        sbc CANX+1
        sta FX+1
        lda PMY
        sec
        sbc CANY
        sta FY
        lda PMY+1
        sbc CANY+1
        sta FY+1
        jsr canxb               ; the canvas -> WORK (DS: the screen, DD:
        sta SVB                 ; WORK, a row on each time)
        MOVW U0, CANY
        lda SVB
        jsr mul80
        ldx #DS
        jsr ofvram
        LDW N0, WORK
        ldx #DD
        jsr ofram
        lda CW
        sta DL
        lda #0
        sta DL+1
        MOVW CNTW, CH
@cp:    jsr dma
        ldx #DS
        jsr add80
        lda DD
        clc
        adc CW
        sta DD
        bcc @cp1
        inc DD+1
@cp1:   lda CNTW
        bne @cp2
        dec CNTW+1
@cp2:   dec CNTW
        lda CNTW
        ora CNTW+1
        bne @cp
        lda #$FF                ; the rows changed: none yet
        sta FYMIN
        sta FYMIN+1
        lda #0
        sta FYMAX
        sta FYMAX+1
        MOVW U0, FY             ; the colour clicked: TC, TCB
        jsr rowptr
        lda FX
        and #7
        sta FBB
        lda FX+1
        sta U1
        lda FX
        lsr U1
        ror
        lsr U1
        ror
        lsr U1
        ror
        sta FBY
        tay
        ldx FBB
        lda (P0),y
        and bitm,x
        beq @t0
        lda #$FF
@t0:    sta TCB
        LDW P1, FSTK            ; the stack: the click
        MOVW NY, FY
        ldy FBY
        ldx FBB
        jsr push
@pop:   lda P1                  ; empty?
        cmp #<FSTK
        bne @go
        lda P1+1
        cmp #>FSTK
        bne @go
        jmp @apply
@go:    lda P1
        sec
        sbc #4
        sta P1
        bcs @g1
        dec P1+1
@g1:    ldy #0
        lda (P1),y
        sta FBY
        iny
        lda (P1),y
        sta FBB
        iny
        lda (P1),y
        sta FY
        iny
        lda (P1),y
        sta FY+1
        MOVW U0, FY
        jsr rowptr
        ldy FBY                 ; still that colour?
        ldx FBB
        lda (P0),y
        eor TCB
        and bitm,x
        bne @pop
        jsr scanl               ; the span: BL, BB .. BR, BRB
        ldy FBY
        ldx FBB
        jsr scanr
        jsr flipspan            ; the other colour now
        lda FY                  ; (the rows changed: FYMIN..FYMAX)
        cmp FYMIN
        lda FY+1
        sbc FYMIN+1
        bcs @mx
        MOVW FYMIN, FY
@mx:    lda FYMAX
        cmp FY
        lda FYMAX+1
        sbc FY+1
        bcs @ab
        MOVW FYMAX, FY
@ab:    lda FY                  ; the rows above and below
        ora FY+1
        beq @below
        lda FY
        sec
        sbc #1
        sta NY
        lda FY+1
        sbc #0
        sta NY+1
        jsr seeds
@below: lda FY
        clc
        adc #1
        sta NY
        lda FY+1
        adc #0
        sta NY+1
        lda NY
        cmp CH
        lda NY+1
        sbc CH+1
        bcs @p2
        jsr seeds
@p2:    jmp @pop
@apply: lda FYMIN+1               ; nothing changed?
        jmi @ad
        MOVW FR, FYMIN          ; the pattern where WORK changed, rows
        lda FR                  ; FYMIN..FYMAX: DS the screen, P0 WORK
        clc
        adc CANY
        sta U0
        lda FR+1
        adc CANY+1
        sta U0+1
        lda SVB
        jsr mul80
        ldx #SPIC
        jsr ofvram
        MOVW U0, FR
        jsr rowptr
        lda CW
        sta DL
        lda #0
        sta DL+1
@ap:    lda FR                  ; this row's pattern byte
        clc
        adc CANY
        and #7
        sta TMP
        lda PAT
        asl
        asl
        asl
        ora TMP
        tax
        lda pats,x
        sta TMP2
        ldx #2
@a1:    lda SPIC,x
        sta DS,x
        dex
        bpl @a1
        LDW N0, RB2
        ldx #DD
        jsr ofram
        jsr dma
        ldy #0
@b:     lda RB2,y
        eor (P0),y
        beq @nb
        sta TMP                 ; mask
        and TMP2
        sta U1
        lda TMP
        eor #$FF
        and RB2,y
        ora U1
        sta RB2,y
@nb:    iny
        cpy CW
        bne @b
        ldx #2                  ; back
@a2:    lda SPIC,x
        sta DD,x
        dex
        bpl @a2
        LDW N0, RB2
        ldx #DS
        jsr ofram
        jsr dma
        ldx #SPIC
        jsr add80
        lda P0
        clc
        adc CW
        sta P0
        bcc @a3
        inc P0+1
@a3:    lda FR
        cmp FYMAX
        bne @a4
        lda FR+1
        cmp FYMAX+1
        beq @ad
@a4:    inc FR
        jne @ap
        inc FR+1
        jmp @ap
@ad:    jmp done
; FR one row on; Z set at the canvas' last
frnext: inc FR
        bne @a
        inc FR+1
@a:     lda FR
        cmp CH
        bne @r
        lda FR+1
        cmp CH+1
@r:     rts
; P0 = WORK + U0 * CW
rowptr: lda #0
        sta P0
        sta P0+1
        lda CW
        sta U1
        MOVW U2, U0
@l:     lsr U1
        bcc @n
        lda P0
        clc
        adc U2
        sta P0
        lda P0+1
        adc U2+1
        sta P0+1
@n:     asl U2
        rol U2+1
        lda U1
        bne @l
        lda P0
        clc
        adc #<WORK
        sta P0
        lda P0+1
        adc #>WORK
        sta P0+1
        rts
bitm:   .byte $80, $40, $20, $10, $08, $04, $02, $01

; From the pixel at byte Y, bit X of row P0 (of the colour TCB), left as
; far as the colour goes: BL, BB
scanl:
@l:     cpx #0
        beq @edge
        dex
        lda (P0),y
        eor TCB
        and bitm,x
        beq @l
        inx
        jmp @d
@edge:  cpy #0
        beq @d
        dey
        lda (P0),y
        cmp TCB
        beq @l                  ; a whole byte of it
        eor TCB
        and #$01
        bne @no
        ldx #7                  ; its last pixel
        jmp @l
@no:    iny
@d:     sty BL
        stx BB
        rts
; ... and right: BR, BRB (the canvas ends with byte CW - 1)
scanr:
@l:     cpx #7
        beq @edge
        inx
        lda (P0),y
        eor TCB
        and bitm,x
        beq @l
        dex
        jmp @d
@edge:  iny
        cpy CW
        beq @back
        lda (P0),y
        cmp TCB
        beq @l                  ; a whole byte (X = 7 still)
        eor TCB
        and #$80
        bne @back
        ldx #0
        jmp @l
@back:  dey
        ldx #7
@d:     sty BR
        stx BRB
        rts
; BL, BB .. BR, BRB of row P0 flipped
flipspan:
        ldx BB
        lda lkeep,x
        eor #$FF
        sta CNT                 ; from BB on
        ldx BRB
        lda rkeep,x
        eor #$FF                ; up to BRB
        ldy BL
        cpy BR
        bne @two
        and CNT
        eor (P0),y
        sta (P0),y
        rts
@two:   pha
        lda CNT
        eor (P0),y
        sta (P0),y
@mid:   iny
        cpy BR
        beq @last
        lda (P0),y
        eor #$FF
        sta (P0),y
        jmp @mid
@last:  pla
        eor (P0),y
        sta (P0),y
        rts
; Seeds on row NY within BL, BB .. BR, BRB: the start of each run of the
; colour
seeds:  MOVW U0, NY
        jsr rowptr
        lda #0
        sta INRUN
        ldy BL
        ldx BB
@l:     cpy BR                  ; past the end?
        bcc @in
        bne @r
        cpx BRB
        beq @in
        bcs @r
@in:    cpx #0
        bne @px
        cpy BR                  ; a whole byte within the span?
        bcc @w
        lda BRB
        cmp #7
        bne @px
@w:     lda (P0),y
        cmp TCB
        beq @run8
        eor #$FF
        cmp TCB
        bne @px
        lda #0                  ; all the other colour
        sta INRUN
        iny
        jmp @l
@run8:  lda INRUN
        bne @n8
        jsr push
        lda #1
        sta INRUN
@n8:    iny
        jmp @l
@px:    lda (P0),y
        eor TCB
        and bitm,x
        bne @no
        lda INRUN
        bne @nx
        jsr push
        lda #1
        sta INRUN
        bne @nx
@no:    lda #0
        sta INRUN
@nx:    inx
        cpx #8
        bne @l
        ldx #0
        iny
        jmp @l
@r:     rts
; Byte Y, bit X, row NY -> the stack (if there is room); X, Y kept
push:   sty FBT
        lda P1
        cmp #<FSTKEND
        lda P1+1
        sbc #>FSTKEND
        bcs @r
        tya
        ldy #0
        sta (P1),y
        iny
        txa
        sta (P1),y
        iny
        lda NY
        sta (P1),y
        iny
        lda NY+1
        sta (P1),y
        lda P1
        clc
        adc #4
        sta P1
        bcc @r
        inc P1+1
@r:     ldy FBT
        rts

; --- FatBits ------------------------------------------------------------------------
m_fatbits:
        jsr pcan
        lda ZOOM
        beq @in
        jmp zoomout
@in:    lda CWP+1               ; around the canvas' middle
        lsr
        lda CWP
        ror
        clc
        adc CANX
        sta PMX
        lda CANX+1
        adc #0
        sta PMX+1
        lda CH+1
        lsr
        lda CH
        ror
        clc
        adc CANY
        sta PMY
        lda CANY+1
        adc #0
        sta PMY+1
; The zoom tool: FatBits around PMX, PMY
t_zoom: jsr endall
        jsr pcan
        lda CW                  ; ZW = CW pixels, ZH = CH / 8 rows
        sta ZW
        lda CH+1
        lsr
        lda CH
        ror
        lsr
        lsr
        sta ZH
        lda VX                  ; the picture's x there - ZW / 2
        asl
        asl
        asl
        sta U0
        lda #0
        rol
        sta U0+1
        lda PMX
        sec
        sbc CANX
        sta N0
        lda PMX+1
        sbc CANX+1
        sta N0+1
        lda N0
        clc
        adc U0
        sta U0
        lda N0+1
        adc U0+1
        sta U0+1
        lda ZW
        lsr
        sta U1
        lda U0
        sec
        sbc U1
        sta ZX
        lda U0+1
        sbc #0
        sta ZX+1
        lda PMY                  ; y: VY + PMY - CANY - ZH / 2
        sec
        sbc CANY
        sta N0
        lda PMY+1
        sbc CANY+1
        sta N0+1
        lda N0
        clc
        adc VY
        sta U0
        lda N0+1
        adc VY+1
        sta U0+1
        lda ZH
        lsr
        sta U1
        lda U0
        sec
        sbc U1
        sta ZY
        lda U0+1
        sbc #0
        sta ZY+1
        jsr zclamp
        lda #1
        sta ZOOM
        lda CLICKS
        jmp drawzoom

; ZX, ZY kept within the picture
zclamp: lda ZX+1
        bpl @a
        lda #0
        sta ZX
        sta ZX+1
@a:     lda ZY+1
        bpl @b
        lda #0
        sta ZY
        sta ZY+1
@b:     lda #<640               ; ZX <= 640 - ZW
        sec
        sbc ZW
        sta U0
        lda #>640
        sbc #0
        sta U0+1
        lda U0
        cmp ZX
        lda U0+1
        sbc ZX+1
        bcs @c
        MOVW ZX, U0
@c:     lda #<400
        sec
        sbc ZH
        sta U0
        lda #>400
        sbc #0
        sta U0+1
        lda U0
        cmp ZY
        lda U0+1
        sbc ZY+1
        bcs @r
        MOVW ZY, U0
@r:     rts

; Back to the normal view, around what FatBits showed
zoomout:
        lda #0
        sta ZOOM
        lda ZW                  ; VX = (ZX + ZW / 2 - CWP / 2) / 8
        lsr
        clc
        adc ZX
        sta U0
        lda ZX+1
        adc #0
        sta U0+1
        lda CWP+1
        lsr
        sta U1+1
        lda CWP
        ror
        sta U1
        lda U0
        sec
        sbc U1
        sta U0
        lda U0+1
        sbc U1+1
        bpl @x
        lda #0
        sta U0
@x:     lsr
        ror U0
        lsr
        ror U0
        lsr
        ror U0
        lda U0
        sta VX
        lda ZH                  ; VY = ZY + ZH / 2 - CH / 2
        lsr
        clc
        adc ZY
        sta U0
        lda ZY+1
        adc #0
        sta U0+1
        lda CH+1
        lsr
        sta U1+1
        lda CH
        ror
        sta U1
        lda U0
        sec
        sbc U1
        sta VY
        lda U0+1
        sbc U1+1
        sta VY+1
        bpl @y
        lda #0
        sta VY
        sta VY+1
@y:     jsr clampv
        lda CLICKS
        jsr showview
        jmp syncbar

; Arrows in FatBits (X = 1-4): 8 pixels across, 4 rows
zoomkey:
        cpx #1
        bne @k2
        lda ZY
        sec
        sbc #4
        sta ZY
        bcs @d
        dec ZY+1
        jmp @d
@k2:    cpx #2
        bne @k3
        lda ZY
        clc
        adc #4
        sta ZY
        bcc @d
        inc ZY+1
        bne @d
@k3:    cpx #3
        bne @k4
        lda ZX
        sec
        sbc #8
        sta ZX
        bcs @d
        dec ZX+1
        jmp @d
@k4:    lda ZX
        clc
        adc #8
        sta ZX
        bcc @d
        inc ZX+1
@d:     jsr zclamp
        jmp drawzoom

; The canvas: ZW x ZH pixels from ZX, ZY, each a 7 x 7 box
drawzoom:
        jsr ink
        lda #0
        sta BCOL
        MOVW X0, CANX
        MOVW Y0, CANY
        lda CANX
        clc
        adc CWP
        sta X1
        lda CANX+1
        adc CWP+1
        sta X1+1
        lda CANY
        clc
        adc CH
        sta Y1
        lda CANY+1
        adc CH+1
        sta Y1+1
        jsr dec1
        lda #C_BOXF
        jsr brect
        lda #1
        sta BCOL
        lda #0
        sta CNT2                ; row
@row:   lda CNT2                ; the picture's row ZY + r -> RB
        clc
        adc ZY
        sta U0
        lda ZY+1
        adc #0
        sta U0+1
        jsr zrow
        lda #0
        sta CNT                 ; column
@c:     lda CNT
        lsr
        lsr
        lsr
        tay
        lda CNT
        and #7
        tax
        lda RB,y
        and bitm,x
        beq @n
        jsr zcell               ; X0..Y1 = cell CNT, CNT2
        lda #C_BOXF
        jsr brect
@n:     inc CNT
        lda CNT
        cmp ZW
        bne @c
        inc CNT2
        lda CNT2
        cmp ZH
        bne @row
        rts
; RB = the picture's row U0, ZW pixels from ZX
zrow:   lda ZX
        and #7
        sta GS
        lda ZX+1
        sta U1
        lda ZX
        lsr U1
        ror
        lsr U1
        ror
        lsr U1
        ror
        jsr mul80
        ldx #DS
        jsr ofpic
        LDW N0, RB2
        ldx #DD
        jsr ofram
        LDW DL, 12
        jsr dma
        ldx #0
@l:     lda RB2+1,x
        sta TMP
        lda RB2,x
        ldy GS
        beq @s
@sh:    asl TMP
        rol a
        dey
        bne @sh
@s:     sta RB,x
        inx
        cpx #11
        bne @l
        rts
; X0..Y1 = FatBits cell CNT, CNT2 (7 x 7)
zcell:  lda CNT
        sta U0
        lda #0
        asl U0
        rol
        asl U0
        rol
        asl U0
        rol
        sta U0+1
        lda U0
        clc
        adc CANX
        sta X0
        lda U0+1
        adc CANX+1
        sta X0+1
        lda CNT2
        sta U0
        lda #0
        asl U0
        rol
        asl U0
        rol
        asl U0
        rol
        sta U0+1
        lda U0
        clc
        adc CANY
        sta Y0
        lda U0+1
        adc CANY+1
        sta Y0+1
        lda X0
        clc
        adc #6
        sta X1
        lda X0+1
        adc #0
        sta X1+1
        lda Y0
        clc
        adc #6
        sta Y1
        lda Y0+1
        adc #0
        sta Y1+1
        rts

; A click in FatBits: the pixel the other colour, and the ones the mouse
; then goes over the same
fatpencil:
        jsr fcell
        bcs @r
        jsr snapshot
        jsr fgetpix
        eor #1
        sta COLR
        jsr fsetpix
@l:     jsr wait1
        bcs @up
        jsr fcell
        bcs @l
        lda CNT
        cmp FCC
        bne @set
        lda CNT2
        cmp FCR
        beq @l
@set:   jsr fsetpix
        jmp @l
@up:    lda CLICKS
        jmp changed
@r:     rts
; CNT, CNT2 = the cell under the mouse; carry set if none
fcell:  lda PMX
        sec
        sbc CANX
        sta U0
        lda PMX+1
        sbc CANX+1
        bcc @no
        lsr
        ror U0
        lsr
        ror U0
        lsr
        ror U0
        lda U0
        cmp ZW
        bcs @no
        sta CNT
        lda PMY
        sec
        sbc CANY
        sta U0
        lda PMY+1
        sbc CANY+1
        bcc @no
        lsr
        ror U0
        lsr
        ror U0
        lsr
        ror U0
        lda U0
        cmp ZH
        bcs @no
        sta CNT2
        clc
        rts
@no:    sec
        rts
; Port A on the picture's byte of cell CNT, CNT2; TMP = its bit mask
fpadr:  lda CNT2
        clc
        adc ZY
        sta U0
        lda ZY+1
        adc #0
        sta U0+1
        lda CNT
        clc
        adc ZX
        sta U1
        lda ZX+1
        adc #0
        sta U1+1
        lda U1
        and #7
        tax
        lda bitm,x
        sta TMP
        lda U1
        lsr U1+1
        ror
        lsr U1+1
        ror
        lsr U1+1
        ror
        jsr mul80
        ldx #DD
        jsr ofpic
        jmp padrdd
fgetpix:
        jsr fpadr
        lda PDATA
        and TMP
        beq @r
        lda #1
@r:     rts
; The cell's pixel = COLR, in the picture and on the canvas
fsetpix:
        lda CNT
        sta FCC
        lda CNT2
        sta FCR
        jsr fpadr
        lda PDATA
        ldx COLR
        beq @c
        ora TMP
        jmp @w
@c:     sta U1
        lda TMP
        eor #$FF
        and U1
@w:     pha
        jsr padrdd              ; (the read moved port A on)
        pla
        sta PDATA
        jsr zcell               ; the cell on the canvas
        jsr ink
        lda COLR
        sta BCOL
        lda #C_BOXF
        jmp brect

; --- variables ------------------------------------------------------------------
RB:     .res MAXCW + 4
RB1:    .res MAXCW + 4
RB2:    .res MAXCW + 4
RB3:    .res MAXCW + 4
RB4:    .res MAXCW + 4
REV:    .res 256
SB0:    .res 1
SNB:    .res 1
SKL:    .res 1
SKR:    .res 1
SVB:    .res 1
PCMD:   .res 1
PX0:    .res 1
PX1:    .res 1
PY0:    .res 2
PY1:    .res 2
GX:     .res 2
GY:     .res 2
GW:     .res 2
GB:     .res 2
GS:     .res 1
GNB:    .res 1
HH:     .res 2
QX0:    .res 2                  ; (QX0..QY1 in X0..Y1's order)
QY0:    .res 2
QX1:    .res 2
QY1:    .res 2
CLOFF:  .res 2
CLW:    .res 2
CLRB:   .res 1
FX:     .res 2
FY:     .res 2
FR:     .res 2
XA:     .res 2
XL:     .res 2
XR:     .res 2
NY:     .res 2
INRUN:  .res 1
HA:     .res 2
HB:     .res 2
HY:     .res 2
OA:     .res 2
OB:     .res 2
FCC:    .res 1
FCR:    .res 1
U3:     .res 1
CNTW:   .res 2
FYMIN:  .res 2
FBY:    .res 1
FBB:    .res 1
FBT:    .res 1
BL:     .res 1
BB:     .res 1
BR:     .res 1
BRB:    .res 1
FYMAX:  .res 2

        .include "paint_oval.inc"
