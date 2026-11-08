;=============================================================================
; edit.asm - full-screen text editor for mini6502          (bank RAM $E000-$EFFF)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
;
;   L EDIT E000 13      load the editor into bank $13 (any bank below $E0)
; Start it from the monitor or from BASIC, with its bank selected:
;   E000R / CALL $E000  start with an empty text
;   E003R / CALL $E003  carry on with the text from last time (empty if none)
; The whole fixed RAM ($0000-$CBFF) of the caller is saved to banks $F0-$FC
; first, and the editor gets its own copy (kept in banks $E0-$EC while away),
; so BASIC and its program stay alive. Esc puts the caller's RAM back and
; returns to it (RTS): to BASIC after a CALL, to the monitor after R.
; While editing, G is pointed at a stub at $CBF0 (in the editor's RAM) that
; selects the editor's bank: after F1, G resumes; Esc then still returns to
; the caller, and the caller's G is put back.
;
; Keys
;   arrows, Home, End, PgUp, PgDn    move           Enter       new line
;   Backspace / Delete               erase          Tab         spaces to
;   Ctrl+S  save    Ctrl+L  load    Ctrl+N  new                 the next 8th
;   Esc     back to the caller (text kept)                      column
;   Typed letters follow F6 (CAPS): switch it off for lower case.
;
; Files are plain text in the mini6502 disk folder (the usual 2-byte load
; address first). Lines end with CR; LF and CR LF are turned into CR when a
; file is loaded, so text from elsewhere works too.
;
; Memory (in the editor's own RAM image): text $0400-$CBEF (51,184 bytes, as
; a gap buffer), state in zero page $10-$3F and page 3 ($0300-$035F), stub
; $CBF0-$CBF7. Banks $E0-$EC and $F0-$FC hold the two RAM images; $EFF0-$EFF6
; in the editor's bank says which one is in the RAM.
; Limits: columns past 255 are not shown; lines longer than 80 columns
; scroll the whole screen sideways.
;=============================================================================

; --- mini6502 I/O --------------------------------------------------------------
        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

MONITOR = $FF1F

; --- memory --------------------------------------------------------------------
BUF     = $0400         ; text buffer start (page aligned: low byte 0)
.ifdef ASM_EDITOR
TOP     = $4400         ; 16K source; output and assembler use the rest
SIG0 = 'A'
SIG1 = 'S'
.else
TOP     = $CBF0         ; text buffer end (exclusive)
SIG0 = 'E'
SIG1 = 'D'
.endif
STUB    = $CBF0         ; 8 bytes: LDA #bank / STA BANK / JMP warm

SWAPLEN = $CC00         ; RAM swapped with the caller: $0000-$CBFF
IMAGE   = $0E0000       ; the editor's RAM while away (banks $E0-$EC)
WORLD   = $0F0000       ; the caller's RAM while editing (banks $F0-$FC)

; in the editor's own bank, after the code (not swapped, not in EDIT's file)
INSIDE  = $EFF0         ; INMAGIC while the RAM holds the editor's image
INMAGIC = $A5
SAVSP   = $EFF1         ; the caller's stack pointer
SAVWLO  = $EFF2         ; the caller's warm start (WARMLO/HI)
SAVWHI  = $EFF3
SAVCOL  = $EFF4         ; the caller's COLOR
RETLO   = $EFF5         ; enter's return address
RETHI   = $EFF6
OPENREQ = $EFF7         ; 1: started by $E006
SAVIRQ  = $EFF8         ; the caller's IRQEN, when its handler is in its RAM
OPENNAME = $EF80        ; the file name for $E006 (up to 40 characters + 0)

GS      = $10           ; 2: gap start = the cursor (text before it: BUF..GS)
GE      = $12           ; 2: gap end (text after the cursor: GE..TOP)
TOPPOS  = $14           ; 2: logical position of the first line on screen
CURLINE = $16           ; 2: cursor line, 0-based
LEFTCOL = $18           ; first column shown
WANTCOL = $19           ; column kept while moving up and down
COL     = $1A           ; cursor column (0-255, saturates)
CURROW  = $1B           ; cursor row on screen
P       = $1C           ; 2: pointer
Q       = $1E           ; 2: pointer
T       = $20           ; 2: temporary / count
POS     = $22           ; 2: logical position while drawing
ROW     = $24
CNT     = $25
REDRAW  = $26           ; 0 nothing, 1 cursor line, 2 everything
MODIFIED = $27          ; nonzero: unsaved changes
TXTCOL  = $28           ; COLOR for text
MYBANK  = $29           ; the bank the editor runs in
NUM     = $2A           ; 2: number to print in decimal
NZ      = $2C           ; digit printed (leading zero suppression)
MSG     = $2D           ; 2: message for the status line, 0 = none
KEY     = $2F
DP      = $30           ; 2: text pointer while drawing (jumps over the gap)

SIG     = $0300         ; "ED" when the state below is valid
NAMELEN = $0302
NAME    = $0310         ; file name (up to 40 characters)
INLEN   = $0340
INBUF   = $0350         ; name being typed (up to 40 characters)
NAMEMAX = 40

