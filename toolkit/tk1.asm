;=============================================================================
; tk1.asm - mini6502 desktop toolkit, bank $10: dispatcher, windows, events
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Programs call it through far-call entry 16 ($CC88):
;   LDA #function : JSR $CC88   (arguments in X, Y, r0-r5; see README.txt)
;=============================================================================

        .include "tk.inc"
        .include "ctl.inc"

; bank 2's entry points (tk2.asm)
M_SETBAR = $E000
M_ITEM   = $E003
M_TRACK  = $E006
M_KEY    = $E009
D_ALERT  = $E00C
D_ASK    = $E00F

; this bank's own variables (not in the swapped RAM)
EXITBUF = $EFF0         ; 5 bytes of TK_EXIT's stack frame
EXITSP  = $EFF5
LEVEL   = $EFF6         ; INITs not yet EXITed (programs started from others)
SAVEIRQ = $EFF7         ; the caller's IRQEN, when its handler is in its RAM

        .org $E000

; --- dispatcher -------------------------------------------------------------------
dispatch:
        cld
        stx ARGX
        sty ARGY
        pha
        tsx
        lda $0104,x             ; FARCALL left the caller's bank under its
        sta CBANK               ; return address (after our PHA: +4)
        pla
        cmp #TK_LAST + 1
        bcs @bad
        asl
        tax
        lda functab+1,x
        pha
        lda functab,x
        pha
        ldx ARGX
        ldy ARGY
        rts                     ; to the function; its RTS returns to the caller
@bad:   sec
        rts

functab:
        .word f_init-1, f_exit-1, f_menubar-1, f_menuitem-1
        .word f_openwin-1, f_closewin-1, f_getevent-1, f_pollevent-1
        .word f_setport-1, f_alert-1, f_ask-1, f_text-1
        .word f_inval-1, f_front-1, f_clear-1, f_settitle-1
        .word f_deskev-1, f_invalrect-1
        .word c_newctl-1, c_dispose-1, c_setvalue-1, c_getvalue-1
        .word c_enable-1, c_setdata-1, c_filedlg-1, c_focus-1
        .word c_acc-1

ARGX:   .byte 0
ARGY:   .byte 0

