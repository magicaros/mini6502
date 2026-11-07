;=============================================================================
; tk5.asm - mini6502 desktop toolkit, bank $19: the file dialog
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Reached through the dispatcher in bank $10 (function 24). Its controls
; are records 16-19 (window DLGWIN); the directory goes to bank $1A.
; See README.txt.
;=============================================================================

        .include "tk.inc"
        .include "ctl.inc"

DIRBUF  = $E000         ; in bank $1A: the directory (disk command 7)
DIREND  = $EC00
NAMES   = $EC00         ; in bank $1A: the names shown (strings)
NAMESEND = $EFFF
STUB    = $C2F0         ; fixed RAM (toolkit's): DIR with bank $1A selected

        .org $E000
        jmp t_filedlg           ; $E000  24 FILEDIALOG

; the other banks' routines
ctlshow:  FAR TKBANK3, T3_SHOW
ctlinit:  FAR TKBANK3, T3_INIT
ctldraw:  FAR TKBANK3, T3_DRAW
forget:   FAR TKBANK3, T3_FORGET
i_click:  FAR TKBANK4, T4_CLICK
i_key:    FAR TKBANK4, T4_KEY
i_idle:   FAR TKBANK4, T4_IDLE
setfocus: FAR TKBANK4, T4_SETFOCUS

; RX0..RY1 shrunk by 1 on each side
shrink: ADDW RX0, RX0, 1
        ADDW RY0, RY0, 1
        SUBW RX1, RX1, 1
        SUBW RY1, RY1, 1
        rts

;=============================================================================
; the file dialog
;=============================================================================

; FILEDIALOG: Y = 0 open, 1 save; r0 = the prompt, r1 = your buffer for the
; name (in: the name to start with; out: the name chosen, up to 40
; characters), r2 = an extension to show only ("TXT", 0 = every file).
; Carry clear: OK, the name is in your buffer. Carry set: Cancel.
t_filedlg:
        sty SAVING
        lda CBANK
        sta FCB
        MOVW FNAMEP, r1
        MOVW T0, r0             ; the prompt -> PRBUF
        LDW QP, PRBUF
        lda #60
        jsr fetchstr
        lda #0                  ; the filter -> EXTB (capitals)
        sta EXTB
        lda r2
        ora r2+1
        beq @nf
        MOVW T0, r2
        LDW QP, EXTB
        lda #3
        jsr fetchstr
        ldy #2
@up:    lda EXTB,y
        jsr upper
        sta EXTB,y
        dey
        bpl @up
@nf:    MOVW T0, r1             ; the name to start with -> NAMEB
        LDW QP, NAMEB
        lda #40
        jsr fetchstr
        lda #<ORIGP             ; the folder it starts in (Cancel goes
        ldx #>ORIGP             ; back there)
        jsr where
        jsr readdir             ; the names -> bank $1A
        lda FOCUS               ; (the program's focus, back afterwards;
        sta OLDFOC              ; meanwhile none, so its field is not
        lda #$FF                ; drawn again without it)
        sta FOCUS
        jsr dlgbuild
        jsr dlgdraw
        ldx #16                 ; Open: the list has the focus; Save: the name
        lda SAVING
        beq @foc
        ldx #17                 ; (its suggested name selected)
        lda C_FLAGS,x
        ora #F_SEL
        sta C_FLAGS,x
@foc:   jsr setfocus
        lda CLICKS
@loop:  jsr waitframe
        jsr i_idle
        lda KBDCR
        bpl @mouse
        lda KBD
        and #$7F
        ldy #0
        cmp #0
        bne @k
        ldy KBDEXT
@k:     cmp #27                 ; Esc: Cancel
        bne @nesc
        jmp @cancel
@nesc:  ldx #DLGWIN
        jsr i_key
        bcs @kn
        cmp #EV_CONTROL
        bne @loop
        jmp @ctl
@kn:    lda KCH                 ; Enter anywhere else: OK
        cmp #13
        bne @loop
        jmp @ok
@mouse: lda CLICKS
        and #1
        beq @loop
        jsr readmouse
        ldx #DLGWIN
        jsr i_click
        bcs @loop
        cmp #EV_CONTROL
        bne @loop
@ctl:   cpx #16                 ; the list
        bne @nl
        sty WHAT
        jsr curitem             ; A = 0 none, 1 a file, 2 a folder
        beq @lp
        cmp #2
        beq @fold
        jsr takename            ; a file: its name into the field
        lda WHAT
        cmp #1
        beq @lp                 ; (chosen: Enter or a double click opens it)
        jmp @ok
@fold:  lda WHAT                ; a folder: Enter or a double click goes in
        cmp #1
        beq @lp
        jsr enterdir
@lp:    jmp @loop
@nl:    cpx #17                 ; the field: Enter = OK
        bne @nfd
        cpy #13
        beq @ok
        jmp @loop
@nfd:   cpx #18
        beq @ok
@cancel:
        jsr dlgclose
        lda #<ORIGP             ; back to the folder it started in
        sta DNAME
        lda #>ORIGP
        sta DNAME+1
        lda #0
        sta DNLEN
        lda #9
        sta DCMD
        sec
        rts
@ok:    lda NAMEB               ; an empty name: not yet
        bne @name
        lda #1
        sta BEEP
        jmp @loop
@name:  MOVW T0, FNAMEP         ; the name -> the caller's buffer
        lda CBANK
        pha
        lda FCB
        sta CBANK
        jsr farptr
        pla
        sta CBANK
        lda #1
        sta PBSTEP
        ldy #0
@cp:    lda NAMEB,y
        sta PBDATA
        beq @cpd
        iny
        bne @cp
@cpd:   jsr dlgclose
        clc
        rts

; LBUF (a file's name, from curitem) -> NAMEB, and the field shows it
takename:
        ldy #0
@c:     lda LBUF,y
        sta NAMEB,y
        beq @e
        iny
        cpy #40
        bne @c
        lda #0
        sta NAMEB,y
@e:     ldx #17                 ; (selected: typing replaces it)
selname:
        lda C_FLAGS,x
        ora #F_SEL
        sta C_FLAGS,x
        jmp ctlshow

; The list's chosen item -> LBUF (without a folder's "/"); A = 0 none, 1 a
; file, 2 a folder (or "..")
curitem:
        ldx #16
        stx CI
        lda C_VALH,x
        beq @some
        lda #0
        rts
@some:  lda C_VALL,x
        jsr listseek
        ldy #0
@c:     lda PBDATA
        sta LBUF,y
        beq @e
        iny
        cpy #63
        bne @c
        lda #0
        sta LBUF,y
@e:     cpy #0
        beq @file
        lda LBUF-1,y            ; "NAME/": a folder
        cmp #'/'
        bne @dots
        lda #0
        sta LBUF-1,y
        lda #2
        rts
@dots:  cpy #2                  ; "..": up
        bne @file
        lda LBUF
        cmp #'.'
        bne @file
        lda LBUF+1
        cmp #'.'
        bne @file
        lda #2
        rts
@file:  lda #1
        rts

; Into the folder in LBUF (or up): its names listed, the path shown
enterdir:
        lda #<LBUF
        sta DNAME
        lda #>LBUF
        sta DNAME+1
        lda #0
        sta DNLEN
        lda #9
        sta DCMD
        jsr readdir
        ldx #16                 ; the list: the new names, none chosen
        lda NNAMES
        sta C_MAXL,x
        lda #0
        sta C_MAXH,x
        sta C_TOP,x
        lda #$FF
        sta C_VALL,x
        sta C_VALH,x
        jsr ctlshow
        jmp drawpath

; The current folder's path -> XA (WHERE)
where:  sta DSTART
        stx DSTART+1
        lda #13
        sta DCMD
        rts

; The current folder, bottom left: its path (the end of it if long)
PATHX   = DX + 20
PATHY   = DY + DH - 38
drawpath:
        jsr clipfull
        LDW RX0, PATHX
        LDW RY0, PATHY
        LDW RX1, PATHX + 21 * 8 - 1
        LDW RY1, PATHY + 15
        lda #0
        jsr fillrect
        ldx #0                  ; its length
@l:     lda CURP,x
        beq @e
        inx
        bne @l
@e:     txa                     ; 21 characters at most: the last ones
        sec
        sbc #21
        bcs @t
        lda #0
@t:     clc
        adc #<CURP
        sta TP
        lda #>CURP
        adc #0
        sta TP+1
        LDW T0, PATHX
        LDW T1, PATHY
        jsr moveto
        lda #0
        sta STYLE
        jmp drawstr

; The directory into bank $1A (disk command 7, through a stub in the fixed
; RAM that has bank $1A selected meanwhile); then the names that pass the
; filter, as strings from NAMES on -> NNAMES
readdir:
        lda #<CURP              ; where we are
        ldx #>CURP
        jsr where
        ldx #stubend - stub - 1
@s:     lda stub,x
        sta STUB,x
        dex
        bpl @s
        LDW DSTART, DIRBUF
        LDW DEND, DIREND
        jsr STUB
        lda #0
        sta NNAMES
        lda DSTAT
        beq @ok
        jmp @end
@ok:    lda PADR                ; (port A is the program's: kept)
        pha
        lda PADR+1
        pha
        lda PADR+2
        pha
        lda PSTEP
        pha
        lda #<NAMES             ; port A writes the names, port B reads the
        sta PADR                ; directory
        lda #>NAMES & $0F | (TKDIRBANK << 4) & $F0
        sta PADR+1
        lda #TKDIRBANK >> 4
        sta PADR+2
        lda #1
        sta PSTEP
        sta PBSTEP
        lda #<DIRBUF
        sta PBADR
        lda #>DIRBUF & $0F | (TKDIRBANK << 4) & $F0
        sta PBADR+1
        lda #TKDIRBANK >> 4
        sta PBADR+2
        LDW NROOM, NAMESEND - NAMES - 64
        lda CURP+1              ; in a folder: ".." first (up)
        beq @file
        lda #'.'
        sta PDATA
        sta PDATA
        lda #0
        sta PDATA
        inc NNAMES
@file:  ldy #0                  ; a name -> LBUF
@n:     lda PBDATA
        sta LBUF,y
        beq @got
        iny
        cpy #63
        bne @n
@skip:  lda PBDATA
        bne @skip
@got:   cpy #0                  ; (an empty name: the end)
        beq @done
        sty TMPB
        lda PBDATA              ; size: $FFFFFE for a folder
        cmp #$FE
        bne @nf
        lda PBDATA
        cmp #$FF
        bne @nf1
        lda PBDATA
        cmp #$FF
        bne @nf2
        lda PBDATA              ; (load address: skipped)
        lda PBDATA
        lda #'/'                ; a folder: "NAME/", whatever the filter
        sta LBUF,y
        iny
        lda #0
        sta LBUF,y
        jmp @keep
@nf:    lda PBDATA
@nf1:   lda PBDATA
@nf2:   lda PBDATA
        lda PBDATA
        jsr filter
        bcc @keep
        jmp @file
@keep:
        ldy #0                  ; written out
@w:     lda LBUF,y
        sta PDATA
        beq @wd
        iny
        bne @w
@wd:    inc NNAMES
        lda NNAMES
        cmp #255
        beq @done
        tya                     ; room left?
        sec
        adc #0
        sta T0
        lda NROOM
        sec
        sbc T0
        sta NROOM
        lda NROOM+1
        sbc #0
        sta NROOM+1
        bcc @done
        jmp @file
@done:  pla
        sta PSTEP
        pla
        sta PADR+2
        pla
        sta PADR+1
        pla
        sta PADR
@end:   rts

stub:   lda #TKDIRBANK          ; (copied to STUB in the fixed RAM)
        sta BANK
        lda #7                  ; DIR into memory
        sta DCMD
        lda #TKBANK5
        sta BANK
        rts
stubend:

; Carry clear if the name in LBUF (length TMPB) ends with "." + EXTB (or
; there is no filter)
filter: lda EXTB
        beq @yes
        ldx #0                  ; the extension's length
@el:    lda EXTB,x
        beq @ee
        inx
        cpx #3
        bne @el
@ee:    stx T0
        lda TMPB                ; the dot: length - extension - 1
        sec
        sbc T0
        bcc @no
        beq @no
        tay
        dey
        lda LBUF,y
        cmp #'.'
        bne @no
        iny
        ldx #0
@c:     cpx T0
        beq @yes
        lda LBUF,y
        jsr upper
        cmp EXTB,x
        bne @no
        iny
        inx
        bne @c
@yes:   clc
        rts
@no:    sec
        rts

upper:  cmp #'a'
        bcc @r
        cmp #'z'+1
        bcs @r
        and #$DF
@r:     rts

; The dialog's controls (16 list, 17 name, 18 OK, 19 Cancel), its box
DW      = 400
DH      = 280
DX      = (640 - DW) / 2
DY      = (396 - DH) / 2
dlgbuild:
        LDW DLGOX, DX
        LDW DLGOY, DY
        lda #DLGWIN
        sta KWIN
        lda CBANK               ; (their texts are in this bank)
        pha
        lda #TKBANK5
        sta CBANK
        lda #CK_LIST
        sta KKIND
        LDW r0, 20
        LDW r1, 36
        LDW r2, DW - 21
        LDW r3, 36 + 4 + 16 * 9 - 1
        LDW r4, NAMES
        lda NNAMES
        sta r5
        lda #0
        sta r5+1
        ldx #16
        jsr ctlinit
        ldx #16
        lda #TKDIRBANK          ; (the names are in bank $1A)
        sta C_BANK,x
        lda #CK_FIELD
        sta KKIND
        LDW r0, 20
        LDW r1, 196
        LDW r2, DW - 21
        LDW r3, 196 + 21
        LDW r4, NAMEB
        LDW r5, 40
        ldx #17
        jsr ctlinit
        lda #CK_BUTTON
        sta KKIND
        LDW r0, DW - 201
        LDW r1, DH - 42
        LDW r2, DW - 121
        LDW r3, DH - 21
        LDW r4, s_open
        lda SAVING
        beq @o
        LDW r4, s_save
@o:     ldx #18
        jsr ctlinit
        LDW r0, DW - 101
        LDW r2, DW - 21
        LDW r4, s_cancel
        ldx #19
        jsr ctlinit
        pla
        sta CBANK
        rts
s_open:   .byte "Open", 0
s_save:   .byte "Save", 0
s_cancel: .byte "Cancel", 0

; the box (what is under it saved on page 1), the prompt, the controls
dlgdraw:
        jsr clipfull
        jsr dlgrect
        ADDW RX1, RX1, 2        ; (with its shadow)
        ADDW RY1, RY1, 2
        jsr saveunder
        jsr dlgrect
        ADDW RX0, RX0, 2        ; the shadow
        ADDW RY0, RY0, 2
        ADDW RX1, RX1, 2
        ADDW RY1, RY1, 2
        lda #1
        jsr fillrect
        jsr dlgrect
        lda #0
        jsr fillrect
        jsr framerect
        jsr dlgrect
        ADDW RX0, RX0, 3
        ADDW RY0, RY0, 3
        SUBW RX1, RX1, 3
        SUBW RY1, RY1, 3
        jsr framerect
        LDW T0, DX + 20         ; the prompt
        LDW T1, DY + 14
        jsr moveto
        lda #0
        sta STYLE
        LDW TP, PRBUF
        jsr drawstr
        ldx #16
@d:     stx CJ
        jsr ctldraw
        ldx CJ
        inx
        cpx #20
        bne @d
        ldx #18                 ; OK is the default: a thick frame
        jsr ctlrect
        SUBW RX0, RX0, 3
        SUBW RY0, RY0, 3
        ADDW RX1, RX1, 3
        ADDW RY1, RY1, 3
        jsr framerect
        jsr shrink
        jsr framerect
        jmp drawpath

dlgrect:
        LDW RX0, DX
        LDW RY0, DY
        LDW RX1, DX + DW - 1
        LDW RY1, DY + DH - 1
        rts

; the box away (page 1 back), its controls gone, the program's focus back
dlgclose:
        jsr clipfull
        jsr dlgrect
        ADDW RX1, RX1, 2
        ADDW RY1, RY1, 2
        jsr restunder
        ldx #16
@f:     jsr forget
        inx
        cpx #20
        bne @f
        lda OLDFOC
        sta FOCUS
        lda #$FF
        sta REPCTL
        lda CLICKS
        rts

        .include "ctlgeo.inc"
        .include "common.inc"
        .include "win.inc"

SAVING: .res 1
WHAT:   .res 1
CURP:   .res 132                ; the current folder's path
ORIGP:  .res 132                ; the folder the dialog started in
FCB:    .res 1
FNAMEP: .res 2
OLDFOC: .res 1
NNAMES: .res 1
NROOM:  .res 2
EXTB:   .res 4
PRBUF:  .res 61
NAMEB:  .res 64
LBUF:   .res 64
        .assert * <= $F000, error, "TK5 must fit in its bank"
