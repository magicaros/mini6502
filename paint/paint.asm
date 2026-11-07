;=============================================================================
; paint.asm - PAINT, a black and white paint program for the desktop
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
;
; A toolkit program in the manner of MacPaint: 640 x 400 hires pictures,
; the tools on the left, 16 patterns. Two parts from one source (paint.cfg):
;   PAINT    for a bank ($E000-$EF7F): menus, files, the main loop
;   PAINT2   main RAM $0800-$3FFF: the canvas, the tools (paint2.inc,
;            paint3.inc)
; The picture lives in 8 banks of the documents zone (32,000 bytes, laid out
; exactly as the hires screen: 80 bytes a row, bit 7 = the left pixel), the
; undo copy in 8 more, the copied selection in 8 more. The window shows a
; part of it (the canvas): the tools draw on the screen, and the canvas is
; copied back into the picture after each one (commit).
; Main RAM $4000-$BFFF: loading / saving and the paint bucket's work area.
;=============================================================================

        .include "tk.inc"
        .macpack longbranch

TOOL    = $CC88
.macro  TK fn
        lda #fn
        jsr TOOL
.endmacro

NAMEIN  = $EF80                 ; start at $E006: the picture to open
WORK    = $4000                 ; files ($4000-$BCFF), the bucket's copy
PICSZ   = 32000
PAGE1   = $7D00                 ; VRAM page 1 (scratch: undo swap, moving)
ROWTL   = $A100                 ; the bucket: row addresses in WORK
ROWTH   = $A300
FSTK    = $A600                 ; the bucket's stack of seeds (x, y)
FSTKEND = $BFF0
CR      = 13
IMG0    = 64                    ; the tools' icons: sprite images 64-77
PALW    = 48                    ; the palette's width
MAXCW   = 70                    ; the canvas: 70 bytes (560 pixels) wide,
MAXCH   = 352                   ; 352 rows high at most

; tools
T_SEL   = 0
T_HAND  = 1
T_TEXT  = 2
T_FILL  = 3
T_SPRAY = 4
T_BRUSH = 5
T_PENCIL = 6
T_LINE  = 7
T_ERASE = 8
T_RECT  = 9
T_RECTF = 10
T_OVAL  = 11
T_OVALF = 12
T_ZOOM  = 13
NTOOL   = 14