; --- INIT: the desktop takes the machine -------------------------------------------
f_init:
        lda LEVEL               ; started from another toolkit program (the
        beq @first              ; toolkit's mark is in the RAM): its RAM is
        lda MAGIC               ; already saved
        cmp #'T'
        bne @first
        lda MAGIC+1
        cmp #'K'
        bne @first
        inc LEVEL
        jmp initscr
@first: lda #1
        sta LEVEL
        lda #0                  ; an interrupt handler in the caller's RAM
        sta SAVEIRQ             ; ($0000-$DFFF) is about to be swapped out:
        lda IRQVEC+1            ; turned off until EXIT (one in a bank keeps
        cmp #$E0                ; running: background music...)
        bcs @irqok
        lda IRQEN
        sta SAVEIRQ
        lda #0
        sta IRQEN
@irqok:
        lda #$00                ; the caller's RAM $0000-$CBFF -> banks $D0-$DC
        sta DMASRC
        sta DMASRC+1
        lda #$FF
        sta DMASRC+2
        lda #$00
        sta DMASRC+3
        lda #(SWAPBANK << 4) & $FF
        sta DMASRC+4
        lda #SWAPBANK >> 4
        sta DMASRC+5
        lda #$00
        sta DMASRC+6
        lda #$CC
        sta DMASRC+7
        lda #0
        sta DMASRC+8
        lda #1
        sta DMACMD
initscr:
        lda CBANK               ; (kept: the clearing below would lose it)
        pha
        ldx #$22                ; toolkit zero page and RAM cleared
        lda #0
@z:     sta 0,x
        inx
        cpx #$80
        bne @z
        tax
@r:     sta WINREC,x
        sta WINREC+$100,x
        inx
        bne @r
        pla
        sta CBANK
        lda #'T'                ; the mark: a toolkit program is running
        sta MAGIC
        lda #'K'
        sta MAGIC+1
        lda #$FF
        sta FRONTW
        sta UPDW
        lda #1
        sta PBSTEP
        lda #3                  ; hires, black on white
        sta MODE
        lda #0
        sta SHOW
        sta DRAW
        sta STYLE
        sta $D306               ; INK black
        lda #15
        sta $D307               ; PAPER white
        jsr clipfull
        jsr patgrey             ; grey desktop over the whole page
        lda #R_SET
        sta ROP
        lda #1
        sta PATON
        lda #C_CLEAR
        sta BCMD
        lda #0
        sta PATON
        jsr menubg
        lda #3                  ; the pointer, following the mouse
        sta PTR
        jsr ctl_reset           ; no controls
        lda #$FF                ; no accessories (and none in the menu)
        sta ACCWIN
        sta ACCWIN+1
        sta ACCITEM
        lda CLICKS              ; forget old clicks and wheel turns
        lda WHEEL
        clc
        rts

; The empty menu bar
menubg: lda #0
        sta RX0
        sta RX0+1
        sta RY0
        sta RY0+1
        sta RY1+1
        LDW RX1, 639
        lda #MENUH - 1
        sta RY1
        lda #0
        jsr fillrect
        lda #MENUH
        sta RY0
        sta RY1
        lda #1
        jmp fillrect

; --- EXIT: everything back as before INIT; returns to the caller ----------------
f_exit:
        lda LEVEL               ; inside another toolkit program: back to it
        cmp #2                  ; (it draws its screen again: CLEAR...)
        bcc @last
        dec LEVEL
        clc
        rts
@last:  lda #0
        sta LEVEL
        tsx                     ; our return frame (FARCALL's return, bank,
        stx EXITSP              ; the caller's return): kept in this bank
        ldy #0
@s:     lda $0101,x
        sta EXITBUF,y
        inx
        iny
        cpy #5
        bne @s
        lda #0
        sta PTR
        sta MODE
        sta ROP
        sta PATON
        sta STYLE
        jsr clipfull
        lda #(SWAPBANK << 4) & $FF   ; banks $D0-$DC -> $0000-$CBFF
        sta DMASRC+1
        lda #SWAPBANK >> 4
        sta DMASRC+2
        lda #0
        sta DMASRC
        sta DMASRC+3
        sta DMASRC+4
        sta DMASRC+6
        sta DMASRC+8
        lda #$FF
        sta DMASRC+5
        lda #$CC
        sta DMASRC+7
        lda #1
        sta DMACMD
        lda IRQVEC+1            ; a handler in the RAM: the caller's again
        cmp #$E0                ; (or one left by a program: off)
        bcs @irqok
        lda SAVEIRQ
        sta IRQEN
@irqok: ldx EXITSP              ; our frame back on the (restored) stack
        ldy #0
@b:     lda EXITBUF,y
        sta $0101,x
        inx
        iny
        cpy #5
        bne @b
        ldx EXITSP
        txs
        clc
        rts

; --- CLEAR: as INIT, for the outermost program after one it started -------
f_clear:
        lda #1
        sta LEVEL
        jmp initscr

; --- SETTITLE: window X's title = r0 -------------------------------------------------
f_settitle:
        cpx #MAXWIN
        bcs @r
        stx TMPB
        jsr winptr
        MOVW T0, r0
        lda WP
        clc
        adc #W_TITLE
        sta QP
        lda WP+1
        adc #0
        sta QP+1
        lda #22
        jsr fetchstr
        ldx TMPB
        jsr wintitle
        jsr adddamage
@r:     clc
        rts

; --- DESKEVENTS: r0 = 1: UPDATEs (X = $FF) for the desktop too ----------------
f_deskev:
        lda r0
        and #1
        sta DESKEV
        beq @r
        lda #0                  ; the whole desktop gets one now
        sta RX0
        sta RX0+1
        sta RY0+1
        lda #MENUH + 1
        sta RY0
        LDW RX1, 639
        LDW RY1, 399
        jsr adddamage
@r:     clc
        rts

; --- INVALRECT: r0-r3 (a rectangle of the screen) will be redrawn ------------
f_invalrect:
        ldx #7
@c:     lda r0,x
        sta RX0,x
        dex
        bpl @c
        jsr adddamage
        clc
        rts

; --- in bank 2 ------------------------------------------------------------------------
; (FARCALL returns to whoever called the code it is in, so each one is a
; routine of its own, called with JSR)
f_menubar:
        FAR TKBANK2, M_SETBAR
f_menuitem:
        FAR TKBANK2, M_ITEM
f_alert:
        FAR TKBANK2, D_ALERT
f_ask:
        FAR TKBANK2, D_ASK
far_key:
        FAR TKBANK2, M_KEY
far_track:
        FAR TKBANK2, M_TRACK

; --- controls (banks $17-$19) ------------------------------------------------------
c_newctl:   FAR TKBANK3, $E000
c_dispose:  FAR TKBANK3, $E003
c_setvalue: FAR TKBANK3, $E006
c_getvalue: FAR TKBANK3, $E009
c_enable:   FAR TKBANK3, $E00C
c_setdata:  FAR TKBANK3, $E00F
c_filedlg:  FAR TKBANK5, T5_FILEDLG
c_focus:    FAR TKBANK4, T4_FOCUS
ctl_reset:  FAR TKBANK3, T3_RESET
ctl_drawwin: FAR TKBANK3, T3_DRAWWIN
ctl_freewin: FAR TKBANK3, T3_FREEWIN
ctl_click:  FAR TKBANK4, T4_CLICK
ctl_key:    FAR TKBANK4, T4_KEY
ctl_idle:   FAR TKBANK4, T4_IDLE
ctl_wheel:  FAR TKBANK4, T4_WHEEL

; --- desk accessories (bank $1B) ---------------------------------------------------
; ACCESSORY: X = accessory (0 clock, 1 calculator): opened; $FF: the ones
; left open. Only once the menu bar has them (MENUBAR found their bank).
c_acc:  lda ACCITEM
        cmp #$FF
        bne acc_open
        sec
        rts
acc_open:  FAR ACCBANK, $E000
acc_event: FAR ACCBANK, $E003
acc_idle:  FAR ACCBANK, $E006

; X = one of the accessories' windows? carry clear if so (A, Y kept)
accwin: cpx #MAXWIN
        bcs @no
        cpx ACCWIN
        beq @yes
        cpx ACCWIN+1
        beq @yes
@no:    sec
        rts
@yes:   clc
        rts

; --- TEXT: the caller's string r0 at X0,Y0 ---------------------------------------
f_text:
        MOVW T0, r0
        jsr farptr
@l:     lda PBDATA
        beq @e
        sta CHOUT
        bne @l
@e:     clc
        rts

; --- windows ----------------------------------------------------------------------------

; WP = record of window X
; OPEN: r0-r3 rectangle, r4 title -> X = window, carry set if none free
f_openwin:
        ldx #0
@f:     jsr winptr
        ldy #W_USED
        lda (WP),y
        beq @free
        inx
        cpx #MAXWIN
        bne @f
        sec
        rts
@free:  stx TMPB
        lda #1
        sta (WP),y
        ldy #W_X0               ; the rectangle (y kept 20 or more below the
@c:     lda r0-W_X0,y           ; menu bar)
        sta (WP),y
        iny
        cpy #W_Y1+2
        bne @c
        ldy #W_Y0+1
        lda (WP),y
        bne @tt
        dey
        lda (WP),y
        cmp #MENUH + 1
        bcs @tt
        lda #MENUH + 1
        sta (WP),y
@tt:    MOVW T0, r4             ; the title: up to 22 characters
        lda WP
        clc
        adc #W_TITLE
        sta QP
        lda WP+1
        adc #0
        sta QP+1
        lda #22
        jsr fetchstr
        ldx NUMW                ; in front
        lda TMPB
        sta ZORDER,x
        inc NUMW
        ldx TMPB
        jsr activate            ; the old front loses its stripes
        ldx TMPB
        sec
        jsr winrect
        jsr adddamage
        ldx TMPB
        clc
        rts

; FRONTW = window X (the top of ZORDER); the title bar of the window that
; was in front is damaged (drawn again without stripes)
activate:
        stx TMPC
        ldx FRONTW
        bmi @n
        cpx TMPC
        beq @n
        jsr wintitle
        jsr adddamage
@n:     ldx NUMW
        beq @none
        lda ZORDER-1,x
        sta FRONTW
        rts
@none:  lda #$FF
        sta FRONTW
        rts

; Index of window X in ZORDER -> Y
zfind:  ldy #0
@l:     txa
        cmp ZORDER,y
        beq @e
        iny
        cpy NUMW
        bne @l
@e:     rts

; Removes window X from ZORDER
zremove:
        jsr zfind
@m:     lda ZORDER+1,y
        sta ZORDER,y
        iny
        cpy NUMW
        bne @m
        dec NUMW
        rts

; CLOSE: window X
f_closewin:
        cpx #MAXWIN
        bcs @bad
        stx TMPB
        jsr winptr
        ldy #W_USED
        lda (WP),y
        beq @bad
        lda #0
        sta (WP),y
        lda TMPB                ; its controls go with it
        pha
        tax
        jsr ctl_freewin
        pla
        sta TMPB
        tax
        sec
        jsr winrect
        jsr adddamage
        ldx TMPB
        jsr zremove
        lda PEND                ; no update for it any more
        jsr bitclr
        sta PEND
        lda #$FF                ; the next window in front gets its stripes
        sta FRONTW
        ldx NUMW
        beq @ok
        lda ZORDER-1,x
        sta FRONTW
        tax
        jsr wintitle
        jsr adddamage
@ok:    clc
        rts
@bad:   sec
        rts

; A AND NOT (1 << TMPB)
bitclr: ldx TMPB
        pha
        lda bits,x
        eor #$FF
        sta TMPC
        pla
        and TMPC
        rts
bits:   .byte 1, 2, 4, 8, 16, 32, 64, 128

; FRONT: brings window X to the front (X = 8 or more: just asks);
; returns X = the window in front ($FF if none)
f_front:
        cpx #MAXWIN
        bcs @r
        cpx FRONTW
        beq @r
        stx TMPB
        jsr zremove
        ldx NUMW
        lda TMPB
        sta ZORDER,x
        inc NUMW
        tax
        jsr activate
        ldx TMPB
        sec
        jsr winrect
        jsr adddamage
@r:     ldx FRONTW              ; X = the window in front ($FF none)
        clc
        rts

; INVAL: window X's contents will get an UPDATE
f_inval:
        cpx #MAXWIN
        bcs @r
        jsr wincontent
        jsr adddamage
@r:     clc
        rts

; SETPORT: clip = window X's contents (within the damage during its
; UPDATE); r0-r3 = its contents rectangle
f_setport:
        stx TMPB
        jsr wincontent
        ldx #7
@c:     lda RX0,x
        sta r0,x
        dex
        bpl @c
        lda PASSON
        beq @set
        lda TMPB
        cmp UPDW
        bne @set
        jsr isectd
@set:   jsr clipset
        clc
        rts

; RX0..RY1 = RX0..RY1 within DX0..DY1 (may become empty: nothing drawn)
isectd: ldx #0
        jsr @max
        ldx #2
        jsr @max
        ldx #4
        jsr @min
        ldx #6
@min:   lda DX0,x               ; R <= D ? keep
        cmp RX0,x
        lda DX0+1,x
        sbc RX0+1,x
        bcs @k
        bcc @take
@max:   lda RX0,x               ; R >= D ? keep
        cmp DX0,x
        lda RX0+1,x
        sbc DX0+1,x
        bcs @k
@take:  lda DX0,x
        sta RX0,x
        lda DX0+1,x
        sta RX0+1,x
@k:     rts

; Carry set if RX0..RY1 and DX0..DY1 overlap
overlap:
        lda DX1                 ; R.x0 <= D.x1
        cmp RX0
        lda DX1+1
        sbc RX0+1
        bcc @no
        lda RX1                 ; D.x0 <= R.x1
        cmp DX0
        lda RX1+1
        sbc DX0+1
        bcc @no
        lda DY1
        cmp RY0
        lda DY1+1
        sbc RY0+1
        bcc @no
        lda RY1
        cmp DY0
        lda RY1+1
        sbc DY0+1
@no:    rts

; Draws window X's frame and empties its contents (through the clip)
drawframe:
        stx TMPB
        sec                     ; shadow
        jsr winrect
        ADDW RX0, RX0, 2
        ADDW RY0, RY0, 2
        lda #1
        jsr fillrect
        ldx TMPB                ; body and frame
        clc
        jsr winrect
        lda #0
        jsr fillrect
        jsr framerect
        ADDW RY0, RY0, TITLEH   ; the line under the title
        MOVW RY1, RY0
        lda #1
        jsr fillrect
        ldx TMPB
        cpx FRONTW
        bne @title
        clc                     ; in front: stripes and a close box
        jsr winrect
        ADDW RX0, RX0, 2
        ADDW RY0, RY0, 3
        SUBW RX1, RX1, 2
        ADDW RY1, RY0, TITLEH - 6
        jsr patstripe
        jsr patrect
        jsr patgrey
        ldx TMPB
        jsr closebox
        lda #0
        jsr fillrect
        jsr framerect
@title: ldx TMPB                ; the title, centred, on a white background
        clc
        jsr winrect
        lda WP
        clc
        adc #W_TITLE
        sta TP
        lda WP+1
        adc #0
        sta TP+1
        jsr strlen
        clc
        adc #2
        jsr centrex
        ADDW T1, RY0, 2
        jsr moveto
        lda #S_OPAQUE
        sta STYLE
        lda #R_SET
        sta ROP
        lda #' '
        sta CHOUT
        jsr drawstr
        lda #' '
        sta CHOUT
        lda #0
        sta STYLE
        rts

; RX0..RY1 = close box of window X
closebox:
        clc
        jsr winrect
        ADDW RX0, RX0, 8
        ADDW RY0, RY0, 4
        ADDW RX1, RX0, 10
        ADDW RY1, RY0, 10
        rts

; --- events -----------------------------------------------------------------------------

f_getevent:
@l:     jsr poll
        cmp #EV_NONE            ; (the flags follow A, not X)
        bne @r
        jsr waitframe
        jmp @l
@r:     rts

f_pollevent:
        jsr poll
        cmp #EV_NONE
        rts

; One event -> A (and X, Y, r0-r3); 0 = none. The desk accessories' events
; are handled here and never reach the program.
poll:   jsr poll0
        cmp #EV_NONE
        bne @ev
        lda ACCWIN              ; nothing: the clock ticks
        and ACCWIN+1
        bmi @none
        jsr acc_idle
@none:  lda #EV_NONE
        rts
@ev:    cmp #EV_MENU            ; one of their items in the first menu?
        bne @k
        cpx #0
        bne @r
        cpy ACCITEM
        bcc @r
        beq @r
        tya
        clc                     ; X = item - ACCITEM - 1
        sbc ACCITEM
        tax
        jsr acc_open
        jmp @none
@k:     cmp #EV_KEY             ; a key while one is in front
        bne @w
        stx ACCKEY
        ldx FRONTW
        jsr accwin
        ldx ACCKEY
        bcs @r
        ldx FRONTW
        bcc @give
@w:     cmp #EV_CLICK           ; UPDATE, CLICK, CLOSE, WHEEL of their
        bcc @r                  ; windows (X = the window)
        cmp #EV_WHEEL + 1
        bcs @r
        jsr accwin
        bcs @r
@give:  jsr acc_event
        jmp @none
@r:     rts

poll0:
        jsr readmouse
        ldx UPDW                ; the window just updated: its controls, over
        cpx #MAXWIN             ; what the program drew
        bcs @noctl
        jsr f_setport
        ldx UPDW
        jsr ctl_drawwin
        lda #$FF
        sta UPDW
@noctl: jsr ctl_idle            ; a scroll arrow held down
        cmp #EV_NONE
        beq @noidle
        rts
@noidle:
        lda DAMAGE
        beq @nodmg
        jsr startpass
@nodmg: lda PASSON
        beq @input
        jsr nextupdate
        bcc @input
        lda #EV_UPDATE
        rts
@input: lda KBDCR               ; a key?
        bpl @mouse
        lda KBD
        and #$7F
        bne @char
        ldy KBDEXT
        jsr @ctlkey
        bcc @r
        ldx #0
        ldy KEXT
        lda #EV_KEY
@r:     rts
@char:  cmp #27
        bcs @key
        jsr far_key             ; Ctrl+letter: a menu shortcut? (A kept if not)
        bcc @key
        lda #EV_MENU
        rts
@key:   jsr @ctlkey
        bcc @r
        ldx KCH
        lda #EV_KEY
        rts
@ctlkey:                        ; for a field or list in the front window?
        ldx FRONTW
        bpl @ck
        sta KCH
        sty KEXT
        sec
        rts
@ck:    jmp ctl_key
@mouse: lda CLICKS
        sta TMPC
        and #1
        bne @left
        lda TMPC
        and #2
        bne @right
        lda WHEEL
        beq @none
        tay
        ldx FRONTW
        bmi @wh
        jsr ctl_wheel           ; a list with the focus scrolls
        bcc @whr
        ldy KEXT
        ldx FRONTW
@wh:    lda #EV_WHEEL
@whr:   rts
@none:  lda #EV_NONE
        rts
@right: lda #2
        jmp click
@left:  lda MY+1                ; in the menu bar?
        bne @win
        lda MY
        cmp #MENUH + 1
        bcs @win
        jsr far_track
        bcc @none
        lda #EV_MENU
        rts
@win:   jsr findwin
        bmi @desk
        cpx FRONTW
        beq @front
        stx TMPB                ; a window behind: comes to the front, and
        jsr wintitle            ; can be dragged by its title at once
        jsr inrect
        php
        ldx TMPB
        jsr f_front
        plp
        bcc @none
        ldx TMPB
        jmp drag
@front: stx TMPB
        jsr closebox
        jsr inrect
        bcc @t
        ldx TMPB
        lda #EV_CLOSE
        rts
@t:     ldx TMPB
        jsr wintitle
        jsr inrect
        bcc @c
        ldx TMPB
        jmp drag
@c:     ldx TMPB                ; on one of its controls?
        jsr ctl_click
        bcc @cr
        lda #1
        jmp click
@cr:    rts
@desk:  lda #1
        jmp click

; A click with buttons A at MX,MY: in a window's contents (r0/r1 relative to
; them) or on the desktop (X = $FF, r0/r1 = the screen position)
click:  sta EVY
        jsr findwin
        stx EVX
        bmi @desk
        jsr wincontent
        jsr inrect
        bcc @no                 ; on the frame: nothing
        lda MX
        sec
        sbc RX0
        sta r0
        lda MX+1
        sbc RX0+1
        sta r0+1
        lda MY
        sec
        sbc RY0
        sta r1
        lda MY+1
        sbc RY0+1
        sta r1+1
        jmp @ev