CR      = $0D
LF      = $0A
ESC     = $1B
STATUSROW = 24
TEXTROWS  = 24
STCOLOR = $70           ; status line: black on light grey

; --- entry points --------------------------------------------------------------
        .org $E000

        jmp cold                ; $E000
        jmp warm                ; $E003
        jmp open                ; $E006: empty text, then load the file whose
                                ; name (0-terminated) is at OPENNAME
.ifdef ASM_EDITOR
        jmp asm_save_fixed      ; $E009: core's RAM-preserving binary writer
.endif

open:   cld
        lda #1
        sta OPENREQ
        bne cold2
cold:
        cld
        lda #0
        sta OPENREQ
cold2:  jsr enter               ; BASIC/the caller's RAM goes to the banks
newimage:
        ldx #$FF
        txs
        lda BANK                ; remember where we live
        sta MYBANK
        lda SAVCOL
        sta TXTCOL
        jsr clearram            ; the editor's RAM image: $0300-$CBEF = 0
        jsr newtext
        lda #SIG0
        sta SIG
        lda #SIG1
        sta SIG+1
        lda #0
        sta NAMELEN
        jsr setstub
        jmp start

warm:
        cld
        jsr enter               ; swap in the editor's RAM image (text kept)
        ldx #$FF
        txs
        lda SIG                 ; state there?
        cmp #SIG0
        bne newimage            ; no: an empty text (already swapped in)
        lda SIG+1
        cmp #SIG1
        bne newimage
        lda BANK
        sta MYBANK
        jsr setstub
start:
.ifdef ASM_EDITOR
        lda #0                  ; desktop .ASM launcher leaves hires active
        sta MODE
        sta PTR                 ; hide its graphics pointer while editing
.endif
        lda TXTCOL
        sta COLOR
        lda #2
        sta SYSCTL              ; clear the screen
        lda #2
        sta REDRAW
        lda #0
        sta MSG+1
        lda OPENREQ             ; started by $E006: load the file
        beq mainloop
        lda #0
        sta OPENREQ
        ldx #0
@n:     lda OPENNAME,x
        beq @nd
        sta INBUF,x
        inx
        cpx #NAMEMAX
        bne @n
@nd:    stx INLEN
        jsr doload

; --- main loop -----------------------------------------------------------------
mainloop:
        jsr fixview
        lda REDRAW
        beq @status
        cmp #1
        beq @line
        jsr drawall
        jmp @status
@line:  jsr drawcur
@status:
        jsr drawstatus
        lda #0
        sta REDRAW
        lda CURROW              ; put the cursor where it belongs
        sta CURY
        sec
        lda COL
        sbc LEFTCOL
        sta CURX
        jsr getkey
        sta KEY
        lda #0
        sta MSG+1               ; a message lasts until the next key
        jsr dokey
        jmp mainloop

; Waits for a key: A = character, or $81-$8A for the extended keys
getkey:
        lda KBDCR
        bpl getkey
        lda KBD
        and #$7F
        bne @done
        lda KBDEXT
        beq getkey              ; a real NUL: ignore it
        ora #$80
@done:  rts

dokey:
        lda KEY
        cmp #$81
        bne :+
        jmp k_up
:       cmp #$82
        bne :+
        jmp k_down
:       cmp #$83
        bne :+
        jmp k_left
:       cmp #$84
        bne :+
        jmp k_right
:       cmp #$85
        bne :+
        jmp k_home
:       cmp #$86
        bne :+
        jmp k_end
:       cmp #$87
        bne :+
        jmp k_pgup
:       cmp #$88
        bne :+
        jmp k_pgdn
:       cmp #$8A
        bne :+
        jmp k_del
:       cmp #CR
        bne :+
        jmp k_enter
:       cmp #$08
        bne :+
        jmp k_bs
:       cmp #$7F
        bne :+
        jmp k_bs
:       cmp #$09
        bne :+
        jmp k_tab
:       cmp #ESC
        bne :+
        jmp k_exit
:       cmp #$13                ; Ctrl+S
        bne :+
        jmp k_save
:       cmp #$0C                ; Ctrl+L
        bne :+
        jmp k_load
:       cmp #$0E                ; Ctrl+N
        bne :+
        jmp k_new
.ifdef ASM_EDITOR
:       cmp #$01                ; Ctrl+A: assemble, then offer binary save
        bne :+
        jmp k_assemble
.endif
:       cmp #' '
        bcc @ignore
        cmp #$7F
        bcs @ignore
        jmp k_char
@ignore:
        rts

; --- keys ----------------------------------------------------------------------
k_char:
        lda KEY
        jsr insert
        bcs @full
        lda #1                  ; only this line changed
        jsr wantredraw
        jmp setwant
@full:  rts

k_enter:
        lda #CR
        jsr insert
        lda #2
        sta REDRAW
        jmp setwant

k_tab:                          ; spaces up to the next multiple of 8
        lda #' '
        jsr insert
        bcs @done
        jsr column
        lda COL
        and #7
        bne k_tab
@done:  lda #1
        jsr wantredraw
        jmp setwant

