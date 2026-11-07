;=============================================================================
; tktest.asm - test program for the mini6502 desktop toolkit (bank $20)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Menus, windows that can be dragged, brought to the front and
; closed (with a confirmation), a dialog that asks for a name, keyboard
; shortcuts. Each window remembers where it was clicked (small squares) and
; the last key typed into it, and draws them again on UPDATE.
;
;   L TK1 E000 10  /  L TK2 E000 11  /  V 10 10 E000   (the toolkit)
;   L TKTEST E000 20  /  D020: 20  /  E000R             (this program)
;=============================================================================

        .include "tk.inc"

TOOL    = $CC88                 ; far-call entry 16: the toolkit

.macro  TK fn
        lda #fn
        jsr TOOL
.endmacro

MAXPT   = 16
A0      = $80               ; this program's zero page ($80-$FF is ours)
A1      = $82
A2      = $84
A3      = $86
AP      = $88

        .org $E000

        jmp start               ; $E000
        .byte "TK"              ; $E003: a toolkit program (for the desktop)
start:
        TK TK_INIT
        LDW r0, menus
        TK TK_MENUBAR
        lda #0
        ldx #MAXWIN - 1
@c:     sta wused,x
        sta npts,x
        sta lastkey,x
        dex
        bpl @c
        lda #0
        sta nextpos
        LDW r4, s_welcome
        jsr newwin
        LDW r4, s_notes
        jsr newwin

; --- the event loop --------------------------------------------------------------------
loop:   TK TK_GETEVENT
        cmp #EV_UPDATE
        bne @n1
        jsr update
        jmp loop
@n1:    cmp #EV_MENU
        bne @n2
        jsr menu
        jmp loop
@n2:    cmp #EV_CLICK
        bne @n3
        jsr click
        jmp loop
@n3:    cmp #EV_CLOSE
        bne @n4
        jsr close
        jmp loop
@n4:    cmp #EV_KEY
        bne loop
        jsr key
        jmp loop

; --- menus ---------------------------------------------------------------------------------
menu:   cpx #0
        bne @file
        LDW r0, s_about         ; About
        LDW r1, 0
        TK TK_ALERT
        rts
@file:  cpx #1
        bne @win
        cpy #0
        bne @f1
        jmp newask              ; New window...
@f1:    cpy #1
        bne @f3
        jsr getfront            ; Close window
        bmi @r
        jmp close
@f3:    cpy #3
        bne @r
        LDW r0, s_quit          ; Quit
        LDW r1, s_quitbtn
        TK TK_ALERT
        cmp #0
        bne @r
        TK TK_EXIT              ; everything back as it was
        pla                     ; and return to whoever started us
        pla
        rts
@win:   cpx #3
        bne @r
        cpy #0
        bne @w1
        jsr getfront            ; Clear the clicks of the front window
        bmi @r
        lda #0
        sta npts,x
        sta lastkey,x
        TK TK_INVAL
        rts
@w1:    cpy #1
        bne @r
        jsr getfront            ; Next window: bring the next one to the front
        ldy #MAXWIN
@nx:    dey
        bmi @r
        lda front
        clc
        adc #1
        and #MAXWIN - 1
        sta front
        tax
        lda wused,x
        bne @go
        jmp @nx
@go:    TK TK_FRONT
@r:     rts

; New window: asks for its name
newask: ldx #0                  ; default: "Untitled"
@c:     lda s_untitled,x
        sta askbuf,x
        beq @a
        inx
        bne @c
@a:     LDW r0, s_ask
        LDW r1, askbuf
        LDW r2, 20
        TK TK_ASK
        bcs @r
        LDW r4, askbuf
        jmp newwin
@r:     rts

; Opens a window titled r4, a little lower right than the last one
newwin: lda nextpos
        asl                     ; x0 = 40 + n * 32, y0 = 40 + n * 24
        asl
        asl
        asl
        asl
        clc
        adc #40
        sta r0
        lda #0
        adc #0
        sta r0+1
        lda nextpos
        asl
        asl
        asl
        sta A0
        asl
        clc
        adc A0
        adc #40
        sta r1
        lda #0
        sta r1+1
        ADDW r2, r0, 300
        ADDW r3, r1, 170
        lda nextpos
        clc
        adc #1
        and #7
        sta nextpos
        TK TK_OPENWIN
        bcs @full
        lda #1
        sta wused,x
        lda #0
        sta npts,x
        sta lastkey,x
        stx front
        rts
@full:  LDW r0, s_full
        LDW r1, 0
        TK TK_ALERT
        rts

; Close box (or File/Close window): asks first
close:  stx curwin
        LDW r0, s_close
        LDW r1, s_closebtn
        TK TK_ALERT
        cmp #0
        bne @r
        ldx curwin
        lda #0
        sta wused,x
        TK TK_CLOSEWIN
@r:     rts

; --- clicks and keys -------------------------------------------------------------------
click:  cpx #MAXWIN             ; the desktop: nothing
        bcs @r
        stx front
        stx curwin
        lda npts,x              ; remember the point (up to 16)
        cmp #MAXPT
        bcs @r
        sta A0
        txa                     ; index = window * 16 + n
        asl
        asl
        asl
        asl
        clc
        adc A0
        tay
        lda r0
        sta ptxl,y
        lda r0+1
        sta ptxh,y
        lda r1
        sta ptyl,y
        lda r1+1
        sta ptyh,y
        inc npts,x
        sty A3                  ; draw it now (it is the front window)
        TK TK_SETPORT
        ldy A3
        jsr drawpt
        ldx curwin
        TK TK_SETPORT           ; and the count
        jsr drawinfo