@desk:  MOVW r0, MX
        MOVW r1, MY
@ev:    lda EVY                 ; a double click: the left button twice in the
        cmp #1                  ; same window within 24 frames -> Y = $81
        bne @single
        lda FRAME
        sec
        sbc LASTCF
        cmp #24
        bcs @single
        lda EVX
        cmp LASTCW
        bne @single
        lda #$81
        sta EVY
        lda #$FE                ; (a third click starts again)
        sta LASTCW
        bne @ev2
@single:
        lda FRAME
        sta LASTCF
        lda EVX
        sta LASTCW
@ev2:   ldx EVX
        ldy EVY
        lda #EV_CLICK
        rts
@no:    lda #EV_NONE
        rts

; X = the window under MX,MY (front first), $FF (N set) if none
findwin:
        ldy NUMW
@l:     dey
        bmi @none
        sty TMPC
        ldx ZORDER,y
        clc
        jsr winrect
        jsr inrect
        ldy TMPC
        bcc @l
        ldx ZORDER,y
        rts
@none:  ldx #$FF
        rts

; A redraw pass: the desktop in the damage, then (one UPDATE each) the
; windows that overlap it, back to front
startpass:
        lda #0
        sta DAMAGE
        lda DY0+1               ; never above the desktop
        bne @ok
        lda DY0
        cmp #MENUH + 1
        bcs @ok
        lda #MENUH + 1
        sta DY0
