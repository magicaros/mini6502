;=============================================================================
; tracker.asm - TRACKER, the desktop's music tracker (a toolkit program)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
;
; Writes songs for the music engine (bank $12, see music/README.txt). Two
; parts from one source (tracker.cfg):
;   TRACKER   for a bank ($E000-$EF7F): menus, files, the dialogs
;   TRACKER2  main RAM $0800-$1FFF: the song, the screen, the keys, playing
; Main RAM while it runs:
;   $2000 instruments (32 x 8)   $2100 the order list (255 x 3)
;   $2400 the title              $3000 patterns 0-63, 256 bytes each
;   $7000-$BFFF the .MUS image built for playing and saving
;=============================================================================

        .include "tk.inc"
        .macpack longbranch

TOOL    = $CC88
.macro  TK fn
        lda #fn
        jsr TOOL
.endmacro

INSTR   = $2000                 ; 32 instruments, 8 bytes: DECAY VOL WAVE
                                ; SWEEP PULSE DUR VIB 0
ORD     = $2100                 ; orders, 3 bytes: the voices' patterns
TITLE   = $2400                 ; 41 bytes
PAT     = $3000                 ; pattern P at PAT + P * 256 (64 rows x 4)
IMG     = $7000                 ; the image (.MUS without its load address)
BLK     = $2500                 ; the copied block: a voice per 256 bytes
LBUF    = $2800                 ; a screen line, its inverted characters
LINV    = $2850
CELLB   = $28A0                 ; typing a cell
CELL4   = $28B0
USED    = $28C0                 ; patterns in use (64)
OLDROW  = $2900
IMGEND  = $C000
MAXPAT  = 64
MAXORD  = 255
NAMEIN  = $EF80                 ; start at $E006: the song to open
VIS     = 19                    ; grid lines shown
GLINE   = 2                     ; the first grid line on the screen
CR      = 13

; zero page
P0      = $80
P1      = $82
P2      = $84
T16     = $86
ORGX    = $88
ORGY    = $8A
CURORD  = $8C                   ; the order shown
CROW    = $8D                   ; the cursor: row, field (voice * 6 + f)
CX      = $8E
TOPR    = $8F                   ; the first row shown
OCT     = $90                   ; octave for the piano keys
CINS    = $91                   ; instrument for new notes (1-32)
DIRTY   = $92
WIN     = $93
SPEED   = $94
NORD    = $95
LOOP    = $96
ROWS    = $97
PLAYING = $98                   ; 0 no, 1 song, 2 pattern
POFF    = $99                   ; the image's first order
PROW    = $9A                   ; the row playing ($FF none)
SBANK   = $9B                   ; the banks the song plays from ($FF none)
TMP     = $9C
TMP2    = $9D
CH      = $9E
EXT     = $9F
CTRL    = $A0
LCOL    = $A1                   ; LBUF: where the next character goes
CNT     = $A2
MAINSP  = $A3
VOICE   = $A4
FIELD   = $A5
NPAT    = $A6
NO      = $A7                   ; the image: orders, first order
FO      = $A8
DLGW    = $A9                   ; a dialog's window
DLGDONE = $AA
INUM    = $AB                   ; the instrument in the dialog
NUM     = $AC                   ; 2 bytes
DLN     = $AE                   ; drawall's line
GV      = $AF                   ; the voice being drawn
DLINE   = $B0                   ; the line being drawn
CT      = $B1                   ; 2 bytes
DIVC    = $B3
OTOP    = $B4
SELON   = $B5                   ; a block is selected: from AROW / AVC to
AROW    = $B6                   ; the cursor
AVC     = $B7
SELDRT  = $B8                   ; the grid must be drawn again
SR0     = $B9                   ; the block: rows SR0-SR1, voices SV0-SV1
SR1     = $BA
SV0     = $BB
SV1     = $BC
BR      = $BD
BV      = $BE
BAR     = $BF                   ; the scroll bar, what it shows
BARM    = $C0
BARV    = $C1
DLIM    = $C2
XL      = $C3                   ; the mouse, from the text's top left
YL      = $C5
MROW    = $C7                   ; mcell: the row, voice, field there
MV      = $C8
MF      = $C9
MLINE   = $CA
SHIFT   = $CB
VT      = $CC
BJ      = $CD                   ; 2 bytes
TDIR    = $CF
BLKR    = $D0                   ; the copied block: rows, voices
BLKV    = $D1
TV0     = $D2

;=============================================================================
; TRACKER: the bank part
;=============================================================================
        .segment "BANK"

        jmp start               ; $E000 an empty song
        .byte "TK"              ; $E003 a toolkit program
        .byte 0
        jmp startfile           ; $E006 the song named at NAMEIN

start:  lda #0
        sta NAMEIN
startfile:
        tsx
        stx MAINSP
        TK TK_INIT
        lda #<s_part2           ; TRACKER2 at $0800 (here, at the top, or
        ldx #>s_part2           ; in /TRACKER)
        jsr loadpart
        beq @ok
        lda #<s_part2p
        ldx #>s_part2p
        jsr loadpart
        beq @ok
        LDW r0, s_nopart
        LDW r1, 0
        TK TK_ALERT
        TK TK_EXIT
        rts
@ok:    jsr songnew
        jsr playinit
        LDW r0, menus
        TK TK_MENUBAR
        LDW r0, 2
        LDW r1, 22
        LDW r2, 637
        LDW r3, 397
        LDW r4, s_untitled
        TK TK_OPENWIN
        stx WIN
        LDW r0, 617             ; the scroll bar, beside the grid
        LDW r1, 34
        LDW r2, 632
        LDW r3, 337
        LDW r4, VIS - 1
        LDW r5, 32 - VIS
        ldy #CK_SCROLL
        TK TK_NEWCTL
        stx BAR
        lda #32 - VIS
        sta BARM
        lda #0
        sta BARV
        sta SELON
        sta BLKR
        sta FNAME
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

loop:   TK TK_POLLEVENT
        bne @ev
        jsr follow              ; nothing: the playing row followed
        lda FRAME
@w:     cmp FRAME
        beq @w
        jmp loop
@ev:    cmp #EV_KEY
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
        jsr orgset
        jsr drawall
        jmp loop
@n3:    cmp #EV_CLICK
        bne @n4
        cpx WIN
        bne loop
        jsr click
        jmp loop
@n4:    cmp #EV_WHEEL
        bne @n5
        cpx WIN
        bne @l
        jsr wheel
@l:     jmp loop
@n5:    cmp #EV_CONTROL
        bne @n6
        cpx BAR
        bne @l
        lda r0
        sta BARV
        jsr setview
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
        .word m_cut-1
        .byte $21
        .word m_copy-1
        .byte $22
        .word m_paste-1
        .byte $23
        .word m_clear-1
        .byte $24
        .word m_selall-1
        .byte $26
        .word m_tup-1
        .byte $27
        .word m_tdown-1
        .byte $29
        .word m_insrow-1
        .byte $2A
        .word m_delrow-1
        .byte $30
        .word settings-1
        .byte $32
        .word m_insord-1
        .byte $33
        .word m_dupord-1
        .byte $34
        .word m_delord-1
        .byte $35
        .word m_newpat-1
        .byte $40
        .word instdlg-1
        .byte $41
        .word m_nextins-1
        .byte $42
        .word m_previns-1
        .byte $50
        .word m_playsong-1
        .byte $51
        .word m_playhere-1
        .byte $52
        .word m_playpat-1
        .byte $53
        .word m_stop-1
        .byte $FF

menus:  .byte "mini6502", 0, "About TRACKER...", 0, 0
        .byte "File", 0, "New/N", 0, "Open.../O", 0, "-", 0, "Save/S", 0
        .byte "Save as...", 0, "-", 0, "Quit/Q", 0, 0
        .byte "Edit", 0, "Cut/X", 0, "Copy/C", 0, "Paste/V", 0, "Clear", 0
        .byte "Select all/A", 0, "-", 0, "Transpose +1/U", 0
        .byte "Transpose -1/B", 0, "-", 0, "Insert row", 0, "Delete row", 0, 0
        .byte "Song", 0, "Settings.../G", 0, "-", 0, "Insert order", 0
        .byte "Duplicate order/D", 0, "Delete order", 0, "New pattern/W", 0, 0
        .byte "Instrument", 0, "Edit.../E", 0, "Next/K", 0, "Previous/L", 0, 0
        .byte "Play", 0, "Song/P", 0, "From this order/R", 0, "Pattern/T", 0
        .byte "Stop/Y", 0, 0
        .byte 0

about:  LDW r0, s_about
        LDW r1, 0
        TK TK_ALERT
        rts

; --- files ------------------------------------------------------------------------
new:    jsr askchanges
        bcs @r
        jsr stop
        jsr songnew
        lda #0
        sta FNAME
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
        LDW r2, s_mus
        ldy #0
        TK TK_FILEDIALOG
        bcs @r
        jmp loadname
@r:     rts

; NAMEB -> the song (an alert if it is not one)
loadname:
        jsr stop
        lda #<NAMEB
        sta DNAME
        lda #>NAMEB
        sta DNAME+1
        lda #0
        sta DNLEN
        LDW DSTART, IMG
        LDW DEND, IMGEND
        lda #3
        sta DCMD
        lda DSTAT
        bne @bad
        jsr unpack              ; the image -> the song (carry: not a song)
        bcs @bad
        ldx #0
@c:     lda NAMEB,x
        sta FNAME,x
        beq @t
        inx
        bne @c
@t:     jsr settitle
        jmp redraw
@bad:   jsr songnew
        LDW r0, s_noload
        LDW r1, 0
        TK TK_ALERT
        jmp redraw

save:   lda FNAME
        bne savefile
        jmp saveas
savefile:
        lda #0                  ; the whole song
        jsr build
        lda #<FNAME
        sta DNAME
        lda #>FNAME
        sta DNAME+1
        lda #0
        sta DNLEN
        LDW DSTART, IMG
        lda P2                  ; (build: P2 = the end)
        sta DEND
        lda P2+1
        sta DEND+1
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
        LDW r2, s_mus
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
        jsr stop
        ldx MAINSP
        txs
        TK TK_EXIT
        rts
@r:     rts

; --- dialogs: their window, a loop until OK / Cancel -------------------------------
; Opens a dialog window: r0-r3, r4 = title
dlgopen:
        TK TK_OPENWIN
        stx DLGW
        lda #0
        sta DLGDONE
        rts