@r:     rts

key:    stx A0
        jsr getfront
        bmi @r
        ldx A0
        ldy front
        txa                     ; the character (0 for arrows and such)
        bne @k
        lda #'?'
@k:     sta lastkey,y
        ldx front
        TK TK_INVAL             ; drawn again by the next UPDATE
@r:     rts

; X = front = the window in front ($FF, N set, if none)
getfront:
        ldx #$FF
        TK TK_FRONT
        stx front
        cpx #$FF
        bne @r
        ldx #$FF                ; (N set)
@r:     rts

; --- drawing a window's contents (clip and r0-r3 set by the toolkit) ---------
update: stx curwin
        jsr drawinfo
        ldx curwin              ; all its points
        lda npts,x
        beq @r
        sta A2
        txa
        asl
        asl
        asl
        asl
        tay
@p:     sty A3
        jsr drawpt
        ldy A3
        iny
        dec A2
        bne @p
@r:     rts

; Text lines at the top of window curwin (r0-r3 = its contents)
drawinfo:
        lda #0                  ; white strip first (the count changes)
        sta ROP
        sta PATON
        sta STYLE
        lda r0
        sta BX0
        lda r0+1
        sta BX0H
        lda r1
        sta BY0
        lda r1+1
        sta BY0H
        lda r2
        sta BX1
        lda r2+1
        sta BX1H
        ADDW A0, r1, 60
        lda A0
        sta BY1
        lda A0+1
        sta BY1H
        lda #0
        sta BCOL
        lda #C_BOXF
        sta BCMD
        ADDW A0, r0, 8          ; line 1
        ADDW A1, r1, 6
        jsr at
        LDW AP, s_info1
        jsr str
        ADDW A1, A1, 18         ; line 2: clicks
        jsr at
        LDW AP, s_info2
        jsr str
        ldx curwin
        lda npts,x
        jsr dec3
        ADDW A1, A1, 18         ; line 3: last key
        jsr at
        LDW AP, s_info3
        jsr str
        ldx curwin
        lda lastkey,x
        beq @r
        sta CHOUT
@r:     rts

; Filled 5x5 square at point Y of curwin (relative to r0, r1)
drawpt: lda #0
        sta ROP
        sta PATON
        lda r0
        clc
        adc ptxl,y
        sta BX0
        lda r0+1
        adc ptxh,y
        sta BX0H
        lda r1
        clc
        adc ptyl,y
        sta BY0
        lda r1+1
        adc ptyh,y
        sta BY0H
        lda BX0
        clc
        adc #4
        sta BX1
        lda BX0H
        adc #0
        sta BX1H
        lda BY0
        clc
        adc #4
        sta BY1
        lda BY0H
        adc #0
        sta BY1H
        lda #1
        sta BCOL
        lda #C_BOXF
        sta BCMD
        rts

at:     lda A0
        sta BX0
        lda A0+1
        sta BX0H
        lda A1
        sta BY0
        lda A1+1
        sta BY0H
        rts

str:    ldy #0
@l:     lda (AP),y
        beq @e
        sta CHOUT
        iny
        bne @l
@e:     rts

; A as 3 decimal digits
dec3:   ldx #'0'
@h:     cmp #100
        bcc @t
        sbc #100
        inx
        bne @h
@t:     stx CHOUT
        ldx #'0'
@t2:    cmp #10
        bcc @o
        sbc #10
        inx
        bne @t2
@o:     stx CHOUT
        ora #'0'
        sta CHOUT
        rts

; --- data ------------------------------------------------------------------------------------
menus:  .byte "mini6502", 0
        .byte "About TKTEST...", 0
        .byte 0
        .byte "File", 0
        .byte "New window.../N", 0
        .byte "Close window/W", 0
        .byte "-", 0
        .byte "Quit/Q", 0
        .byte 0
        .byte "Edit", 0
        .byte "(Undo/Z", 0
        .byte "-", 0
        .byte "(Cut", 0
        .byte "(Copy", 0
        .byte "(Paste", 0
        .byte 0
        .byte "Window", 0
        .byte "Clear clicks/K", 0
        .byte "Next window/T", 0
        .byte 0
        .byte 0

s_welcome:  .byte "Welcome", 0
s_notes:    .byte "Notes", 0
s_untitled: .byte "Untitled", 0
s_about:    .byte "TKTEST - a test of the mini6502 desktop toolkit", 13
            .byte "(C) 2026 Benoit Colson - GNU GPL 3", 13
            .byte "With the help of Claude AI.", 0
s_quit:     .byte "Quit TKTEST and go back?", 0
s_quitbtn:  .byte "Quit|Cancel", 0
s_close:    .byte "Close this window?", 0
s_closebtn: .byte "Close|Cancel", 0
s_ask:      .byte "Name of the new window:", 0
s_full:     .byte "No more windows: 8 at most.", 0
s_info1:    .byte "Click in here, type a key.", 0
s_info2:    .byte "Clicks: ", 0
s_info3:    .byte "Last key: ", 0

; --- variables (in this bank) ------------------------------------------------------
wused:  .res MAXWIN
npts:   .res MAXWIN
lastkey: .res MAXWIN
front:  .res 1
curwin: .res 1
nextpos: .res 1
askbuf: .res 24
ptxl:   .res MAXWIN * MAXPT
ptxh:   .res MAXWIN * MAXPT
ptyl:   .res MAXWIN * MAXPT
ptyh:   .res MAXWIN * MAXPT
