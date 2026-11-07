;=============================================================================
; tk3.asm - mini6502 desktop toolkit, bank $17: controls (the functions,
; drawing)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Reached through the dispatcher in bank $10 (functions 18-23) and from the
; toolkit's other banks. See README.txt.
;=============================================================================

TK3     = 1
        .include "tk.inc"
        .include "ctl.inc"

        .org $E000
        jmp t_newctl            ; $E000  18 NEWCTL
        jmp t_dispose           ; $E003  19 DISPOSECTL
        jmp t_setvalue          ; $E006  20 SETVALUE
        jmp t_getvalue          ; $E009  21 GETVALUE
        jmp t_enable            ; $E00C  22 ENABLECTL
        jmp t_setdata           ; $E00F  23 SETDATA
        jmp i_reset             ; $E012  (INIT, CLEAR) no controls
        jmp i_drawwin           ; $E015  X = window: its controls (UPDATE)
        jmp i_freewin           ; $E018  X = window: its controls are gone
        jmp ctlshow             ; $E01B  X = control: shown now (or damaged)
        jmp radiogroup          ; $E01E  CI = radio on: the rest of its group off
        jmp ctlinit             ; $E021  X = control from KWIN, KKIND, r0-r5
        jmp ctldraw             ; $E024  X = control drawn through the clip
        jmp forget              ; $E027  X = control gone


;=============================================================================
; the functions
;=============================================================================

; NEWCTL: X = window, Y = kind, r0-r3 = rectangle inside the window's
; contents (x0, y0, x1, y1), r4 / r5 as the kind says -> X = control
t_newctl:
        stx KWIN
        sty KKIND
        cpy #CK_BUTTON
        bcc @bad
        cpy #CK_LABEL + 1
        bcs @bad
        ldx #0
@f:     lda C_KIND,x
        beq @free
        inx
        cpx #MAXCTL
        bne @f
@bad:   sec
        rts
@free:  jsr ctlinit
        jsr ctlshow
        ldx CI
        clc
        rts

; Control X = kind KKIND in window KWIN, from r0-r5 and CBANK
ctlinit:
        stx CI
        lda KKIND
        sta C_KIND,x
        lda KWIN
        sta C_WIN,x
        lda #0
        sta C_FLAGS,x
        sta C_VALL,x
        sta C_VALH,x
        sta C_TOP,x
        lda r0
        sta C_X0L,x
        lda r0+1
        sta C_X0H,x
        lda r1
        sta C_Y0L,x
        lda r1+1
        sta C_Y0H,x
        lda r2
        sta C_X1L,x
        lda r2+1
        sta C_X1H,x
        lda r3
        sta C_Y1L,x
        lda r3+1
        sta C_Y1H,x
        lda r4
        sta C_PTRL,x
        lda r4+1
        sta C_PTRH,x
        lda CBANK
        sta C_BANK,x
        lda r5
        sta C_MAXL,x
        sta C_AUX,x             ; (radio: the group)
        lda r5+1
        sta C_MAXH,x
        lda KKIND
        cmp #CK_SCROLL
        bne @nsc
        lda r4                  ; scroll bar: r4 = page step (1 at least)
        bne @pg
        lda #1
@pg:    sta C_AUX,x
@nsc:   cmp #CK_FIELD
        bne @nfd
        jsr fieldmax
@nfd:   lda KKIND
        cmp #CK_LIST
        bne @r
        lda #$FF                ; a list starts with nothing chosen
        sta C_VALL,x
        sta C_VALH,x
        lda C_MAXH,x            ; (255 items at most)
        beq @r
        lda #255
        sta C_MAXL,x
        lda #0
        sta C_MAXH,x
@r:     rts

; a field's maximum length: 1-60
fieldmax:
        lda C_MAXH,x
        bne @60
        lda C_MAXL,x
        beq @60
        cmp #61
        bcc @r
@60:    lda #60
        sta C_MAXL,x
        lda #0
        sta C_MAXH,x
@r:     rts