@ok:    lda DX1+1               ; nor past the screen
        cmp #>640
        bcc @x
        lda DX1
        cmp #<640
        bcc @x
        LDW DX1, 639
@x:     lda DY1+1
        cmp #>400
        bcc @y
        lda DY1
        cmp #<400
        bcc @y
        LDW DY1, 399
@y:     ldx #7
@c:     lda DX0,x
        sta RX0,x
        dex
        bpl @c
        jsr clipset
        jsr patgrey
        jsr patrect
        lda #0                  ; which windows overlap it
        sta PEND
        ldy #0
@w:     cpy NUMW
        beq @done
        sty TMPC
        ldx ZORDER,y
        stx TMPB
        sec
        jsr winrect
        jsr overlap
        bcc @next
        ldx TMPB
        lda PEND
        ora bits,x
        sta PEND
@next:  ldy TMPC
        iny
        bne @w
@done:  lda DESKEV              ; the desktop itself first, if asked for
        sta DESKPEND
        lda #1
        sta PASSON
        rts

; Next window of the pass (back first): frame drawn, clip = its contents
; within the damage, r0-r3 = its contents. Carry clear when the pass is over.
nextupdate:
        lda DESKPEND            ; the desktop: X = $FF, r0-r3 = the damage
        beq @wins               ; (the clip is already set to it)
        lda #0
        sta DESKPEND
        ldx #7
