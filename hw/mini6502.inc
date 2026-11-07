; mini6502.inc - made by hw/gen.py from hw/mini6502.def: edit that, not this.
; Copyright (C) 2026 Benoit Colson, with the help of Claude AI; GNU GPL 3 or later (COPYING).
; The mini6502's registers, banks, far-call entries and system calls.
; In a program: .include "mini6502.inc" (ca65 -I path/to/hw). Including it
; twice is fine.

.ifndef MINI6502_INC
MINI6502_INC = 1

; registers
SYSCTL      = $D000   ; read/write
FRAME       = $D001   ; read
WARMLO      = $D002   ; read/write
WARMHI      = $D003   ; read/write
CLOCKH      = $D004   ; read
CLOCKM      = $D005   ; read
CLOCKS      = $D006   ; read
IRQEN       = $D007   ; read/write
IRQFLAGS    = $D008   ; read
IRQBANK     = $D009   ; read/write
IRQVEC      = $D00A   ; read/write, 2 bytes
KBD         = $D010   ; read
KBDCR       = $D011   ; read
DSP         = $D012   ; write
DSPCR       = $D013   ; reads 0
KBDPEEK     = $D014   ; read
CURX        = $D015   ; read/write
CURY        = $D016   ; read/write
VCHR        = $D017   ; read/write
VCOL        = $D018   ; read/write
KBDEXT      = $D019   ; read
KEYSEL      = $D01A   ; read/write
KEYHELD     = $D01B   ; read
KEYPOS      = $D01C   ; read/write
POSHELD     = $D01D   ; read
KBDFLAGS    = $D01E   ; read/write
BANK        = $D020   ; read/write
COLOR       = $D021   ; read/write
SND         = $D030   ; read/write, 16 bytes
V1          = $D030   ; read/write, 4 bytes
V2          = $D034   ; read/write, 4 bytes
V3          = $D038   ; read/write, 4 bytes
V4          = $D03C   ; read/write, 4 bytes
SHP         = $D050   ; read/write, 16 bytes
S1          = $D050   ; read/write, 4 bytes
S2          = $D054   ; read/write, 4 bytes
S3          = $D058   ; read/write, 4 bytes
S4          = $D05C   ; read/write, 4 bytes
BEEP        = $D100   ; read/write
DCMD        = $D040   ; read/write
DSTAT       = $D041   ; read/write
DSTART      = $D042   ; read/write, 2 bytes
DEND        = $D044   ; read/write, 2 bytes
DNAME       = $D046   ; read/write, 2 bytes
DNLEN       = $D048   ; read/write
PADR        = $D200   ; read/write, 3 bytes
PDATA       = $D203   ; read/write
PSTEP       = $D204   ; read/write
PBADR       = $D208   ; read/write, 3 bytes
PBDATA      = $D20B   ; read/write
PBSTEP      = $D20C   ; read/write
DMASRC      = $D210   ; read/write, 3 bytes
DMADST      = $D213   ; read/write, 3 bytes
DMALEN      = $D216   ; read/write, 3 bytes
DMACMD      = $D219   ; read/write
DMAFILL     = $D21A   ; read/write
DMASTAT     = $D21B   ; read
VID         = $D300   ; read/write, 64 bytes
MODE        = $D300   ; read/write
SHOW        = $D301   ; read/write
DRAW        = $D302   ; read/write
INTENS      = $D303   ; read/write
MASTER      = $D304   ; read/write
TRANSP      = $D305   ; read/write
INK         = $D306   ; read/write
PAPER       = $D307   ; read/write
PALIDX      = $D308   ; read/write
PALR        = $D309   ; read/write
PALG        = $D30A   ; read/write
PALB        = $D30B   ; read/write
BX0         = $D310   ; read/write
BY0         = $D311   ; read/write
BX1         = $D312   ; read/write
BY1         = $D313   ; read/write
BCOL        = $D314   ; read/write
BDX         = $D315   ; read/write
BDY         = $D316   ; read/write
BSRC        = $D317   ; read/write
BCMD        = $D318   ; read/write
BPIXEL      = $D319   ; read
BX0H        = $D31A   ; read/write
BY0H        = $D31B   ; read/write
BX1H        = $D31C   ; read/write
BY1H        = $D31D   ; read/write
BDXH        = $D31E   ; read/write
BDYH        = $D31F   ; read/write
COLLSS      = $D320   ; read, 4 bytes
COLLBG      = $D324   ; read, 4 bytes
ROP         = $D328   ; read/write
PATON       = $D329   ; read/write
CHR         = $D32A   ; read/write
STYLE       = $D32B   ; read/write
CHOUT       = $D32C   ; read/write
PATTERN     = $D330   ; read/write, 8 bytes
CLIPR       = $D338   ; read/write, 8 bytes
SPR         = $D400   ; read/write, 256 bytes
MOUSEX      = $D500   ; read, 2 bytes
MOUSEY      = $D502   ; read, 2 bytes
BUTTONS     = $D504   ; read
WHEEL       = $D505   ; read
CLICKS      = $D506   ; read
PTR         = $D508   ; read/write
PTRX        = $D509   ; read/write, 2 bytes
PTRY        = $D50B   ; read/write, 2 bytes
HOTX        = $D50D   ; read/write
HOTY        = $D50E   ; read/write
PTRIMG      = $D510   ; read/write, 32 bytes
PTRMASK     = $D530   ; read/write, 32 bytes
MOUSELX     = $D550   ; read
MOUSELY     = $D551   ; read
MOUSECOL    = $D552   ; read
MOUSEROW    = $D553   ; read
; numbers
IRQ_FRAME   = 1
IRQ_KEY     = 2
IRQ_MOUSE   = 4
V_NOTE      = 0
V_VOL       = 1
V_WAVE      = 2
V_DUR       = 3
S_DECAY     = 0
S_SWEEP     = 1
S_PULSE     = 2
S_BEND      = 3
C_CLEAR     = 1
C_PSET      = 2
C_LINE      = 3
C_BOX       = 4
C_BOXF      = 5
C_COPY      = 6
C_COPYT     = 7
C_DIM       = 8
C_UNDIM     = 9
C_STAMP     = $0A
C_CHAR      = $0B
VTAB        = $CC00
VTCOUNT     = $CC02
VTENTRY     = $CC08
VTMAX       = $28
VTNAMES     = $CD48
BANKMAP     = $CF00
FARCALL     = $FFD0
; bank zones (first, last)
Z_BASICEXT  = 0       ; BASIC extensions, "!" commands (basicx/README.txt)
Z_BASICEXT_END= 7
Z_USER      = 8       ; yours: load by hand; never handed out
Z_USER_END  = $0F
Z_SYSTEM    = $10     ; the system's programs
Z_SYSTEM_END= $1F
Z_PROGRAMS  = $20     ; programs (the allocator hands these out)
Z_PROGRAMS_END= $7F
Z_DOCUMENTS = $80     ; documents, songs, data (handed out too)
Z_DOCUMENTS_END= $BF
Z_SWAP      = $C0     ; the fixed RAM's copies while programs swap it
Z_SWAP_END  = $FF
; fixed banks
B_GFX       = 0       ; the BASIC extension GFX: !commands (DESKTOP.TXT loads it)
B_DOS       = 1       ; the BASIC extension DOS: folders and files (DESKTOP.TXT loads it)
B_LULLABY   = 8       ; the lullaby demo (BOOT.TXT loads it)
B_TK1       = $10     ; the toolkit, part 1 (TK1)
B_TK2       = $11     ; the toolkit, part 2 (TK2)
B_MUSIC     = $12     ; the music engine (MUSIC)
B_EDIT      = $13     ; the editor (EDIT)
B_DESK1     = $14     ; the desktop, part 1 (DESK1)
B_DESK2     = $15     ; the desktop, part 2 (DESK2)
B_DESK3     = $16     ; the desktop, part 3: icons (DESK3)
B_TK3       = $17     ; the toolkit, part 3: controls (TK3)
B_TK4       = $18     ; the toolkit, part 4: controls' clicks and keys (TK4)
B_TK5       = $19     ; the toolkit, part 5: the file dialog (TK5)
B_TKDIR     = $1A     ; the file dialog's directory and names
B_ACC       = $1B     ; the desk accessories: clock, calculator (ACC)
B_CLIP      = $1C     ; the clipboard every program shares: its length (2 bytes), then the text
B_LAUNCH    = $20     ; where the desktop loads bank programs
B_DESKSAVE  = $C0     ; the desktop's RAM while a program runs
B_TKSWAP    = $D0     ; the caller's RAM while a toolkit program runs
B_EDITIMG   = $E0     ; the editor's RAM while away
B_EDITWORLD = $F0     ; the caller's RAM while editing
; far-call entries: E_NAME = its address (JSR E_NAME), EN_NAME = its number
E_LULLABY   = $CC08   ; plays the lullaby
EN_LULLABY  = 0
E_EDITNEW   = $CC10   ; the editor, with an empty text
EN_EDITNEW  = 1
E_EDIT      = $CC18   ; the editor, with the text as it was (BASIC: CALL EDIT)
EN_EDIT     = 2
E_TOOLKIT   = $CC88   ; the toolkit: LDA #function, JSR
EN_TOOLKIT  = $10
E_DESKTOP   = $CC90   ; the desktop (BASIC: CALL DESKTOP)
EN_DESKTOP  = $11
E_MUSIC     = $CCD0   ; the music engine: LDA #function, LDX #arg, JSR
EN_MUSIC    = $19
E_MUSICB    = $CCD8   ; the music engine from BASIC (mailbox $CCDE)
EN_MUSICB   = $1A
E_RESUME    = $CC98   ; the desktop: back from a program (G after F1)
EN_RESUME   = $12
E_LAUNCH    = $CCA0   ; the desktop: calls a program, then RESUME
EN_LAUNCH   = $13
E_TARGET    = $CCB0   ; the desktop: the program being started
EN_TARGET   = $15
E_BANKLD    = $CCB8   ; the desktop: disk LOAD into the launch bank
EN_BANKLD   = $16
; bank map owners
OWN_FREE    = 0       ; free
OWN_MAIN    = $FD     ; a main-RAM program (started from the desktop)
OWN_HAND    = $FE     ; loaded by hand (L ... BB in the monitor)
OWN_SYSTEM  = $FF     ; reserved: zones and banks that are never handed out
; system calls in the ROM
BALLOC      = $FFB0   ; A = owner, X = how many banks (next to each other), Y = 0 pr
BFREE       = $FFB3   ; A = bank
BFREEALL    = $FFB6   ; A = owner
BCLAIM      = $FFB9   ; A = owner, X = bank
VFIND       = $FFBC   ; X/Y = address of a name (low, high; up to 8 characters, endi
BOWNER      = $FFBF   ; A = bank

.endif