; DISPOSECTL: X = control (or $80 + window: all of that window's)
t_dispose:
        txa
        bpl @one
        and #7
        tax
        jsr i_freewin
        clc
        rts
@one:   cpx #MAXCTL
        bcs @r
        lda C_KIND,x
        beq @r
        stx CI
        jsr ctlrect             ; what it covered is drawn again
        jsr adddamage
        ldx CI
        jsr forget
@r:     clc
        rts

; control X is gone (kind 0, no focus, no repeat)
forget: lda #0
        sta C_KIND,x
        cpx FOCUS
        bne @f
        lda #$FF
        sta FOCUS
@f:     cpx REPCTL
        bne @r
        lda #$FF
        sta REPCTL
@r:     rts

; SETVALUE: X = control, r0 = value
t_setvalue:
        jsr valid
        bcs @r
        lda r0
        sta C_VALL,x
        lda r0+1
        sta C_VALH,x
        jsr clampval
        lda C_KIND,x
        cmp #CK_RADIO
        bne @s
        lda C_VALL,x
        beq @s
        jsr radiogroup
@s:     ldx CI
        jsr ctlshow
        clc
@r:     rts

; GETVALUE: X = control -> r0 = value (A = its low byte)
t_getvalue:
        jsr valid
        bcs @r
        lda C_VALH,x
        sta r0+1
        lda C_VALL,x
        sta r0
        clc
@r:     rts

; ENABLECTL: X = control, Y = 1 enabled, 0 disabled (greyed, not clickable)
t_enable:
        jsr valid
        bcs @r
        lda #0
        cpy #0
        bne @e
        lda #F_OFF
@e:     sta C_FLAGS,x
        tay                     ; (disabled: it loses the focus)
        beq @s
        cpx FOCUS
        bne @s
        lda #$FF
        sta FOCUS
@s:     jsr ctlshow
        clc
@r:     rts

; SETDATA: X = control, r0 = its text / buffer / items, r1 = its number
; (field: maximum length, list: count, scroll bar: maximum)
t_setdata:
        jsr valid
        bcs @r
        lda r0
        sta C_PTRL,x
        lda r0+1
        sta C_PTRH,x
        lda CBANK
        sta C_BANK,x
        lda C_KIND,x
        cmp #CK_FIELD
        beq @n
        cmp #CK_LIST
        beq @list
        cmp #CK_SCROLL
        bne @s
@n:     lda r1
        sta C_MAXL,x
        lda r1+1
        sta C_MAXH,x
        lda C_KIND,x
        cmp #CK_FIELD
        bne @c
        jsr fieldmax
@c:     jsr clampval
@s:     ldx CI
        jsr ctlshow
        clc
@r:     rts
@list:  lda r1+1                ; a new list: nothing chosen, from the top
        beq @l
        lda #255
        sta r1
@l:     lda r1
        sta C_MAXL,x
        lda #0
        sta C_MAXH,x
        sta C_TOP,x
        lda #$FF
        sta C_VALL,x
        sta C_VALH,x
        jmp @s

; Keeps control X's value in range
clampval:
        lda C_KIND,x
        cmp #CK_CHECK
        beq @01
        cmp #CK_RADIO
        beq @01
        cmp #CK_SCROLL
        beq @max
        cmp #CK_LIST
        bne @r
        lda C_VALH,x            ; a list: $FFFF (none) or below the count
        bne @none
        lda C_VALL,x
        cmp C_MAXL,x
        bcc @vis
@none:  lda #$FF
        sta C_VALL,x
        sta C_VALH,x
@r:     rts
@vis:   jmp showsel
@01:    lda C_VALL,x
        ora C_VALH,x
        beq @z
        lda #1
@z:     sta C_VALL,x
        lda #0
        sta C_VALH,x
        rts
@max:   lda C_VALH,x            ; value > max: max (negative: 0)
        bmi @zero
        lda C_MAXL,x
        cmp C_VALL,x
        lda C_MAXH,x
        sbc C_VALH,x
        bcs @r
        lda C_MAXL,x
        sta C_VALL,x
        lda C_MAXH,x
        sta C_VALH,x
        rts
@zero:  lda #0
        sta C_VALL,x
        sta C_VALH,x
        rts

; The other radio buttons of control CI's window and group: off
radiogroup:
        lda CI
        sta RGC
        ldx #0
@l:     cpx RGC
        beq @n
        lda C_KIND,x
        cmp #CK_RADIO
        bne @n
        ldy RGC
        lda C_WIN,x
        cmp C_WIN,y
        bne @n
        lda C_AUX,x
        cmp C_AUX,y
        bne @n
        lda C_VALL,x
        beq @n
        lda #0
        sta C_VALL,x
        stx RGX
        jsr ctlshow
        ldx RGX
@n:     inx
        cpx #MAXALL
        bne @l
        lda RGC
        sta CI
        tax
        rts

;=============================================================================
; from the event code in bank $10
;=============================================================================

; INIT / CLEAR: no controls
i_reset:
        lda #0
        ldx #MAXALL - 1
@c:     sta C_KIND,x
        dex
        bpl @c
        lda #$FF
        sta FOCUS
        sta REPCTL
        sta LASTC
        lda #0
        sta PRESSED
        clc
        rts

; Window X is closed: its controls go too
i_freewin:
        stx KWIN
        ldx #MAXALL - 1
@l:     lda C_KIND,x
        beq @n
        lda C_WIN,x
        cmp KWIN
        bne @n
        jsr forget
@n:     dex
        bpl @l
        clc
        rts

; UPDATE of window X: its controls, through the clip already set (r0-r7 kept)
i_drawwin:
        stx KWIN
        jsr saver
        ldx #0
@l:     stx CJ
        lda C_KIND,x
        beq @n
        lda C_WIN,x
        cmp KWIN
        bne @n
        jsr ctldraw
@n:     ldx CJ
        inx
        cpx #MAXCTL
        bne @l
        jsr restr
        clc
        rts

saver:  ldx #7
@c:     lda r0,x
        sta SAVR,x
        dex
        bpl @c
        rts
restr:  ldx #7
@c:     lda SAVR,x
        sta r0,x
        dex
        bpl @c
        rts

; T1 = RY0 + (height - 16) / 2: where a line of text goes in RY0..RY1
textmid:
        lda RY1
        sec
        sbc RY0
        sec
        sbc #15                 ; height - 16
        bcs @p
        lda #0
@p:     lsr
        clc
        adc RY0
        sta T1
        lda RY0+1
        adc #0
        sta T1+1
        rts

; The clip = (the clip kept in SAVCLIP) within RX0..RY1
clipin: ldx #0
        jsr @max
        ldx #2
        jsr @max
        ldx #4
        jsr @min
        ldx #6
        jsr @min
        rts
@max:   lda RX0,x               ; the larger of the two lower edges
        cmp SAVCLIP,x
        lda RX0+1,x
        sbc SAVCLIP+1,x
        bcs @r
        bcc @k
@min:   lda SAVCLIP,x           ; the smaller of the two upper edges
        cmp RX0,x
        lda SAVCLIP+1,x
        sbc RX0+1,x
        bcs @r
@k:     lda SAVCLIP,x
        sta CLIPR,x
        lda SAVCLIP+1,x
        sta CLIPR+1,x
        rts
@r:     lda RX0,x
        sta CLIPR,x
        lda RX0+1,x
        sta CLIPR+1,x
        rts

keepclip:
        ldx #7
@c:     lda CLIPR,x
        sta SAVCLIP,x
        dex
        bpl @c
        rts
backclip:
        ldx #7
@c:     lda SAVCLIP,x
        sta CLIPR,x
        dex
        bpl @c
        rts
keepclip2:
        ldx #7
@c:     lda CLIPR,x
        sta SAVCLIP2,x
        dex
        bpl @c
        rts
backclip2:
        ldx #7
@c:     lda SAVCLIP2,x
        sta CLIPR,x
        dex
        bpl @c
        rts

;=============================================================================
; drawing
;=============================================================================

; Shows control X now: drawn at once in the window in front (or the file
; dialog), else its place is damaged (drawn again by the next redraw pass)
ctlshow:
        stx CI
        lda C_WIN,x
        cmp #DLGWIN
        beq @dlg
        cmp FRONTW
        bne @later
        lda PASSON
        bne @later
        jsr keepclip2           ; the clip = the window's contents
        ldx CI
        lda C_WIN,x
        tax
        jsr wincontent
        jsr clipset
        ldx CI
        jsr ctldraw
        jmp backclip2
@dlg:   jsr keepclip2
        jsr clipfull
        ldx CI
        jsr ctldraw
        jmp backclip2
@later: ldx CI
        jsr ctlrect
        jmp adddamage

; Draws control X (through the clip, never outside its own rectangle)
ctldraw:
        stx CI
        jsr keepclip
        ldx CI
        jsr ctlrect
        jsr clipin
        lda #R_SET
        sta ROP
        lda #0
        sta PATON
        sta STYLE
        ldx CI
        lda C_KIND,x
        asl
        tax
        lda drawtab-1,x
        pha
        lda drawtab-2,x
        pha
        rts                     ; to the kind's routine, back to @done
drawtab:
        .word d_button-1, d_check-1, d_radio-1, d_scroll-1, d_field-1
        .word d_list-1, d_label-1
d_done: ldx CI                  ; disabled: greyed (half the ink cleared)
        lda C_FLAGS,x
        and #F_OFF
        beq @ok
        jsr ctlrect
        jsr patgrey
        lda #5                  ; ROP 5: CLEAR where the pattern is 1
        sta ROP
        lda #1
        sta PATON
        jsr fillr2
        lda #0
        sta PATON
        lda #R_SET
        sta ROP
@ok:    jmp backclip

; The control's text (label) -> LBUF, TP = LBUF
gettext:
        ldx CI
        lda C_PTRL,x
        sta T0
        lda C_PTRH,x
        sta T0+1
        lda CBANK
        pha
        lda C_BANK,x
        sta CBANK
        LDW QP, LBUF
        lda #63
        jsr fetchstr
        pla
        sta CBANK
        LDW TP, LBUF
        rts

; BUTTON: a frame with rounded corners, the label in the middle; PRESSED:
; inverted
d_button:
        lda #0
        jsr fillrect
        jsr framerect
        jsr corners
        jsr gettext
        jsr strlen
        jsr centrex
        jsr textmid
        jsr moveto
        jsr drawstr
        lda PRESSED
        beq @d
        ldx CI
        jsr ctlrect
        jsr shrink
        jsr invrect
@d:     jmp d_done

; the four corner pixels of RX0..RY1 cleared (rounded look)
corners:
        lda #0
        sta BCOL
        MOVW LX0, RX0
        MOVW LY0, RY0
        jsr pset
        MOVW LX0, RX1
        jsr pset
        MOVW LY0, RY1
        jsr pset
        MOVW LX0, RX0
pset:   jsr lxy
        lda #C_PSET
        sta BCMD
        rts

; RX0..RY1 shrunk by 1 on each side
shrink: ADDW RX0, RX0, 1
        ADDW RY0, RY0, 1
        SUBW RX1, RX1, 1
        SUBW RY1, RY1, 1
        rts

; RX0,RY0.. = the 12 x 12 box of a check box or radio button
markbox:
        jsr textmid             ; (T1 = the text line; the box 2 lower)
        ADDW RY0, T1, 2
        ADDW RY1, RY0, 11
        ADDW RX1, RX0, 11
        rts

; the label right of the box
marklabel:
        ldx CI
        jsr ctlrect
        ADDW T0, RX0, 18
        jsr textmid
        jsr moveto
        jsr gettext
        jmp drawstr

; CHECK: a box, crossed when the value is 1
d_check:
        lda #0
        jsr fillrect
        jsr markbox
        jsr framerect
        ldx CI
        lda C_VALL,x
        beq @l
        ADDW LX0, RX0, 2        ; the cross
        ADDW LY0, RY0, 2
        ADDW LX1, RX1, -2
        ADDW LY1, RY1, -2
        jsr line
        lda LY0
        ldx LY1
        sta LY1
        stx LY0
        lda LY0+1
        ldx LY1+1
        sta LY1+1
        stx LY0+1
        jsr line
@l:     jsr marklabel
        jmp d_done

; RADIO: a diamond, with a dot when the value is 1
d_radio:
        lda #0
        jsr fillrect
        jsr markbox
        ADDW T2, RX0, 6         ; the middle
        ADDW T3, RY0, 6
        ldx #3                  ; its four sides, from the top or bottom
@side:  txa                     ; point to the left or right one
        pha
        ldy #3
@m:     lda T2,y                ; both ends = the middle, then moved
        sta LX0,y
        sta LX1,y
        dey
        bpl @m
        lda rdy,x
        ldy #LY0 - LX0
        jsr addto
        pla
        pha
        tax
        lda rdx,x
        ldy #LX1 - LX0
        jsr addto
        jsr line
        pla
        tax
        dex
        bpl @side
        ldx CI
        lda C_VALL,x
        beq @l
        SUBW RX0, T2, 2         ; the dot
        SUBW RY0, T3, 2
        ADDW RX1, T2, 2
        ADDW RY1, T3, 2
        lda #1
        jsr fillrect
@l:     jsr marklabel
        jmp d_done

rdy:    .byte <-6, 6, 6, <-6
rdx:    .byte 6, 6, <-6, <-6
; A (-128..127) added to the word at LX0 + Y
addto:  pha
        clc
        adc LX0,y
        sta LX0,y
        pla
        and #$80
        beq @p
        lda #$FF
@p:     adc LX0+1,y
        sta LX0+1,y
        rts

; LABEL: the text
d_label:
        lda #0
        jsr fillrect
        lda RX0
        sta T0
        lda RX0+1
        sta T0+1
        jsr textmid
        jsr moveto
        jsr gettext
        jsr drawstr
        jmp d_done

; FIELD: a frame (double when it has the focus), the end of the text that
; fits, and a cursor when it has the focus
d_field:
        lda #0
        jsr fillrect
        jsr framerect
        jsr focusframe
        jsr gettext             ; (the caller's buffer -> LBUF)
        jsr strlen
        sta T2                  ; T2 = what is shown: the text (+ the cursor)
        ldx CI
        cpx FOCUS
        bne @nf
        inc T2
@nf:    lda RX1                 ; T3 = characters that fit: width / 8 - 1
        sec
        sbc RX0
        sta T3
        lda RX1+1
        sbc RX0+1
        lsr
        ror T3
        lsr
        ror T3
        lsr
        ror T3
        dec T3
        lda T2                  ; from: shown - fit (0 if it all fits)
        sec
        sbc T3
        bcs @st
        lda #0
@st:    clc
        adc #<LBUF
        sta TP
        lda #>LBUF
        adc #0
        sta TP+1
        ADDW T0, RX0, 4
        jsr textmid
        jsr moveto
        ldx CI                  ; selected: inverted
        lda C_FLAGS,x
        and #F_SEL
        beq @ns
        lda #S_OPAQUE + S_INV
        sta STYLE
@ns:    jsr drawstr
        lda #0
        sta STYLE
        ldx CI
        cpx FOCUS
        bne @d
        lda #'_'
        sta CHOUT
@d:     jmp d_done

; a second frame inside RX0..RY1 if control CI has the focus
focusframe:
        ldx CI
        cpx FOCUS
        bne @r
        jsr shrink
        jsr framerect
        ldx CI
        jsr ctlrect
@r:     rts

; SCROLL: a vertical scroll bar
d_scroll:
        jsr sbsetup
        jsr sbdraw
        jmp d_done

; LIST: a frame, a row of 16 pixels per item, the chosen one inverted, and a
; scroll bar on the right when they do not all fit
d_list: lda #0
        jsr fillrect
        jsr framerect
        jsr focusframe
        jsr listgeom
        ldx CI                  ; the rows
        lda C_TOP,x
        sta T2                  ; the item of the row
        jsr listseek
        lda #0
        sta T3                  ; the row
@row:   lda T3
        cmp ROWS
        bcs @rows
        lda T2
        ldx CI
        cmp C_MAXL,x
        bcs @rows
        jsr rowrect             ; RX0..RY1 = the row, the clip = it
        jsr clipin
        ADDW T0, RX0, 3
        MOVW T1, RY0
        jsr moveto
@ch:    lda PBDATA
        beq @end
        sta CHOUT
        jmp @ch
@end:   ldx CI                  ; the chosen item: inverted
        lda C_VALH,x
        bne @ni
        lda C_VALL,x
        cmp T2
        bne @ni
        jsr invrect
@ni:    inc T2
        inc T3
        jmp @row
@rows:  jsr backclip            ; the scroll bar
        jsr keepclip
        lda SHOWSB
        beq @d
        ldx CI
        jsr ctlrect
        jsr clipin
        jsr sbsetup
        jsr sbdraw
@d:     jmp d_done

; RX0..RY1 = row T3 of list CI (inside the frame, left of the scroll bar)
rowrect:
        ldx CI
        jsr ctlrect
        ADDW RX0, RX0, 2
        MOVW RX1, TXR
        lda T3                  ; y0 = list y0 + 2 + 16 * row
        asl
        asl
        asl
        asl
        clc
        adc #2
        adc RY0
        sta RY0
        lda RY0+1
        adc #0
        sta RY0+1
        ADDW RY1, RY0, 15
        rts

sbdraw: MOVW RX0, SBX0          ; the whole bar
        ADDW RX1, SBX0, 15
        MOVW RY0, SBY0
        MOVW RY1, SBY1
        lda #0
        jsr fillrect
        jsr framerect
        ADDW RY1, SBY0, 15      ; the up arrow's box
        jsr framerect
        ADDW LY0, SBY0, 10
        ADDW LY1, SBY0, 5
        jsr chevron
        SUBW RY0, SBY1, 15      ; the down arrow's box
        MOVW RY1, SBY1
        jsr framerect
        SUBW LY0, SBY1, 10
        SUBW LY1, SBY1, 5
        jsr chevron
        ADDW RX0, SBX0, 1       ; the track: grey
        ADDW RX1, SBX0, 14
        ADDW RY0, SBY0, 16
        SUBW RY1, SBY1, 16
        jsr patgrey
        jsr patrect
        lda SBM                 ; the thumb (none if there is nothing to scroll)
        ora SBM+1
        beq @r
        jsr sbthumb
        MOVW RX0, SBX0
        ADDW RX1, SBX0, 15
        MOVW RY0, THY
        ADDW RY1, THY, 15
        lda #0
        jsr fillrect
        jsr framerect
@r:     rts

; an arrow: from (middle - 4, LY0) to (middle, LY1) to (middle + 4, LY0)
chevron:
        ADDW LX0, SBX0, 3
        ADDW LX1, SBX0, 7
        jsr line
        ADDW LX0, SBX0, 11
        jsr line
        rts

; A line LX0,LY0 - LX1,LY1 in ink
line:   jsr lxy
        lda #R_SET
        sta ROP
        lda #0
        sta PATON
        lda #1
        sta BCOL
        lda #C_LINE
        sta BCMD
        rts
; LX0, LY0, LX1, LY1 -> the blitter's coordinates
lxy:    ldx #3
@c:     txa
        asl
        tay
        lda LX0,y
        sta BX0,x
        lda LX0+1,y
        sta BX0H,x
        dex
        bpl @c
        rts


        .include "ctlgeo.inc"
        .include "common.inc"
        .include "win.inc"

LBUF:   .res 64                 ; a control's text
        .assert * <= $F000, error, "TK3 must fit in its bank"