@d:     lda DX0,x
        sta r0,x
        dex
        bpl @d
        ldx #$FF
        stx UPDW
        sec
        rts
@wins:
        ldy #0
@l:     cpy NUMW
        beq @over
        ldx ZORDER,y
        lda PEND
        and bits,x
        bne @this
        iny
        bne @l
@over:  lda #0
        sta PASSON
        lda #$FF
        sta UPDW
        jsr clipfull
        clc
        rts
@this:  stx UPDW
        stx TMPB
        lda PEND
        jsr bitclr
        sta PEND
        ldx #7                  ; the frame, within the damage
@c:     lda DX0,x
        sta RX0,x
        dex
        bpl @c
        jsr clipset
        ldx UPDW
        jsr drawframe
        ldx UPDW
        jsr f_setport
        ldx UPDW
        sec
        rts

; --- dragging a window by its title ----------------------------------------------------
drag:
        stx DRAGW
        clc
        jsr winrect
        ldx #7                  ; original rectangle
@o:     lda RX0,x
        sta OX0,x
        sta NX0,x
        dex
        bpl @o
        MOVW SX, MX
        MOVW SY, MY
        jsr clipfull
        jsr xorframe
@loop:  jsr waitframe
        jsr readmouse
        lda BUTTONS
        and #1
        beq @up
        jsr newpos
        lda NX0                 ; moved?
        cmp RX0
        bne @mv
        lda NX0+1
        cmp RX0+1
        bne @mv
        lda NY0
        cmp RY0
        bne @mv
        lda NY0+1
        cmp RY0+1
        beq @loop
