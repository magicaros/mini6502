;=============================================================================
; note.asm - NOTE, the mini6502 desktop's text editor (a toolkit program)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
;
; Two parts, from one source (note.cfg makes both):
;   NOTE   the program for a bank ($E000): menus, files, dialogs, find,
;          the clipboard; it loads NOTE2 at start
;   NOTE2  main RAM $0800-$17FF: the text itself (editing, moving, the
;          selection, drawing)
; The text is in the main RAM, $1800-$BFFF (43,008 bytes), lines ending
; with CR. The clipboard is the system's: banks $1C-$1F (see README.txt).
;=============================================================================

        .include "tk.inc"

TOOL    = $CC88                 ; far-call entry 16: the toolkit
.macro  TK fn
        lda #fn
        jsr TOOL
.endmacro

TEXT    = $1800                 ; the text: TEXT .. TEND-1
LIMIT   = $C000
CLIPLEN = $01C000               ; the clipboard (banks $1C-$1F): its length
CLIPDAT = $01C002               ;   (2 bytes), then the bytes
CLIPMAX = 16382
ROWS    = 21                    ; lines shown
COLS    = 76                    ; columns shown
TXO     = 4                     ; the text inside the window's contents
TYO     = 1
STATUSY = ROWS * 16 + TYO + 1   ; the status line (contents y), a line
                                ; above it
BARX    = 617                   ; the scroll bar (contents coordinates)
NAMEIN  = $EF80                 ; start at $E006: the file to open (name, 0)
CR      = 13