k_bs:                           ; delete the character before the cursor
        jsr charbefore
        bcs @none
        cmp #CR
        bne @line
        lda CURLINE             ; joining two lines
        bne :+
        dec CURLINE+1
:       dec CURLINE
        lda #2
        sta REDRAW
        bne @dec
@line:  lda #1
        jsr wantredraw
@dec:   lda GS
        bne :+
        dec GS+1
:       dec GS
        lda #1
        sta MODIFIED
@none:  jmp setwant

; Delete the character after the cursor (GE side)
k_del:
        jsr delafter
        jmp setwant

delafter:
        lda GE                  ; at the end?
        cmp #<TOP
        bne @go
        lda GE+1
        cmp #>TOP
        beq @done
@go:    ldy #0
        lda (GE),y
        inc GE
        bne :+
        inc GE+1
:       cmp #CR
        beq @all
        lda #1
        jsr wantredraw
        jmp @mod
@all:   lda #2
        sta REDRAW
@mod:   lda #1
        sta MODIFIED
@done:  rts

k_left:
        jsr left1
        jmp setwant
k_right:
        jsr right1
        jmp setwant
k_home:
        jsr linestart
        jmp setwant
k_end:
        jsr lineend
        jmp setwant

k_up:
        jsr up1
        rts
k_down:
        jsr down1
        rts
k_pgup:
        ldx #TEXTROWS-1
@loop:  txa
        pha
        jsr up1
        pla
        tax
        dex
        bne @loop
        rts
k_pgdn:
        ldx #TEXTROWS-1
@loop:  txa
        pha
        jsr down1
        pla
        tax
        dex
        bne @loop
        rts

k_exit:
        jmp leave               ; back to the caller, its RAM put back

k_new:
        jsr confirm
        bcs @no
        jsr newtext
        lda #0
        sta NAMELEN
        lda #2
        sta REDRAW
@no:    rts

k_save:
        lda #<s_saveas
        ldx #>s_saveas
        jsr askname
        bcs @no
        jsr closegap            ; text = BUF .. GS+n, contiguous
        lda #<BUF
        sta DSTART
        lda #>BUF
        sta DSTART+1
        clc
        lda GS
        adc T
        sta DEND
        lda GS+1
        adc T+1
        sta DEND+1
        jsr setdname
        lda #2
        sta DCMD
        jsr opengap             ; put the gap back at the cursor
        lda DSTAT
        bne @err
        jsr usename
        lda #0
        sta MODIFIED
        lda #<s_saved
        ldx #>s_saved
        jmp setmsg
@err:   jmp diskmsg
@no:    rts

k_load:
        jsr confirm
        bcs klno
        lda #<s_load
        ldx #>s_load
        jsr askname
        bcc doload
klno:   rts
doload: lda #<BUF               ; (INBUF/INLEN = the name)
        sta DSTART
        lda #>BUF
        sta DSTART+1
        lda #<TOP
        sta DEND
        lda #>TOP
        sta DEND+1
        jsr setdname
        lda #3                  ; load at BUF, must fit below TOP
        sta DCMD
        lda DSTAT
        bne @err
        jsr usename
        lda DEND                ; the text is BUF..DEND
        sta GS
        lda DEND+1
        sta GS+1
        jsr fixlf               ; LF / CR LF -> CR
        lda #<TOP
        sta GE
        lda #>TOP
        sta GE+1
        jsr gaptostart          ; cursor at the start of the text
        lda #0
        sta MODIFIED
        lda #2
        sta REDRAW
        lda #<s_loaded
        ldx #>s_loaded
        jmp setmsg
@err:   cmp #1
        bne :+
        lda #<s_notfound
        ldx #>s_notfound
        jmp setmsg
:       jmp diskmsg
@no:    rts

; With unsaved changes, asks for Y; carry set = do not go on
confirm:
        lda MODIFIED
        beq @ok
        lda #<s_discard
        ldx #>s_discard
        jsr prompt
        jsr getkey
        and #$DF
        cmp #'Y'
        bne @no
@ok:    clc
        rts
@no:    sec
        rts

; --- cursor movement -----------------------------------------------------------

; One character left (carry set if at the start); A = the character passed
left1:
        lda GS
        bne :+
        lda GS+1
        cmp #>BUF
        beq @start
:       lda GS
        bne :+
        dec GS+1
:       dec GS
        lda GE
        bne :+
        dec GE+1
:       dec GE
        ldy #0
        lda (GS),y
        sta (GE),y
        cmp #CR
        bne @done
        lda CURLINE
        bne :+
        dec CURLINE+1
:       dec CURLINE
        lda #CR
@done:  clc
        rts
@start: sec
        rts

; One character right (carry set if at the end); A = the character passed
right1:
        lda GE
        cmp #<TOP
        bne @go
        lda GE+1
        cmp #>TOP
        beq @end
@go:    ldy #0
        lda (GE),y
        sta (GS),y
        inc GS
        bne :+
        inc GS+1
:       inc GE
        bne :+
        inc GE+1
:       cmp #CR
        bne @done
        inc CURLINE
        bne @done
        inc CURLINE+1
@done:  clc
        rts