@mv:    jsr xorframe            ; rub out the old outline
        jsr newrect
        jsr xorframe
        jmp @loop
@up:    jsr xorframe            ; released: rub it out
        lda CLICKS              ; (the release is not a click)
        lda NX0                 ; not moved: done
        cmp OX0
        bne @move
        lda NX0+1
        cmp OX0+1
        bne @move
        lda NY0
        cmp OY0
        bne @move
        lda NY0+1
        cmp OY0+1
        bne @move
        lda #EV_NONE
        rts
@move:  ldx DRAGW               ; old place damaged, new place too
        sec
        jsr winrect
        jsr adddamage
        ldx DRAGW
        jsr winptr
        ldy #W_X0
@n:     lda NX0-W_X0,y
        sta (WP),y
        iny
        cpy #W_Y1+2
        bne @n
        ldx DRAGW
        sec
        jsr winrect
        jsr adddamage
        lda #EV_NONE
        rts

; NX0..NY1 = the original rectangle moved by the mouse, kept on the screen
newpos:
        lda MX                  ; NX0 = OX0 + MX - SX
        sec
        sbc SX
        sta T0
        lda MX+1
        sbc SX+1
        sta T0+1
        lda OX0
        clc
        adc T0
        sta NX0
        lda OX0+1
        adc T0+1
        sta NX0+1
        bpl @x1
        lda #0                  ; not left of 0
        sta NX0
        sta NX0+1