; zero page ($80-$FF is the program's)
P0      = $80
P1      = $82
P2      = $84
U0      = $86
U1      = $88
U2      = $8A
DS      = $8C                   ; DMA source, destination (3 bytes), length
DD      = $8F
DL      = $92
WIN     = $94
BAR     = $95
TOOL_   = $96                   ; the tool
PAT     = $97                   ; the pattern (0-15)
LW      = $98                   ; the line width (1-4)
DIRTY   = $99
MAINSP  = $9A
PICB    = $9B                   ; banks: the picture, its undo copy, the
UNDB    = $9C                   ; copied selection ($FF: none)
CLPB    = $9D
CX0     = $9E                   ; the window's contents: top left (screen)
CY0     = $A0
CANX    = $A2                   ; the canvas on the screen (CANX: a multiple
CANY    = $A4                   ; of 8), CW bytes x CH rows
CW      = $A6
CH      = $A7                   ; 2 bytes
VX      = $A9                   ; the picture's byte column and row at the
VY      = $AA                   ; canvas' top left (VY: 2 bytes)
PMX      = $AC                   ; the mouse
PMY      = $AE
SX      = $B0                   ; where a drag started
SY      = $B2
LX      = $B4                   ; the mouse before
LY      = $B6
X0      = $B8                   ; a rectangle (screen)
Y0      = $BA
X1      = $BC
Y1      = $BE
TMP     = $C0
TMP2    = $C1
CNT     = $C2
CNT2    = $C3
COLR    = $C4
SEL     = $C5                   ; a selection: SX0..SY1 (screen)
SX0     = $C6
SY0     = $C8
SX1     = $CA
SY1     = $CC
ZOOM    = $CE                   ; FatBits: the picture's ZX, ZY at the top
ZX      = $CF                   ; left
ZY      = $D1
TXON    = $D3                   ; typing text: the caret at TXX, TXY
TXX     = $D4
TXY     = $D6
TXN     = $D8                   ; characters typed on this line
TSTYLE  = $D9
TXL     = $DA                   ; the line's left
RND     = $DC
KCH     = $DE
KEXT    = $DF
N0      = $E0
N1      = $E2
N2      = $E4
RXO     = $E6                   ; ovals: the radii, the centre
RYO     = $E8
CXC     = $E9
CYC     = $EB
TACC    = $ED
TSTEP   = $EF
PDX     = $F1
CDX     = $F3
DYC     = $F5
BS      = $F6                   ; a brush's size, its step
BSTEP   = $F7
CWP     = $F8                   ; the canvas' width in pixels (CW * 8)
SHAPE   = $FA
ACCX    = $FB
ZW      = $FC                   ; FatBits: pixels across, rows
ZH      = $FD
SPIC    = TACC              ; showrect's addresses (3 bytes each; the
SVR     = PDX               ; ovals' variables are free meanwhile)
TC      = $FE                   ; the bucket: the colour filled, its byte
TCB     = $FF

;=============================================================================
; PAINT: the bank part
;=============================================================================
        .segment "BANK"

        jmp start               ; $E000 an empty picture
        .byte "TK"              ; $E003 a toolkit program
        .byte 0
        jmp startfile           ; $E006 the picture named at NAMEIN

start:  lda #0
        sta NAMEIN
startfile:
        tsx
        stx MAINSP
        TK TK_INIT
        lda #<s_part2           ; PAINT2 at $0800 (here, at the top, or in
        ldx #>s_part2           ; /PAINT)
        jsr loadpart
        beq @ok
        lda #<s_part2p
        ldx #>s_part2p
        jsr loadpart
        beq @ok
        LDW r0, s_nopart
        jmp @fail
@ok:    jsr getbanks
        bcc @mem
        LDW r0, s_nomem
@fail:  LDW r1, 0
        TK TK_ALERT
        TK TK_EXIT
        rts
@mem:   jsr lowinit
        jsr clearpic
        LDW r0, menus
        TK TK_MENUBAR
        LDW r0, 7               ; the window (its contents start at x = 8)
        LDW r1, 22
        LDW r2, 637
        LDW r3, 397
        LDW r4, s_untitled
        TK TK_OPENWIN
        stx WIN
        LDW r0, 609             ; the scroll bar, right of the canvas
        LDW r1, 0
        LDW r2, 624
        LDW r3, MAXCH - 1
        LDW r4, 64
        LDW r5, 400 - MAXCH
        ldy #CK_SCROLL
        TK TK_NEWCTL
        stx BAR
        lda #0
        sta FNAME
        sta DIRTY
        jsr settitle
        lda NAMEIN
        beq loop
        ldx #0
@c:     lda NAMEIN,x
        sta NAMEB,x
        beq @l
        inx
        cpx #63
        bne @c
        lda #0
        sta NAMEB,x
@l:     jsr loadname

loop:   TK TK_GETEVENT
        cmp #EV_KEY
        bne @n1
        jsr key
        jmp loop
@n1:    cmp #EV_MENU
        bne @n2
        jsr menu
        jmp loop
@n2:    cmp #EV_UPDATE
        bne @n3
        cpx WIN
        bne loop
        jsr update
        jmp loop
@n3:    cmp #EV_CLICK
        bne @n4
        cpx WIN
        bne @l
        jsr click
@l:     jmp loop
@n4:    cmp #EV_WHEEL
        bne @n5
        cpx WIN
        bne @l
        jsr wheel
        jmp loop
@n5:    cmp #EV_CONTROL
        bne @n6
        cpx BAR
        bne @l
        jsr barmoved
        jmp loop
@n6:    cmp #EV_CLOSE
        bne @l
        cpx WIN
        bne @l
        jmp quit

; Loads the program part named at XA; Z set if it worked
loadpart:
        sta DNAME
        stx DNAME+1
        lda #0
        sta DNLEN
        sta DEND
        sta DEND+1
        lda #1
        sta DCMD
        lda DSTAT
        rts

; The banks: picture, undo, clipboard (8 each, the documents zone; the
; clipboard is left out if there is no room). Carry set: no room.
getbanks:
        lda BANK
        ldx #8
        ldy #1
        jsr BALLOC
        bcs @r
        sta PICB
        lda BANK
        ldx #8
        ldy #1
        jsr BALLOC
        bcs @r
        sta UNDB
        lda BANK
        ldx #8
        ldy #1
        jsr BALLOC
        bcc @c
        lda #$FF
@c:     sta CLPB
        clc
@r:     rts

; --- menus ----------------------------------------------------------------------
menu:   txa
        asl
        asl
        asl
        asl
        sty TMP
        ora TMP
        sta TMP
        ldx #0
@f:     lda mtab,x
        cmp #$FF
        beq @r
        cmp TMP
        beq @go
        inx
        inx
        inx
        bne @f
@go:    lda mtab+2,x
        pha
        lda mtab+1,x
        pha
@r:     rts
mtab:   .byte $00
        .word about-1
        .byte $10
        .word new-1
        .byte $11
        .word open-1
        .byte $13
        .word save-1
        .byte $14
        .word saveas-1
        .byte $16
        .word quit-1
        .byte $20
        .word m_undo-1
        .byte $22
        .word m_cut-1
        .byte $23
        .word m_copy-1
        .byte $24
        .word m_paste-1
        .byte $25
        .word m_clear-1
        .byte $26
        .word m_selall-1
        .byte $28
        .word m_fliph-1
        .byte $29
        .word m_flipv-1
        .byte $2A
        .word m_invert-1
        .byte $30
        .word m_fatbits-1
        .byte $32
        .word m_plain-1
        .byte $33
        .word m_bold-1
        .byte $34
        .word m_italic-1
        .byte $35
        .word m_under-1
        .byte $FF

menus:  .byte "mini6502", 0, "About PAINT...", 0, 0
        .byte "File", 0, "New/N", 0, "Open.../O", 0, "-", 0, "Save/S", 0
        .byte "Save as...", 0, "-", 0, "Quit/Q", 0, 0
        .byte "Edit", 0, "Undo/Z", 0, "-", 0, "Cut/X", 0, "Copy/C", 0
        .byte "Paste/V", 0, "Clear", 0, "Select all/A", 0, "-", 0
        .byte "Flip horizontal", 0, "Flip vertical", 0, "Invert", 0, 0
        .byte "Goodies", 0, "FatBits/B", 0, "-", 0, "Plain text", 0
        .byte "Bold", 0, "Italic", 0, "Underline", 0, 0
        .byte 0

about:  LDW r0, s_about
        LDW r1, 0
        TK TK_ALERT
        rts

; --- files ----------------------------------------------------------------------
new:    jsr askchanges
        bcs @r
        jsr endall
        jsr clearpic
        lda #0
        sta FNAME
        sta DIRTY
        sta VX
        sta VY
        sta VY+1
        sta ZOOM
        jsr settitle
        jmp redraw
@r:     rts

open:   jsr askchanges
        bcs @r
        ldx #0
@c:     lda FNAME,x
        sta NAMEB,x
        beq @d
        inx
        bne @c
@d:     LDW r0, s_openp
        LDW r1, NAMEB
        LDW r2, s_pic
        ldy #0
        TK TK_FILEDIALOG
        bcs @r
        jmp loadname
@r:     rts

; NAMEB -> the picture (an alert if it cannot be)
loadname:
        jsr endall
        lda #<NAMEB
        sta DNAME
        lda #>NAMEB
        sta DNAME+1
        lda #0
        sta DNLEN
        LDW DSTART, WORK
        LDW DEND, $C000
        lda #3
        sta DCMD
        lda DSTAT
        beq @ok
        LDW r0, s_noload
        LDW r1, 0
        TK TK_ALERT
        rts
@ok:    jsr ramtopic            ; WORK -> the picture
        jsr snapshot
        ldx #0
@c:     lda NAMEB,x
        sta FNAME,x
        beq @t
        inx
        bne @c
@t:     lda #0
        sta DIRTY
        sta VX
        sta VY
        sta VY+1
        sta ZOOM
        jsr settitle
        jmp redraw

save:   lda FNAME
        bne savefile
        jmp saveas
savefile:
        jsr pictoram            ; the picture -> WORK
        lda #<FNAME
        sta DNAME
        lda #>FNAME
        sta DNAME+1
        lda #0
        sta DNLEN
        LDW DSTART, WORK
        LDW DEND, WORK + PICSZ
        lda #2
        sta DCMD
        lda DSTAT
        beq @ok
        LDW r0, s_nosave
        LDW r1, 0
        TK TK_ALERT
        sec
        rts
@ok:    lda #0
        sta DIRTY
        jsr settitle
        clc
        rts

saveas: ldx #0
        lda FNAME
        bne @c
@u:     lda s_defname,x
        sta NAMEB,x
        beq @d
        inx
        bne @u
@c:     lda FNAME,x
        sta NAMEB,x
        beq @d
        inx
        bne @c
@d:     LDW r0, s_savep
        LDW r1, NAMEB
        LDW r2, s_pic
        ldy #1
        TK TK_FILEDIALOG
        bcs @r
        ldx #0
@n:     lda NAMEB,x
        sta FNAME,x
        beq @s
        inx
        bne @n
@s:     jmp savefile
@r:     rts

; Unsaved changes? Save, don't, or Cancel (carry set)
askchanges:
        lda DIRTY
        bne @ask
        clc
        rts
@ask:   LDW r0, s_ask
        LDW r1, s_askbtn
        TK TK_ALERT
        cmp #1
        beq @no
        cmp #0
        bne @cancel
        jmp save
@no:    clc
        rts
@cancel:
        sec
        rts

; The window's title: the file's name, * when changed
settitle:
        ldx #0
        ldy #0
        lda FNAME
        bne @c
@u:     lda s_untitled,x
        beq @e
        sta TBUF,y
        inx
        iny
        bne @u
@c:     lda FNAME,x
        beq @e
        sta TBUF,y
        inx
        iny
        cpy #20
        bne @c
@e:     lda DIRTY
        beq @z
        lda #' '
        sta TBUF,y
        iny
        lda #'*'
        sta TBUF,y
        iny
@z:     lda #0
        sta TBUF,y
        LDW r0, TBUF
        ldx WIN
        TK TK_SETTITLE
        rts

quit:   jsr askchanges
        bcs @r
        lda BANK                ; our banks back (the desktop would do it
        jsr BFREEALL            ; too)
        ldx MAINSP
        txs
        TK TK_EXIT
        rts
@r:     rts

; --- texts ----------------------------------------------------------------------
s_part2:  .byte "PAINT2", 0
s_part2p: .byte "/PAINT/PAINT2", 0
s_nopart: .byte "PAINT2 is not on the disk: PAINT needs it.", 0
s_nomem:  .byte "There are not enough free banks for a picture.", 0
s_untitled: .byte "Untitled", 0
s_defname: .byte "PICTURE.PIC", 0
s_pic:    .byte "PIC", 0
s_openp:  .byte "Open which picture?", 0
s_savep:  .byte "Save the picture as:", 0
s_noload: .byte "That picture could not be loaded.", 0
s_nosave: .byte "The picture could not be saved.", 0
s_ask:    .byte "Save the changes to this picture?", 0
s_askbtn: .byte "Save|Don't save|Cancel", 0
s_about:  .byte "PAINT - black and white pictures, 640 x 400", 13, 13
          .byte "Tools on the left, patterns under them, line widths", 13
          .byte "in between. Arrows, the wheel or the hand scroll.", 13
          .byte "FatBits (Ctrl+B) to edit pixel by pixel.", 13, 13
          .byte "(C) 2026 Benoit Colson - GNU GPL 3", 13
          .byte "With the help of Claude AI.", 0

FNAME:  .res 64
NAMEB:  .res 64
TBUF:   .res 32

;=============================================================================
; PAINT2: the main-RAM part
;=============================================================================
        .segment "LOW"
        .include "paint2.inc"
        .include "paint3.inc"