@end:   sec
        rts

; Character before / after the cursor; carry set if there is none
charbefore:
        lda GS
        bne :+
        lda GS+1
        cmp #>BUF
        beq @none
:       lda GS
        sec
        sbc #1
        sta P
        lda GS+1
        sbc #0
        sta P+1
        ldy #0
        lda (P),y
        clc
        rts
@none:  sec
        rts

charafter:
        lda GE
        cmp #<TOP
        bne @go
        lda GE+1
        cmp #>TOP
        beq @none
@go:    ldy #0
        lda (GE),y
        clc
        rts
@none:  sec
        rts

linestart:
        jsr charbefore
        bcs @done
        cmp #CR
        beq @done
        jsr left1
        jmp linestart
@done:  rts

lineend:
        jsr charafter
        bcs @done
        cmp #CR
        beq @done
        jsr right1
        jmp lineend
@done:  rts

; COL = cursor column (characters since the last CR, at most 255)
column:
        lda GS
        sta P
        lda GS+1
        sta P+1
        ldx #0
@loop:  lda P                   ; at BUF?
        bne :+
        lda P+1
        cmp #>BUF
        beq @done
:       lda P
        bne :+
        dec P+1
:       dec P
        ldy #0
        lda (P),y
        cmp #CR
        beq @done
        inx
        bne @loop
        dex                     ; 255 at most
@done:  stx COL
        rts

setwant:
        jsr column
        lda COL
        sta WANTCOL
        rts

; Up one line, to WANTCOL or the end of that line
up1:
        jsr linestart
        jsr left1               ; onto the previous line's CR
        bcs @top                ; first line: stay at its start
        jsr linestart
        jmp towant
@top:   rts

down1:
        jsr lineend
        jsr right1              ; past the CR
        bcs @end
        jmp towant
@end:   rts

; Right, up to WANTCOL columns, not past the end of the line
towant:
        ldx WANTCOL
        beq @done
@loop:  txa
        pha
        jsr charafter
        bcs @stop
        cmp #CR
        beq @stop
        jsr right1
        pla
        tax
        dex
        bne @loop
        rts
@stop:  pla
@done:  rts

; --- editing -------------------------------------------------------------------

; Inserts A at the cursor; carry set (and a beep) if the buffer is full
insert:
        tax
        lda GS
        cmp GE
        bne @room
        lda GS+1
        cmp GE+1
        bne @room
        sta BEEP
        sec
        rts
@room:  txa
        ldy #0
        sta (GS),y
        inc GS
        bne :+
        inc GS+1
:       cmp #CR
        bne :+
        inc CURLINE
        bne :+
        inc CURLINE+1
:       lda #1
        sta MODIFIED
        clc
        rts

; REDRAW = max(REDRAW, A)
wantredraw:
        cmp REDRAW
        bcc @keep
        sta REDRAW
@keep:  rts

; Empty text, cursor at the start
newtext:
        lda #<BUF
        sta GS
        lda #>BUF
        sta GS+1
        lda #<TOP
        sta GE
        lda #>TOP
        sta GE+1
        lda #0
        sta TOPPOS
        sta TOPPOS+1
        sta CURLINE
        sta CURLINE+1
        sta LEFTCOL
        sta WANTCOL
        sta COL
        sta MODIFIED
        rts

