;=============================================================================
; paint2.inc - PAINT2 (main RAM): the canvas, the palette, the events, the
; drawing tools. Part of paint.asm.
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
;=============================================================================

; --- start ------------------------------------------------------------------
; The icons into sprite images, the bit-reversal table, the settings
lowinit:
        lda #1
        sta PSTEP
        LDW P0, toolicons
        lda #0
        sta CNT
@i:     lda #0
        sta PADR
        lda CNT
        clc
        adc #IMG0
        sta PADR+1
        lda #$FD
        sta PADR+2
        ldy #0
@r:     lda (P0),y              ; a row: 16 bits -> 16 bytes (1 ink, $80
        sta TMP                 ; nothing)
        iny
        lda (P0),y
        sta TMP2
        iny
        ldx #16
@b:     asl TMP2
        rol TMP
        lda #$80
        bcc @w
        lda #1
@w:     sta PDATA
        dex
        bne @b
        cpy #32
        bne @r
        ADDW P0, P0, 32
        inc CNT
        lda CNT
        cmp #NTOOL
        bne @i
        ldx #0                  ; REV: a byte's bits the other way round
@v:     stx TMP
        lda #0
        ldy #8
@vb:    lsr TMP
        rol a
        dey
        bne @vb
        sta REV,x
        inx
        bne @v
        lda #T_PENCIL
        sta TOOL_
        lda #0
        sta PAT
        sta ZOOM
        sta SEL
        sta TXON
        sta TSTYLE
        sta VX
        sta VY
        sta VY+1
        lda #1
        sta LW
        lda #$A5
        sta RND
        sta RND+1
        rts

; --- addresses and the DMA ----------------------------------------------------
; N0 = U0 * 80 + A
mul80:  pha
        lda U0
        sta N1
        lda U0+1
        sta N1+1
        asl N1                  ; N1 = U0 * 16
        rol N1+1
        asl N1
        rol N1+1
        asl N1
        rol N1+1
        asl N1
        rol N1+1
        lda N1                  ; N0 = N1 * 4 + N1
        sta N0
        lda N1+1
        sta N0+1
        asl N0
        rol N0+1
        asl N0
        rol N0+1
        lda N0
        clc
        adc N1
        sta N0
        lda N0+1
        adc N1+1
        sta N0+1
        pla
        clc
        adc N0
        sta N0
        bcc @r
        inc N0+1
@r:     rts

; The 3-byte address at zero page X = a buffer + N0: picture, undo copy,
; clipboard (bank * 4096 + N0), VRAM page 0 ($FE0000 + N0), main RAM
ofpic:  lda PICB
        jmp ofbank
ofund:  lda UNDB
        jmp ofbank
ofclp:  lda CLPB
ofbank: pha
        asl
        asl
        asl
        asl
        clc
        adc N0+1
        sta 1,x
        pla
        lsr
        lsr
        lsr
        lsr
        adc #0
        sta 2,x
        lda N0
        sta 0,x
        rts
ofvram: lda #$FE
        bne ofhigh
ofram:  lda #$FF
ofhigh: sta 2,x
        lda N0
        sta 0,x
        lda N0+1
        sta 1,x
        rts

; DL bytes from DS to DD
dma:    ldx #2
@c:     lda DS,x
        sta DMASRC,x
        lda DD,x
        sta DMASRC+3,x
        dex
        bpl @c
        lda DL
        sta DMASRC+6
        lda DL+1
        sta DMASRC+7
        lda #0
        sta DMASRC+8
        lda #1
        sta DMACMD
        rts

; The whole picture: copied to the undo copy (before a change)
snapshot:
        lda #0
        sta N0
        sta N0+1
        ldx #DS
        jsr ofpic
        ldx #DD
        jsr ofund
picsz:  LDW DL, PICSZ
        jmp dma

; WORK <-> the picture (loading, saving)
ramtopic:
        lda #<WORK
        sta N0
        lda #>WORK
        sta N0+1
        ldx #DS
        jsr ofram
        lda #0
        sta N0
        sta N0+1
        ldx #DD
        jsr ofpic
        jmp picsz
pictoram:
        lda #0
        sta N0
        sta N0+1
        ldx #DS
        jsr ofpic
        lda #<WORK
        sta N0
        lda #>WORK
        sta N0+1
        ldx #DD
        jsr ofram
        jmp picsz

; The picture: all white (and its undo copy the same)
clearpic:
        lda #0
        sta N0
        sta N0+1
        ldx #DD
        jsr ofpic
        lda #0
        sta DMAFILL
        ldx #2
@c:     lda DD,x
        sta DMASRC+3,x
        dex
        bpl @c
        LDW DMASRC+6, PICSZ
        lda #0
        sta DMASRC+8
        lda #2
        sta DMACMD
        jmp snapshot

; Undo: the picture and its undo copy swapped (through VRAM page 1)
m_undo: jsr setport
        jsr endall
        lda #0
        sta N0
        sta N0+1
        ldx #DS
        jsr ofpic
        LDW N0, PAGE1
        ldx #DD
        jsr ofvram
        jsr picsz
        lda #0
        sta N0
        sta N0+1
        ldx #DS
        jsr ofund
        ldx #DD
        jsr ofpic
        jsr picsz
        LDW N0, PAGE1
        ldx #DS
        jsr ofvram
        lda #0
        sta N0
        sta N0+1
        ldx #DD
        jsr ofund
        jsr picsz
        jsr changed
        jmp showview