; X = control: a number field (r0-r3 = where, buffer at DA..)
; The dialog's events until DLGDONE: 1 OK, 2 Cancel. Controls 0..: the
; caller's DLGCTL routine (XA) is called with X = control
dlgrun: sta DLGJ+1
        stx DLGJ+2
@l:     TK TK_GETEVENT
        cmp #EV_UPDATE
        bne @n1
        cpx DLGW
        beq @dlg
        cpx WIN
        bne @l
        jsr orgset
        jsr drawall
        jmp @l
@dlg:   jsr DLGTXT
        jmp @l
@n1:    cmp #EV_CONTROL
        bne @n2
        jsr DLGJ
        lda DLGDONE
        beq @l
        bne @end
@n2:    cmp #EV_CLOSE
        bne @l
        cpx DLGW
        bne @l
        lda #2
        sta DLGDONE
@end:   ldx DLGW
        TK TK_CLOSEWIN
        rts
DLGJ:   jmp $0000               ; (set by dlgrun)
DLGTXT: jmp (DLGTV)             ; the dialog's texts (its UPDATE)
DLGTV:  .word 0

; Texts at the places in a table (x, y: words, then the string's address),
; ending with 0 0
dtexts: stx P2
        sty P2+1
@l:     ldy #0
        lda (P2),y
        iny
        ora (P2),y
        beq @r
        ldy #0
        lda r0                  ; x = the contents' left + x
        clc
        adc (P2),y
        sta BX0
        iny
        lda r0+1
        adc (P2),y
        sta BX0H
        iny
        lda r1
        clc
        adc (P2),y
        sta BY0
        iny
        lda r1+1
        adc (P2),y
        sta BY0H
        iny
        lda (P2),y
        sta P1
        iny
        lda (P2),y
        sta P1+1
        lda #0
        sta STYLE
        sta ROP
        ldy #0
@c:     lda (P1),y
        beq @n
        sta CHOUT
        iny
        bne @c
@n:     lda P2
        clc
        adc #6
        sta P2
        bcc @l
        inc P2+1
        bne @l
@r:     rts

; --- the instrument dialog ---------------------------------------------------------
; controls: 0-3 waves (radio), 4-10 number fields, 11 Test, 12 Prev,
; 13 Next, 14 OK
instdlg:
        lda CINS
        sta INUM
        LDW r0, 150
        LDW r1, 50
        LDW r2, 490
        LDW r3, 345
        LDW r4, s_insttl
        jsr dlgopen
        LDW DLGTV, idtexts
        ldx #0                  ; the controls, from the table
@c:     stx CNT
        txa
        asl
        asl
        asl
        tax
        ldy #0
@r:     lda ictls,x
        sta r0,y
        inx
        iny
        cpy #8
        bne @r
        lda CNT                 ; r4: radio labels / field buffers / labels
        asl
        tax
        lda ictl4,x
        sta r4
        lda ictl4+1,x
        sta r4+1
        ldx CNT
        lda ictlk,x
        tay
        lda #1                  ; r5: radio group 1; field length 4
        cpy #CK_FIELD
        bne @g
        lda #4
@g:     sta r5
        lda #0
        sta r5+1
        ldx DLGW
        TK TK_NEWCTL
        ldx CNT
        inx
        cpx #15
        bne @c
        jsr ishow               ; the instrument's values in them
        ldx #4
        TK TK_FOCUS
        lda #<idctl
        ldx #>idctl
        jsr dlgrun
        lda DLGDONE
        cmp #1
        bne @r2
        jsr istore
@r2:    jsr changed
        jmp redraw

; A control did something in the instrument dialog
idctl:  cpx #11
        bcc @f
        bne @n12
        jsr istore              ; Test: its note, now
        lda INUM
        sta TMP2
        lda #60
        jmp preview
@n12:   cpx #12
        bne @n13
        jsr istore              ; Prev
        dec INUM
        bne @sh
        lda #32
        sta INUM
@sh:    jsr ishow
        jmp ititle
@n13:   cpx #13
        bne @ok
        jsr istore              ; Next
        inc INUM
        lda INUM
        cmp #33
        bcc @sh
        lda #1
        sta INUM
        bne @sh
@ok:    lda #1                  ; OK
        sta DLGDONE
        rts
@f:     cpy #13                 ; Enter in a field: OK too
        beq @ok
        rts

; The dialog's title: "Instrument NN"
ititle: ldx #0
@c:     lda s_insttl,x
        sta TBUF,x
        beq @n
        inx
        bne @c
@n:     dex
        dex
        lda INUM
        jsr hexto
        LDW r0, TBUF
        ldx DLGW
        TK TK_SETTITLE
        rts
; A as 2 hex digits at TBUF,X (X moves on)
hexto:  pha
        lsr
        lsr
        lsr
        lsr
        jsr @d
        pla
        and #$0F
@d:     cmp #10
        bcc @n
        adc #6
@n:     adc #'0'
        sta TBUF,x
        inx
        rts

; instrument INUM -> the dialog's controls
ishow:  jsr ititle
        lda INUM
        jsr insptr              ; P0 = the instrument
        ldy #2                  ; wave: its radio on
        lda (P0),y
        and #3
        tax
        LDW r0, 1
        TK TK_SETVALUE
        ldx #0                  ; the fields: the bytes in fieldmap order
@f:     stx CNT
        ldy fieldmap,x
        lda (P0),y
        sta NUM
        lda #0
        sta NUM+1
        cpy #3                  ; sweep is signed
        bne @u
        lda NUM
        bpl @u
        dec NUM+1
@u:     ldx CNT
        cpx #5                  ; vibrato: speed (hi nibble), depth (lo)
        bcc @w
        lda NUM
        beq @w
        cpx #5
        bne @dp
        lsr NUM
        lsr NUM
        lsr NUM
        lsr NUM
        jmp @w
@dp:    lda NUM
        and #$0F
        sta NUM
@w:     ldx CNT
        jsr fieldbuf            ; P1 = its buffer
        jsr numstr              ; NUM -> (P1)
        ldx CNT
        txa
        clc
        adc #4
        tax
        stx TMP
        lda P1
        sta r0
        lda P1+1
        sta r0+1
        LDW r1, 4
        TK TK_SETDATA
        ldx CNT
        inx
        cpx #7
        bne @f
        rts

; the dialog's controls -> instrument INUM
istore: lda INUM
        jsr insptr
        ldx #0                  ; the wave: the radio that is on
@w:     stx CNT
        TK TK_GETVALUE
        lda r0
        bne @wv
        ldx CNT
        inx
        cpx #4
        bne @w
        ldx #0
        stx CNT
@wv:    lda CNT
        ldy #2
        sta (P0),y
        ldx #0
@f:     stx CNT
        jsr fieldbuf
        jsr strnum              ; (P1) -> NUM (signed, decimal)
        ldx CNT
        ldy fieldmap,x
        lda NUM
        cpx #0                  ; volume, pulse: 0-15
        beq @15
        cpx #4
        beq @15
        cpx #5
        bcs @vib
        jmp @st
@15:    cmp #16
        bcc @st
        lda #15
        bne @st
@vib:   and #$0F                ; vibrato: speed, depth into one byte
        sta TMP
        ldy #6
        lda (P0),y
        cpx #5
        bne @dep
        and #$0F
        sta TMP2
        lda TMP
        asl
        asl
        asl
        asl
        ora TMP2
        jmp @st
@dep:   and #$F0
        ora TMP
@st:    sta (P0),y
        ldx CNT
        inx
        cpx #7
        bne @f
        rts

; P1 = the buffer of number field X (0-6)
fieldbuf:
        txa
        asl
        asl
        clc
        adc #<FBUFS
        sta P1
        lda #>FBUFS
        adc #0
        sta P1+1
        rts

; the fields: decay?? -> bytes: vol(1) dur(5) decay(0) sweep(3) pulse(4)
; vib speed, vib depth (6)
fieldmap: .byte 1, 5, 0, 3, 4, 6, 6

DLX     = 16
ictls:  .word DLX, 6, DLX + 70, 22              ; 0-3 waves
        .word DLX + 76, 6, DLX + 166, 22
        .word DLX + 174, 6, DLX + 230, 22
        .word DLX + 238, 6, DLX + 300, 22
        .word 236, 34, 286, 54                  ; 4-10 fields
        .word 236, 58, 286, 78
        .word 236, 82, 286, 102
        .word 236, 106, 286, 126
        .word 236, 130, 286, 150
        .word 236, 154, 286, 174
        .word 236, 178, 286, 198
        .word DLX, 222, DLX + 64, 242           ; 11-14 buttons
        .word DLX + 76, 222, DLX + 140, 242
        .word DLX + 152, 222, DLX + 216, 242
        .word DLX + 236, 222, DLX + 300, 242
ictl4:  .word s_sq, s_tri, s_saw, s_noise
        .word FBUFS, FBUFS + 4, FBUFS + 8, FBUFS + 12
        .word FBUFS + 16, FBUFS + 20, FBUFS + 24
        .word s_test, s_prev, s_next, s_ok
ictlk:  .byte CK_RADIO, CK_RADIO, CK_RADIO, CK_RADIO
        .byte CK_FIELD, CK_FIELD, CK_FIELD, CK_FIELD, CK_FIELD, CK_FIELD
        .byte CK_FIELD, CK_BUTTON, CK_BUTTON, CK_BUTTON, CK_BUTTON
idtexts:
        ldx #<idtab
        ldy #>idtab
        jmp dtexts
idtab:  .word DLX, 36, s_l1
        .word DLX, 60, s_l2
        .word DLX, 84, s_l3
        .word DLX, 108, s_l4
        .word DLX, 132, s_l5
        .word DLX, 156, s_l6
        .word DLX, 180, s_l7
        .word 0, 0
s_l1:   .byte "Volume (0-15)", 0
s_l2:   .byte "Duration (frames, 0 held)", 0
s_l3:   .byte "Decay (0-255)", 0
s_l4:   .byte "Sweep (-128..127)", 0
s_l5:   .byte "Pulse width (0-15)", 0
s_l6:   .byte "Vibrato speed (0-15)", 0
s_l7:   .byte "Vibrato depth (0-15)", 0
s_sq:   .byte "Square", 0
s_tri:  .byte "Triangle", 0
s_saw:  .byte "Saw", 0
s_noise: .byte "Noise", 0
s_test: .byte "Test", 0
s_prev: .byte "Prev", 0
s_next: .byte "Next", 0
s_ok:   .byte "OK", 0
s_cancel: .byte "Cancel", 0
s_insttl: .byte "Instrument 01", 0

; --- the song's settings -----------------------------------------------------------
; controls: 0 title, 1 speed, 2 rows, 3 loop, 4 OK, 5 Cancel
settings:
        LDW r0, 140
        LDW r1, 90
        LDW r2, 500
        LDW r3, 300
        LDW r4, s_settl
        jsr dlgopen
        LDW DLGTV, sdtexts
        ldx #0                  ; title -> TBUF2
@t:     lda TITLE,x
        sta TBUF2,x
        beq @td
        inx
        cpx #40
        bne @t
@td:    lda SPEED               ; numbers -> their buffers
        sta NUM
        lda #0
        sta NUM+1
        ldx #0
        jsr fieldbuf
        jsr numstr
        lda ROWS
        sta NUM
        ldx #1
        jsr fieldbuf
        jsr numstr
        ldx #2                  ; loop: hex, empty = none
        jsr fieldbuf
        ldy #0
        lda LOOP
        cmp #$FF
        beq @nl
        ldx #0
        jsr hexto
        lda TBUF
        sta (P1),y
        iny
        lda TBUF+1
        sta (P1),y
        iny
@nl:    lda #0
        sta (P1),y
        ldx #0
@c:     stx CNT
        txa
        asl
        asl
        asl
        tax
        ldy #0
@r:     lda sctls,x
        sta r0,y
        inx
        iny
        cpy #8
        bne @r
        lda CNT
        asl
        tax
        lda sctl4,x
        sta r4
        lda sctl4+1,x
        sta r4+1
        ldx CNT
        lda sctl5,x
        sta r5
        lda #0
        sta r5+1
        lda sctlk,x
        tay
        ldx DLGW
        TK TK_NEWCTL
        ldx CNT
        inx
        cpx #6
        bne @c
        ldx #0
        TK TK_FOCUS
        lda #<sdctl
        ldx #>sdctl
        jsr dlgrun
        lda DLGDONE
        cmp #1
        bne @r2
        ldx #0                  ; OK: store them
@ts:    lda TBUF2,x
        sta TITLE,x
        beq @sp
        inx
        cpx #40
        bne @ts
        lda #0
        sta TITLE,x
@sp:    ldx #0
        jsr fieldbuf
        jsr strnum
        lda NUM
        beq @rw
        sta SPEED
@rw:    ldx #1
        jsr fieldbuf
        jsr strnum
        lda NUM
        beq @lp
        cmp #65
        bcs @lp
        sta ROWS
@lp:    ldx #2
        jsr fieldbuf
        jsr strhex
        sta LOOP
        cmp #$FF
        beq @fix
        cmp NORD
        bcc @fix
        lda #0
        sta LOOP
@fix:   jsr fixcursor
        jsr changed
@r2:    jmp redraw

sdctl:  cpx #5
        beq @cancel
        cpx #4
        beq @ok
        cpy #13                 ; Enter in a field
        bne @r
@ok:    lda #1
        bne @s
@cancel:
        lda #2
@s:     sta DLGDONE
@r:     rts

sdtexts:
        ldx #<sdtab
        ldy #>sdtab
        jmp dtexts
sdtab:  .word 12, 12, s_s1
        .word 12, 58, s_s2
        .word 12, 82, s_s3
        .word 12, 106, s_s4
        .word 0, 0
s_s1:   .byte "Title:", 0
s_s2:   .byte "Speed (frames a row)", 0
s_s3:   .byte "Rows (1-64)", 0
s_s4:   .byte "Loop to order (hex, empty: stop)", 0
s_settl: .byte "Song", 0
sctls:  .word 12, 30, 346, 50
        .word 200, 54, 250, 74
        .word 200, 78, 250, 98
        .word 280, 102, 330, 122
        .word 170, 150, 250, 170
        .word 262, 150, 342, 170
sctl4:  .word TBUF2, FBUFS, FBUFS + 4, FBUFS + 8, s_ok, s_cancel
sctl5:  .byte 40, 4, 4, 3, 0, 0
sctlk:  .byte CK_FIELD, CK_FIELD, CK_FIELD, CK_FIELD, CK_BUTTON, CK_BUTTON

; --- texts -------------------------------------------------------------------------
s_part2:  .byte "TRACKER2", 0
s_part2p: .byte "/TRACKER/TRACKER2", 0
s_nopart: .byte "TRACKER2 is not on the disk: TRACKER needs it.", 0
s_untitled: .byte "Untitled", 0
s_defname: .byte "SONG.MUS", 0
s_mus:    .byte "MUS", 0
s_openp:  .byte "Open which song?", 0
s_savep:  .byte "Save the song as:", 0
s_noload: .byte "That file is not a song (or it is too big).", 0
s_nosave: .byte "The song could not be saved.", 0
s_ask:    .byte "Save the changes to this song?", 0
s_askbtn: .byte "Save|Don't save|Cancel", 0
s_about:  .byte "TRACKER - songs for the music engine", 13, 13
          .byte "Piano keys (Z S X D C.. and Q 2 W 3 E..) enter notes,", 13
          .byte "1 = note off. Enter: type a cell. Space: play / stop.", 13
          .byte "Ctrl + Left / Right: order, Ctrl + Up / Down: pattern.", 13, 13
          .byte "(C) 2026 Benoit Colson - GNU GPL 3", 13
          .byte "With the help of Claude AI.", 0

FNAME:  .res 64
NAMEB:  .res 64
TBUF:   .res 32
TBUF2:  .res 42
FBUFS:  .res 28                 ; 7 number fields, 4 bytes each

;=============================================================================
; TRACKER2: the main-RAM part
;=============================================================================
        .segment "LOW"

; --- the song ---------------------------------------------------------------------
; A new song: one order (patterns 1, 2, 3), 4 instruments
songnew:
        lda #0                  ; everything cleared (DMA fill), but
        sta DMAFILL             ; not the copied block
        LDW DMASRC+3, INSTR
        lda #$FF
        sta DMASRC+5
        LDW DMASRC+6, BLK - INSTR
        lda #0
        sta DMASRC+8
        lda #2
        sta DMACMD
        LDW DMASRC+3, PAT
        LDW DMASRC+6, MAXPAT * 256
        lda #2
        sta DMACMD
        ldx #4 * 8 - 1          ; the first instruments
@i:     lda definst,x
        sta INSTR,x
        dex
        bpl @i
        lda #1
        sta ORD
        lda #2
        sta ORD+1
        lda #3
        sta ORD+2
        lda #1
        sta NORD
        lda #0
        sta LOOP
        sta CURORD
        sta CROW
        sta CX
        sta TOPR
        sta DIRTY
        sta PLAYING
        lda #6
        sta SPEED
        lda #32
        sta ROWS
        lda #4
        sta OCT
        lda #1
        sta CINS
        lda #$FF
        sta PROW
        rts
definst:
        .byte 0, 11, 0, 0, 8, 0, 0, 0           ; 1 square lead
        .byte 0, 15, 1, 0, 15, 0, 0, 0          ; 2 triangle bass
        .byte 0, 7, 2, 0, 15, 0, 0, 0           ; 3 saw
        .byte 3, 12, 3, 0, 15, 0, 0, 0          ; 4 noise drum

; The image at IMG -> the song; carry set if it is not one
unpack: lda IMG
        cmp #'M'
        bne @bad
        lda IMG+1
        cmp #'U'
        beq @ok
@bad:   sec
        rts
@ok:    jsr songnew
        lda IMG+3
        sta SPEED
        lda IMG+4
        sta NORD
        lda IMG+5
        sta LOOP
        lda IMG+6
        sta ROWS
        LDW P0, IMG + 16        ; instruments (32 at most)
        LDW P1, INSTR
        lda IMG+4               ; (no orders, no rows: not a song)
        beq @bad2
        lda IMG+6
        beq @bad2
        cmp #65
        bcs @bad2
        lda IMG+7
        beq @ord
        cmp #33
        bcc @ni
        lda #32
@ni:    asl
        asl
        asl
        sta CNT
        ldy #0
@ic:    lda (P0),y
        sta (P1),y
        iny
        cpy CNT
        bne @ic
        beq @ord
@bad2:  sec
        rts
@ord:   lda IMG+10              ; orders
        clc
        adc #<IMG
        sta P0
        lda IMG+11
        adc #>IMG
        sta P0+1
        LDW P1, ORD
        lda NORD
        sta CNT
@o:     ldy #2
@o3:    lda (P0),y
        cmp #MAXPAT
        bcc @o4
        lda #0
@o4:    sta (P1),y
        dey
        bpl @o3
        ADDW P0, P0, 3
        ADDW P1, P1, 3
        dec CNT
        bne @o
        lda IMG+12              ; patterns: ROWS * 4 bytes each -> 256
        clc
        adc #<IMG
        sta P0
        lda IMG+13
        adc #>IMG
        sta P0+1
        LDW P1, PAT
        lda IMG+8
        beq @tt
        cmp #MAXPAT + 1
        bcc @np
        lda #MAXPAT
@np:    sta CNT
        lda ROWS
        asl
        asl
        sta TMP                 ; (0 = 256 for 64 rows)
@p:     ldy #0
@pc:    lda (P0),y
        sta (P1),y
        iny
        cpy TMP
        bne @pc
        lda P0
        clc
        adc TMP
        sta P0
        bcc @pn
        inc P0+1
@pn:    lda TMP
        bne @pa
        inc P0+1
@pa:    inc P1+1
        dec CNT
        bne @p
@tt:    lda IMG+14              ; the title
        clc
        adc #<IMG
        sta P0
        lda IMG+15
        adc #>IMG
        sta P0+1
        ldy #0
@t:     lda (P0),y
        sta TITLE,y
        beq @td
        iny
        cpy #40
        bne @t
        lda #0
        sta TITLE,y
@td:    clc
        rts

; The image -> IMG (P2 = its end). A = 0 the whole song, 1 from CURORD on,
; 2 the pattern of CURORD only
build:  sta TMP2
        ldx #0                  ; patterns: 1 + the highest one used
        stx NPAT
        LDW P0, ORD
        lda NORD
        sta CNT
@hp:    ldy #2
@h3:    lda (P0),y
        cmp NPAT
        bcc @h4
        sta NPAT
@h4:    dey
        bpl @h3
        ADDW P0, P0, 3
        dec CNT
        bne @hp
        inc NPAT
        lda #0                  ; which orders
        sta FO
        lda NORD
        sta NO
        lda LOOP
        sta TMP
        lda TMP2
        beq @hdr
        lda CURORD
        sta FO
        lda TMP2
        cmp #2
        bne @from
        lda #1
        sta NO
        lda #0
        sta TMP
        beq @hdr
@from:  lda NORD
        sec
        sbc CURORD
        sta NO
        lda LOOP
        cmp #$FF
        beq @hdr
        sec
        sbc CURORD
        bcs @lk
        lda #0
@lk:    sta TMP
@hdr:   lda #'M'
        sta IMG
        lda #'U'
        sta IMG+1
        lda #1
        sta IMG+2
        lda SPEED
        sta IMG+3
        lda NO
        sta IMG+4
        lda TMP
        sta IMG+5
        lda ROWS
        sta IMG+6
        lda #32
        sta IMG+7
        lda NPAT
        sta IMG+8
        lda #0
        sta IMG+9
        LDW IMG+10, 16 + 32 * 8         ; orders offset
        lda NO                          ; patterns offset: + 3 * orders
        sta T16
        lda #0
        sta T16+1
        asl T16
        rol T16+1
        lda T16
        clc
        adc NO
        sta T16
        lda T16+1
        adc #0
        sta T16+1
        lda T16
        clc
        adc #<(16 + 32 * 8)
        sta IMG+12
        lda T16+1
        adc #>(16 + 32 * 8)
        sta IMG+13
        LDW P1, INSTR           ; instruments
        LDW P2, IMG + 16
        LDW T16, 32 * 8
        jsr copy
        lda FO                  ; orders: ORD + FO * 3
        sta T16
        lda #0
        sta T16+1
        asl T16
        rol T16+1
        lda T16
        clc
        adc FO
        sta T16
        lda T16+1
        adc #0
        sta T16+1
        lda T16
        clc
        adc #<ORD
        sta P1
        lda T16+1
        adc #>ORD
        sta P1+1
        lda IMG+12              ; (length = patterns offset - orders offset)
        sec
        sbc #<(16 + 32 * 8)
        sta T16
        lda IMG+13
        sbc #>(16 + 32 * 8)
        sta T16+1
        jsr copy
        lda #0                  ; patterns
        sta CNT
@pp:    LDW P1, PAT
        lda CNT
        clc
        adc P1+1
        sta P1+1
        lda ROWS
        asl
        asl
        sta T16
        lda #0
        sta T16+1
        lda ROWS
        cmp #64
        bne @pl
        inc T16+1               ; (64 rows: 256 bytes)
@pl:    jsr copy
        inc CNT
        lda CNT
        cmp NPAT
        bne @pp
        lda P2                  ; the title's offset
        sec
        sbc #<IMG
        sta IMG+14
        lda P2+1
        sbc #>IMG
        sta IMG+15
        ldy #0
@t:     lda TITLE,y
        sta (P2),y
        beq @te
        iny
        cpy #40
        bne @t
        lda #0
        sta (P2),y
@te:    iny
        tya
        clc
        adc P2
        sta P2
        bcc @r
        inc P2+1
@r:     rts

; T16 bytes from P1 to P2 (P2 moves on) with the DMA
copy:   lda T16
        ora T16+1
        beq @r
        lda P1
        sta DMASRC
        lda P1+1
        sta DMASRC+1
        lda #$FF
        sta DMASRC+2
        sta DMASRC+5
        lda P2
        sta DMASRC+3
        lda P2+1
        sta DMASRC+4
        lda T16
        sta DMASRC+6
        lda T16+1
        sta DMASRC+7
        lda #0
        sta DMASRC+8
        lda #1
        sta DMACMD
        lda P2
        clc
        adc T16
        sta P2
        lda P2+1
        adc T16+1
        sta P2+1
@r:     rts

; P0 = instrument A (1-32)
insptr: sec
        sbc #1
        and #31
        asl
        asl
        asl
        clc
        adc #<INSTR
        sta P0
        lda #>INSTR
        adc #0
        sta P0+1
        rts

; P1 = order A's 3 pattern numbers
ordptr: sta P1
        lda #0
        sta P1+1
        lda P1
        asl
        rol P1+1
        clc
        adc P1
        sta P1
        lda P1+1
        adc #0
        sta P1+1
        lda P1
        clc
        adc #<ORD
        sta P1
        lda P1+1
        adc #>ORD
        sta P1+1
        rts

; P0 = the cell of voice X, row Y in order CURORD (A = its pattern)
cellptr:
        stx CT
        sty CT+1
        lda CURORD
        jsr ordptr
        ldy CT
        lda (P1),y
        pha
        clc
        adc #>PAT
        sta P0+1
        lda CT+1
        asl
        asl
        sta P0
        pla
        rts

; The text changed: the title shows *
changed:
        lda DIRTY
        bne @r
        lda #1
        sta DIRTY
        jmp settitle
@r:     rts

; --- numbers in text --------------------------------------------------------------
; NUM (signed, 16 bits) in decimal -> (P1), with a 0
numstr: ldy #0
        lda NUM+1
        bpl @p
        lda #'-'
        sta (P1),y
        iny
        lda #0                  ; NUM = -NUM
        sec
        sbc NUM
        sta NUM
        lda #0
        sbc NUM+1
        sta NUM+1
@p:     sty TMP
        ldx #0
@d:     jsr div10
        pha
        inx
        lda NUM
        ora NUM+1
        bne @d
        ldy TMP
@o:     pla
        sta (P1),y
        iny
        dex
        bne @o
        lda #0
        sta (P1),y
        rts
div10:  lda #16
        sta DIVC
        lda #0
@l:     asl NUM
        rol NUM+1
        rol
        cmp #10
        bcc @n
        sbc #10
        inc NUM
@n:     dec DIVC
        bne @l
        ora #'0'
        rts

; (P1) in decimal, maybe with "-" -> NUM (A = its low byte)
strnum: lda #0
        sta NUM
        sta NUM+1
        sta TMP2
        ldy #0
        lda (P1),y
        cmp #'-'
        bne @d
        inc TMP2
        iny
@d:     lda (P1),y
        sec
        sbc #'0'
        bcc @e
        cmp #10
        bcs @e
        pha                     ; NUM = NUM * 10 + digit
        asl NUM
        rol NUM+1
        lda NUM
        sta T16
        lda NUM+1
        sta T16+1
        asl NUM
        rol NUM+1
        asl NUM
        rol NUM+1
        lda NUM
        clc
        adc T16
        sta NUM
        lda NUM+1
        adc T16+1
        sta NUM+1
        pla
        clc
        adc NUM
        sta NUM
        bcc @nx
        inc NUM+1
@nx:    iny
        bne @d
@e:     lda TMP2
        beq @r
        lda #0
        sec
        sbc NUM
        sta NUM
        lda #0
        sbc NUM+1
        sta NUM+1
@r:     lda NUM
        rts

; (P1): two hex digits -> A ($FF if empty)
strhex: ldy #0
        lda (P1),y
        bne @h
        lda #$FF
        rts
@h:     lda #0
        sta TMP
@l:     lda (P1),y
        jsr hexval
        bcs @e
        asl TMP
        asl TMP
        asl TMP
        asl TMP
        ora TMP
        sta TMP
        iny
        cpy #2
        bne @l
@e:     lda TMP
        rts
; A = a hex digit's value; carry set if it is not one
hexval: cmp #'a'
        bcc @u
        and #$DF
@u:     sec
        sbc #'0'
        bcc @no
        cmp #10
        bcc @ok
        sbc #7
        cmp #10
        bcc @no
        cmp #16
        bcs @no
@ok:    clc
        rts
@no:    sec
        rts

; --- playing -------------------------------------------------------------------
; The banks to play from (5: 20K)
playinit:
        lda #$FF
        sta SBANK
        lda BANK                ; owned by us (freed when we are done)
        ldx #5
        ldy #1
        jsr BALLOC
        bcs @r
        sta SBANK
@r:     rts

; Plays: A = 0 the song, 1 from this order, 2 this pattern
play:   pha
        jsr stop
        pla
        pha
        jsr build
        pla
        tax
        inx
        stx PLAYING
        lda SBANK
        cmp #$FF
        beq @no
        lda #<IMG               ; the image -> the banks
        sta DMASRC
        lda #>IMG
        sta DMASRC+1
        lda #$FF
        sta DMASRC+2
        lda #0
        sta DMASRC+3
        lda SBANK               ; bank * $1000
        asl
        asl
        asl
        asl
        sta DMASRC+4
        lda SBANK
        lsr
        lsr
        lsr
        lsr
        sta DMASRC+5
        lda P2
        sec
        sbc #<IMG
        sta DMASRC+6
        lda P2+1
        sbc #>IMG
        sta DMASRC+7
        lda #0
        sta DMASRC+8
        lda #1
        sta DMACMD
        lda FO
        sta POFF
        lda #0                  ; PLAY
        ldx SBANK
        jsr E_MUSIC
        bcs @no
        lda #$FF
        sta PROW
        jmp drawhdr
@no:    lda #0
        sta PLAYING
        lda #1
        sta BEEP
        rts

stop:   lda PLAYING
        beq @r
        lda #1                  ; STOP
        jsr E_MUSIC
        lda #0
        sta PLAYING
        lda PROW
        ldx #$FF
        stx PROW
        jsr rowline             ; its marker away
        jsr drawhdr
@r:     rts

m_playsong:
        lda #0
        jmp play
m_playhere:
        lda #1
        jmp play
m_playpat:
        lda #2
        jmp play
m_stop: jmp stop

; Nothing happening: where the engine is, shown
follow: lda PLAYING
        beq @r
        lda #4                  ; STATUS: A state, X order, Y row
        jsr E_MUSIC
        cmp #0
        bne @on
        jmp stop
@on:    sty TMP2
        txa
        clc
        adc POFF
        cmp CURORD
        beq @row
        cmp NORD
        bcs @r
        sta CURORD              ; another order: all again
        lda TMP2
        sta PROW
        sta CROW
        jsr fixtop
        jmp drawall2
@row:   lda TMP2
        cmp PROW
        beq @r
        lda PROW
        pha
        lda TMP2
        sta PROW
        sta CROW
        jsr fixtop
        bcs @all
        pla
        jsr rowline             ; the old row, the new one
        lda PROW
        jmp rowline
@all:   pla
        jmp drawall2
@r:     rts

; A note on voice VOICE now (A = note, instrument TMP2)
preview:
        pha
        lda PLAYING
        beq @go
        pla
        rts
@go:    lda TMP2
        jsr insptr
        lda VOICE
        and #3
        asl
        asl
        tax
        ldy #0                  ; DECAY
        lda (P0),y
        sta S1 + S_DECAY,x
        ldy #3
        lda (P0),y
        sta S1 + S_SWEEP,x
        iny
        lda (P0),y
        sta S1 + S_PULSE,x
        lda #0
        sta S1 + S_BEND,x
        ldy #1
        lda (P0),y
        sta V1 + V_VOL,x
        iny
        lda (P0),y
        sta V1 + V_WAVE,x
        ldy #5
        lda (P0),y
        bne @d
        lda #30                 ; (held: half a second here)
@d:     sta V1 + V_DUR,x
        pla
        sta V1 + V_NOTE,x
        rts

; --- the screen ----------------------------------------------------------------
orgset: ADDW ORGX, r0, 4
        ADDW ORGY, r1, 2
        rts
setport:
        ldx WIN
        TK TK_SETPORT
        jmp orgset

; Everything drawn again (now, if we are in front; else at the UPDATE)
redraw: ldx #$FF
        TK TK_FRONT
        cpx WIN
        beq @f
        ldx WIN
        TK TK_INVAL
        rts
@f:     jsr setport
        jsr syncbar
drawall:
        lda #0
        sta DLN
@l:     lda DLN
        jsr drawline
        inc DLN
        lda DLN
        cmp #22
        bne @l
        rts
; (from the idle loop: the port first)
drawall2:
        jsr inport
        bcs @r
        jmp drawall
@r:     rts
; Carry clear (and the port set) if our window is in front
inport: ldx #$FF
        TK TK_FRONT
        cpx WIN
        beq @f
        sec
        rts
@f:     jsr setport
        clc
        rts
drawhdr:
        jsr inport
        bcs @r
        lda #0
        jsr drawline
        lda #1
        jmp drawline
@r:     rts
; The grid line of row A ($FF: none), if it is shown
rowline:
        cmp #$FF
        beq @r
        sec
        sbc TOPR
        bcc @r
        cmp #VIS
        bcs @r
        clc
        adc #GLINE
        pha
        jsr inport
        pla
        bcs @r
        jmp drawline
@r:     rts

; Screen line A built in LBUF / LINV, then drawn
drawline:
        sta DLINE
        ldx #79                 ; spaces, not inverted
@c:     lda #' '
        sta LBUF,x
        lda #0
        sta LINV,x
        dex
        bpl @c
        lda DLINE
        beq @hdr
        cmp #1
        beq @heads
        cmp #21
        beq @help
        jsr gridline
        jmp @out
@hdr:   jsr hdrline
        jmp @out
@heads: jsr headline
        jmp @out
@help:  ldx #0
        lda #<s_help
        ldy #>s_help
        jsr lstr
@out:   lda DLINE               ; at its place: x = ORGX, y = ORGY + 16 * line
        asl
        asl
        asl
        asl
        clc
        adc ORGY
        sta BY0
        lda ORGY+1
        adc #0
        sta BY0H
        lda DLINE
        cmp #16                 ; (lines 16+: 256 more)
        bcc @lo
        inc BY0H
@lo:    lda #78                 ; (the grid's lines: not over the bar)
        ldx DLINE
        cpx #GLINE
        bcc @lim
        cpx #GLINE + VIS
        bcs @lim
        lda #76
@lim:   sta DLIM
        lda ORGX
        sta BX0
        lda ORGX+1
        sta BX0H
        lda #R_SET
        sta ROP
        ldx #0
@o:     lda #S_OPAQUE
        ldy LINV,x
        beq @s
        lda #S_OPAQUE + S_INV
@s:     sta STYLE
        lda LBUF,x
        sta CHOUT
        inx
        cpx DLIM
        bne @o
        lda #0
        sta STYLE
        rts

; the string at AY -> LBUF,X (X moves on)
lstr:   sta P2
        sty P2+1
        ldy #0
@c:     lda (P2),y
        beq @r
        sta LBUF,x
        inx
        iny
        bne @c
@r:     rts
; A in hex -> LBUF,X
lhex:   pha
        lsr
        lsr
        lsr
        lsr
        jsr @d
        pla
        and #$0F
@d:     cmp #10
        bcc @n
        adc #6
@n:     adc #'0'
        sta LBUF,x
        inx
        rts
; A in decimal (0-255) -> LBUF,X
ldec:   sta NUM
        lda #0
        sta NUM+1
        stx LCOL
        txa
        clc
        adc #<LBUF
        sta P1
        lda #>LBUF
        adc #0
        sta P1+1
        jsr numstr
        ldx LCOL
@e:     lda LBUF,x              ; past the digits (numstr's 0 -> space)
        beq @z
        inx
        bne @e
@z:     lda #' '
        sta LBUF,x
        rts

; line 0: the title, speed, rows, order, loop, octave, instrument, playing
hdrline:
        ldx #0
        ldy #0
@t:     lda TITLE,y
        beq @te
        sta LBUF,x
        inx
        iny
        cpy #24
        bne @t
@te:    ldx #26
        lda #<s_hspeed
        ldy #>s_hspeed
        jsr lstr
        lda SPEED
        jsr ldec
        ldx #36
        lda #<s_hrows
        ldy #>s_hrows
        jsr lstr
        lda ROWS
        jsr ldec
        ldx #45
        lda #<s_hloop
        ldy #>s_hloop
        jsr lstr
        lda LOOP
        cmp #$FF
        bne @lh
        lda #'-'
        sta LBUF,x
        inx
        sta LBUF,x
        bne @oc
@lh:    jsr lhex
@oc:    ldx #54
        lda #<s_hoct
        ldy #>s_hoct
        jsr lstr
        lda OCT
        ora #'0'
        sta LBUF,x
        ldx #61
        lda #<s_hins
        ldy #>s_hins
        jsr lstr
        lda CINS
        jsr lhex
        lda PLAYING
        beq @r
        ldx #70
        lda #<s_hplay
        ldy #>s_hplay
        jsr lstr
@r:     rts

; line 1: "Ord P1 P2 P3 | Row  Voice 1 (pp) ..."
headline:
        ldx #0
        lda #<s_heads
        ldy #>s_heads
        jsr lstr
        lda CURORD
        jsr lhex
        lda #'/'
        sta LBUF,x
        inx
        lda NORD
        jsr lhex
        ldx #13
        lda #<s_row
        ldy #>s_row
        jsr lstr
        lda #0
        sta GV
@v:     lda GV                  ; "Voice n  pattern pp" at 18 + 20 * n
        asl
        asl
        sta TMP
        asl
        asl
        clc
        adc TMP
        adc #18
        tax
        lda #<s_voice
        ldy #>s_voice
        jsr lstr
        lda GV
        clc
        adc #'1'
        sta LBUF,x
        inx
        lda #<s_vpat
        ldy #>s_vpat
        jsr lstr
        lda CURORD
        jsr ordptr
        ldy GV
        lda (P1),y
        jsr lhex
        inc GV
        lda GV
        cmp #3
        bne @v
        rts

; a grid line (screen line TMP2): the order list's line, the row
gridline:
        jsr calcsel
        jsr ordtop              ; order = the first shown + line - 2
        lda DLINE
        sec
        sbc #GLINE
        clc
        adc OTOP
        bcs @row
        sta TMP
        cmp NORD
        bcs @row
        ldx #1
        jsr lhex
        inx
        lda TMP
        jsr ordptr
        ldy #0
@op:    sty CNT
        lda (P1),y
        jsr lhex
        inx
        ldy CNT
        iny
        cpy #3
        bne @op
        lda TMP
        cmp CURORD
        bne @row
        ldx #11                 ; the order shown: inverted
@oi:    lda #1
        sta LINV,x
        dex
        bpl @oi
@row:   lda #'|'
        sta LBUF+12
        lda DLINE               ; row = TOPR + line - 2
        sec
        sbc #GLINE
        clc
        adc TOPR
        sta TMP
        cmp ROWS
        bcc @in
        rts
@in:    ldx #14
        jsr lhex
        lda TMP
        cmp CROW
        bne @np
        lda #1
        sta LINV+14
        sta LINV+15
@np:    lda PLAYING
        beq @cells
        lda TMP
        cmp PROW
        bne @cells
        lda #'>'
        sta LBUF+13
@cells: lda #0
        sta GV
@cv:    ldx GV
        ldy TMP
        jsr cellptr
        lda GV               ; x = 18 + 20 * voice
        asl
        asl
        sta CNT
        asl
        asl
        clc
        adc CNT
        adc #18
        tax
        stx LCOL
        jsr fmtcell
        lda SELON               ; in the block: the cell inverted
        beq @cur
        lda TMP
        cmp SR0
        bcc @cur
        lda SR1
        cmp TMP
        bcc @cur
        lda GV
        cmp SV0
        bcc @cur
        lda SV1
        cmp GV
        bcc @cur
        ldx LCOL
        ldy #10
        lda #1
@bi:    sta LINV,x
        inx
        dey
        bne @bi
@cur:   lda TMP                 ; the cursor's field: inverted (the other
        cmp CROW                ; way in the block)
        bne @nx
        lda CX
        sec
        sbc GV
        sbc GV
        sbc GV
        sbc GV
        sbc GV
        sbc GV
        cmp #6
        bcs @nx
        tay
        lda LCOL
        clc
        adc foff,y
        tax
        jsr flipinv
        cpy #0
        bne @nx
        inx                     ; (a note: 3 characters)
        jsr flipinv
        inx
        jsr flipinv
@nx:    inc GV
        lda GV
        cmp #3
        bne @cv
        rts
foff:   .byte 0, 4, 5, 7, 8, 9
flipinv:
        lda LINV,x
        eor #1
        sta LINV,x
        rts

; OTOP = the first order in the list (the one shown in its middle)
ordtop: lda CURORD
        sec
        sbc #9
        bcs @s
        lda #0
@s:     sta OTOP
        rts

; the cell at P0 -> LBUF,X: "C-4 01 A37" (--- .. ...)
fmtcell:
        ldy #0
        lda (P0),y
        bne @n
        lda #'-'
        sta LBUF,x
        sta LBUF+1,x
        sta LBUF+2,x
        bne @ins
@n:     cmp #$FF
        bne @nn
        lda #'='
        sta LBUF,x
        sta LBUF+1,x
        sta LBUF+2,x
        bne @ins
@nn:    jsr notename            ; -> LBUF,X (3)
@ins:   inx
        inx
        inx
        inx
        ldy #1
        lda (P0),y
        bne @ih
        lda #'.'
        sta LBUF,x
        sta LBUF+1,x
        inx
        inx
        bne @ef
@ih:    jsr lhex
@ef:    inx
        ldy #2
        lda (P0),y
        beq @noe
        cmp #9
        bcs @noe
        tay
        lda effl-1,y
        sta LBUF,x
        inx
        ldy #3
        lda (P0),y
        jmp lhex
@noe:   lda #'.'
        sta LBUF,x
        sta LBUF+1,x
        sta LBUF+2,x
        rts
effl:   .byte "ASVLTJBP"

; note A (1-127) -> 3 characters at LBUF,X (X kept)
notename:
        ldy #0                  ; octave = A / 12 - 1
@o:     cmp #12
        bcc @s
        sbc #12
        iny
        bne @o
@s:     asl                     ; name: 2 characters
        sty TMP2+0
        tay
        lda names,y
        sta LBUF,x
        lda names+1,y
        sta LBUF+1,x
        lda TMP2
        beq @q                  ; (octave -1: "?")
        sec
        sbc #1
        ora #'0'
        sta LBUF+2,x
        rts
@q:     lda #'?'
        sta LBUF+2,x
        rts
names:  .byte "C-C#D-D#E-F-F#G-G#A-A#B-"

; --- the cursor -----------------------------------------------------------------
; TOPR so that CROW is shown; carry set if it moved
fixtop: lda CROW
        cmp TOPR
        bcc @up
        sec
        sbc TOPR
        cmp #VIS
        bcc @ok
        lda CROW
        sec
        sbc #VIS - 1
        sta TOPR
        sec
        rts
@up:    lda CROW
        sta TOPR
        sec
        rts
@ok:    clc
        rts
; the cursor within the song (after ROWS or NORD changed)
fixcursor:
        lda CURORD
        cmp NORD
        bcc @o
        ldx NORD
        dex
        stx CURORD
@o:     lda CROW
        cmp ROWS
        bcc @r
        ldx ROWS
        dex
        stx CROW
@r:     lda #0
        sta TOPR
        jsr fixtop
        rts

; After a move: the rows drawn again (the whole grid if the view moved or
; a block is shown)
moved:  jsr fixtop
        bcs @all
        lda SELON
        ora SELDRT
        bne @all
        jsr inport
        bcs @r
        lda OLDROW
        jsr rowline
        lda CROW
        jmp rowline
@all:   lda #0
        sta SELDRT
        jmp drawgrid
@r:     rts

; The grid's lines drawn again (now if we are in front, else later)
drawgrid:
        jsr inport
        bcc @go
        ldx WIN
        TK TK_INVAL
        rts
@go:    jsr syncbar
        lda #GLINE
        sta DLN
@l:     lda DLN
        jsr drawline
        inc DLN
        lda DLN
        cmp #GLINE + VIS
        bne @l
        rts

; The scroll bar: its maximum (rows not shown) and value (TOPR)
syncbar:
        lda ROWS
        sec
        sbc #VIS
        bcs @m
        lda #0
@m:     cmp BARM
        beq @v
        sta BARM
        sta r1
        lda #0
        sta r1+1
        sta r0
        sta r0+1
        ldx BAR
        TK TK_SETDATA
@v:     lda TOPR
        cmp BARV
        beq @r
        sta BARV
        sta r0
        lda #0
        sta r0+1
        ldx BAR
        TK TK_SETVALUE
@r:     rts

; The view from row A on (the scroll bar, the wheel); the cursor stays
; where it is (the view comes back to it when it moves)
setview:
        sta TMP
        lda ROWS
        sec
        sbc #VIS
        bcs @m
        lda #0
@m:     cmp TMP
        bcs @ok
        sta TMP
@ok:    lda TMP
        sta TOPR
        jmp drawgrid

; The wheel: Y steps (signed), 3 rows each
wheel:  tya
        beq @r
        sta TMP
        asl
        clc
        adc TMP
        ldx TMP
        bmi @neg
        clc
        adc TOPR
        bcc @set
        lda #$FF
        bne @set
@neg:   clc
        adc TOPR
        bcs @set
        lda #0
@set:   jmp setview
@r:     rts

; A = the cursor's voice
curv:   lda CX
        ldx #0
@l:     cmp #6
        bcc @d
        sbc #6
        inx
        bne @l
@d:     txa
        rts
; A = A * 6 (a voice's first field)
cxof:   sta TMP
        asl
        adc TMP
        asl
        rts
; The block's other end: here
anchor: lda CROW
        sta AROW
        jsr curv
        sta AVC
        rts
; No block (the grid to be drawn again if there was one)
selclr: lda SELON
        beq @r
        lda #0
        sta SELON
        lda #1
        sta SELDRT
@r:     rts
; SR0-SR1, SV0-SV1: the block (the cursor's cell if none)
calcsel:
        jsr curv
        ldx SELON
        bne @s
        sta SV0
        sta SV1
        lda CROW
        sta SR0
        sta SR1
        rts
@s:     cmp AVC
        bcc @v1
        sta SV1
        lda AVC
        sta SV0
        jmp @r
@v1:    sta SV0
        lda AVC
        sta SV1
@r:     lda CROW
        cmp AROW
        bcc @r1
        sta SR1
        lda AROW
        sta SR0
        jmp @c
@r1:    sta SR0
        lda AROW
        sta SR1
@c:     ldx ROWS
        dex
        cpx SR1
        bcs @c2
        stx SR1
@c2:    cpx SR0
        bcs @c3
        stx SR0
@c3:    rts

; --- keys ---------------------------------------------------------------------------
key:    stx CH
        sty EXT
        lda CROW
        sta OLDROW
        lda #141                ; Ctrl held?
        sta KEYSEL
        lda KEYHELD
        sta CTRL
        lda #140                ; Shift held?
        sta KEYSEL
        lda KEYHELD
        sta SHIFT
        lda CX                  ; VOICE, FIELD from the cursor
        ldx #0
@v:     cmp #6
        bcc @vf
        sbc #6
        inx
        bne @v
@vf:    stx VOICE
        sta FIELD
        lda CH
        beq @ext
        jmp chr
@ext:   lda EXT
        ldx CTRL
        beq @plain
        cmp #3                  ; Ctrl + Left / Right: order
        beq k_prevord
        cmp #4
        beq k_nextord
        cmp #1                  ; Ctrl + Up / Down: the voice's pattern
        beq k_patup
        cmp #2
        beq k_patdn
@plain: cmp #11
        bcs @r
        cmp #1
        bcc @r
        cmp #9                  ; moving: with Shift the block grows,
        bcs @go                 ; else it goes
        pha
        lda SHIFT
        beq @ns
        lda SELON
        bne @pl
        jsr anchor
        inc SELON
        bne @pl
@ns:    jsr selclr
@pl:    pla
@go:    asl
        tax
        lda keytab-1,x
        pha
        lda keytab-2,x
        pha
@r:     rts
keytab: .word k_up-1, k_down-1, k_left-1, k_right-1, k_home-1, k_end-1
        .word k_pgup-1, k_pgdn-1, k_ins-1, k_del-1

k_prevord:
        lda CURORD
        beq kr
        dec CURORD
        jmp ordmoved
k_nextord:
        ldx CURORD
        inx
        cpx NORD
        bcs kr
        stx CURORD
ordmoved:
        jmp redraw
kr:     rts
k_patup:
        jsr curpat              ; P1 + VOICE = this voice's pattern
        lda (P1),y
        cmp #MAXPAT - 1
        bcs kr
        adc #1
        sta (P1),y
        jsr changed
        jmp redraw
k_patdn:
        jsr curpat
        lda (P1),y
        beq kr
        sec
        sbc #1
        sta (P1),y
        jsr changed
        jmp redraw
; P1 = this order's patterns, Y = VOICE
curpat: lda CURORD
        jsr ordptr
        ldy VOICE
        rts

k_up:   lda CROW
        beq @r
        dec CROW
@r:     jmp moved
k_down: ldx CROW
        inx
        cpx ROWS
        bcs @r
        stx CROW
@r:     jmp moved
k_left: lda CX
        beq @r
        dec CX
@r:     jmp moved
k_right:
        lda CX
        cmp #17
        bcs @r
        inc CX
@r:     jmp moved
k_home: lda #0
        sta CROW
        jmp moved
k_end:  ldx ROWS
        dex
        stx CROW
        jmp moved
k_pgup: lda CROW
        sec
        sbc #16
        bcs @s
        lda #0
@s:     sta CROW
        jmp moved
k_pgdn: lda CROW
        clc
        adc #16
        cmp ROWS
        bcc @s
        ldx ROWS
        dex
        txa
@s:     sta CROW
        jmp moved
k_ins:  jmp m_insrow
k_del:  lda SELON                ; Delete: the block cleared, or the field
        beq @f                  ; (and one row down)
        jmp m_clear
@f:     jsr editcell
        bcs @r
        ldx FIELD
        lda #0
        cpx #0
        bne @i
        ldy #0                  ; note: note and instrument
        sta (P0),y
        iny
        sta (P0),y
        jmp stepdown
@i:     cpx #3
        bcs @e
        ldy #1                  ; instrument
        sta (P0),y
        jmp stepdown
@e:     ldy #2                  ; effect and parameter
        sta (P0),y
        iny
        sta (P0),y
        jmp stepdown
@r:     rts

; P0 = the cursor's cell, ready to change (a voice on pattern 0 gets a
; pattern of its own first); carry set if none could be had
editcell:
        jsr curpat
        lda (P1),y
        bne @ok
        jsr freepat             ; A = an unused pattern, carry set if none
        bcs @no
        pha
        jsr curpat
        pla
        sta (P1),y
        jsr redraw
@ok:    ldx VOICE
        ldy CROW
        jsr cellptr
        jsr changed
        clc
        rts
@no:    lda #1
        sta BEEP
        sec
        rts

; A = the first pattern (1-63) no order uses; carry set if there is none
freepat:
        ldx #MAXPAT - 1         ; USED[] cleared
        lda #0
@c:     sta USED,x
        dex
        bpl @c
        lda #0
        sta CNT
@o:     lda CNT
        cmp NORD
        beq @find
        jsr ordptr
        ldy #2
@v:     lda (P1),y
        tax
        lda #1
        sta USED,x
        dey
        bpl @v
        inc CNT
        bne @o
@find:  ldx #1
@f:     lda USED,x
        beq @got
        inx
        cpx #MAXPAT
        bne @f
        sec
        rts
@got:   txa                     ; (cleared, in case)
        clc
        adc #>PAT
        sta P0+1
        lda #0
        sta P0
        tay
@z:     sta (P0),y
        iny
        bne @z
        txa
        clc
        rts

; One row down after an entry, and the screen
stepdown:
        ldx CROW
        inx
        cpx ROWS
        bcs @s
        stx CROW
@s:     jmp moved

; A character
chr:    lda CH
        cmp #' '                ; Space: play from this order, or stop
        bne @n1
        lda PLAYING
        beq @pl
        jmp stop
@pl:    lda #1
        jmp play
@n1:    cmp #27                 ; Esc: no block
        bne @n1b
        jsr selclr
        jmp moved
@n1b:   cmp #CR                 ; Enter: type the cell
        bne @n2
        jmp typecell
@n2:    cmp #8                  ; Backspace: the row deleted
        bne @n3
        jmp m_delrow
@n3:    cmp #9                  ; Tab: the next voice
        bne @n4
        lda VOICE
        clc
        adc #1
        cmp #3
        bcc @t
        lda #0
@t:     sta TMP
        asl
        adc TMP
        asl
        sta CX
        jmp moved
@n4:    cmp #'+'                ; octave
        beq @oup
        cmp #'='
        bne @n5
@oup:   lda OCT
        cmp #8
        bcs @od
        inc OCT
@od:    jmp drawhdr
@n5:    cmp #'-'
        bne @n6
        lda OCT
        beq @od
        dec OCT
        jmp drawhdr
@n6:    jsr selclr            ; typing: no block
        lda SELDRT
        beq @n7
        jsr drawgrid
        lda #0
        sta SELDRT
@n7:    lda CH
        ldx FIELD
        bne @nib
        jmp pianokey
@nib:   cpx #3
        bne @hex
        jmp effkey
@hex:   jsr hexval              ; instrument / parameter: a hex digit
        bcc @hv
        rts
@hv:    sta TMP
        jsr editcell
        bcs @r
        ldx FIELD
        ldy #1                  ; (fields 1, 2: byte 1; 4, 5: byte 3)
        cpx #4
        bcc @b
        ldy #3
@b:     lda (P0),y
        cpx #1                  ; hi nibble
        beq @hi
        cpx #4
        beq @hi
        and #$F0                ; lo nibble: then back to hi, a row down
        ora TMP
        sta (P0),y
        dec CX
        jmp stepdown
@hi:    and #$0F
        sta TMP2
        lda TMP
        asl
        asl
        asl
        asl
        ora TMP2
        sta (P0),y
        inc CX
        jmp moved
@r:     rts

; The effect field: a letter (A S V L T J B P), "." none
effkey: lda CH
        and #$DF
        ldx #7
@f:     cmp effl,x
        beq @got
        dex
        bpl @f
        lda CH
        cmp #'.'
        bne @r
        ldx #$FF
@got:   inx
        stx TMP
        jsr editcell
        bcs @r
        lda TMP
        ldy #2
        sta (P0),y
        inc CX                  ; on to the parameter
        jmp moved
@r:     rts

; The note field: a piano key (where it is on the keyboard, or which
; character), "1" note off
pianokey:
        ldx #0                  ; the keys held, by position
@p:     lda pianopos,x
        sta KEYPOS
        lda POSHELD
        bne @pos
        inx
        cpx #NPIANO
        bne @p
        lda CH                  ; else by the character (as on QWERTY)
        cmp #'a'
        bcc @u
        and #$DF
@u:     ldx #NPIANO - 1
@c:     cmp pianochr,x
        beq @pos
        dex
        bpl @c
        rts
@pos:   lda pianosemi,x
        cmp #$FF
        beq @off
        sta TMP
        lda OCT                 ; note = 12 * (octave + 1) + semitone
        clc
        adc #1
        sta TMP2
        asl
        adc TMP2
        asl
        asl
        clc
        adc TMP
        cmp #128
        bcc @nt
        lda #127
@nt:    pha
        jsr editcell
        pla
        bcs @r
        ldy #0
        sta (P0),y
        pha
        lda CINS
        iny
        sta (P0),y
        sta TMP2
        pla
        jsr preview
        jmp stepdown
@off:   jsr editcell
        bcs @r
        lda #$FF
        ldy #0
        sta (P0),y
        iny
        lda #0
        sta (P0),y
        jmp stepdown
@r:     rts
NPIANO  = 30
pianopos:                       ; PC scancodes (US positions)
        .byte 44, 31, 45, 32, 46, 47, 34, 48, 35, 49, 36, 50, 51
        .byte 16, 3, 17, 4, 18, 19, 6, 20, 7, 21, 8, 22, 23, 10, 24, 11
        .byte 2
pianochr:
        .byte "ZSXDCVGBHNJM,Q2W3ER5T6Y7UI9O01"
        .byte 0
pianosemi:
        .byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
        .byte 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27
        .byte $FF

; Enter: the cell typed as text ("C-4 01 A37"; --- === .. ...)
typecell:
        ldx VOICE
        ldy CROW
        jsr cellptr
        ldx #0                  ; its text now -> CELLB
        jsr fmtcell
        ldx #9
@c:     lda LBUF,x
        sta CELLB,x
        dex
        bpl @c
        lda #0
        sta CELLB+10
        ldy #3                  ; (an empty cell: nothing to rub out)
@z:     lda (P0),y
        bne @ask
        dey
        bpl @z
        sta CELLB
@ask:   LDW r0, s_cellp
        LDW r1, CELLB
        LDW r2, 12
        TK TK_ASK
        bcs @r
        jsr parsecell           ; -> CELL4, carry set if wrong
        bcs @bad
        jsr editcell
        bcs @r
        ldy #3
@s:     lda CELL4,y
        sta (P0),y
        dey
        bpl @s
        jmp stepdown
@bad:   LDW r0, s_badcell
        LDW r1, 0
        TK TK_ALERT
@r:     rts

; CELLB -> CELL4 (note, instrument, effect, parameter)
parsecell:
        ldx #0
        jsr skipsp
        lda CELLB,x             ; the note
        cmp #'-'
        beq @none
        cmp #'.'
        beq @none
        cmp #'='
        beq @off
        and #$DF
        sec
        sbc #'A'
        cmp #7
        jcs @bad
        tay
        lda semis,y
        sta TMP
        lda CELLB+1,x
        cmp #'#'
        bne @nb
        inc TMP
@nb:    lda CELLB+2,x
        sec
        sbc #'0'
        cmp #10
        jcs @bad
        clc
        adc #1                  ; 12 * (octave + 1) + semitone
        sta TMP2
        asl
        adc TMP2
        asl
        asl
        adc TMP
        bpl @n127
        lda #127
@n127:  sta CELL4
        jmp @n3
@none:  lda #0
        beq @sn
@off:   lda #$FF
@sn:    sta CELL4
@n3:    inx
        inx
        inx
        jsr skipsp              ; the instrument: 2 hex digits or ..
        lda #0
        sta CELL4+1
        sta CELL4+2
        sta CELL4+3
        lda CELLB,x
        beq @ok
        cmp #'.'
        beq @ni
        jsr hex2
        jcs @bad
        sta CELL4+1
        jmp @eff
@ni:    inx
        inx
@eff:   jsr skipsp              ; the effect: a letter and 2 hex digits
        lda CELLB,x
        beq @ok
        cmp #'.'
        beq @ok
        and #$DF
        ldy #7
@f:     cmp effl,y
        beq @fe
        dey
        bpl @f
        jmi @bad
@fe:    iny
        sty CELL4+2
        inx
        jsr hex2
        jcs @bad
        sta CELL4+3
@ok:    clc
        rts
@bad:   sec
        rts
semis:  .byte 9, 11, 0, 2, 4, 5, 7      ; A B C D E F G
skipsp: lda CELLB,x
        cmp #' '
        bne @r
        inx
        bne skipsp
@r:     rts
; 2 hex digits at CELLB,X -> A (X moves on); carry set if not
hex2:   lda CELLB,x
        jsr hexval
        bcs @r
        asl
        asl
        asl
        asl
        sta TMP
        inx
        lda CELLB,x
        jsr hexval
        bcs @r
        ora TMP
        inx
        clc
@r:     rts

; The cell at XL, YL (from the text's top left): A = 0 on the grid (MROW,
; MV, MF; MLINE its line), 1 above it, 2 below it, 3 left of it (the order
; list, MLINE)
mcell:  lda YL+1
        bmi @above
        lda YL
        sta TMP
        lda YL+1
        lsr
        ror TMP
        lsr
        ror TMP
        lsr
        ror TMP
        lsr
        ror TMP
        lda TMP
        sec
        sbc #GLINE
        bcc @above
        cmp #VIS
        bcs @below
        sta MLINE
        clc
        adc TOPR
        cmp ROWS
        bcc @rw
        ldx ROWS
        dex
        txa
@rw:    sta MROW
        lda XL+1
        bmi @left
        lda XL
        sta TMP
        lda XL+1
        lsr
        ror TMP
        lsr
        ror TMP
        lsr
        ror TMP
        lda TMP
        cmp #12
        bcc @left
        sec
        sbc #18
        bcs @g
        lda #0
@g:     ldx #0
@v:     cmp #20
        bcc @vd
        cpx #2
        beq @last
        sbc #20
        inx
        bne @v
@last:  lda #9
@vd:    stx MV
        ldy #5
@f:     cmp foff,y
        bcs @fd
        dey
        bpl @f
@fd:    sty MF
        lda #0
        rts
@above: lda #1
        rts
@below: lda #2
        rts
@left:  lda #3
        rts

; A click (r0, r1 in the contents): the cursor, a block (Shift, or
; dragged), or the order shown (order list)
click:  lda r0
        sec
        sbc #4
        sta XL
        lda r0+1
        sbc #0
        sta XL+1
        lda r1
        sec
        sbc #2
        sta YL
        lda r1+1
        sbc #0
        sta YL+1
        jsr setport
        lda #140
        sta KEYSEL
        lda KEYHELD
        sta SHIFT
        lda CROW
        sta OLDROW
        jsr mcell
        cmp #3
        bne @g
        jsr ordtop              ; the order list: that order
        lda MLINE
        clc
        adc OTOP
        jcs @r
        cmp NORD
        jcs @r
        sta CURORD
        jmp redraw
@g:     cmp #0
        jne @r
        lda SHIFT
        beq @ns
        lda SELON               ; Shift: the block up to here
        bne @mv
        jsr anchor
        inc SELON
        bne @mv
@ns:    jsr selclr
@mv:    lda MROW
        sta CROW
        lda MV
        jsr cxof
        clc
        adc MF
        sta CX
        lda SHIFT
        bne @dr
        jsr anchor
@dr:    jsr moved
@d:     lda BUTTONS             ; dragged: the block follows
        and #1
        beq @end
        lda FRAME
@w:     cmp FRAME
        beq @w
        lda MOUSEX
        sec
        sbc ORGX
        sta XL
        lda MOUSEX+1
        sbc ORGX+1
        sta XL+1
        lda MOUSEY
        sec
        sbc ORGY
        sta YL
        lda MOUSEY+1
        sbc ORGY+1
        sta YL+1
        lda CROW
        sta OLDROW
        jsr mcell
        cmp #1
        bne @n1
        lda TOPR                ; above: up a row
        beq @d
        sec
        sbc #1
        sta MROW
        jmp @cv
@n1:    cmp #2
        bne @n2
        lda TOPR                ; below: down a row
        clc
        adc #VIS
        cmp ROWS
        bcs @d
        sta MROW
        jmp @cv
@n2:    cmp #0
        bne @d
        jsr curv
        cmp MV
        bne @new
        lda MROW
        cmp CROW
        beq @d
        bne @new
@cv:    jsr curv
        sta MV
@new:   lda #1
        sta SELON
        lda MROW
        sta CROW
        lda MV
        jsr cxof
        sta CX
        jsr moved
        jmp @d
@end:   lda CLICKS              ; (the release is not a click)
@r:     rts

; --- Edit and Song menus ---------------------------------------------------------
; Routine XA for each cell of the block (P0 = the cell, BR / BV where)
forblock:
        sta BJ
        stx BJ+1
        jsr calcsel
        lda SV0
        sta BV
@v:     lda SR0
        sta BR
@r:     ldx BV
        ldy BR
        jsr cellptr
        jsr @call
        lda BR
        cmp SR1
        bcs @nv
        inc BR
        jmp @r
@nv:    lda BV
        cmp SV1
        bcs @e
        inc BV
        jmp @v
@e:     rts
@call:  jmp (BJ)

; Copy: the block (or the cell) -> BLK
m_copy: lda #<bcopy
        ldx #>bcopy
        jsr forblock
        lda SR1
        sec
        sbc SR0
        sta BLKR
        inc BLKR
        lda SV1
        sec
        sbc SV0
        sta BLKV
        inc BLKV
        rts
bcopy:  lda BV
        sec
        sbc SV0
        clc
        adc #>BLK
        sta P2+1
        lda BR
        sec
        sbc SR0
        asl
        asl
        sta P2
        ldy #3
@c:     lda (P0),y
        sta (P2),y
        dey
        bpl @c
        rts

; Cut: copied, then cleared
m_cut:  jsr m_copy
; Clear: the block's cells emptied
m_clear:
        lda #<bclear
        ldx #>bclear
blockchg:
        jsr forblock
        jsr changed
        jmp drawgrid
bclear: lda #0
        ldy #3
@c:     sta (P0),y
        dey
        bpl @c
        rts

; Transpose: the block's notes a semitone up / down
m_tup:  lda #1
        bne trans
m_tdown:
        lda #$FF
trans:  sta TDIR
        lda #<btrans
        ldx #>btrans
        jmp blockchg
btrans: ldy #0
        lda (P0),y
        beq @r
        cmp #$FF
        beq @r
        clc
        adc TDIR
        beq @r                  ; (1 - 1, 127 + 1: left as they are)
        bmi @r
        sta (P0),y
@r:     rts

; Select all: every row of the three voices
m_selall:
        lda ROWS
        sec
        sbc #1
        sta AROW
        lda #2
        sta AVC
        lda #1
        sta SELON
        lda CROW
        sta OLDROW
        lda #0
        sta CROW
        sta CX
        jmp moved

; Paste: the copied block, its top left at the cursor (voices that have
; pattern 0 get a new pattern)
m_paste:
        lda BLKR
        beq @r
        jsr curv
        sta TV0
        lda #0
        sta BV
@v:     lda BV
        clc
        adc TV0
        cmp #3
        bcs @done
        sta VT
        jsr vpage
        bcs @done
        sta P0+1
        lda #0
        sta BR
@rw:    lda BR
        clc
        adc CROW
        cmp ROWS
        bcs @nv
        asl
        asl
        sta P0
        lda BR
        asl
        asl
        sta P2
        lda BV
        clc
        adc #>BLK
        sta P2+1
        ldy #3
@c:     lda (P2),y
        sta (P0),y
        dey
        bpl @c
        inc BR
        lda BR
        cmp BLKR
        bcc @rw
@nv:    inc BV
        lda BV
        cmp BLKV
        bcc @v
@done:  jsr changed
        jmp redraw
@r:     rts

; A = the page of voice VT's pattern in this order (a new one if it was
; 0); carry set if there is no pattern left
vpage:  lda CURORD
        jsr ordptr
        ldy VT
        lda (P1),y
        bne @ok
        jsr freepat
        bcs @r
        pha
        lda CURORD
        jsr ordptr
        pla
        ldy VT
        sta (P1),y
@ok:    clc
        adc #>PAT
        clc
@r:     rts

; Insert row: this voice's rows from the cursor on move down one
m_insrow:
        jsr editcell
        bcs @r
        lda P0                  ; (P0 low = the cursor's offset)
        sta TMP
        lda #0
        sta P0
        ldy #251
@mv:    cpy TMP
        bcc @d
        lda (P0),y
        iny
        iny
        iny
        iny
        sta (P0),y
        dey
        dey
        dey
        dey
        dey
        cpy #$FF
        bne @mv
@d:     ldy TMP                 ; the cursor's row: empty
        lda #0
        sta (P0),y
        iny
        sta (P0),y
        iny
        sta (P0),y
        iny
        sta (P0),y
        jmp redraw
@r:     rts
; Delete row: this voice's rows below the cursor move up one
m_delrow:
        jsr editcell
        bcs @r
        ldy P0                  ; (P0 low = the cursor's offset)
        lda #0
        sta P0
@mv:    cpy #252
        bcs @e
        iny
        iny
        iny
        iny
        lda (P0),y
        dey
        dey
        dey
        dey
        sta (P0),y
        iny
        bne @mv
@e:     lda #0
        sta (P0),y
        iny
        sta (P0),y
        iny
        sta (P0),y
        iny
        sta (P0),y
        jmp redraw
@r:     rts

; Insert order: a copy of patterns 0 0 0 before this one
m_insord:
        lda #0
        beq insord
; Duplicate order: the same patterns after this one
m_dupord:
        lda #1
insord: sta TMP2
        lda NORD
        cmp #MAXORD
        bcs @r
        lda NORD                ; the orders from here move up one
        sta CNT
@m:     lda CNT
        cmp CURORD
        beq @mm
        bcc @mm
        sec
        sbc #1
        jsr ordptr
        ldy #2
@c:     lda (P1),y
        iny
        iny
        iny
        sta (P1),y
        dey
        dey
        dey
        dey
        bpl @c
        dec CNT
        jmp @m
@mm:    lda TMP2
        bne @dup
        lda CURORD              ; insert: silent
        jsr ordptr
        lda #0
        ldy #2
@z:     sta (P1),y
        dey
        bpl @z
        jmp @done
@dup:   inc CURORD              ; duplicate: shown, the copy
@done:  inc NORD
        lda LOOP
        cmp #$FF
        beq @l
        cmp CURORD
        bcc @l
        inc LOOP
@l:     jsr changed
        jmp redraw
@r:     rts

; Delete order (not the last one left)
m_delord:
        lda NORD
        cmp #2
        bcc @r
        lda CURORD
        sta CNT
@m:     lda CNT
        clc
        adc #1
        cmp NORD
        bcs @d
        lda CNT
        jsr ordptr
        ldy #0
@c:     iny
        iny
        iny
        lda (P1),y
        dey
        dey
        dey
        sta (P1),y
        iny
        cpy #3
        bne @c
        inc CNT
        bne @m
@d:     dec NORD
        lda LOOP
        cmp #$FF
        beq @f
        cmp NORD
        bcc @f
        lda #0
        sta LOOP
@f:     jsr fixcursor
        jsr changed
        jmp redraw
@r:     rts

; New pattern: this voice gets an unused one
m_newpat:
        jsr curpat
        jsr freepat
        bcs @r
        pha
        jsr curpat
        pla
        sta (P1),y
        jsr changed
        jmp redraw
@r:     lda #1
        sta BEEP
        rts

m_nextins:
        lda CINS
        cmp #32
        bcs @r
        inc CINS
@r:     jmp drawhdr
m_previns:
        lda CINS
        cmp #2
        bcc @r
        dec CINS
@r:     jmp drawhdr

; --- texts ----------------------------------------------------------------------
s_help:   .byte "Piano Z S X../Q 2 W.. 1=off  +/- octave  Enter=cell  "
          .byte "Shift=block  Space=play", 0
s_heads:  .byte "Ord ", 0
s_row:    .byte "Row", 0
s_vpat:   .byte "  pat ", 0
s_voice:  .byte "Voice ", 0
s_hspeed: .byte "Speed ", 0
s_hrows:  .byte "Rows ", 0
s_hloop:  .byte "Loop ", 0
s_hoct:   .byte "Oct ", 0
s_hins:   .byte "Ins ", 0
s_hplay:  .byte "PLAYING", 0
s_cellp:  .byte "Cell (note ins effect, e.g. C-4 01 A37):", 0
s_badcell: .byte "Not a cell: a note (C-4, C#4, --- or ===),", 13
           .byte "then an instrument (2 hex digits or ..), then an", 13
           .byte "effect (A S V L T J B P + 2 hex digits, or ...).", 0

