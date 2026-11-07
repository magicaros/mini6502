;=============================================================================
; tk.inc - mini6502 desktop toolkit: shared definitions (both toolkit banks)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; See README.txt for the programming interface.
;=============================================================================

        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

TKBANK1 = $10           ; dispatcher, windows, events
TKBANK2 = $11           ; menus, dialogs
TKBANK3 = $17           ; controls: functions, drawing
TKBANK4 = $18           ; controls: clicks, keys
TKBANK5 = $19           ; the file dialog
TKDIRBANK = $1A         ; the file dialog's directory
ACCBANK = $1B           ; the desk accessories (desktop/acc.asm)
SWAPBANK = $D0          ; the caller's RAM ($0000-$CBFF) while the desktop runs

; --- function numbers (A when calling TOOL = $CC88) --------------------------
TK_INIT     = 0
TK_EXIT     = 1
TK_MENUBAR  = 2
TK_MENUITEM = 3
TK_OPENWIN  = 4
TK_CLOSEWIN = 5
TK_GETEVENT = 6
TK_POLLEVENT = 7
TK_SETPORT  = 8
TK_ALERT    = 9
TK_ASK      = 10
TK_TEXT     = 11
TK_INVAL    = 12
TK_FRONT    = 13
TK_CLEAR    = 14
TK_SETTITLE = 15
TK_DESKEVENTS = 16
TK_INVALRECT = 17
TK_NEWCTL   = 18
TK_DISPOSECTL = 19
TK_SETVALUE = 20
TK_GETVALUE = 21
TK_ENABLECTL = 22
TK_SETDATA  = 23
TK_FILEDIALOG = 24
TK_FOCUS    = 25
TK_ACCESSORY = 26
TK_LAST     = 26

; --- control kinds (Y for NEWCTL) ---------------------------------------------------
CK_BUTTON   = 1         ; r4 = label; EV_CONTROL when clicked
CK_CHECK    = 2         ; r4 = label; value 0 / 1, flips when clicked
CK_RADIO    = 3         ; r4 = label, r5 = group; the one clicked: 1, the rest 0
CK_SCROLL   = 4         ; vertical; r4 = page step, r5 = maximum; value 0..max
CK_FIELD    = 5         ; r4 = your buffer, r5 = maximum length (1-60)
CK_LIST     = 6         ; r4 = items (strings, each ending with 0), r5 = count
CK_LABEL    = 7         ; r4 = text

; --- events (A after GETEVENT / POLLEVENT) ---------------------------------------
EV_NONE   = 0
EV_KEY    = 1           ; X = character (0: Y = KBDEXT code)
EV_MENU   = 2           ; X = menu, Y = item
EV_CLICK  = 3           ; X = window ($FF desktop), Y = buttons (+$80 double), r0/r1 = x/y
EV_UPDATE = 4           ; X = window: draw its contents (clip already set)
EV_CLOSE  = 5           ; X = window: its close box was clicked
EV_WHEEL  = 6           ; X = front window ($FF none), Y = steps (signed)
EV_CONTROL = 7          ; X = control, Y = what (1 changed / clicked, 13 Enter,
                        ; $81 double click in a list), r0 = its value

; --- hardware ------------------------------------------------------------------------

R_SET   = 0
R_XOR   = 3
R_INV   = 4
S_BOLD  = 1
S_UNDER = 2
S_INV   = 8
S_OPAQUE = 16