@x1:    lda OX1                 ; width
        sec
        sbc OX0
        sta T1
        lda OX1+1
        sbc OX0+1
        sta T1+1
        lda #<639               ; T2 = 639 - width: rightmost NX0
        sec
        sbc T1
        sta T2
        lda #>639
        sbc T1+1
        sta T2+1
        lda T2                  ; NX0 > T2 ? NX0 = T2
        cmp NX0
        lda T2+1
        sbc NX0+1
        bcs @x2
        MOVW NX0, T2
@x2:    lda NX0
        clc
        adc T1
        sta NX1
        lda NX0+1
        adc T1+1
        sta NX1+1
        lda MY                  ; the same down: NY0 = OY0 + MY - SY
        sec
        sbc SY
        sta T0
        lda MY+1
        sbc SY+1
        sta T0+1
        lda OY0
        clc
        adc T0
        sta NY0
        lda OY0+1
        adc T0+1
        sta NY0+1
        bmi @top
        bne @y1
        lda NY0
        cmp #MENUH + 1
        bcs @y1
@top:   LDW NY0, MENUH + 1      ; not over the menu bar
@y1:    lda OY1
        sec
        sbc OY0
        sta T1
        lda OY1+1
        sbc OY0+1
        sta T1+1
        lda #<399
        sec
        sbc T1
        sta T2
        lda #>399
        sbc T1+1
        sta T2+1
        lda T2
        cmp NY0
        lda T2+1
        sbc NY0+1
        bcs @y2
        MOVW NY0, T2
@y2:    lda NY0
        clc
        adc T1
        sta NY1
        lda NY0+1
        adc T1+1
        sta NY1+1
        rts

; RX0..RY1 = NX0..NY1
newrect:
        ldx #7
@c:     lda NX0,x
        sta RX0,x
        dex
        bpl @c
        rts

; The outline RX0..RY1 in XOR
xorframe:
        lda #R_XOR
        sta ROP
        lda #0
        sta PATON
        lda #1
        sta BCOL
        jsr setrect
        lda #C_BOX
        sta BCMD
        lda #R_SET
        sta ROP
        rts

        .include "common.inc"
        .include "win.inc"

; --- this bank's variables ------------------------------------------------------------
DRAGW:  .res 1
OX0:    .res 2
OY0:    .res 2
OX1:    .res 2
OY1:    .res 2
NX0:    .res 2
NY0:    .res 2
NX1:    .res 2
NY1:    .res 2
SX:     .res 2
SY:     .res 2
LASTCF: .res 1
LASTCW: .res 1
