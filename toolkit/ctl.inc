;=============================================================================
; ctl.inc - controls: their records and shared variables (fixed RAM), for
; toolkit banks 3, 4 and 5
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
;=============================================================================

MAXCTL  = 16            ; controls for programs (0-15)
MAXALL  = 20            ; + 4 for the file dialog (16-19)
DLGWIN  = $FE           ; the "window" of the file dialog's controls
F_OFF   = 1             ; C_FLAGS: disabled
F_SEL   = 2             ; C_FLAGS: a field's text is selected (shown
                        ; inverted): the first key replaces it

; records: one array of MAXALL bytes per field, in the toolkit's fixed RAM
CTLMEM  = $0600
C_KIND  = CTLMEM + 0 * MAXALL   ; 0 = free
C_WIN   = CTLMEM + 1 * MAXALL
C_FLAGS = CTLMEM + 2 * MAXALL
C_X0L   = CTLMEM + 3 * MAXALL   ; rectangle in the window's contents
C_X0H   = CTLMEM + 4 * MAXALL
C_Y0L   = CTLMEM + 5 * MAXALL
C_Y0H   = CTLMEM + 6 * MAXALL
C_X1L   = CTLMEM + 7 * MAXALL
C_X1H   = CTLMEM + 8 * MAXALL
C_Y1L   = CTLMEM + 9 * MAXALL
C_Y1H   = CTLMEM + 10 * MAXALL
C_VALL  = CTLMEM + 11 * MAXALL  ; value
C_VALH  = CTLMEM + 12 * MAXALL
C_MAXL  = CTLMEM + 13 * MAXALL  ; maximum / count / length
C_MAXH  = CTLMEM + 14 * MAXALL
C_TOP   = CTLMEM + 15 * MAXALL  ; a list's top row
C_PTRL  = CTLMEM + 16 * MAXALL  ; text / buffer / items, in bank C_BANK
C_PTRH  = CTLMEM + 17 * MAXALL
C_BANK  = CTLMEM + 18 * MAXALL
C_AUX   = CTLMEM + 19 * MAXALL  ; scroll bar: page step; radio: group
CV      = CTLMEM + 20 * MAXALL  ; ($0790) the shared variables:
CI      = CV + 0                ; the control being worked on
CJ      = CV + 1
KWIN    = CV + 2
KKIND   = CV + 3
KCH     = CV + 4
KEXT    = CV + 5
FOCUS   = CV + 6                ; the field or list that gets the keys
REPCTL  = CV + 7                ; scroll arrow / page held: the control
REPPART = CV + 8
REPT    = CV + 9
LASTC   = CV + 10               ; list double clicks
LASTR   = CV + 11
LASTF   = CV + 12
PRESSED = CV + 13               ; a button being held
RGC     = CV + 14
RGX     = CV + 15
ROWS    = CV + 16
SHOWSB  = CV + 17
SBP     = CV + 18
OXW     = CV + 19               ; 2-byte ones from here
OYW     = CV + 21
TXR     = CV + 23
SBX0    = CV + 25
SBY0    = CV + 27
SBY1    = CV + 29
SBV     = CV + 31
SBM     = CV + 33
TRL     = CV + 35
THY     = CV + 37
OLDV    = CV + 39
OLDV2   = CV + 41
LX0     = CV + 43
LY0     = CV + 45
LX1     = CV + 47
LY1     = CV + 49
MA      = CV + 51
MB      = CV + 53
MD      = CV + 55
REM     = CV + 57
DLGOX   = CV + 59
DLGOY   = CV + 61
PR      = CV + 63               ; 4 bytes
SAVCLIP = CV + 67               ; 8 bytes
SAVCLIP2 = CV + 75
SAVR    = CV + 83               ; 8 bytes; ends at CV + 91 ($07EB)
.assert SAVR + 8 <= MAGIC, error, "the control variables reach MAGIC"

; TK3 ($17) entries
T3_RESET  = $E012
T3_DRAWWIN = $E015
T3_FREEWIN = $E018
T3_SHOW   = $E01B
T3_RADIO  = $E01E
T3_INIT   = $E021
T3_DRAW   = $E024
T3_FORGET = $E027
; TK4 ($18) entries
T4_FOCUS  = $E000
T4_CLICK  = $E003
T4_KEY    = $E006
T4_IDLE   = $E009
T4_WHEEL  = $E00C
T4_SETFOCUS = $E00F
; TK5 ($19) entry
T5_FILEDLG = $E000