; --- zero page -----------------------------------------------------------------------
r0      = $02           ; r0-r15: arguments and results, 2 bytes each
r1      = $04
r2      = $06
r3      = $08
r4      = $0A
r5      = $0C
RX0     = $22           ; the rectangle the drawing helpers use
RY0     = $24
RX1     = $26
RY1     = $28
DX0     = $2A           ; damage rectangle (redraw pass)
DY0     = $2C
DX1     = $2E
DY1     = $30
TP      = $32           ; text pointer
QP      = $34           ; second pointer
T0      = $36           ; temporaries
T1      = $38
T2      = $3A
T3      = $3C
WP      = $3E           ; pointer to a window record
CBANK   = $40           ; the caller's bank (set by the dispatcher)
EVX     = $41           ; event being returned: X, Y
EVY     = $42
TMPB    = $43
TMPC    = $44
MX      = $46           ; mouse position, 2 bytes each
MY      = $48
NUMW    = $4A           ; number of windows open
FRONTW  = $4B           ; window in front ($FF none)
PASSON  = $4C           ; nonzero: a redraw pass is going on
PEND    = $4D           ; windows still to redraw (bit per window)
UPDW    = $4E           ; window of the UPDATE being drawn ($FF none)
NMENU   = $4F           ; menus in the bar
DAMAGE  = $50           ; nonzero: DX0..DY1 must be redrawn
DESKEV  = $51           ; nonzero: UPDATE events for the desktop (X = $FF)
DESKPEND = $52          ; the desktop's UPDATE is next in this pass

; --- fixed RAM ----------------------------------------------------------------------
WINREC  = $0200         ; 8 window records of 32 bytes
W_USED  = 0             ;  1 if open
W_X0    = 1             ;  outer rectangle (the shadow is 2 more right/down)
W_Y0    = 3
W_X1    = 5
W_Y1    = 7
W_TITLE = 9             ;  title, up to 22 characters + 0
ZORDER  = $0300         ; window numbers, back to front (NUMW of them)
MTL     = $0308         ; menu: title address, low / high (8 + 8)
MTH     = $0310
MFIRST  = $0318         ; menu: first item number (8)
MCOUNT  = $0320         ; menu: number of items (8)
MXL     = $0328         ; menu: title x position, low / high (8 + 8)
MXH     = $0330
MWIDTH  = $0338         ; menu: width of its box in characters (8)
IPL     = $0340         ; item: text address, low / high (64 + 64)
IPH     = $0380
IFLAG   = $03C0         ; item: 1 enabled, 2 separator (64)
IKEY    = $0400         ; item: Ctrl+key shortcut letter, 0 none (64)
MTEXT   = $0480         ; menu texts (384 bytes)
MTEXTEND = $0600        ; then the controls ($0600-$07EA, ctl.inc)
ACCWIN  = $07EC         ; the accessories' windows ($FF: closed), 2
ACCITEM = $07EE         ; menu 0: the item before them ($FF: none)
ACCKEY  = $07EF         ; KEY for an accessory: the character
MAGIC   = $07FE         ; "TK" while a toolkit program runs
STRBUF  = $C000         ; strings copied from the caller (dialogs)
STRBUF2 = $C100
ASKBUF  = $C200

MAXWIN  = 8
MAXMENU = 8
MAXITEM = 64
TITLEH  = 19            ; window title bar: rows y0..y0+18, line at y0+19
MENUH   = 19            ; menu bar: rows 0..18, line at 19

; --- helpers ---------------------------------------------------------------------------
.macro  LDW dst, val            ; dst = 16-bit constant
        lda #<(val)
        sta dst
        lda #>(val)
        sta dst+1
.endmacro
.macro  MOVW dst, src           ; dst = src (16-bit)
        lda src
        sta dst
        lda src+1
        sta dst+1
.endmacro
.macro  ADDW dst, src, val      ; dst = src + constant
        lda src
        clc
        adc #<(val)
        sta dst
        lda src+1
        adc #>(val)
        sta dst+1
.endmacro
.macro  SUBW dst, src, val      ; dst = src - constant
        lda src
        sec
        sbc #<(val)
        sta dst
        lda src+1
        sbc #>(val)
        sta dst+1
.endmacro
.macro  FAR bank, addr          ; call into another bank: returns to whoever
                                ; called the routine this is in (use it as
                                ; the whole body of a routine called by JSR)
        jsr $FFD0
        .byte bank
        .word addr
.endmacro
