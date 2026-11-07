;=============================================================================
; tk4.asm - mini6502 desktop toolkit, bank $18: controls (clicks, keys)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Reached through the dispatcher in bank $10 (function 25) and from its
; event code and the file dialog (bank $19). See README.txt.
;=============================================================================

        .include "tk.inc"
        .include "ctl.inc"


        .org $E000
        jmp t_focus             ; $E000  25 FOCUS
        jmp i_click             ; $E003  X = window: a click on a control?
        jmp i_key               ; $E006  A = key, Y = KBDEXT: for a control?
        jmp i_idle              ; $E009  scroll arrows held down
        jmp i_wheel             ; $E00C  Y = wheel steps: for a list?
        jmp setfocus            ; $E00F  X = control: it gets the keys

; bank 3's routines
ctlshow:  FAR TKBANK3, T3_SHOW
radiogroup: FAR TKBANK3, T3_RADIO
ctlinit:  FAR TKBANK3, T3_INIT
ctldraw:  FAR TKBANK3, T3_DRAW
forget:   FAR TKBANK3, T3_FORGET

; RX0..RY1 shrunk by 1 on each side
shrink: ADDW RX0, RX0, 1
        ADDW RY0, RY0, 1
        SUBW RX1, RX1, 1
        SUBW RY1, RY1, 1
        rts


; FOCUS: X = the field or list that gets the keys ($FF none)
t_focus:
        cpx #$FF
        beq @set
        jsr valid
        bcs @r
@set:   jsr setfocus
        clc
@r:     rts

;=============================================================================
; clicks, keys
;=============================================================================

; X = the window (in front, or the file dialog), MX/MY = the mouse: a click
; on one of its controls? Carry clear: A = the event (EV_CONTROL: X = the
; control, Y = what, r0 = its value; or EV_NONE). Carry set: not a control.
i_click:
        stx KWIN
        ldx #MAXALL - 1
@l:     stx CJ
        lda C_KIND,x
        beq @n
        cmp #CK_LABEL
        beq @n
        lda C_WIN,x
        cmp KWIN
        bne @n
        lda C_FLAGS,x
        and #F_OFF
        bne @n
        jsr ctlrect
        jsr inrect
        bcs @hit
@n:     ldx CJ
        dex
        bpl @l
        sec
        rts
@hit:   ldx CJ
        stx CI
        lda C_KIND,x
        asl
        tax
        lda clicktab-1,x
        pha
        lda clicktab-2,x
        pha
        rts
clicktab:
        .word c_button-1, c_check-1, c_radio-1, c_scroll-1, c_field-1
        .word c_list-1

; EV_CONTROL for control CI, what = A
event:  tay
        ldx CI
        lda C_VALL,x
        sta r0
        lda C_VALH,x
        sta r0+1
        lda #EV_CONTROL
        clc
        rts
noevent:
        lda #EV_NONE
        clc
        rts

; BUTTON: inverted while held over it; released over it = clicked
c_button:
        lda #1
        sta PRESSED
        ldx CI
        jsr ctlshow
@hold:  jsr waitframe
        jsr readmouse
        ldx CI
        jsr ctlrect
        jsr inrect
        lda #0
        rol
        cmp PRESSED
        beq @same
        sta PRESSED
        ldx CI
        jsr ctlshow
@same:  lda BUTTONS
        and #1
        bne @hold
        lda CLICKS              ; (the release is not a click)
        lda PRESSED
        beq @no
        lda #0
        sta PRESSED
        ldx CI
        jsr ctlshow
        lda #1
        jmp event
@no:    jmp noevent

c_check:
        ldx CI
        lda C_VALL,x
        eor #1
        sta C_VALL,x
        jsr ctlshow
        lda #1
        jmp event

c_radio:
        ldx CI
        lda #1
        sta C_VALL,x
        jsr radiogroup
        ldx CI
        jsr ctlshow
        lda #1
        jmp event

c_field:
        ldx CI                  ; (a click unselects its text)
        lda C_FLAGS,x
        and #$FF - F_SEL
        sta C_FLAGS,x
        jsr setfocus
        jmp noevent

c_scroll:
        jsr sbclick
        bcs @n
        lda #1
        jmp event