; --- the window ----------------------------------------------------------------
; From r0 / r1 (the contents' top left): CX0, CY0 and the canvas
geom:   MOVW CX0, r0
        MOVW CY0, r1
        ADDW CANX, CX0, PALW + 7
        lda CANX
        and #$F8
        sta CANX
        MOVW CANY, CY0
        ADDW U0, CX0, 608       ; CW = (CX0 + 608 - CANX) / 8, 70 at most,
        lda U0                  ; on the screen
        sec
        sbc CANX
        sta U0
        lda U0+1
        sbc CANX+1
        jsr geomdiv8
        cmp #MAXCW
        bcc @w1
        lda #MAXCW
@w1:    sta CW
        lda #<640
        sec
        sbc CANX
        sta U0
        lda #>640
        sbc CANX+1
        jsr geomdiv8
        cmp CW
        bcs @w2
        sta CW
@w2:    lda CW
        sta CWP
        lda #0
        sta CWP+1
        asl CWP
        rol CWP+1
        asl CWP
        rol CWP+1
        asl CWP
        rol CWP+1
        lda #<400               ; CH = 400 - CANY, 352 at most
        sec
        sbc CANY
        sta CH
        lda #>400
        sbc CANY+1
        sta CH+1
        bpl @h
        lda #0
        sta CH
        sta CH+1
@h:     lda CH
        cmp #<MAXCH
        lda CH+1
        sbc #>MAXCH
        bcc clampv
        LDW CH, MAXCH
; the view kept within the picture
clampv: lda #80
        sec
        sbc CW
        cmp VX
        bcs @x
        sta VX
@x:     jsr vymax               ; U0 = 400 - CH
        lda U0
        cmp VY
        lda U0+1
        sbc VY+1
        bcs @r
        MOVW VY, U0
@r:     rts
geomdiv8:  bmi @z                  ; (A:U0) / 8 -> A; negative -> 0
        lsr
        ror U0
        lsr
        ror U0
        lsr
        ror U0
        lda U0
        rts
@z:     lda #0
        rts
vymax:  lda #<400
        sec
        sbc CH
        sta U0
        lda #>400
        sbc CH+1
        sta U0+1
        rts

setport:
        ldx WIN
        TK TK_SETPORT
        jmp geom

; Z set if our window is in front
infront:
        ldx #$FF
        TK TK_FRONT
        cpx WIN
        rts

; The clip: the canvas
canclip:
        lda CANX
        sta CLIPR
        lda CANX+1
        sta CLIPR+1
        lda CANY
        sta CLIPR+2
        lda CANY+1
        sta CLIPR+3
        lda CANX
        clc
        adc CWP
        sta U0
        lda CANX+1
        adc CWP+1
        sta U0+1
        lda U0
        sec
        sbc #1
        sta CLIPR+4
        lda U0+1
        sbc #0
        sta CLIPR+5
        lda CANY
        clc
        adc CH
        sta U0
        lda CANY+1
        adc CH+1
        sta U0+1
        lda U0
        sec
        sbc #1
        sta CLIPR+6
        lda U0+1
        sbc #0
        sta CLIPR+7
        rts

; Everything drawn again (now if we are in front, else at the UPDATE)
redraw: jsr infront
        beq @f
        ldx WIN
        TK TK_INVAL
        rts
@f:     jsr setport
        jsr drawpal
        jsr showview
        jmp syncbar

; UPDATE (r0-r3 our contents, the clip set): the palette and the canvas
; within the clip. A selection or text being typed ends: the window is
; drawn once more without them.
update: jsr geom
        jsr drawpal
        lda CLIPR               ; the part to draw: the clip
        sta X0
        lda CLIPR+1
        sta X0+1
        lda CLIPR+2
        sta Y0
        lda CLIPR+3
        sta Y0+1
        lda CLIPR+4
        sta X1
        lda CLIPR+5
        sta X1+1
        lda CLIPR+6
        sta Y1
        lda CLIPR+7
        sta Y1+1
        jsr showrect
        bcc @r                  ; (nothing of the canvas: they stay)
        lda SEL
        ora TXON
        beq @r
        lda #0
        sta SEL
        sta TXON
        ldx WIN
        TK TK_INVAL
@r:     rts

; The scroll bar: maximum 400 - CH, value VY
syncbar:
        jsr vymax
        MOVW r1, U0
        LDW r0, 0
        ldx BAR
        TK TK_SETDATA
        MOVW r0, VY
        ldx BAR
        TK TK_SETVALUE
        rts

; --- the canvas from the picture ------------------------------------------------
; The whole canvas
showview:
        lda ZOOM
        beq @n
        jmp drawzoom
@n:     MOVW X0, CANX
        MOVW Y0, CANY
        LDW X1, $7FFF
        LDW Y1, $7FFF
; The rectangle X0..Y1 of the screen (within the canvas) from the picture
showrect:
        lda ZOOM
        beq @n
        jmp drawzoom
@n:     lda X0                  ; within the canvas
        cmp CANX
        lda X0+1
        sbc CANX+1
        bcs @a
        MOVW X0, CANX
@a:     lda Y0
        cmp CANY
        lda Y0+1
        sbc CANY+1
        bcs @b
        MOVW Y0, CANY
@b:     lda CANX                ; U0 = the canvas' last x
        clc
        adc CWP
        sta U0
        lda CANX+1
        adc CWP+1
        sta U0+1
        lda U0
        bne @b1
        dec U0+1
@b1:    dec U0
        lda U0
        cmp X1
        lda U0+1
        sbc X1+1
        bcs @c
        MOVW X1, U0
@c:     lda CANY                ; U0 = the canvas' last row
        clc
        adc CH
        sta U0
        lda CANY+1
        adc CH+1
        sta U0+1
        lda U0
        bne @c1
        dec U0+1
@c1:    dec U0
        lda U0
        cmp Y1
        lda U0+1
        sbc Y1+1
        bcs @d
        MOVW Y1, U0
@d:     lda X1                  ; empty?
        cmp X0
        lda X1+1
        sbc X0+1
        bcc @r
        lda Y1
        cmp Y0
        lda Y1+1
        sbc Y0+1
        bcs @go
@r:     clc                     ; (carry clear: nothing to draw)
        rts
@go:    lda X0                  ; the bytes: B0 (from the canvas' left),
        sec                     ; NB of them, the edge masks
        sbc CANX
        sta U0
        lda X0+1
        sbc CANX+1
        lsr
        ror U0
        lsr
        ror U0
        lsr
        ror U0
        lda U0
        sta SB0
        lda X1
        sec
        sbc CANX
        sta U0
        lda X1+1
        sbc CANX+1
        lsr
        ror U0
        lsr
        ror U0
        lsr
        ror U0
        lda U0
        sec
        sbc SB0
        clc
        adc #1
        sta SNB
        lda X0
        and #7
        tax
        lda lkeep,x
        sta SKL
        lda X1
        and #7
        tax
        lda rkeep,x
        sta SKR
        jsr canxb               ; the canvas' first byte on the screen row
        clc
        adc SB0
        sta SVB
        lda Y0                  ; picture row = VY + Y0 - CANY: SPIC
        sec
        sbc CANY
        sta U0
        lda Y0+1
        sbc CANY+1
        sta U0+1
        lda U0
        clc
        adc VY
        sta U0
        lda U0+1
        adc VY+1
        sta U0+1
        lda VX
        clc
        adc SB0
        jsr mul80
        ldx #SPIC
        jsr ofpic
        MOVW U0, Y0             ; the screen's: SVR
        lda SVB
        jsr mul80
        ldx #SVR
        jsr ofvram
        lda SNB
        sta DL
        lda #0
        sta DL+1
@row:   ldx #2                  ; the picture's bytes -> RB1
@q1:    lda SPIC,x
        sta DS,x
        dex
        bpl @q1
        LDW N0, RB1
        ldx #DD
        jsr ofram
        jsr dma
        lda SKL                 ; edges: the screen's bytes -> RB2, merged
        ora SKR
        beq @put
        ldx #2
@q2:    lda SVR,x
        sta DS,x
        dex
        bpl @q2
        LDW N0, RB2
        ldx #DD
        jsr ofram
        jsr dma
        lda SKL
        eor #$FF
        and RB1
        sta TMP
        lda SKL
        and RB2
        ora TMP
        sta RB1
        ldx SNB
        dex
        lda SKR
        eor #$FF
        and RB1,x
        sta TMP
        lda SKR
        and RB2,x
        ora TMP
        sta RB1,x
@put:   ldx #2                  ; RB1 -> the screen
@q3:    lda SVR,x
        sta DD,x
        dex
        bpl @q3
        LDW N0, RB1
        ldx #DS
        jsr ofram
        jsr dma
        ldx #SPIC               ; both one row on
        jsr add80
        ldx #SVR
        jsr add80
        lda Y0                  ; the next row
        cmp Y1
        bne @nx
        lda Y0+1
        cmp Y1+1
        beq @end
@nx:    inc Y0
        bne @row1
        inc Y0+1
@row1:  jmp @row
@end:   sec
        rts
; A = CANX / 8
canxb:  lda CANX+1
        sta U1
        lda CANX
        lsr U1
        ror
        lsr U1
        ror
        lsr U1
        ror
        rts
lkeep:  .byte $00, $80, $C0, $E0, $F0, $F8, $FC, $FE
rkeep:  .byte $7F, $3F, $1F, $0F, $07, $03, $01, $00

; The canvas -> the picture (after a tool drew on it)
commit: lda ZOOM
        bne @r
        MOVW U0, CANY           ; the screen: DS, the picture: DD
        jsr canxb
        jsr mul80
        ldx #DS
        jsr ofvram
        MOVW U0, VY
        lda VX
        jsr mul80
        ldx #DD
        jsr ofpic
        lda CW
        sta DL
        lda #0
        sta DL+1
        MOVW CNTW, CH
@l:     jsr dma
        ldx #DS
        jsr add80
        ldx #DD
        jsr add80
        lda CNTW
        bne @c
        dec CNTW+1
@c:     dec CNTW
        lda CNTW
        ora CNTW+1
        bne @l
@r:     rts
; The 3-byte address at zero page X: 80 more
add80:  lda 0,x
        clc
        adc #80
        sta 0,x
        bcc @r
        inc 1,x
        bne @r
        inc 2,x
@r:     rts

; After a change: committed, the title shows *
done:   lda CLICKS              ; (the release is not a click: read at
        jsr commit              ; once, a click meanwhile is kept)
changed:
        lda DIRTY
        bne @r
        lda #1
        sta DIRTY
        jmp settitle
@r:     rts

; --- the palette ---------------------------------------------------------------
; A box: X0..Y1 = CX0 / CY0 + the 4 numbers after the JSR, A = command
pbox:   sta PCMD
        pla
        sta P2
        pla
        sta P2+1
        ldy #1
        lda (P2),y
        clc
        adc CX0
        sta BX0
        lda CX0+1
        adc #0
        sta BX0H
        iny
        lda (P2),y
        clc
        adc CY0
        sta BY0
        lda CY0+1
        adc #0
        sta BY0H
        iny
        lda (P2),y
        clc
        adc CX0
        sta BX1
        lda CX0+1
        adc #0
        sta BX1H
        iny
        lda (P2),y
        clc
        adc CY0
        sta BY1
        lda CY0+1
        adc #0
        sta BY1H
        lda PCMD
        sta BCMD
        lda P2                  ; on after the 4 bytes
        clc
        adc #4
        sta P2
        bcc @j
        inc P2+1
@j:     lda P2+1
        pha
        lda P2
        pha
        rts

; X0..Y1 (CX0 / CY0 + the bytes PX0, PY0, PX1, PY1; PY may be > 255)
pboxv:  lda PX0
        clc
        adc CX0
        sta BX0
        lda CX0+1
        adc #0
        sta BX0H
        lda PY0
        clc
        adc CY0
        sta BY0
        lda PY0+1
        adc CY0+1
        sta BY0H
        lda PX1
        clc
        adc CX0
        sta BX1
        lda CX0+1
        adc #0
        sta BX1H
        lda PY1
        clc
        adc CY0
        sta BY1
        lda PY1+1
        adc CY0+1
        sta BY1H
        rts

; The pattern P (A) into the PATTERN registers
setpat: asl
        asl
        asl
        tax
        ldy #0
@c:     lda pats,x
        sta PATTERN,y
        inx
        iny
        cpy #8
        bne @c
        rts

drawpal:
        lda #R_SET
        sta ROP
        lda #0
        sta PATON
        sta BCOL
        lda #0                  ; white
        sta PX0
        sta PY0
        sta PY0+1
        lda #PALW - 1
        sta PX1
        LDW PY1, 354
        jsr pboxv
        lda #C_BOXF
        sta BCMD
        lda #1
        sta BCOL
        lda #0                  ; the tools
        sta CNT
@t:     lda CNT
        jsr toolxy              ; PX0, PY0 = its cell
        lda PX0
        clc
        adc #23
        sta PX1
        lda PY0
        clc
        adc #23
        sta PY1
        lda #0
        sta PY1+1
        sta PY0+1
        jsr pboxv
        lda #C_BOX
        sta BCMD
        lda PX0                 ; its icon
        clc
        adc #4
        adc CX0
        sta BX0
        lda CX0+1
        adc #0
        sta BX0H
        lda PY0
        clc
        adc #4
        adc CY0
        sta BY0
        lda CY0+1
        adc #0
        sta BY0H
        lda CNT
        clc
        adc #IMG0
        sta BCOL
        lda #C_STAMP
        sta BCMD
        lda #1
        sta BCOL
        lda CNT
        cmp TOOL_
        bne @nt
        jsr toolinv
@nt:    inc CNT
        lda CNT
        cmp #NTOOL
        bne @t
        lda #0                  ; the line widths
        sta CNT
@w:     lda CNT                 ; y = 172 + 12 * i
        asl
        asl
        sta TMP
        asl
        adc TMP
        adc #172
        sta PY0
        clc
        adc #10
        sta PY1
        lda #0
        sta PY0+1
        sta PY1+1
        lda #2
        sta PX0
        lda #45
        sta PX1
        jsr pboxv
        lda #C_BOX
        sta BCMD
        lda CNT                 ; the line in it: CNT + 1 rows
        clc
        adc #1
        cmp LW
        bne @nf
        lda #3                  ; (the one in use: a second frame)
        sta PX0
        lda #44
        sta PX1
        inc PY0
        dec PY1
        jsr pboxv
        lda #C_BOX
        sta BCMD
        dec PY0
        inc PY1
@nf:    lda #8
        sta PX0
        lda #39
        sta PX1
        lda PY0
        clc
        adc #5
        sta PY0
        clc
        adc CNT
        sta PY1
        jsr pboxv
        lda #C_BOXF
        sta BCMD
        inc CNT
        lda CNT
        cmp #4
        bne @w
        lda PAT                 ; the pattern in use, large
        jsr setpat
        lda #1
        sta PATON
        lda #C_BOXF
        jsr pbox
        .byte 2, 224, 45, 247
        lda #0
        sta PATON
        lda #C_BOX
        jsr pbox
        .byte 2, 224, 45, 247
        lda #0                  ; the 16 patterns
        sta CNT
@p:     jsr patcell             ; PX0.. = pattern CNT's swatch
        lda CNT
        jsr setpat
        lda #1
        sta PATON
        jsr pboxv
        lda #C_BOXF
        sta BCMD
        lda #0
        sta PATON
        lda #C_BOX
        sta BCMD
        lda CNT
        cmp PAT
        bne @np
        dec PX0                 ; the one in use: a frame around it
        dec PY0
        inc PX1
        inc PY1
        jsr pboxv
        lda #C_BOX
        sta BCMD
@np:    inc CNT
        lda CNT
        cmp #16
        bne @p
        rts

; PX0, PY0 = tool A's cell (2 across, 24 x 24)
toolxy: pha
        and #1
        tax
        lda txcol,x
        sta PX0
        pla
        lsr
        sta TMP                 ; row * 24
        asl
        adc TMP
        asl
        asl
        asl
        sta PY0
        lda #0
        sta PY0+1
        rts
txcol:  .byte 0, 24
; Tool CNT's cell inverted (inside its frame)
toolinv:
        lda CNT
        jsr toolxy
        inc PX0
        inc PY0
        lda PX0
        clc
        adc #21
        sta PX1
        lda PY0
        clc
        adc #21
        sta PY1
        lda #0
        sta PY1+1
        jsr pboxv
        lda #R_INV
        sta ROP
        lda #C_BOXF
        sta BCMD
        lda #R_SET
        sta ROP
        rts
; PX0..PY1 = pattern CNT's swatch (2 across, 13 high, from y = 252)
patcell:
        lda CNT
        and #1
        tax
        lda txcol,x
        clc
        adc #3
        sta PX0
        adc #18
        sta PX1
        lda CNT
        lsr
        sta TMP                 ; row * 13
        asl
        asl
        sta TMP2
        asl
        adc TMP2
        adc TMP
        adc #253
        sta PY0
        lda #0
        adc #0
        sta PY0+1
        lda PY0
        clc
        adc #10
        sta PY1
        lda PY0+1
        adc #0
        sta PY1+1
        rts

; --- events ----------------------------------------------------------------------
; A click in the window: the palette or the canvas
click:  jsr setport
        jsr mouse
        lda PMX
        cmp CANX
        lda PMX+1
        sbc CANX+1
        bcs @can
        jmp palclick
@can:   jsr incanvas
        bcc @r
        jsr canclip
        lda ZOOM
        beq @tool
        lda TOOL_
        cmp #T_ZOOM
        bne @fat
        jmp zoomout
@fat:   jmp fatpencil
@tool:  lda TOOL_
        cmp #T_SEL              ; another tool: no selection
        beq @s
        jsr selnone
@s:     lda TOOL_
        cmp #T_TEXT
        beq @t
        jsr textend
@t:     lda TOOL_
        asl
        tax
        lda tooltab+1,x
        pha
        lda tooltab,x
        pha
@r:     rts
tooltab:
        .word t_sel-1, t_hand-1, t_text-1, t_fill-1, t_spray-1, t_brush-1
        .word t_pencil-1, t_line-1, t_erase-1, t_rect-1, t_rectf-1
        .word t_oval-1, t_ovalf-1, t_zoom-1

; Carry set if PMX, PMY is on the canvas
incanvas:
        lda PMX
        sec
        sbc CANX
        sta U0
        lda PMX+1
        sbc CANX+1
        sta U0+1
        bcc @no
        lda U0
        cmp CWP
        lda U0+1
        sbc CWP+1
        bcs @no
        lda PMY
        sec
        sbc CANY
        sta U0
        lda PMY+1
        sbc CANY+1
        sta U0+1
        bcc @no
        lda U0
        cmp CH
        lda U0+1
        sbc CH+1
        bcs @no
        sec
        rts
@no:    clc
        rts

; The palette: a tool, a line width, a pattern
palclick:
        lda PMX
        sec
        sbc CX0
        sta TMP                 ; x in the palette
        cmp #PALW
        bcs @r
        lda PMY
        sec
        sbc CY0
        sta U0
        lda PMY+1
        sbc CY0+1
        bmi @r
        bne @hi
        lda U0
        cmp #168
        bcs @wid
        ldx #0                  ; a tool: row = y / 24
@d:     cmp #24
        bcc @dd
        sbc #24
        inx
        bne @d
@dd:    jsr @half
        cmp #NTOOL
        bcs @r
        jsr settool
        jsr setport             ; (ending the text set the canvas' clip)
        jmp drawpal
@wid:   cmp #172
        bcc @r
        cmp #220
        bcs @pat
        sbc #172 - 1            ; (carry clear: - 172)
        ldx #1
@w:     cmp #12
        bcc @wd
        sbc #12
        inx
        bne @w
@wd:    stx LW
        jmp drawpal
@pat:   cmp #252
        bcc @r
        sbc #252
        jmp @p
@hi:    lda U0                  ; (y >= 256: y - 252)
        clc
        adc #4
@p:     ldx #0                  ; row = / 13
@pd:    cmp #13
        bcc @pr
        sbc #13
        inx
        bne @pd
@pr:    jsr @half
        cmp #16
        bcs @r
        sta PAT
        jmp drawpal
@r:     rts
@half:  txa                     ; row * 2 + the right column
        asl
        ldx TMP
        cpx #24
        adc #0
        rts

; A tool chosen (A): the selection and the text end
settool:
        pha
        jsr selnone
        jsr textend
        pla
        sta TOOL_
        rts

; The selection and the text typed: ended
endall: jsr selnone
        jmp textend

; PMX, PMY = the mouse; carry set if the button is up
mouse:  lda MOUSEX
        sta PMX
        lda MOUSEX+1
        sta PMX+1
        lda MOUSEY
        sta PMY
        lda MOUSEY+1
        sta PMY+1
        lda BUTTONS
        and #1
        eor #1
        lsr
        rts
; The next frame, then the mouse
wait1:  lda FRAME
@w:     cmp FRAME
        beq @w
        jmp mouse
; Carry clear if the mouse moved (PMX, PMY not LX, LY)
moved:  lda PMX
        cmp LX
        bne @y
        lda PMX+1
        cmp LX+1
        bne @y
        lda PMY
        cmp LY
        bne @y
        lda PMY+1
        cmp LY+1
        bne @y
        sec
        rts
@y:     clc
        rts
mtol:   MOVW LX, PMX
        MOVW LY, PMY
        rts

; A key: text being typed, else the arrows scroll, Esc, Delete, the tools'
; letters
key:    stx KCH
        sty KEXT
        jsr setport
        jsr canclip
        lda TXON
        beq @nt
        jmp textkey
@nt:    lda KCH
        bne @ch
        lda KEXT                ; arrows: the view moves
        cmp #10
        beq @del
        cmp #1
        bcc @r
        cmp #5
        bcs @r
        tax
        lda ZOOM
        beq @sc
        jmp zoomkey
@sc:    jsr selnone
        cpx #1
        bne @k2
        jsr vyup
        jmp scrolled
@k2:    cpx #2
        bne @k3
        jsr vydown
        jmp scrolled
@k3:    cpx #3
        bne @k4
        lda VX
        beq @r
        dec VX
        jmp scrolled
@k4:    inc VX
        jsr clampv
        jmp scrolled
@ch:    cmp #27                 ; Esc: no selection, out of FatBits
        bne @c1
        jsr selnone
        lda ZOOM
        beq @r
        jmp zoomout
@c1:    cmp #8
        beq @del
        cmp #127
        bne @c2
@del:   lda SEL                 ; Delete, Backspace: the selection cleared
        beq @r
        jmp m_clear
@c2:    and #$DF                ; a tool's letter
        ldx #NTOOL - 1
@f:     cmp toolkeys,x
        beq @tk
        dex
        bpl @f
@r:     rts
@tk:    txa
        jsr settool
        jsr setport
        jmp drawpal
toolkeys:
        .byte "SHTFABPLERGOQZ"

vyup:   lda VY
        sec
        sbc #16
        sta VY
        lda VY+1
        sbc #0
        sta VY+1
        bcs @r
        lda #0
        sta VY
        sta VY+1
@r:     rts
vydown: lda VY
        clc
        adc #16
        sta VY
        bcc @c
        inc VY+1
@c:     jmp clampv

; The view moved: drawn again, the bar too
scrolled:
        jsr showview
        jmp syncbar

; The wheel (Y steps, + = down): 16 rows a step
wheel:  sty CNT
        jsr setport
        lda ZOOM
        bne @r
        jsr endall
        lda CNT
        beq @r
        bmi @up
@d:     jsr vydown
        dec CNT
        bne @d
        jmp scrolled
@up:    jsr vyup
        inc CNT
        bne @up
        jmp scrolled
@r:     rts

; The scroll bar moved: r0 = VY
barmoved:
        MOVW VY, r0
        jsr setport
        lda ZOOM
        bne @r
        jsr endall
        jsr clampv
        jsr showview
@r:     rts

; --- the simple tools -------------------------------------------------------------
; Blitter coordinates: X0 = a, Y0 = b (from zero page X, Y)
bxy0:   lda 0,x
        sta BX0
        lda 1,x
        sta BX0H
        lda 0,y
        sta BY0
        lda 1,y
        sta BY0H
        rts
bxy1:   lda 0,x
        sta BX1
        lda 1,x
        sta BX1H
        lda 0,y
        sta BY1
        lda 1,y
        sta BY1H
        rts
; The rectangle X0..Y1 -> the blitter, then command A
brect:  pha
        ldx #X0
        ldy #Y0
        jsr bxy0
        ldx #X1
        ldy #Y1
        jsr bxy1
        pla
        sta BCMD
        rts
; Plain drawing: SET, black, no pattern
ink:    lda #R_SET
        sta ROP
        lda #0
        sta PATON
        lda #1
        sta BCOL
        rts
; The pattern in use, SET
inkpat: lda #R_SET
        sta ROP
        lda PAT
        jsr setpat
        lda #1
        sta PATON
        rts

; Pencil: black (white over black) lines following the mouse
t_pencil:
        jsr snapshot
        ldx #PMX
        ldy #PMY
        jsr bxy0
        lda BPIXEL
        eor #1
        and #1
        sta COLR
        jsr mtol
@seg:   jsr ink
        lda COLR
        sta BCOL
        ldx #LX
        ldy #LY
        jsr bxy0
        ldx #PMX
        ldy #PMY
        jsr bxy1
        lda #C_LINE
        sta BCMD
        jsr mtol
@l:     jsr wait1
        bcs @up
        jsr moved
        bcs @l
        bcc @seg
@up:    jmp done

; Brush: squares of the pattern; eraser: white squares
t_brush:
        lda LW
        asl
        asl
        bne brush
t_erase:
        lda #16
brush:  sta BS
        lsr
        bne @s
        lda #1
@s:     sta BSTEP
        jsr snapshot
        jsr mtol
        jsr dab
@l:     jsr wait1
        bcs @up
        jsr moved
        bcs @l
        jsr stroke
        jsr mtol
        jmp @l
@up:    jmp done

; From LX, LY to PMX, PMY: dabs every BSTEP pixels (halving the way)
stroke: lda PMX
        sec
        sbc LX
        sta U0
        lda PMX+1
        sbc LX+1
        jsr abs16
        bne @far
        lda U0
        cmp BSTEP
        bcs @far
        lda PMY
        sec
        sbc LY
        sta U0
        lda PMY+1
        sbc LY+1
        jsr abs16
        bne @far
        lda U0
        cmp BSTEP
        bcs @far
        jmp dab
@far:   lda PMX+1                ; the end kept, the middle first
        pha
        lda PMX
        pha
        lda PMY+1
        pha
        lda PMY
        pha
        lda PMX
        clc
        adc LX
        sta PMX
        lda PMX+1
        adc LX+1
        lsr
        sta PMX+1
        ror PMX
        lda PMY
        clc
        adc LY
        sta PMY
        lda PMY+1
        adc LY+1
        lsr
        sta PMY+1
        ror PMY
        jsr stroke
        jsr mtol
        pla
        sta PMY
        pla
        sta PMY+1
        pla
        sta PMX
        pla
        sta PMX+1
        jmp stroke
; A:U0 (16 bits, signed) -> its size; A = the high byte (Z: < 256)
abs16:  sta U0+1
        bpl @p
        lda #0
        sec
        sbc U0
        sta U0
        lda #0
        sbc U0+1
        sta U0+1
@p:     lda U0+1
        rts

; A square of BS pixels at PMX, PMY: the pattern (brush) or white (eraser)
dab:    lda PMX
        sec
        sbc BSTEP
        sta X0
        lda PMX+1
        sbc #0
        sta X0+1
        lda PMY
        sec
        sbc BSTEP
        sta Y0
        lda PMY+1
        sbc #0
        sta Y0+1
        bcs @y
        lda #0
        sta Y0
        sta Y0+1
@y:     lda X0+1
        bpl @x
        lda #0
        sta X0
        sta X0+1
@x:     lda X0
        clc
        adc BS
        sta X1
        lda X0+1
        adc #0
        sta X1+1
        lda Y0
        clc
        adc BS
        sta Y1
        lda Y0+1
        adc #0
        sta Y1+1
        jsr dec1
        lda TOOL_
        cmp #T_ERASE
        beq @w
        jsr inkpat
        lda #C_BOXF
        jmp brect
@w:     jsr ink
        lda #0
        sta BCOL
        lda #C_BOXF
        jmp brect
; X1, Y1 one less
dec1:   lda X1
        bne @a
        dec X1+1
@a:     dec X1
        lda Y1
        bne @b
        dec Y1+1
@b:     dec Y1
        rts

; Spray: dots of the pattern within 8 pixels of the mouse
t_spray:
        jsr snapshot
        jsr inkpat
@l:     lda #10
        sta CNT
@d:     jsr rand
        and #15
        sec
        sbc #8
        sta TMP                 ; -8..7
        jsr rand
        and #15
        sec
        sbc #8
        sta TMP2
        lda TMP                 ; within the circle: x^2 + y^2 < 64
        jsr sq
        sta CNT2
        lda TMP2
        jsr sq
        clc
        adc CNT2
        bcs @n
        cmp #64
        bcs @n
        lda TMP                 ; the dot
        jsr sxt
        clc
        adc PMX
        sta BX0
        txa
        adc PMX+1
        sta BX0H
        lda TMP2
        jsr sxt
        clc
        adc PMY
        sta BY0
        txa
        adc PMY+1
        sta BY0H
        lda #C_PSET
        sta BCMD
@n:     dec CNT
        bne @d
        jsr wait1
        bcc @l
        jmp done
; A = A * A (A between -8 and 7)
sq:     bpl @p
        eor #$FF
        clc
        adc #1
@p:     tax
        lda sqt,x
        rts
sqt:    .byte 0, 1, 4, 9, 16, 25, 36, 49, 64
; A (signed) -> A, X = its high byte
sxt:    ldx #0
        cmp #0
        bpl @r
        dex
@r:     rts
; A = a random byte
rand:   ldx #8                  ; (a 16-bit LFSR, 8 steps)
@l:     asl RND
        rol RND+1
        bcc @n
        lda RND
        eor #$2D
        sta RND
@n:     dex
        bne @l
        lda RND
        rts

; --- rubber-band shapes: line, rectangles, ovals ---------------------------------
t_line: lda #0
        beq rubber
t_rect: lda #1
        bne rubber
t_rectf:
        lda #2
        bne rubber
t_oval: lda #3
        bne rubber
t_ovalf:
        lda #4
rubber: sta SHAPE
        jsr snapshot
        MOVW SX, PMX
        MOVW SY, PMY
        jsr mtol
        jsr xorshape
@l:     jsr wait1
        bcs @up
        jsr mclamp
        jsr moved
        bcs @l
        jsr xorshape            ; the old one away, the new one
        jsr mtol
        jsr xorshape
        jmp @l
@up:    jsr xorshape
        jsr mclamp
        jsr mtol
        lda SHAPE
        asl
        tax
        lda finaltab+1,x
        pha
        lda finaltab,x
        pha
        rts                     ; -> the shape drawn, then done
finaltab:
        .word f_line-1, f_rect-1, f_rectf-1, f_oval-1, f_ovalf-1

; PMX, PMY kept on the canvas
mclamp: lda PMX
        cmp CANX
        lda PMX+1
        sbc CANX+1
        bcs @a
        MOVW PMX, CANX
@a:     lda PMY
        cmp CANY
        lda PMY+1
        sbc CANY+1
        bcs @b
        MOVW PMY, CANY
@b:     lda CANX                ; < CANX + CWP
        clc
        adc CWP
        sta U0
        lda CANX+1
        adc CWP+1
        sta U0+1
        lda PMX
        cmp U0
        lda PMX+1
        sbc U0+1
        bcc @c
        lda U0
        sec
        sbc #1
        sta PMX
        lda U0+1
        sbc #0
        sta PMX+1
@c:     lda CANY
        clc
        adc CH
        sta U0
        lda CANY+1
        adc CH+1
        sta U0+1
        lda PMY
        cmp U0
        lda PMY+1
        sbc U0+1
        bcc @r
        lda U0
        sec
        sbc #1
        sta PMY
        lda U0+1
        sbc #0
        sta PMY+1
@r:     rts

; X0..Y1 = SX, SY .. LX, LY in order (left top, right bottom)
order:  MOVW X0, SX
        MOVW X1, LX
        lda X1
        cmp X0
        lda X1+1
        sbc X0+1
        bcs @y
        MOVW X0, LX
        MOVW X1, SX
@y:     MOVW Y0, SY
        MOVW Y1, LY
        lda Y1
        cmp Y0
        lda Y1+1
        sbc Y0+1
        bcs @r
        MOVW Y0, LY
        MOVW Y1, SY
@r:     rts

; The shape from S to L, one pixel wide, XORed (the rubber band)
xorshape:
        lda #R_XOR
        sta ROP
        lda #0
        sta PATON
        lda #1
        sta BCOL
        lda SHAPE
        bne @n
        ldx #SX
        ldy #SY
        jsr bxy0
        ldx #LX
        ldy #LY
        jsr bxy1
        lda #C_LINE
        sta BCMD
        jmp @r
@n:     jsr order
        lda SHAPE
        cmp #3
        bcs @o
        lda #C_BOX
        jsr brect
        jmp @r
@o:     lda #0
        sta CNT2
        jsr ovalspans           ; (XOR: each pixel once)
@r:     lda #R_SET
        sta ROP
        rts

f_line: jsr ink                 ; LW x LW lines side by side
        lda #0
        sta CNT
@i:     lda #0
        sta CNT2
@j:     lda SX
        clc
        adc CNT
        sta BX0
        lda SX+1
        adc #0
        sta BX0H
        lda SY
        clc
        adc CNT2
        sta BY0
        lda SY+1
        adc #0
        sta BY0H
        lda LX
        clc
        adc CNT
        sta BX1
        lda LX+1
        adc #0
        sta BX1H
        lda LY
        clc
        adc CNT2
        sta BY1
        lda LY+1
        adc #0
        sta BY1H
        lda #C_LINE
        sta BCMD
        inc CNT2
        lda CNT2
        cmp LW
        bne @j
        inc CNT
        lda CNT
        cmp LW
        bne @i
        jmp done

f_rectf:
        jsr order
        jsr inkpat
        lda #C_BOXF
        jsr brect
        jmp f_r2
f_rect: jsr order
f_r2:   jsr ink                 ; LW frames, each one inside the last
        lda LW
        sta CNT
@l:     lda #C_BOX
        jsr brect
        lda X1                  ; too small for another?
        sec
        sbc X0
        sta U0
        lda X1+1
        sbc X0+1
        bne @in
        lda U0
        cmp #2
        bcc @e
@in:    lda Y1
        sec
        sbc Y0
        sta U0
        lda Y1+1
        sbc Y0+1
        bne @in2
        lda U0
        cmp #2
        bcc @e
@in2:   inc X0
        bne @a
        inc X0+1
@a:     inc Y0
        bne @b
        inc Y0+1
@b:     jsr dec1
        dec CNT
        bne @l
@e:     jmp done

f_ovalf:
        jsr order
        jsr inkpat
        lda #1
        sta CNT2
        jsr ovalspans
f_oval: jsr order
        jsr ink
        lda LW
        sta CNT
@l:     lda #0
        sta CNT2
        jsr ovalspans
        lda X1                  ; one pixel smaller all round
        sec
        sbc X0
        sta U0
        lda X1+1
        sbc X0+1
        bne @in
        lda U0
        cmp #3
        bcc @e
@in:    lda Y1
        sec
        sbc Y0
        sta U0
        lda Y1+1
        sbc Y0+1
        bne @in2
        lda U0
        cmp #3
        bcc @e
@in2:   inc X0
        bne @a
        inc X0+1
@a:     inc Y0
        bne @b
        inc Y0+1
@b:     jsr dec1
        dec CNT
        bne @l
@e:     jmp done

; --- the hand: the view dragged -----------------------------------------------------
t_hand: jsr mtol
        lda #0
        sta ACCX
@l:     jsr wait1
        bcs @up
        jsr moved
        bcs @l
        lda LX                  ; x: whole bytes only
        sec
        sbc PMX
        clc
        adc ACCX
        sta ACCX
        lda #0
        sta CNT                 ; changed?
@x1:    lda ACCX
        bmi @xn
        cmp #8
        bcc @y
        sbc #8
        sta ACCX
        inc VX
        inc CNT
        bne @x1
@xn:    cmp #$F9                ; <= -8
        bcs @y
        adc #8
        sta ACCX
        lda VX
        beq @x1
        dec VX
        inc CNT
        bne @x1
@y:     lda LY                  ; y: VY += LY - PMY
        sec
        sbc PMY
        sta U0
        lda LY+1
        sbc PMY+1
        sta U0+1
        ora U0
        beq @s
        inc CNT
        lda VY
        clc
        adc U0
        sta VY
        lda VY+1
        adc U0+1
        sta VY+1
        bpl @s
        lda #0
        sta VY
        sta VY+1
@s:     jsr clampv
        jsr mtol
        lda CNT
        beq @l
        jsr showview
        jmp @l
@up:    lda CLICKS
        jmp syncbar

; --- the patterns ----------------------------------------------------------------
pats:   .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF    ; black
        .byte $00, $00, $00, $00, $00, $00, $00, $00    ; white
        .byte $AA, $55, $AA, $55, $AA, $55, $AA, $55    ; grey
        .byte $88, $22, $88, $22, $88, $22, $88, $22    ; light grey
        .byte $77, $DD, $77, $DD, $77, $DD, $77, $DD    ; dark grey
        .byte $88, $00, $22, $00, $88, $00, $22, $00    ; lighter
        .byte $FF, $00, $00, $00, $FF, $00, $00, $00    ; lines across
        .byte $88, $88, $88, $88, $88, $88, $88, $88    ; lines down
        .byte $01, $02, $04, $08, $10, $20, $40, $80    ; diagonal /
        .byte $80, $40, $20, $10, $08, $04, $02, $01    ; diagonal \
        .byte $FF, $80, $80, $80, $FF, $80, $80, $80    ; grid
        .byte $FF, $80, $80, $80, $FF, $08, $08, $08    ; bricks
        .byte $F0, $F0, $F0, $F0, $0F, $0F, $0F, $0F    ; checks
        .byte $81, $42, $24, $18, $18, $24, $42, $81    ; crosses
        .byte $00, $18, $24, $C3, $00, $18, $24, $C3    ; waves
        .byte $80, $00, $00, $00, $08, $00, $00, $00    ; dots

        .include "paint_icons.inc"
