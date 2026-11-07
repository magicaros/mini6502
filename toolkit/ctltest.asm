;=============================================================================
; ctltest.asm - test program for the toolkit's controls and file dialog
; (bank $20)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; One window with one of each control: buttons, a check box, radio buttons,
; a text field, a list, a scroll bar, labels. The line at the bottom says
; what the last event was; Open... and Save... show the file dialog.
;
;   from the desktop: double-click CTLTEST
;   by hand: the toolkit (DESKTOP.TXT's L lines), L CTLTEST E000 20,
;   D020: 20, E000R
;=============================================================================

        .include "tk.inc"

TOOL    = $CC88                 ; far-call entry 16: the toolkit

.macro  TK fn
        lda #fn
        jsr TOOL
.endmacro

A0      = $80                   ; this program's zero page
A1      = $82
A2      = $84

        .org $E000

        jmp start               ; $E000
        .byte "TK"              ; $E003: a toolkit program (for the desktop)
start:
        TK TK_INIT
        LDW r0, menus
        TK TK_MENUBAR
        LDW r0, 30              ; the window
        LDW r1, 40
        LDW r2, 610
        LDW r3, 360
        LDW r4, s_title
        TK TK_OPENWIN
        stx win
        lda #0                  ; the controls, from the table
        sta A1
@c:     ldy A1
        lda ctls,y
        beq @done
        pha
        ldx #0
@r:     iny                     ; r0-r5 from the table
        lda ctls,y
        sta r0,x
        inx
        cpx #12
        bne @r
        iny
        sty A1
        pla
        tay
        ldx win
        TK TK_NEWCTL
        jmp @c
@done:  ldx #5                  ; the field gets the keys
        TK TK_FOCUS

; --- the event loop ----------------------------------------------------------
loop:   TK TK_GETEVENT
        cmp #EV_CONTROL
        bne @n1
        jsr control
        jmp loop
@n1:    cmp #EV_MENU
        bne @n2
        cpx #0                  ; mini6502 / About CTLTEST...
        bne quit                ; File / Quit
        LDW r0, s_about
        LDW r1, 0
        TK TK_ALERT
        jmp loop
@n2:    cmp #EV_CLOSE
        beq quit
        cmp #EV_KEY
        bne loop
        cpx #27                 ; Esc: quit too
        bne loop
quit:   TK TK_EXIT
        rts

; --- a control did something: X = control, Y = what, r0 = its value -----------
control:
        stx A0                  ; "Control n: what w, value v"
        sty A0+1
        MOVW A1, r0
        ldy #0
        ldx #0
@t:     lda s_ctl,x
        beq @t2
        sta msg,y
        iny
        inx
        bne @t
@t2:    lda A0
        jsr num8
        ldx #0
@w:     lda s_what,x
        beq @w2
        sta msg,y
        iny
        inx
        bne @w
@w2:    lda A0+1
        jsr num8
        ldx #0
@v:     lda s_value,x
        beq @v2
        sta msg,y
        iny
        inx
        bne @v
@v2:    MOVW T0, A1
        jsr num16
        lda #0
        sta msg,y
        lda A0                  ; the scroll bar: its value shown as well
        cmp #7
        bne @nsb
        jsr showval
@nsb:   lda A0
        cmp #9                  ; Open... / Save...
        beq @open
        cmp #10
        beq @save
        cmp #11                 ; Disable / enable the list
        beq @dis
        cmp #0                  ; Beep
        bne @show
        lda #1
        sta BEEP
@show:  jmp status
@open:  ldy #0
        LDW r0, s_openp
        jmp @dlg
@save:  ldy #1
        LDW r0, s_savep
@dlg:   LDW r1, fname
        LDW r2, 0
        TK TK_FILEDIALOG
        bcs @cancel
        ldy #0
@c1:    lda s_chosen,y
        beq @c2
        sta msg,y
        iny
        bne @c1
@c2:    ldx #0
@c3:    lda fname,x
        sta msg,y
        beq status
        iny
        inx
        bne @c3
@cancel:
        ldy #0
@c4:    lda s_cancel,y
        sta msg,y
        beq status
        iny
        bne @c4
@dis:   lda listoff
        eor #1
        sta listoff
        eor #1                  ; Y = 1 enabled, 0 disabled
        tay
        ldx #6
        TK TK_ENABLECTL
        jmp status

; the bottom line shows msg again
status: LDW r0, msg
        ldx #12
        TK TK_SETDATA
        rts

; the scroll bar's value -> label 8
showval:
        ldy #0
@t:     lda s_sb,y
        beq @n
        sta vtext,y
        iny
        bne @t
@n:     MOVW T0, A1
        tya
        pha
        ldy #0
        jsr num16v
        pla
        rts

; A -> msg,y in decimal (Y moves on)
num8:   sta T0
        lda #0
        sta T0+1
; T0 -> msg,y in decimal
num16:  ldx #0
@d:     jsr div10               ; digits, last first, on the stack
        pha
        inx
        lda T0
        ora T0+1
        bne @d
@o:     pla
        sta msg,y
        iny
        dex
        bne @o
        rts
; T0 -> the label's text after "Scroll bar: "
num16v: ldx #0
@d:     jsr div10
        pha
        inx
        lda T0
        ora T0+1
        bne @d
        ldy #12
@o:     pla
        sta vtext,y
        iny
        dex
        bne @o
        lda #0
        sta vtext,y
        LDW r0, vtext
        ldx #8
        TK TK_SETDATA
        rts
; T0 = T0 / 10, A = the remainder as a digit
div10:  lda #16
        sta A2
        lda #0
@l:     asl T0
        rol T0+1
        rol
        cmp #10
        bcc @n
        sbc #10
        inc T0
@n:     dec A2
        bne @l
        ora #'0'
        rts

; --- data --------------------------------------------------------------------------
; kind, then r0-r5 (12 bytes): x0, y0, x1, y1, r4, r5
.macro  CTL k, x0, y0, x1, y1, p4, p5
        .byte k
        .word x0, y0, x1, y1, p4, p5
.endmacro
ctls:   CTL CK_BUTTON,  16,  16,  96,  36, s_beep, 0            ; 0
        CTL CK_CHECK,   16,  50, 180,  66, s_check, 0           ; 1
        CTL CK_RADIO,   16,  76, 180,  92, s_small, 1           ; 2
        CTL CK_RADIO,   16,  96, 180, 112, s_medium, 1          ; 3
        CTL CK_RADIO,   16, 116, 180, 132, s_large, 1           ; 4
        CTL CK_FIELD,   16, 150, 260, 170, fieldbuf, 30         ; 5
        CTL CK_LIST,   300,  16, 480, 146, items, 12            ; 6
        CTL CK_SCROLL, 500,  16, 516, 146, 10, 100              ; 7
        CTL CK_LABEL,  300, 156, 560, 172, vtext, 0             ; 8
        CTL CK_BUTTON,  16, 200, 116, 220, s_open, 0            ; 9
        CTL CK_BUTTON, 130, 200, 230, 220, s_save, 0            ; 10
        CTL CK_BUTTON, 244, 200, 380, 220, s_disable, 0         ; 11
        CTL CK_LABEL,   16, 250, 560, 266, msg, 0               ; 12
        .byte 0

menus:  .byte "mini6502", 0       ; (the toolkit adds the accessories)
        .byte "About CTLTEST...", 0
        .byte 0
        .byte "File", 0
        .byte "Quit/Q", 0
        .byte 0
        .byte 0
s_about: .byte "CTLTEST", 13, 13
        .byte "One of each of the toolkit's controls,", 13
        .byte "and the file dialog.", 13, 13
        .byte "(C) 2026 Benoit Colson - GNU GPL 3", 13
        .byte "With the help of Claude AI.", 0
s_title: .byte "Controls", 0
s_beep:  .byte "Beep", 0
s_check: .byte "Sound on", 0
s_small: .byte "Small", 0
s_medium: .byte "Medium", 0
s_large: .byte "Large", 0
s_open:  .byte "Open...", 0
s_save:  .byte "Save...", 0
s_disable: .byte "List on/off", 0
items:  .byte "Apple", 0, "Banana", 0, "Cherry", 0, "Date", 0, "Elderberry", 0
        .byte "Fig", 0, "Grape", 0, "Kiwi", 0, "Lemon", 0, "Mango", 0
        .byte "Orange", 0, "Pear", 0
s_ctl:   .byte "Control ", 0
s_what:  .byte ": what ", 0
s_value: .byte ", value ", 0
s_sb:    .byte "Scroll bar: ", 0
s_chosen: .byte "File: ", 0
s_cancel: .byte "Cancelled", 0
s_openp: .byte "Open which file?", 0
s_savep: .byte "Save as:", 0
win:     .byte 0
listoff: .byte 0
fieldbuf: .byte "Type here", 0
        .res 22
fname:  .byte "UNTITLED.TXT", 0
        .res 30
vtext:  .byte "Scroll bar: 0", 0
        .res 8
msg:    .byte "Click something", 0
        .res 50