; --- swapping the RAM ----------------------------------------------------------
; The editor and the program that called it (BASIC, the monitor...) each have
; their own copy of the fixed RAM $0000-$CBFF, kept in banks by DMA:
;   WORLD  ($F0000, banks $F0-$FC)  the caller's RAM while the editor runs
;   IMAGE  ($E0000, banks $E0-$EC)  the editor's RAM (text, state) meanwhile
; Entering saves the caller's RAM to WORLD and (warm start) copies IMAGE in;
; Esc does the opposite and returns to the caller with RTS, on its own stack.
; INSIDE (in the editor's bank, not in the swapped RAM) says that the RAM
; holds the editor's image: after F1, G (or E003R) just carries on.

; Copies 9 bytes from a table to the DMA registers and starts a COPY. Inline
; (a macro, not a subroutine): the copy may replace the stack page.
.macro  DMACOPY tbl
        .local @l
        ldx #8
@l:     lda tbl,x
        sta DMASRC,x
        dex
        bpl @l
        lda #1
        sta DMACMD
.endmacro

; Called first by cold and warm (JSR: the return address is on the caller's
; stack, which is saved with the rest; we come back to it only if nothing was
; swapped yet, or before the swap replaces it)
enter:
        lda BANK                ; the editor must not run from a bank the
.ifdef ASM_EDITOR
        cmp #$80                ; ASM allocates its image in $80-$BF
.else
        cmp #$E0                ; swap uses ($E0-$FF)
.endif
        bcc @bankok
        pla                     ; refused: beep and return to the caller
        pla
        lda #1
        sta BEEP
        rts
@bankok:
.ifdef ASM_EDITOR
        jsr asm_image
.endif
        lda INSIDE              ; the RAM already holds the editor's image?
        cmp #INMAGIC
        bne @swap
        lda SIG                 ; ...and it still looks like it
        cmp #SIG0
        bne @swap
        lda SIG+1
        cmp #SIG1
        bne @swap
        rts                     ; yes: nothing to swap
@swap:  pla                     ; our return address, kept in the bank: the
        sta RETLO               ; stack page is about to change
        pla
        sta RETHI
        tsx                     ; the caller's stack pointer (after its JSR)
        stx SAVSP
        lda WARMLO              ; the caller's warm start (G), put back by Esc
        sta SAVWLO
        lda WARMHI
        sta SAVWHI
        lda COLOR
        sta SAVCOL
.ifdef ASM_EDITOR
        lda MODE                ; capture only on a real caller -> ASM swap
        sta ASMMODE             ; F1/G must not replace these saved values
        lda PTR
        sta ASMPTR
.endif
        lda #0                  ; an interrupt handler in the caller's RAM is
        sta SAVIRQ              ; turned off while it is swapped out (one in
        lda IRQVEC+1            ; a bank keeps running)
        cmp #$E0
        bcs @irqok
        lda IRQEN
        sta SAVIRQ
        lda #0
        sta IRQEN
@irqok:
        DMACOPY d_save          ; caller's RAM -> WORLD
        DMACOPY d_load          ; IMAGE -> RAM (cold clears it afterwards)
        lda #INMAGIC
        sta INSIDE
        lda RETHI               ; return (to cold or warm, which reset the
        pha                     ; stack anyway)
        lda RETLO
        pha
        rts

; Esc: the editor's RAM back to IMAGE, the caller's RAM back, RTS to it.
; Nothing in the zero page may be used after the second copy.
leave:
        lda #2
        sta SYSCTL              ; clear the screen
        DMACOPY d_keep          ; RAM -> IMAGE
        DMACOPY d_back          ; WORLD -> RAM
        lda IRQVEC+1            ; a handler in the RAM: the caller's again
        cmp #$E0
        bcs @irqok
        lda SAVIRQ
        sta IRQEN
@irqok: lda #0
        sta INSIDE
        lda SAVWLO
        sta WARMLO
        lda SAVWHI
        sta WARMHI
        lda SAVCOL
        sta COLOR
.ifdef ASM_EDITOR
        lda ASMMODE
        sta MODE
        lda ASMPTR
        sta PTR
.endif
        ldx SAVSP
        txs
        rts                     ; to the caller (CALL in BASIC, R, G...)

; DMA descriptors: source (3 bytes), destination (3), length (3)
d_save: .byte $00,$00,$FF, <WORLD,>WORLD,^WORLD, <SWAPLEN,>SWAPLEN,0
d_load: .byte <IMAGE,>IMAGE,^IMAGE, $00,$00,$FF, <SWAPLEN,>SWAPLEN,0
d_keep: .byte $00,$00,$FF, <IMAGE,>IMAGE,^IMAGE, <SWAPLEN,>SWAPLEN,0
d_back: .byte <WORLD,>WORLD,^WORLD, $00,$00,$FF, <SWAPLEN,>SWAPLEN,0

clearram:
        lda #<$0300
        sta P
        lda #>$0300
        sta P+1
        lda #0
        tay
@loop:  sta (P),y
        iny
        bne @loop
        inc P+1
        ldx P+1
        cpx #>TOP               ; up to $CBFF: the stub is written afterwards
        bcc @loop
        beq @loop
        rts

; G -> this bank, warm start
setstub:
        lda #$A9                ; LDA #bank
        sta STUB
        lda MYBANK
        sta STUB+1
        lda #$8D                ; STA BANK
        sta STUB+2
        lda #<BANK
        sta STUB+3
        lda #>BANK
        sta STUB+4
        lda #$4C                ; JMP warm
        sta STUB+5
        lda #<warm
        sta STUB+6
        lda #>warm
        sta STUB+7
        lda #<STUB
        sta WARMLO
        lda #>STUB
        sta WARMHI
        rts

; Moves the text after the gap down to GS: the text becomes BUF..GS+T
; (T = its length). The cursor stays logically at GS.
closegap:
        sec
        lda #<TOP
        sbc GE
        sta T
        lda #>TOP
        sbc GE+1
        sta T+1
        lda GE                  ; from GE
        sta Q
        lda GE+1
        sta Q+1
        lda GS                  ; to GS
        sta P
        lda GS+1
        sta P+1
        jmp copyup              ; forward copy (destination is lower)

; Puts it back: GS..GS+T moves to GE..TOP
opengap:
        lda GS
        sta Q
        lda GS+1
        sta Q+1
        lda GE
        sta P
        lda GE+1
        sta P+1
        jmp copydown            ; backward copy (destination is higher)

; After a load: text BUF..GS, gap GS..TOP. Moves the text to the top, so
; the cursor is at the start: GE = TOP - length, GS = BUF.
gaptostart:
        sec
        lda GS
        sbc #<BUF
        sta T
        lda GS+1
        sbc #>BUF
        sta T+1
        sec
        lda #<TOP
        sbc T
        sta GE
        sta P
        lda #>TOP
        sbc T+1
        sta GE+1
        sta P+1
        lda #<BUF
        sta Q
        sta GS
        lda #>BUF
        sta Q+1
        sta GS+1
        jsr copydown
        lda #0
        sta CURLINE
        sta CURLINE+1
        sta TOPPOS
        sta TOPPOS+1
        sta LEFTCOL
        sta WANTCOL
        rts

; Copies T bytes from (Q) to (P), lowest address first (P < Q)
copyup:
        ldy #0
        ldx T+1
        beq @last
@page:  lda (Q),y
        sta (P),y
        iny
        bne @page
        inc Q+1
        inc P+1
        dex
        bne @page
@last:  ldx T
        beq @done
@byte:  lda (Q),y
        sta (P),y
        iny
        dex
        bne @byte
@done:  rts

; Copies T bytes from (Q) to (P), highest address first (P > Q)
copydown:
        lda T                   ; nothing to do?
        ora T+1
        beq @done
        clc                     ; point at the last byte of each block
        lda Q
        adc T
        sta Q
        lda Q+1
        adc T+1
        sta Q+1
        clc
        lda P
        adc T
        sta P
        lda P+1
        adc T+1
        sta P+1
@loop:  lda Q
        bne :+
        dec Q+1
:       dec Q
        lda P
        bne :+
        dec P+1
:       dec P
        ldy #0
        lda (Q),y
        sta (P),y
        lda T
        bne :+
        dec T+1
:       dec T
        lda T
        ora T+1
        bne @loop
@done:  rts

; In BUF..GS: CR LF -> CR, LF -> CR (the text gets shorter, GS moves down)
fixlf:
        lda #<BUF
        sta P                   ; read
        sta Q                   ; write
        lda #>BUF
        sta P+1
        sta Q+1
        lda #0
        sta KEY                 ; previous character
@loop:  lda P
        cmp GS
        bne @go
        lda P+1
        cmp GS+1
        beq @end
@go:    ldy #0
        lda (P),y
        inc P
        bne :+
        inc P+1
:       cmp #LF
        bne @store
        ldx KEY                 ; LF after CR: drop it
        cpx #CR
        beq @next
        lda #CR
@store: ldy #0
        sta (Q),y
        inc Q
        bne :+
        inc Q+1
:
@next:  sta KEY
        jmp @loop
@end:   lda Q
        sta GS
        lda Q+1
        sta GS+1
        rts

; --- screen --------------------------------------------------------------------

; Logical position (POS) -> character in A, carry set past the end
getc:
        lda POS
        sta P
        clc
        lda POS+1
        adc #>BUF
        sta P+1                 ; P = BUF + POS
        lda P
        cmp GS
        lda P+1
        sbc GS+1
        bcc @read               ; before the gap
        sec                     ; after it: P = GE + (P - GS)
        lda P
        sbc GS
        sta T
        lda P+1
        sbc GS+1
        sta T+1
        clc
        lda T
        adc GE
        sta P
        lda T+1
        adc GE+1
        sta P+1
        lda P
        cmp #<TOP
        lda P+1
        sbc #>TOP
        bcs @end
@read:  ldy #0
        lda (P),y
        clc
        rts
@end:   sec
        rts

incpos:
        inc POS
        bne :+
        inc POS+1
:       rts

; Keeps the cursor on screen: TOPPOS, CURROW, LEFTCOL, COL
fixview:
        jsr column
        ; cursor position (logical) = GS - BUF
        sec
        lda GS
        sbc #<BUF
        sta T
        lda GS+1
        sbc #>BUF
        sta T+1
        ; above the screen? TOPPOS = start of the cursor line
        lda T
        cmp TOPPOS
        lda T+1
        sbc TOPPOS+1
        bcs @below
        sec
        lda T
        sbc COL
        sta TOPPOS
        lda T+1
        sbc #0
        sta TOPPOS+1
        lda #2
        sta REDRAW
@below: ; rows between TOPPOS and the cursor (all before the gap)
        jsr countrows
        cmp #TEXTROWS
        bcc @rowok
        ; too far down: move TOPPOS down one line at a time
@down:  jsr topnext
        jsr countrows
        cmp #TEXTROWS
        bcs @down
        pha
        lda #2
        sta REDRAW
        pla
@rowok: sta CURROW
        ; sideways
        lda COL
        cmp LEFTCOL
        bcs @right
        sta LEFTCOL
        lda #2
        sta REDRAW
        rts
@right: sec
        sbc LEFTCOL
        cmp #80
        bcc @ok
        lda COL
        sec
        sbc #79
        sta LEFTCOL
        lda #2
        sta REDRAW
@ok:    rts

; A = number of CRs from TOPPOS to the cursor (stops at TEXTROWS)
countrows:
        lda TOPPOS
        sta P
        clc
        lda TOPPOS+1
        adc #>BUF
        sta P+1
        ldx #0
@loop:  lda P
        cmp GS
        bne @go
        lda P+1
        cmp GS+1
        beq @done
@go:    ldy #0
        lda (P),y
        cmp #CR
        bne :+
        inx
        cpx #TEXTROWS
        bcs @done
:       inc P
        bne @loop
        inc P+1
        bne @loop
@done:  txa
        rts

; TOPPOS = start of the line after the one at TOPPOS
topnext:
        lda TOPPOS
        sta POS
        lda TOPPOS+1
        sta POS+1
@loop:  jsr getc
        bcs @done
        jsr incpos
        cmp #CR
        bne @loop
@done:  lda POS
        sta TOPPOS
        lda POS+1
        sta TOPPOS+1
        rts

drawall:
        lda TOPPOS              ; TOPPOS is never after the cursor, so it is
        sta DP                  ; before the gap: DP = BUF + TOPPOS
        clc
        lda TOPPOS+1
        adc #>BUF
        sta DP+1
        lda #0
        sta ROW
@loop:  jsr drawline
        inc ROW
        lda ROW
        cmp #TEXTROWS
        bcc @loop
        rts

; Only the cursor's line
drawcur:
        sec                     ; DP = GS - COL: the start of the cursor line
        lda GS
        sbc COL
        sta DP
        lda GS+1
        sbc #0
        sta DP+1
        lda CURROW
        sta ROW
        ; falls into drawline

; Draws the line at DP on screen row ROW; DP ends at the next line
drawline:
        lda TXTCOL
        sta COLOR
        lda ROW
        sta CURY
        lda #0
        sta CURX
        ldx LEFTCOL             ; skip the columns left of the screen
        beq @show
@skip:  txa
        pha
        jsr getp
        bcs @skipend
        cmp #CR
        beq @skipend
        jsr incdp
        pla
        tax
        dex
        bne @skip
        beq @show
@skipend:
        pla
@show:  lda #80
        sta CNT
@char:  jsr getp
        bcs @pad
        cmp #CR
        beq @pad
        cmp #' '                ; control characters (tabs...) as spaces
        bcs :+
        lda #' '
:       sta DSP
        jsr incdp
        dec CNT
        bne @char
@rest:  jsr getp                ; the part right of the screen
        bcs @done
        jsr incdp
        cmp #CR
        bne @rest
        rts
@pad:   lda #' '
@padl:  sta DSP
        dec CNT
        bne @padl
        jsr getp                ; past the CR
        bcs @done
        jsr incdp
@done:  rts

; Character at DP (jumping over the gap), carry set at the end
getp:
        lda DP
        cmp GS
        bne @chk
        lda DP+1
        cmp GS+1
        bne @chk
        lda GE                  ; at the gap: continue after it
        sta DP
        lda GE+1
        sta DP+1
@chk:   lda DP
        cmp #<TOP
        bne @read
        lda DP+1
        cmp #>TOP
        beq @end
@read:  ldy #0
        lda (DP),y
        clc
        rts
@end:   sec
        rts

incdp:
        inc DP
        bne :+
        inc DP+1
:       rts

drawstatus:
        lda #STCOLOR
        sta COLOR
        lda #STATUSROW
        sta CURY
        lda #0
        sta CURX
        lda MSG+1
        beq @normal
.ifdef ASM_EDITOR
        cmp #$C5
        bne @message
        lda $C400
        beq @message
        lda #<asm_error_line
        ldx #>asm_error_line
        jsr puts
        lda $C401
        sta NUM
        lda $C402
        sta NUM+1
        jsr prdec
        lda #<asm_error_col
        ldx #>asm_error_col
        jsr puts
        lda $C412
        sta NUM
        lda #0
        sta NUM+1
        jsr prdec
@message:
.endif
        lda MSG
        ldx MSG+1
        jsr puts
        jmp @fill
@normal:
        lda #<s_title
        ldx #>s_title
        jsr puts
        lda NAMELEN
        bne @name
        lda #<s_noname
        ldx #>s_noname
        jsr puts
        jmp @mod
@name:  ldx #0
@nl:    lda NAME,x
        sta DSP
        inx
        cpx NAMELEN
        bcc @nl
@mod:   lda MODIFIED
        beq :+
        lda #'*'
        sta DSP
:       lda #<s_line
        ldx #>s_line
        jsr puts
        clc
        lda CURLINE
        adc #1
        sta NUM
        lda CURLINE+1
        adc #0
        sta NUM+1
        jsr prdec
        lda #<s_col
        ldx #>s_col
        jsr puts
        clc
        lda COL
        adc #1
        sta NUM
        lda #0
        adc #0
        sta NUM+1
        jsr prdec
        lda #<s_free
        ldx #>s_free
        jsr puts
        sec
        lda GE
        sbc GS
        sta NUM
        lda GE+1
        sbc GS+1
        sta NUM+1
        jsr prdec
        lda #<s_keys
        ldx #>s_keys
        jsr puts
@fill:  lda CURX                ; spaces to column 78, then the last cell
        cmp #79
        bcs @last
        lda #' '
        sta DSP
        jmp @fill
@last:  lda #79                 ; written directly: printing there would
        sta CURX                ; scroll the screen
        lda #' '
        sta VCHR
        lda #STCOLOR
        sta VCOL
        lda TXTCOL
        sta COLOR
        rts

; Prints the zero-terminated string at X (high) A (low), stops at column 79
puts:
        sta Q
        stx Q+1
        ldy #0
@loop:  lda (Q),y
        beq @done
        ldx CURX
        cpx #79
        bcs @done
        sta DSP
        iny
        bne @loop
@done:  rts

; Prints NUM (0-65535) in decimal
prdec:
        lda #0
        sta NZ
        ldx #0                  ; power of ten index
@digit: ldy #'0'
@sub:   lda NUM                 ; NUM >= 10^n ?
        cmp tens_lo,x
        lda NUM+1
        sbc tens_hi,x
        bcc @put
        sta NUM+1
        lda NUM
        sbc tens_lo,x
        sta NUM
        iny
        bne @sub
@put:   tya
        cpx #4                  ; always print the last digit
        beq @show
        cmp #'0'
        bne @show
        ldy NZ
        beq @skip
@show:  sta DSP
        sta NZ
@skip:  inx
        cpx #5
        bcc @digit
        rts
tens_lo: .byte <10000, <1000, <100, <10, <1
tens_hi: .byte >10000, >1000, >100, >10, >1

setmsg:
        sta MSG
        stx MSG+1
        rts

; Message for a failed disk command
diskmsg:
        lda #<s_diskerr
        ldx #>s_diskerr
        jmp setmsg

; Shows a prompt on the status line
prompt:
        pha
        txa
        pha
        lda #STCOLOR
        sta COLOR
        lda #STATUSROW
        sta CURY
        lda #0
        sta CURX
        pla
        tax
        pla
        jsr puts
@clr:   lda CURX                ; clear the rest of the line
        pha
@sp:    lda CURX
        cmp #79
        bcs @back
        lda #' '
        sta DSP
        jmp @sp
@back:  pla
        sta CURX
        rts

; Asks for a file name on the status line (starts with the current name).
; Carry set if Esc. The name is in INBUF / INLEN.
askname:
        jsr prompt
        lda CURX
        sta ROW                 ; where the name starts
        ldx #0
@copy:  cpx NAMELEN
        bcs @copied
        lda NAME,x
        sta INBUF,x
        inx
        bne @copy
@copied:
        stx INLEN
@show:  lda ROW                 ; redraw the name
        sta CURX
        ldx #0
@sl:    cpx INLEN
        bcs @sp
        lda INBUF,x
        sta DSP
        inx
        bne @sl
@sp:    lda CURX
        pha
        lda #' '
        sta DSP
        pla
        sta CURX                ; cursor after the name
@key:   jsr getkey
        cmp #CR
        beq @enter
        cmp #ESC
        beq @esc
        cmp #$08
        beq @bs
        cmp #$7F
        beq @bs
        jsr namechar
        bcs @key
        ldx INLEN
        cpx #NAMEMAX
        bcs @key
        sta INBUF,x
        inc INLEN
        bne @show
@bs:    lda INLEN
        beq @key
        dec INLEN
        jmp @show
@enter: lda INLEN
        beq @key                ; a name is needed
        lda #2                  ; the status line will be redrawn
        jsr wantredraw
        clc
        rts
@esc:   lda #2
        jsr wantredraw
        sec
        rts

; Carry clear if A may be in a file name (A-Z a-z 0-9 . _ -)
namechar:
        cmp #'.'
        beq @ok
        cmp #'_'
        beq @ok
        cmp #'-'
        beq @ok
        cmp #'0'
        bcc @no
        cmp #'9'+1
        bcc @ok
        cmp #'A'
        bcc @no
        cmp #'Z'+1
        bcc @ok
        cmp #'a'
        bcc @no
        cmp #'z'+1
        bcc @ok
@no:    sec
        rts
@ok:    clc
        rts

; Disk name = INBUF / INLEN
setdname:
        lda #<INBUF
        sta DNAME
        lda #>INBUF
        sta DNAME+1
        lda INLEN
        sta DNLEN
        rts

; The typed name becomes the file's name
usename:
        ldx #0
@loop:  cpx INLEN
        bcs @done
        lda INBUF,x
        sta NAME,x
        inx
        bne @loop
@done:  stx NAMELEN
        rts

; --- text ----------------------------------------------------------------------
.ifdef ASM_EDITOR
        .include "editor.inc"
s_title:   .byte " ASM  ", 0
.else
s_title:   .byte " EDIT  ", 0
.endif
s_noname:  .byte "(new)", 0
s_line:    .byte "   Ln ", 0
s_col:     .byte "  Col ", 0
s_free:    .byte "  Free ", 0
.ifdef ASM_EDITOR
s_keys:    .byte " ^A assemble ^S save ^L load Esc exit", 0
.else
s_keys:    .byte "   ^S save ^L load ^N new Esc exit", 0
.endif
s_saveas:  .byte " Save as: ", 0
s_load:    .byte " Load: ", 0
s_saved:   .byte " Saved", 0
s_loaded:  .byte " Loaded", 0
s_notfound: .byte " No such file on the disk", 0
s_diskerr: .byte " Disk error (bad name, or the file does not fit)", 0
s_discard: .byte " Unsaved changes: press Y to throw them away", 0

        .assert * <= $F000, error, "the editor must fit in $E000-$EFFF"