@n:     jmp noevent

; A click in scroll bar SBX0.. of control CI: arrows and pages move one step
; and keep repeating while held (i_idle), the thumb follows the mouse.
; Carry clear if the value moved.
sbclick:
        ldx CI
        jsr ctlrect
        jsr sbsetup
        MOVW OLDV, SBV
        MOVW OLDV2, SBV
        jsr sbpart
        cmp #2
        beq @drag
        sta REPPART
        jsr sbstep
        jsr sbstore
        ldx CI
        stx REPCTL
        lda FRAME               ; the first repeat after 1/4 s
        clc
        adc #15
        sta REPT
        jmp @show
@drag:  jsr waitframe
        jsr readmouse
        ldx CI
        jsr ctlrect
        jsr sbsetup
        jsr sbfromy
        lda SBV
        cmp OLDV2
        bne @mv
        lda SBV+1
        cmp OLDV2+1
        beq @same
@mv:    MOVW OLDV2, SBV
        jsr sbstore
        ldx CI
        jsr ctlshow
@same:  lda BUTTONS
        and #1
        bne @drag
        lda CLICKS
@show:  ldx CI
        jsr ctlshow
        ldx CI                  ; moved?
        jsr ctlrect
        jsr sbsetup
        lda SBV
        cmp OLDV
        bne @y
        lda SBV+1
        cmp OLDV+1
        bne @y
        sec
        rts
@y:     clc
        rts

; LIST: the bar scrolls it; a row chooses its item (twice quickly: $81)
c_list: ldx CI
        jsr setfocus
        jsr listgeom
        lda SHOWSB
        beq @rows
        SUBW T0, RX1, 15        ; on the bar?
        lda MX
        cmp T0
        lda MX+1
        sbc T0+1
        bcc @rows
        jsr sbclick
        jmp noevent
@rows:  lda MY                  ; row = (MY - y0 - 2) / 16
        sec
        sbc RY0
        sta T0
        lda MY+1
        sbc RY0+1
        sta T0+1
        SUBW T0, T0, 2
        bmi @none
        lsr T0+1
        ror T0
        lsr T0+1
        ror T0
        lsr T0+1
        ror T0
        lsr T0+1
        ror T0
        lda T0
        cmp ROWS
        bcs @none
        ldx CI
        clc
        adc C_TOP,x
        bcs @none
        cmp C_MAXL,x
        bcs @none
        sta T2                  ; the item
        ldy #1                  ; the same item again quickly: a double click
        cpx LASTC
        bne @single
        cmp LASTR
        bne @single
        lda FRAME
        sec
        sbc LASTF
        cmp #24
        bcs @single
        ldy #$81
        lda #$FF
        sta LASTC
        bne @set
@single:
        stx LASTC
        lda T2
        sta LASTR
        lda FRAME
        sta LASTF
@set:   tya                     ; (kept: drawing uses TMPB)
        pha
        lda T2
        sta C_VALL,x
        lda #0
        sta C_VALH,x
        jsr ctlshow
        pla
        jmp event
@none:  jmp noevent

; Scroll arrows and pages held down: one more step every 3 frames. -> A =
; an event (a SCROLL control moved) or EV_NONE
i_idle: lda REPCTL
        bmi @none
        lda BUTTONS
        and #1
        bne @held
        lda #$FF
        sta REPCTL
@none:  lda #EV_NONE
        rts
@held:  lda FRAME
        sec
        sbc REPT
        bmi @none
        lda FRAME
        clc
        adc #3
        sta REPT
        ldx REPCTL
        stx CI
        lda C_WIN,x             ; only in front (or in the file dialog)
        cmp #DLGWIN
        beq @go
        cmp FRONTW
        bne @none
@go:    jsr ctlrect
        jsr sbsetup
        MOVW OLDV, SBV
        lda REPPART
        jsr sbstep
        jsr sbstore
        ldx CI
        jsr ctlshow
        ldx CI
        lda C_KIND,x
        cmp #CK_SCROLL
        bne @none
        lda SBV
        cmp OLDV
        bne @ev
        lda SBV+1
        cmp OLDV+1
        beq @none
@ev:    lda #1
        jmp event