; zero page ($80-$FF is the program's)
P0      = $80                   ; pointers
P1      = $82
P2      = $84
CUR     = $86                   ; the caret (an address in the text)
SELA    = $88                   ; the other end of the selection
TEND    = $8A                   ; the end of the text
TOP     = $8C                   ; the first line shown, its number
TOPLN   = $8E
NLINES  = $90                   ; lines in the text (CRs + 1)
SELS    = $92                   ; the selection, start / end (empty: equal)
SELE    = $94
N16     = $96
ORGX    = $98                   ; the text's top left on the screen
ORGY    = $9A
XL      = $9C                   ; signed position, for the mouse
YL      = $9E
DA      = $A0
DB      = $A2
BARM    = $A4                   ; what the scroll bar shows
BARV    = $A6
DS      = $A8                   ; DMA: source (3), destination (3), length
DD      = $AB
DL      = $AE
LEFT    = $B0                   ; the first column shown
ROW     = $B1
CROW    = $B2                   ; the caret's row ($FF: not shown), column
CCOL    = $B3
OROW    = $B4                   ; the caret's row when last drawn
ALL     = $B5                   ; everything must be drawn again
DIRTY   = $B6                   ; changed since loaded / saved
WIN     = $B7
BAR     = $B8
CNT     = $B9
CH      = $BA
EXT     = $BB
SHIFT   = $BC
GOAL    = $BD                   ; the column up / down aim for
OSEL    = $BE                   ; a selection was shown
ENDF    = $BF
CLKY    = $C0
FLEN    = $C1
MAINSP  = $C2
TMP     = $C3
SCRL    = $C4                   ; scrolled while dragging
PGC     = $C5                   ; PgUp / PgDn: lines to go
STL     = $C6                   ; the status line: its length so far
SCAPS   = $C7                   ; CAPS as last shown
DCNT    = $C8

;=============================================================================
; NOTE: the bank part
;=============================================================================
        .segment "BANK"

        jmp start               ; $E000 an empty text
        .byte "TK"              ; $E003 a toolkit program (for the desktop)
        .byte 0
        jmp startfile           ; $E006 the file named at NAMEIN

start:  lda #0
        sta NAMEIN
startfile:
        tsx                     ; (EXIT returns from here)
        stx MAINSP
        TK TK_INIT
        lda #<s_note2           ; the other part: NOTE2 at $0800
        sta DNAME
        lda #>s_note2
        sta DNAME+1
        lda #0
        sta DNLEN
        sta DEND
        sta DEND+1
        lda #1
        sta DCMD
        lda DSTAT
        beq @ok
        lda #<s_note2p          ; or in NOTE's own folder
        sta DNAME
        lda #>s_note2p
        sta DNAME+1
        lda #1
        sta DCMD
        lda DSTAT
        beq @ok
        LDW r0, s_nonote2
        LDW r1, 0
        TK TK_ALERT
        TK TK_EXIT
        rts
@ok:    jsr textinit
        LDW r0, menus
        TK TK_MENUBAR
        LDW r0, 2               ; the window: almost the whole screen
        LDW r1, 22
        LDW r2, 637
        LDW r3, 397
        LDW r4, s_untitled
        TK TK_OPENWIN
        stx WIN
        LDW r0, BARX            ; its scroll bar
        LDW r1, 0
        LDW r2, BARX + 16
        LDW r3, ROWS * 16 + TYO - 1     ; (the status line below it)
        LDW r4, ROWS - 1
        LDW r5, 0
        ldy #CK_SCROLL
        TK TK_NEWCTL
        stx BAR
        lda #0
        sta FNAME
        jsr settitle
        lda NAMEIN              ; a file to open?
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

; --- the event loop -------------------------------------------------------------
loop:   TK TK_POLLEVENT
        bne @ev
        lda KBDFLAGS            ; nothing: CAPS switched (F6)? The status
        and #1                  ; line says so
        cmp SCAPS
        beq @wait
        jsr view
@wait:  lda FRAME
@wf:    cmp FRAME
        beq @wf
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
        jsr drawupd
        jmp loop
@n3:    cmp #EV_CLICK
        bne @n4
        cpx WIN
        bne loop
        jsr click
        jmp loop
@n4:    cmp #EV_WHEEL
        bne @n5
        jsr wheel
        jmp loop
@n5:    cmp #EV_CONTROL
        bne @n6
        cpx BAR
        bne loop
        MOVW DA, r0
        jsr scrollto
        jmp loop
@n6:    cmp #EV_CLOSE
        bne loop
        cpx WIN
        bne loop
        jmp quit

; --- menus ---------------------------------------------------------------------------
menu:   txa                     ; menu * 8 + item -> the table
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
        .byte $08
        .word new-1
        .byte $09
        .word open-1
        .byte $0B
        .word save-1
        .byte $0C
        .word saveas-1
        .byte $0E
        .word quit-1
        .byte $10
        .word cut-1
        .byte $11
        .word copy-1
        .byte $12
        .word paste-1
        .byte $13
        .word clear-1
        .byte $15
        .word selall-1
        .byte $18
        .word find-1
        .byte $19
        .word findnext-1
        .byte $FF

menus:  .byte "mini6502", 0, "About NOTE...", 0, 0
        .byte "File", 0, "New/N", 0, "Open.../O", 0, "-", 0, "Save/S", 0
        .byte "Save as...", 0, "-", 0, "Quit/Q", 0, 0
        .byte "Edit", 0, "Cut/X", 0, "Copy/C", 0, "Paste/V", 0, "Clear", 0
        .byte "-", 0, "Select all/A", 0, 0
        .byte "Search", 0, "Find.../F", 0, "Find next/G", 0, 0
        .byte 0

about:  LDW r0, s_about
        LDW r1, 0
        TK TK_ALERT
        rts

; --- files ------------------------------------------------------------------------------
new:    jsr askchanges
        bcs @r
        jsr textinit
        lda #0
        sta FNAME
        jsr settitle
        jsr drawnow
@r:     rts

open:   jsr askchanges
        bcs @r
        ldx #0                  ; the dialog starts with the current name
@c:     lda FNAME,x
        sta NAMEB,x
        beq @d
        inx
        bne @c
@d:     LDW r0, s_openp
        LDW r1, NAMEB
        LDW r2, 0
        ldy #0
        TK TK_FILEDIALOG
        bcs @r
        jmp loadname
@r:     rts

; NAMEB -> the text; an alert if it could not be
loadname:
        lda #<NAMEB
        sta DNAME
        lda #>NAMEB
        sta DNAME+1
        lda #0
        sta DNLEN
        LDW DSTART, TEXT
        LDW DEND, LIMIT
        lda #3
        sta DCMD
        lda DSTAT
        beq @ok
        ldx #<s_noload
        ldy #>s_noload
        cmp #3
        bne @a
        ldx #<s_toobig
        ldy #>s_toobig
@a:     stx r0
        sty r0+1
        LDW r1, 0
        TK TK_ALERT
        sec
        rts
@ok:    MOVW TEND, DEND
        jsr loaded              ; LF -> CR, lines counted, from the top
        ldx #0
@c:     lda NAMEB,x
        sta FNAME,x
        beq @t
        inx
        bne @c
@t:     jsr settitle
        jsr drawnow
        clc
        rts

save:   lda FNAME
        bne savefile
        jmp saveas
; the text -> FNAME; carry set if not saved
savefile:
        lda TEND
        cmp #<TEXT
        bne @go
        lda TEND+1
        cmp #>TEXT
        bne @go
        LDW r0, s_empty         ; nothing to save
        jmp @fail
@go:    lda #<FNAME
        sta DNAME
        lda #>FNAME
        sta DNAME+1
        lda #0
        sta DNLEN
        LDW DSTART, TEXT
        MOVW DEND, TEND
        lda #2
        sta DCMD
        lda DSTAT
        beq @ok
        LDW r0, s_nosave
@fail:  LDW r1, 0
        TK TK_ALERT
        sec
        rts
@ok:    lda #0
        sta DIRTY
        jsr settitle
        jsr view                ; (the status line: unmodified)
        clc
        rts

; Save as: carry set if not saved
saveas: ldx #0
        lda FNAME
        bne @c
@u:     lda s_defname,x         ; (no name yet)
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
        LDW r2, 0
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

; Changed? Then save first, or not, or Cancel: carry set = cancelled
askchanges:
        lda DIRTY
        bne @ask
        clc
        rts
@ask:   ldy #0                  ; "Save the changes to NAME?"
        ldx #0
@a:     lda s_ask1,x
        beq @n
        sta MSGB,y
        iny
        inx
        bne @a
@n:     jsr nameto
        ldx #0
@b:     lda s_ask2,x
        sta MSGB,y
        beq @go
        iny
        inx
        bne @b
@go:    LDW r0, MSGB
        LDW r1, s_askbtn
        TK TK_ALERT
        cmp #1                  ; Don't save
        beq @no
        cmp #0
        bne @cancel
        jmp save                ; Save (carry from it)
@no:    clc
        rts
@cancel:
        sec
        rts

; The file's name (or "Untitled") -> MSGB,Y (Y moves on)
nameto: ldx #0
        lda FNAME
        bne @c
@u:     lda s_untitled,x
        beq @r
        sta MSGB,y
        iny
        inx
        bne @u
@c:     lda FNAME,x
        beq @r
        sta MSGB,y
        iny
        inx
        cpx #20
        bne @c
@r:     rts

; The window's title: the name, " *" when changed
settitle:
        ldy #0
        jsr nameto
        lda DIRTY
        beq @e
        lda #' '
        sta MSGB,y
        iny
        lda #'*'
        sta MSGB,y
        iny
@e:     lda #0
        sta MSGB,y
        LDW r0, MSGB
        ldx WIN
        TK TK_SETTITLE
        rts

quit:   jsr askchanges
        bcs @r
        ldx MAINSP
        txs
        TK TK_EXIT
        rts                     ; to whoever started NOTE
@r:     rts

; --- the clipboard (banks $1C-$1F, shared by every program) ---------------------------
copy:   jsr calcsel
        bcs @r
        lda SELE                ; length = SELE - SELS
        sec
        sbc SELS
        sta N16
        lda SELE+1
        sbc SELS+1
        sta N16+1
        lda N16                 ; too big for it?
        cmp #<(CLIPMAX + 1)
        lda N16+1
        sbc #>(CLIPMAX + 1)
        bcc @fits
        LDW r0, s_clipbig
        LDW r1, 0
        TK TK_ALERT
        sec
        rts
@fits:  MOVW DS, SELS           ; the bytes
        lda #$FF
        sta DS+2
        LDW DD, CLIPDAT & $FFFF
        lda #^CLIPDAT
        sta DD+2
        MOVW DL, N16
        jsr dmago
        lda #<N16               ; its length
        sta DS
        lda #>N16
        sta DS+1
        LDW DD, CLIPLEN & $FFFF
        lda #^CLIPLEN
        sta DD+2
        LDW DL, 2
        jsr dmago
        clc
@r:     rts

cut:    jsr copy
        bcs @r
        jmp clear
@r:     rts

clear:  jsr calcsel
        bcs @r
        jsr delsel
        jsr changed
        jmp refresh
@r:     rts

paste:  LDW DS, CLIPLEN & $FFFF ; its length -> N16
        lda #^CLIPLEN
        sta DS+2
        lda #<N16
        sta DD
        lda #>N16
        sta DD+1
        lda #$FF
        sta DD+2
        LDW DL, 2
        jsr dmago
        lda N16
        ora N16+1
        beq @r
        lda N16                 ; (never more than it holds)
        cmp #<(CLIPMAX + 1)
        lda N16+1
        sbc #>(CLIPMAX + 1)
        bcs @r
        jsr calcsel             ; it replaces the selection
        bcs @ns
        MOVW XL, N16
        jsr delsel
        MOVW N16, XL
@ns:    jsr insertn
        bcc @in
        jmp nospace
@in:    LDW DS, CLIPDAT & $FFFF
        lda #^CLIPDAT
        sta DS+2
        MOVW DD, CUR
        lda #$FF
        sta DD+2
        MOVW DL, N16
        jsr dmago
        MOVW P0, CUR            ; its lines
        lda CUR
        clc
        adc N16
        sta CUR
        sta P1
        lda CUR+1
        adc N16+1
        sta CUR+1
        sta P1+1
        jsr countcr
        jsr addlines
        MOVW SELA, CUR
        jsr changed
        jsr setgoal
        jmp refresh
@r:     rts

selall: LDW SELA, TEXT
        MOVW CUR, TEND
        lda #1
        sta ALL
        jmp refresh

nospace:
        LDW r0, s_full
        LDW r1, 0
        TK TK_ALERT
        rts

; --- find ------------------------------------------------------------------------------
find:   LDW r0, s_findp
        LDW r1, FINDB
        LDW r2, 40
        TK TK_ASK
        bcs @r
        lda FINDB
        bne findnext
@r:     rts

; The next place with FINDB (any case), after the caret or the selection,
; going round from the top: selected
findnext:
        ldx #0
@l:     lda FINDB,x
        beq @ln
        inx
        bne @l
@ln:    stx FLEN
        cpx #0
        beq find
        jsr calcsel             ; from the end of the selection, or the caret
        MOVW P0, CUR
        bcs @from
        MOVW P0, SELE
@from:  MOVW DA, P0             ; (where it started)
        lda TEND                ; last start: TEND - FLEN
        sec
        sbc FLEN
        sta P1
        lda TEND+1
        sbc #0
        sta P1+1
        MOVW DB, P1
        jsr search              ; P0 .. P1
        bcc @found
        LDW P0, TEXT            ; then from the top, up to where it
        MOVW P1, DA             ; started (or the last start)
        lda DB
        cmp P1
        lda DB+1
        sbc P1+1
        bcs @p1
        MOVW P1, DB
@p1:
        jsr search
        bcc @found
        LDW r0, s_notfound
        LDW r1, 0
        TK TK_ALERT
        rts
@found: MOVW SELA, P0
        lda P0
        clc
        adc FLEN
        sta CUR
        lda P0+1
        adc #0
        sta CUR+1
        lda #1
        sta ALL
        jsr setgoal
        jmp refresh

; FINDB at P0, P0+1 ... up to P1: carry clear and P0 = where
search:
@l:     lda P1                  ; past P1: not there
        cmp P0
        lda P1+1
        sbc P0+1
        bcc @no
        ldy #0
@c:     lda (P0),y
        jsr upper
        sta TMP
        lda FINDB,y
        jsr upper
        cmp TMP
        bne @next
        iny
        cpy FLEN
        bne @c
        clc
        rts
@next:  inc P0
        bne @l
        inc P0+1
        bne @l
@no:    sec
        rts
upper:  cmp #'a'
        bcc @r
        cmp #'z' + 1
        bcs @r
        and #$DF
@r:     rts

; --- texts ------------------------------------------------------------------------------------
s_note2:   .byte "NOTE2", 0
s_note2p:  .byte "/NOTE/NOTE2", 0
s_nonote2: .byte "NOTE2 is not on the disk: NOTE needs it.", 0
s_untitled: .byte "Untitled", 0
s_defname: .byte "UNTITLED.TXT", 0
s_about:   .byte "NOTE - a text editor", 13, 13
           .byte "Drag to select, Shift + arrows too. Cut, Copy and", 13
           .byte "Paste go through the clipboard every program shares.", 13
           .byte "Search/Find looks for a word, any case.", 13, 13
           .byte "(C) 2026 Benoit Colson - GNU GPL 3", 13
           .byte "With the help of Claude AI.", 0
s_openp:   .byte "Open which text?", 0
s_savep:   .byte "Save the text as:", 0
s_noload:  .byte "That file could not be opened.", 0
s_toobig:  .byte "That file is too big for NOTE (43,008 bytes at most).", 0
s_nosave:  .byte "The text could not be saved (is the name valid?).", 0
s_empty:   .byte "There is no text to save.", 0
s_ask1:    .byte "Save the changes to ", 0
s_ask2:    .byte "?", 0
s_askbtn:  .byte "Save|Don't save|Cancel", 0
s_clipbig: .byte "The clipboard holds 16,382 characters at most.", 0
s_full:    .byte "The text is full (43,008 characters).", 0
s_findp:   .byte "Find:", 0
s_notfound: .byte "Not found.", 0

FNAME:  .res 64                 ; the file's name (empty: none yet)
NAMEB:  .res 64                 ; names for the dialogs
FINDB:  .res 42                 ; what Find looks for
MSGB:   .res 80                 ; alerts, the title

;=============================================================================
; NOTE2: the text (main RAM, $0800)
;=============================================================================
        .segment "LOW"

; An empty text, from the top
textinit:
        LDW TEND, TEXT
loaded: ldx #0                  ; (loaded: LF and CR LF -> CR)
        LDW P0, TEXT
        LDW P1, TEXT
@l:     lda P0                  ; P0 reads, P1 writes
        cmp TEND
        lda P0+1
        sbc TEND+1
        bcs @e
        ldy #0
        lda (P0),y
        cmp #10
        bne @w
        cpx #CR                 ; LF after CR: dropped
        beq @skip
        lda #CR
@w:     sta (P1),y
        tax
        inc P1
        bne @n
        inc P1+1
        jmp @n
@skip:  ldx #0
@n:     inc P0
        bne @l
        inc P0+1
        bne @l
@e:     MOVW TEND, P1
        LDW P0, TEXT            ; lines: CRs + 1
        MOVW P1, TEND
        jsr countcr
        ADDW NLINES, N16, 1
        LDW CUR, TEXT
        LDW SELA, TEXT
        LDW TOP, TEXT
        lda #0
        sta TOPLN
        sta TOPLN+1
        sta LEFT
        sta GOAL
        sta DIRTY
        sta OSEL
        lda #1
        sta ALL
        lda #$FF
        sta OROW
        sta BARM                ; (the scroll bar: set again)
        sta BARM+1
        rts

; --- events ------------------------------------------------------------------------------
; A key: X = character, or 0 and Y = its KBDEXT code
key:    stx CH
        sty EXT
        lda #140                ; Shift held?
        sta KEYSEL
        lda KEYHELD
        sta SHIFT
        lda CH
        bne @char
        lda EXT
        cmp #10                 ; Delete
        beq @del
        cmp #9
        bcs @r
        tax
        dex
        bmi @r
        txa
        asl
        tax
        lda movetab+1,x
        pha
        lda movetab,x
        pha
@r:     rts
@del:   jsr calcsel
        bcc @ds
        lda CUR                 ; the character after the caret
        cmp TEND
        lda CUR+1
        sbc TEND+1
        bcs @r
        MOVW DA, CUR
        ADDW DB, CUR, 1
        jsr delrange
        jmp @done
@ds:    jsr delsel
@done:  jsr changed
        jsr setgoal
        jmp refresh
@char:  cmp #8                  ; Backspace
        bne @tab
        jsr calcsel
        bcc @ds
        lda CUR
        cmp #<TEXT
        bne @bs
        lda CUR+1
        cmp #>TEXT
        beq @r
@bs:    SUBW DA, CUR, 1
        MOVW DB, CUR
        jsr delrange
        jmp @done
@tab:   cmp #9                  ; Tab: spaces to the next column of 8
        bne @ent
        jsr calcsel
        bcs @t1
        jsr delsel
@t1:    jsr colof
        and #7
        eor #7
        clc
        adc #1
        sta CNT
@t2:    lda #' '
        jsr typeone
        bcs @done
        dec CNT
        bne @t2
        jmp @done
@ent:   cmp #CR
        beq @type
        cmp #32
        bcc @no
        cmp #127
        bcc @type
@no:    rts
@type:  pha
        jsr calcsel
        bcs @t3
        jsr delsel
@t3:    pla
        jsr typeone
        jmp @done
movetab:
        .word m_up-1, m_down-1, m_left-1, m_right-1
        .word m_home-1, m_end-1, m_pgup-1, m_pgdn-1

; A typed at the caret; carry set if the text is full
typeone:
        pha
        LDW N16, 1
        jsr insertn
        pla
        bcs @full
        ldy #0
        sta (CUR),y
        cmp #CR
        bne @n
        inc NLINES
        bne @a
        inc NLINES+1
@a:     lda #1
        sta ALL
@n:     inc CUR
        bne @s
        inc CUR+1
@s:     MOVW SELA, CUR
        clc
        rts
@full:  jsr nospace
        sec
        rts

; --- moving the caret (Shift: the selection grows) --------------------------------------
m_left: lda CUR
        cmp #<TEXT
        bne @l
        lda CUR+1
        cmp #>TEXT
        beq moved
@l:     lda CUR
        bne @d
        dec CUR+1
@d:     dec CUR
        jmp movedh
m_right:
        lda CUR
        cmp TEND
        lda CUR+1
        sbc TEND+1
        bcs moved
        inc CUR
        bne movedh
        inc CUR+1
movedh: jsr setgoal             ; across: a new column to aim for
moved:  lda SHIFT
        bne @s
        MOVW SELA, CUR
@s:     jmp refresh
m_home: MOVW P0, CUR
        jsr linestart
        MOVW CUR, P0
        jmp movedh
m_end:  MOVW P0, CUR
        jsr lineend
        MOVW CUR, P0
        jmp movedh
m_up:   jsr up1
        jmp moved
m_down: jsr down1
        jmp moved
m_pgup: lda #ROWS - 1
        sta PGC
@l:     jsr up1
        dec PGC
        bne @l
        jmp moved
m_pgdn: lda #ROWS - 1
        sta PGC
@l:     jsr down1
        dec PGC
        bne @l
        jmp moved
; one line up / down, at the GOAL column (or the line's end)
up1:    MOVW P0, CUR
        jsr linestart
        lda P0
        cmp #<TEXT
        bne @u
        lda P0+1
        cmp #>TEXT
        beq @r
@u:     lda P0
        bne @d
        dec P0+1
@d:     dec P0
        jsr linestart
        lda GOAL
        jsr ptrat
        MOVW CUR, P0
@r:     rts
down1:  MOVW P0, CUR
        jsr nextline
        bcs @r
        lda GOAL
        jsr ptrat
        MOVW CUR, P0
@r:     rts
setgoal:
        jsr colof
        sta GOAL
        rts

; --- the mouse -----------------------------------------------------------------------------
; A click: r0 / r1 = where in the contents, Y = buttons ($81 double)
click:  sty CLKY
        lda r0                  ; on the text (the scroll bar is the
        cmp #<(BARX - 2)        ; toolkit's)?
        lda r0+1
        sbc #>(BARX - 2)
        bcc @in
        rts
@in:    SUBW XL, r0, TXO
        SUBW YL, r1, TYO
        jsr setport
        lda #140
        sta KEYSEL
        lda KEYHELD
        sta SHIFT
        jsr posat
        MOVW CUR, P0
        lda SHIFT
        bne @sh
        MOVW SELA, CUR
@sh:    lda CLKY
        bpl @drag
        jsr word                ; a double click: the word
        jmp @end
@drag:  jsr setgoal
        jsr view
@d:     lda BUTTONS             ; dragging: the selection follows
        and #1
        beq @end
        lda FRAME
@w:     cmp FRAME
        beq @w
        lda #0
        sta SCRL
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
        bpl @nup
        jsr lineup              ; above: scroll up
        jmp @pos
@nup:   lda YL                  ; below: scroll down
        cmp #<(ROWS * 16)
        lda YL+1
        sbc #>(ROWS * 16)
        bcc @pos
        jsr linedown
@pos:   jsr posat
        lda SCRL
        bne @new
        lda P0
        cmp CUR
        bne @new
        lda P0+1
        cmp CUR+1
        beq @d
@new:   MOVW CUR, P0
        jsr setgoal
        jsr view
        jmp @d
@end:   lda CLICKS              ; (the release is not a click)
        jsr setgoal
        jmp refresh

; The word around the caret: selected
word:   MOVW P0, CUR
@b:     lda P0                  ; back to its start
        cmp #<TEXT
        bne @b1
        lda P0+1
        cmp #>TEXT
        beq @fw
@b1:    SUBW P1, P0, 1
        ldy #0
        lda (P1),y
        jsr isword
        bcs @fw
        MOVW P0, P1
        jmp @b
@fw:    MOVW SELA, P0
        MOVW P0, CUR
@f:     lda P0                  ; on to its end
        cmp TEND
        lda P0+1
        sbc TEND+1
        bcs @e
        ldy #0
        lda (P0),y
        jsr isword
        bcs @e
        inc P0
        bne @f
        inc P0+1
        bne @f
@e:     MOVW CUR, P0
        lda #1
        sta ALL
        rts
; carry clear if A is a letter, a digit or _
isword: cmp #'_'
        beq @y
        cmp #'0'
        bcc @n
        cmp #'9' + 1
        bcc @y
        jsr upper
        cmp #'A'
        bcc @n
        cmp #'Z' + 1
        bcc @y
@n:     sec
        rts
@y:     clc
        rts

; P0 = the place at XL, YL (signed, from the text's top left)
posat:  lda YL+1                ; row: 0 .. ROWS - 1
        bpl @y0
        lda #0
        beq @row
@y0:    lda YL
        lsr YL+1
        ror
        lsr YL+1
        ror
        lsr YL+1
        ror
        lsr YL+1
        ror
        ldx YL+1
        bne @last
        cmp #ROWS
        bcc @row
@last:  lda #ROWS - 1
@row:   jsr rowstart
        lda XL+1                ; column: (x + 4) / 8, + LEFT
        bmi @x0
        lda XL
        clc
        adc #4
        sta XL
        bcc @xs
        inc XL+1
@xs:    lda XL
        lsr XL+1
        ror
        lsr XL+1
        ror
        lsr XL+1
        ror
        ldx XL+1
        bne @xmax
        clc
        adc LEFT
        bcc @col
@xmax:  lda #255
        bne @col
@x0:    lda LEFT
@col:   jmp ptrat

; The wheel: Y steps, 3 lines each
wheel:  tya
        bmi @up
        beq @r
        asl
        clc
        adc TOPLN
        sta DA
        lda TOPLN+1
        adc #0
        sta DA+1
        tya
        clc
        adc DA
        sta DA
        bcc @go
        inc DA+1
        bcs @go
@up:    eor #$FF                ; steps up: TOPLN - 3 * steps (0 at least)
        clc
        adc #1
        sta TMP
        asl
        adc TMP
        sta TMP
        lda TOPLN
        sec
        sbc TMP
        sta DA
        lda TOPLN+1
        sbc #0
        sta DA+1
        bcs @go
        lda #0
        sta DA
        sta DA+1
@go:    jmp scrollto
@r:     rts

; The view starts at line DA (kept in range); the caret stays where it is
scrollto:
        jsr maxtop              ; N16 = the last top line
        lda N16
        cmp DA
        lda N16+1
        sbc DA+1
        bcs @l
        MOVW DA, N16
@l:     lda TOPLN               ; down
        cmp DA
        lda TOPLN+1
        sbc DA+1
        bcs @up
        jsr linedown
        jmp @l
@up:    lda DA                  ; up
        cmp TOPLN
        lda DA+1
        sbc TOPLN+1
        bcs @done
        jsr lineup
        jmp @up
@done:  jmp view

; N16 = the highest TOPLN: NLINES - ROWS, 0 at least
maxtop: lda NLINES
        sec
        sbc #ROWS
        sta N16
        lda NLINES+1
        sbc #0
        sta N16+1
        bcs @r
        lda #0
        sta N16
        sta N16+1
@r:     rts

; The view one line up / down (SCRL set if it moved)
lineup: lda TOPLN
        ora TOPLN+1
        beq @r
        SUBW P0, TOP, 1
        jsr linestart
        MOVW TOP, P0
        lda TOPLN
        bne @d
        dec TOPLN+1
@d:     dec TOPLN
        lda #1
        sta ALL
        sta SCRL
@r:     rts
linedown:
        jsr maxtop
        lda TOPLN
        cmp N16
        lda TOPLN+1
        sbc N16+1
        bcs @r
        MOVW P0, TOP
        jsr nextline
        MOVW TOP, P0
        inc TOPLN
        bne @a
        inc TOPLN+1
@a:     lda #1
        sta ALL
        sta SCRL
@r:     rts

; --- changing the text ------------------------------------------------------------------------
; Room for N16 bytes at the caret (the rest moves up); carry set if full
insertn:
        lda TEND
        clc
        adc N16
        sta DB
        lda TEND+1
        adc N16+1
        sta DB+1
        bcs @full
        lda DB                  ; past LIMIT?
        cmp #<(LIMIT + 1)
        lda DB+1
        sbc #>(LIMIT + 1)
        bcs @full
        MOVW DS, CUR            ; CUR .. TEND -> CUR + N16
        lda CUR
        clc
        adc N16
        sta DD
        lda CUR+1
        adc N16+1
        sta DD+1
        lda TEND
        sec
        sbc CUR
        sta DL
        lda TEND+1
        sbc CUR+1
        sta DL+1
        lda #$FF
        sta DS+2
        sta DD+2
        lda DL
        ora DL+1
        beq @e
        jsr dmago
@e:     MOVW TEND, DB
        clc
        rts
@full:  sec
        rts

; The selection removed (calcsel first)
delsel: MOVW DA, SELS
        MOVW DB, SELE
; DA .. DB-1 removed; the caret goes there
delrange:
        MOVW P0, DA             ; its lines
        MOVW P1, DB
        jsr countcr
        lda N16
        ora N16+1
        beq @top
        lda #1
        sta ALL
        lda NLINES
        sec
        sbc N16
        sta NLINES
        lda NLINES+1
        sbc N16+1
        sta NLINES+1
@top:   lda DA                  ; starts above the view: the view starts
        cmp TOP                 ; at its line
        lda DA+1
        sbc TOP+1
        bcs @move
        MOVW P0, DA
        jsr linestart
        MOVW P2, P0
        MOVW P1, TOP
        jsr countcr
        lda TOPLN
        sec
        sbc N16
        sta TOPLN
        lda TOPLN+1
        sbc N16+1
        sta TOPLN+1
        MOVW TOP, P2
        lda #1
        sta ALL
@move:  MOVW DS, DB             ; DB .. TEND -> DA
        MOVW DD, DA
        lda TEND
        sec
        sbc DB
        sta DL
        lda TEND+1
        sbc DB+1
        sta DL+1
        lda #$FF
        sta DS+2
        sta DD+2
        lda DL
        ora DL+1
        beq @e
        jsr dmago
@e:     lda TEND                ; TEND -= DB - DA
        sec
        sbc DB
        sta TEND
        lda TEND+1
        sbc DB+1
        sta TEND+1
        lda TEND
        clc
        adc DA
        sta TEND
        lda TEND+1
        adc DA+1
        sta TEND+1
        MOVW CUR, DA
        MOVW SELA, DA
        rts

; NLINES += N16
addlines:
        lda NLINES
        clc
        adc N16
        sta NLINES
        lda NLINES+1
        adc N16+1
        sta NLINES+1
        lda N16
        ora N16+1
        beq @r
        lda #1
        sta ALL
@r:     rts

; The text was changed: the title says so
changed:
        lda DIRTY
        bne @r
        lda #1
        sta DIRTY
        jmp settitle
@r:     rts

; DMA: DL bytes from DS to DD (3-byte addresses: $FFxxxx = this memory)
dmago:  ldx #2
@c:     lda DS,x
        sta DMASRC,x
        lda DD,x
        sta DMASRC+3,x
        dex
        bpl @c
        lda DL
        sta DMASRC+6
        lda DL+1
        sta DMASRC+7
        lda #0
        sta DMASRC+8
        lda #1
        sta DMACMD
        rts

; --- lines ---------------------------------------------------------------------------------------
; P0 = the start of its line
linestart:
@l:     lda P0
        cmp #<TEXT
        bne @c
        lda P0+1
        cmp #>TEXT
        beq @r
@c:     lda P0
        bne @d
        dec P0+1
@d:     dec P0
        ldy #0
        lda (P0),y
        cmp #CR
        bne @l
        inc P0
        bne @r
        inc P0+1
@r:     rts

; P0 = the end of its line (its CR, or TEND)
lineend:
@l:     lda P0
        cmp TEND
        lda P0+1
        sbc TEND+1
        bcs @r
        ldy #0
        lda (P0),y
        cmp #CR
        beq @r
        inc P0
        bne @l
        inc P0+1
        bne @l
@r:     rts

; P0 = the start of the next line; carry set (P0 at TEND) if there is none
nextline:
        jsr lineend
        lda P0
        cmp TEND
        lda P0+1
        sbc TEND+1
        bcs @r
        inc P0
        bne @c
        inc P0+1
@c:     clc
@r:     rts

; P0 = A characters on from the line start P0 (or its end)
ptrat:  sta CNT
@l:     lda CNT
        beq @r
        lda P0
        cmp TEND
        lda P0+1
        sbc TEND+1
        bcs @r
        ldy #0
        lda (P0),y
        cmp #CR
        beq @r
        inc P0
        bne @n
        inc P0+1
@n:     dec CNT
        jmp @l
@r:     rts

; A = the caret's column (255 at most)
colof:  MOVW P0, CUR
        jsr linestart
        lda CUR
        sec
        sbc P0
        tax
        lda CUR+1
        sbc P0+1
        beq @r
        ldx #255
@r:     txa
        rts

; N16 = the CRs from P0 to P1 (P0 moves to P1)
countcr:
        lda #0
        sta N16
        sta N16+1
@l:     lda P0
        cmp P1
        lda P0+1
        sbc P1+1
        bcs @r
        ldy #0
        lda (P0),y
        cmp #CR
        bne @n
        inc N16
        bne @n
        inc N16+1
@n:     inc P0
        bne @l
        inc P0+1
        bne @l
@r:     rts

; P0 = the start of the line in row A (the last line if there are fewer)
rowstart:
        tax
        MOVW P0, TOP
@l:     cpx #0
        beq @r
        lda P0
        pha
        lda P0+1
        pha
        txa
        pha
        jsr nextline
        pla
        tax
        pla
        bcs @back
        pla
        dex
        jmp @l
@back:  sta P0+1
        pla
        sta P0
@r:     rts

; SELS / SELE from CUR and SELA; carry set if nothing is selected
calcsel:
        lda CUR
        cmp SELA
        lda CUR+1
        sbc SELA+1
        bcs @ca
        MOVW SELS, CUR
        MOVW SELE, SELA
        sec
        bcs @t
@ca:    MOVW SELS, SELA
        MOVW SELE, CUR
@t:     lda SELS
        cmp SELE
        bne @some
        lda SELS+1
        cmp SELE+1
        bne @some
        sec
        rts
@some:  clc
        rts

; --- showing it ------------------------------------------------------------------------------
; After a change or a move: the caret in view, then drawn
refresh:
        jsr ensure
; Drawn now (the window in front) or at its UPDATE
view:   jsr calcsel
        lda #0
        rol
        eor #1                  ; 1: something selected
        tax
        ora OSEL
        beq @ns
        lda #1
        sta ALL
@ns:    stx OSEL
        jsr calcrow
        ldx #$FF                ; in front?
        TK TK_FRONT
        cpx WIN
        beq @front
        ldx WIN
        TK TK_INVAL
        jmp syncbar
@front: jsr setport
        lda ALL
        beq @rows
        jsr drawall
        jmp @bar
@rows:  lda OROW                ; the caret's old row, its new one
        cmp CROW
        beq @cr
        cmp #ROWS
        bcs @cr
        sta ROW
        jsr rowstart
        MOVW P2, P0
        jsr drawrow
@cr:    lda CROW
        cmp #ROWS
        bcs @bar
        sta ROW
        jsr rowstart
        MOVW P2, P0
        jsr drawrow
@bar:   jsr status
        lda #0
        sta ALL
        lda CROW
        sta OROW
; The scroll bar shows TOPLN out of maxtop
syncbar:
        jsr maxtop
        lda N16
        cmp BARM
        bne @set
        lda N16+1
        cmp BARM+1
        bne @set
        lda TOPLN
        cmp BARV
        bne @val
        lda TOPLN+1
        cmp BARV+1
        beq @r
        bne @val
@set:   MOVW BARM, N16
        MOVW r1, N16
        LDW r0, 0
        ldx BAR
        TK TK_SETDATA
@val:   MOVW BARV, TOPLN
        MOVW r0, TOPLN
        ldx BAR
        TK TK_SETVALUE
@r:     rts

; Everything drawn now (after NEW, a load)
drawnow:
        lda #1
        sta ALL
        jmp refresh

; UPDATE: r0-r3 = the contents, the clip is set
drawupd:
        jsr orgset
        jsr calcsel
        jsr calcrow
        jsr drawall
        jsr status
        lda CROW
        sta OROW
        rts

; The caret in view: TOP / TOPLN / LEFT moved if needed
ensure: lda CUR                 ; above the view?
        cmp TOP
        lda CUR+1
        sbc TOP+1
        bcs @below
        MOVW P0, CUR
        jsr linestart
        MOVW P2, P0
        MOVW P1, TOP
        jsr countcr
        lda TOPLN
        sec
        sbc N16
        sta TOPLN
        lda TOPLN+1
        sbc N16+1
        sta TOPLN+1
        MOVW TOP, P2
        lda #1
        sta ALL
        jmp @h
@below: MOVW P0, TOP            ; under it?
        MOVW P1, CUR
        jsr countcr
        lda N16+1
        bne @down
        lda N16
        cmp #ROWS
        bcc @h
@down:  lda N16                 ; N16 - (ROWS - 1) lines down
        sec
        sbc #ROWS - 1
        sta DA
        lda N16+1
        sbc #0
        sta DA+1
@dl:    MOVW P0, TOP
        jsr nextline
        MOVW TOP, P0
        inc TOPLN
        bne @dd
        inc TOPLN+1
@dd:    lda DA
        bne @dx
        dec DA+1
@dx:    dec DA
        lda DA
        ora DA+1
        bne @dl
        lda #1
        sta ALL
@h:     jsr colof               ; sideways
        cmp LEFT
        bcs @right
        and #$F0
        sta LEFT
        lda #1
        sta ALL
        rts
@right: sec
        sbc LEFT
        cmp #COLS
        bcc @r
        jsr colof               ; LEFT = (col - COLS + 16) rounded to 16
        sec
        sbc #COLS - 16
        and #$F0
        sta LEFT
        lda #1
        sta ALL
@r:     rts

; CROW / CCOL: where the caret is drawn (CROW $FF: not in view)
calcrow:
        lda #$FF
        sta CROW
        lda CUR
        cmp TOP
        lda CUR+1
        sbc TOP+1
        bcc @r
        MOVW P0, TOP
        MOVW P1, CUR
        jsr countcr
        lda N16+1
        bne @r
        lda N16
        cmp #ROWS
        bcs @r
        sta CROW
        jsr colof
        sta CCOL
@r:     rts

; The clip = the window's contents; ORGX / ORGY
setport:
        ldx WIN
        TK TK_SETPORT
orgset: ADDW ORGX, r0, TXO
        ADDW ORGY, r1, TYO
        rts

; Every row
drawall:
        lda #0
        sta ROW
        MOVW P2, TOP
@r:     jsr drawrow
        lda P2+1                ; the next line's start
        cmp #$FF
        beq @n
        MOVW P0, P2
        jsr nextline
        bcc @ok
        lda #$FF
        sta P0+1
@ok:    MOVW P2, P0
@n:     inc ROW
        lda ROW
        cmp #ROWS
        bne @r
        rts

; Row ROW: the line starting at P2 (P2+1 = $FF: none)
drawrow:
        lda #R_SET
        sta ROP
        lda #0
        sta PATON
        lda ROW                 ; y = ORGY + ROW * 16
        asl
        asl
        asl
        asl
        sta TMP
        lda #0
        rol
        tax
        lda TMP
        clc
        adc ORGY
        sta BY0
        txa
        adc ORGY+1
        sta BY0H
        lda ORGX
        sta BX0
        lda ORGX+1
        sta BX0H
        lda #0
        sta ENDF
        MOVW P0, P2
        lda P2+1
        cmp #$FF
        bne @skip
        inc ENDF
        bne @go
@skip:  ldx LEFT                ; the columns left of the view
@sk:    beq @go
        lda P0
        cmp TEND
        lda P0+1
        sbc TEND+1
        bcs @go
        ldy #0
        lda (P0),y
        cmp #CR
        beq @go
        inc P0
        bne @sk1
        inc P0+1
@sk1:   dex
        jmp @sk
@go:    lda #COLS
        sta CNT
@c:     lda #S_OPAQUE
        sta TMP
        lda #' '
        ldx ENDF
        bne @out
        ldx P0                  ; at the end of the text: nothing more
        cpx TEND
        bne @ch
        ldx P0+1
        cpx TEND+1
        bne @ch
        inc ENDF
        bne @out
@ch:    ldy #0
        lda (P0),y
        jsr insel
        cmp #CR
        bne @nc
        inc ENDF                ; the line's end (a selected CR: one cell)
        lda #' '
        bne @out
@nc:    inc P0
        bne @pr
        inc P0+1
@pr:    cmp #32
        bcs @out
        lda #' '
@out:   ldx TMP
        stx STYLE
        sta CHOUT
        dec CNT
        bne @c
        lda #0
        sta STYLE
        lda ROW                 ; the caret
        cmp CROW
        bne @r
        lda CCOL
        sec
        sbc LEFT
        bcc @r
        cmp #COLS
        bcs @r
        ldx #0                  ; x = ORGX + col * 8 (2 pixels wide)
        stx TMP
        asl
        rol TMP
        asl
        rol TMP
        asl
        rol TMP
        ldx TMP
        sta TMP
        clc
        adc ORGX
        sta TMP
        txa
        adc ORGX+1
        tax
        lda TMP
        sta BX0
        stx BX0H
        lda BX0
        clc
        adc #1
        sta BX1
        lda BX0H
        adc #0
        sta BX1H
        lda BY0
        clc
        adc #15
        sta BY1
        lda BY0H
        adc #0
        sta BY1H
        lda #R_XOR
        sta ROP
        lda #1
        sta BCOL
        lda #C_BOXF
        sta BCMD
        lda #R_SET
        sta ROP
@r:     rts

; Selected? (P0 in SELS .. SELE-1): TMP gets S_INV too. A kept.
insel:  pha
        lda P0
        cmp SELS
        lda P0+1
        sbc SELS+1
        bcc @n
        lda P0
        cmp SELE
        lda P0+1
        sbc SELE+1
        bcs @n
        lda #S_OPAQUE + S_INV
        sta TMP
@n:     pla
        rts

; --- the status line ---------------------------------------------------------------------
; Under the text: line, column, room left, changed or not, CAPS
status: ldy #0
        sty STL
        lda #<s_line
        ldy #>s_line
        jsr stradd
        jsr curline             ; the caret's line, from 1
        jsr numadd
        lda #<s_col
        ldy #>s_col
        jsr stradd
        jsr colof
        clc
        adc #1
        sta DA
        lda #0
        adc #0
        sta DA+1
        jsr numadd
        lda #<s_free
        ldy #>s_free
        jsr stradd
        lda #<LIMIT             ; room left
        sec
        sbc TEND
        sta DA
        lda #>LIMIT
        sbc TEND+1
        sta DA+1
        jsr numadd
        lda #<s_mod
        ldy #>s_mod
        ldx DIRTY
        bne @m
        lda #<s_unmod
        ldy #>s_unmod
@m:     jsr stradd
        lda KBDFLAGS
        and #1
        sta SCAPS
        lda #<s_capson
        ldy #>s_capson
        ldx SCAPS
        bne @c
        lda #<s_capsoff
        ldy #>s_capsoff
@c:     jsr stradd
        lda #R_SET              ; the line above it
        sta ROP
        lda #0
        sta PATON
        lda ORGX
        sec
        sbc #TXO
        sta BX0
        lda ORGX+1
        sbc #0
        sta BX0H
        lda BX0
        clc
        adc #<633
        sta BX1
        lda BX0H
        adc #>633
        sta BX1H
        lda ORGY
        clc
        adc #<(STATUSY - TYO - 1)
        sta BY0
        sta BY1
        lda ORGY+1
        adc #>(STATUSY - TYO - 1)
        sta BY0H
        sta BY1H
        lda #1
        sta BCOL
        lda #C_BOXF
        sta BCMD
        lda ORGX                ; the text, padded with spaces
        sta BX0
        lda ORGX+1
        sta BX0H
        lda BY0
        clc
        adc #1
        sta BY0
        lda BY0H
        adc #0
        sta BY0H
        lda #S_OPAQUE
        sta STYLE
        ldx #0
@t:     lda #' '
        cpx STL
        bcs @o
        lda STBUF,x
@o:     sta CHOUT
        inx
        cpx #77
        bne @t
        lda #0
        sta STYLE
        rts

; The string at AY -> STBUF
stradd: sta P1
        sty P1+1
        ldy #0
        ldx STL
@l:     lda (P1),y
        beq @e
        sta STBUF,x
        inx
        iny
        bne @l
@e:     stx STL
        rts

; DA in decimal -> STBUF
numadd: ldx #0                  ; digits, last first, on the stack
@d:     jsr div10
        pha
        inx
        lda DA
        ora DA+1
        bne @d
        stx DCNT
        ldx STL
@o:     pla
        sta STBUF,x
        inx
        dec DCNT
        bne @o
        stx STL
        rts
; DA = DA / 10, A = the remainder as a digit
div10:  lda #16
        sta CNT
        lda #0
@l:     asl DA
        rol DA+1
        rol
        cmp #10
        bcc @n
        sbc #10
        inc DA
@n:     dec CNT
        bne @l
        ora #'0'
        rts

; DA = the caret's line number, from 1
curline:
        lda CUR
        cmp TOP
        lda CUR+1
        sbc TOP+1
        bcc @above
        MOVW P0, TOP            ; TOPLN + the CRs from TOP to the caret
        MOVW P1, CUR
        jsr countcr
        lda TOPLN
        clc
        adc N16
        sta DA
        lda TOPLN+1
        adc N16+1
        sta DA+1
        jmp @one
@above: MOVW P0, CUR            ; TOPLN - the CRs from the caret to TOP
        MOVW P1, TOP
        jsr countcr
        lda TOPLN
        sec
        sbc N16
        sta DA
        lda TOPLN+1
        sbc N16+1
        sta DA+1
@one:   inc DA
        bne @r
        inc DA+1
@r:     rts

s_line:   .byte "Line ", 0
s_col:    .byte "    Column ", 0
s_free:   .byte "    Free ", 0
s_mod:    .byte "    Modified", 0
s_unmod:  .byte "    Unmodified", 0
s_capson: .byte "    CAPS on", 0
s_capsoff: .byte "    CAPS off", 0
STBUF:    .res 80