; Focus to control X ($FF none): both drawn again
setfocus:
        lda FOCUS
        stx FOCUS
        cmp FOCUS
        beq @r
        tay
        bmi @new
        tax
        lda C_KIND,x
        beq @new
        jsr ctlshow
@new:   ldx FOCUS
        bmi @r
        jsr ctlshow
@r:     rts

; A key (A, or 0 and Y = the KBDEXT code) for window X: the field or list
; with the focus takes it; Tab moves the focus. Carry clear: taken, A = the
; event. Carry set: not for a control.
i_key:  stx KWIN
        sta KCH
        sty KEXT
        cmp #9                  ; Tab: the next field or list
        bne @nt
        jsr nextfocus
        bcs @no
        jmp noevent
@nt:    ldx FOCUS
        bmi @no
        stx CI
        lda C_KIND,x
        beq @no
        lda C_WIN,x
        cmp KWIN
        bne @no
        lda C_KIND,x
        cmp #CK_FIELD
        beq k_field
        cmp #CK_LIST
        bne @no
        jmp k_list
@no:    sec
        rts

; FIELD: typing, Backspace; Enter -> 13. A selected text (F_SEL) goes
; with the first character or Backspace; other keys just unselect it.
k_field:
        ldx CI
        lda C_FLAGS,x
        and #F_SEL
        beq @go
        lda C_FLAGS,x
        and #$FF - F_SEL
        sta C_FLAGS,x
        lda KCH
        cmp #' '
        bcs @clr
        cmp #8
        beq @clr
        jsr ctlshow
        jmp @go
@clr:   lda #0                  ; the text emptied
        jsr fieldat
        lda #0
        sta PBDATA
        lda KCH
        cmp #8
        beq @chg
        cmp #127
        beq @chg
@go:    lda KCH
        cmp #13
        bne @nr
        lda #13
        jmp event
@nr:    cmp #8
        beq @bs
        cmp #127
        beq @bs
        cmp #' '
        bcc @no
        jsr fieldlen
        ldx CI
        cmp C_MAXL,x
        bcs @full
        jsr fieldat             ; port B on the 0: the key, then a new 0
        lda KCH
        sta PBDATA
        lda #0
        sta PBDATA
        jmp @chg
@bs:    jsr fieldlen
        beq @full
        sec
        sbc #1
        jsr fieldat
        lda #0
        sta PBDATA
@chg:   ldx CI
        jsr ctlshow
        lda #1
        jmp event
@full:  lda #1                  ; (full / empty: a beep)
        sta BEEP
        jmp noevent
@no:    sec
        rts

; A = the length of field CI's text (port B then on its 0)
fieldlen:
        lda #0
        jsr fieldat
        ldx #0
@l:     lda PBDATA
        beq @e
        inx
        cpx #255
        bne @l
@e:     txa
        rts

; Port B on character A of field CI's buffer
fieldat:
        ldx CI
        clc
        adc C_PTRL,x
        sta T0
        lda C_PTRH,x
        adc #0
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
        rts

; LIST: Up / Down choose the item before / after; Enter -> 13
k_list: lda KCH
        cmp #13
        bne @nr
        lda #13
        jmp event
@nr:    cmp #0
        bne @no
        ldx CI
        lda C_MAXL,x
        beq @no
        lda KEXT
        cmp #1                  ; Up
        bne @dn
        lda C_VALH,x
        bne @first
        lda C_VALL,x
        beq @same
        dec C_VALL,x
        jmp @move
@dn:    cmp #2                  ; Down
        bne @no
        lda C_VALH,x
        bne @first
        lda C_VALL,x
        clc
        adc #1
        cmp C_MAXL,x
        bcs @same
        sta C_VALL,x
        jmp @move
@first: lda #0
        sta C_VALL,x
        sta C_VALH,x
@move:  jsr showsel
        ldx CI
        jsr ctlshow
        lda #1
        jmp event
@same:  jmp noevent
@no:    sec
        rts

; Focus to the next field or list of window KWIN (carry set: none)
nextfocus:
        ldx FOCUS
        ldy #MAXALL
@l:     inx
        cpx #MAXALL
        bcc @in
        ldx #0
@in:    lda C_WIN,x
        cmp KWIN
        bne @n
        lda C_FLAGS,x
        and #F_OFF
        bne @n
        lda C_KIND,x
        cmp #CK_FIELD
        beq @y
        cmp #CK_LIST
        beq @y
@n:     dey
        bne @l
        sec
        rts
@y:     jsr setfocus
        clc
        rts

; The wheel (Y steps) over window X: the list with the focus scrolls
i_wheel:
        stx KWIN
        sty KEXT
        ldx FOCUS
        bmi @no
        stx CI
        lda C_KIND,x
        cmp #CK_LIST
        bne @no
        lda C_WIN,x
        cmp KWIN
        bne @no
        jsr ctlrect
        jsr sbsetup
        lda KEXT                ; top + steps, kept within 0 .. max
        bmi @up
        clc
        adc SBV
        sta SBV
        bcs @max
        cmp SBM
        bcc @set
@max:   lda SBM
        sta SBV
        jmp @set
@up:    clc
        adc SBV
        sta SBV
        bcs @set
        lda #0
        sta SBV
@set:   jsr sbstore
        ldx CI
        jsr ctlshow
        jmp noevent
@no:    sec
        rts

; Part of the bar at MY: 0 up arrow, 1 above the thumb, 2 thumb, 3 below,
; 4 down arrow -> A
sbpart: ADDW T0, SBY0, 15
        lda T0                  ; MY <= SBY0 + 15: up
        cmp MY
        lda T0+1
        sbc MY+1
        bcc @n1
        lda #0
        rts
@n1:    SUBW T0, SBY1, 15       ; MY >= SBY1 - 15: down
        lda MY
        cmp T0
        lda MY+1
        sbc T0+1
        bcc @n2
        lda #4
        rts
@n2:    lda SBM
        ora SBM+1
        bne @th
        lda #3                  ; (no thumb: a page down)
        rts
@th:    jsr sbthumb
        lda MY                  ; above the thumb
        cmp THY
        lda MY+1
        sbc THY+1
        bcs @n3
        lda #1
        rts
@n3:    ADDW T0, THY, 15
        lda T0
        cmp MY
        lda T0+1
        sbc MY+1
        bcc @n4
        lda #2
        rts
@n4:    lda #3
        rts

; One step for part A (0 up, 1 page up, 3 page down, 4 down) on SBV
sbstep: cmp #0
        bne @n0
        lda #1
        bne @dec
@n0:    cmp #1
        bne @n1
        lda SBP
@dec:   sta T0
        lda SBV
        sec
        sbc T0
        sta SBV
        lda SBV+1
        sbc #0
        sta SBV+1
        bcs @r
        lda #0
        sta SBV
        sta SBV+1
@r:     rts
@n1:    cmp #3
        bne @n3
        lda SBP
        jmp @inc
@n3:    lda #1
@inc:   clc
        adc SBV
        sta SBV
        lda SBV+1
        adc #0
        sta SBV+1
        lda SBM                 ; not past the maximum
        cmp SBV
        lda SBM+1
        sbc SBV+1
        bcs @r
        MOVW SBV, SBM
        rts

; SBV from the mouse while the thumb is dragged: (MY - SBY0 - 24) * SBM / TRL
sbfromy:
        jsr sbtrack
        lda MY
        sec
        sbc SBY0
        sta MA
        lda MY+1
        sbc SBY0+1
        sta MA+1
        SUBW MA, MA, 24
        bpl @p
        lda #0
        sta SBV
        sta SBV+1
        rts
@p:     lda SBM
        sta MB
        lda SBM+1
        sta MB+1
        jsr mul16
        lda TRL
        ora TRL+1
        beq @max
        lda TRL
        sta MD
        lda TRL+1
        sta MD+1
        jsr div32
        lda PR
        sta SBV
        lda PR+1
        sta SBV+1
        lda PR+2                ; past the maximum: the maximum
        ora PR+3
        bne @max
        lda SBM
        cmp SBV
        lda SBM+1
        sbc SBV+1
        bcs @r
@max:   MOVW SBV, SBM
@r:     rts


        .include "ctlgeo.inc"
        .include "common.inc"
        .include "win.inc"

LBUF:   .res 64
        .assert * <= $F000, error, "TK4 must fit in its bank"
