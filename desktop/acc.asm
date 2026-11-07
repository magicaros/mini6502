;=============================================================================
; acc.asm - mini6502 desk accessories, bank $1B: the clock and the calculator
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Any toolkit program has them: the toolkit adds their names to its first
; menu ("mini6502") and passes the events of their windows here, so the
; program never sees those windows. They run inside the program's GETEVENT,
; so they keep their zero page and buffers to themselves (the zero page
; they use, $80-$AF, is saved and put back). Their variables live in this
; bank, so the calculator keeps its number from one program to the next.
;=============================================================================

        .include "desk.inc"

A32     = $A0                   ; calculator arithmetic, 4 bytes each
B32     = $A4
R32     = $A8
SIGN    = $AC
CNT     = $AD
NACC    = 2                     ; 0 the clock, 1 the calculator

        .org $E000

        jmp a_open              ; $E000 X = accessory: open (or to the
                                ;       front); $FF: those left open
        jmp a_event             ; $E003 A = event (UPDATE, CLICK, KEY,
                                ;       CLOSE), X = its window; KEY: the
                                ;       character in ACCKEY
        jmp a_idle              ; $E006 nothing happening: the clock ticks
        .byte "AC"              ; $E009 the mark, then the menu items
        .byte "-", 0, "Clock", 0, "Calculator", 0, 0

; --- the entries: the program's zero page is kept ------------------------------------
a_open: jsr zpsave
        jsr open
        jmp zpback
a_event:
        jsr zpsave
        jsr event
        jmp zpback
a_idle: jsr zpsave
        jsr idle
zpback: ldx #$2F
@c:     lda ZPSAVE,x
        sta $80,x
        dex
        bpl @c
        rts
zpsave: cld
        pha
        txa
        pha
        ldx #$2F
@c:     lda $80,x
        sta ZPSAVE,x
        dex
        bpl @c
        pla
        tax
        pla
        rts

; X = accessory: its window opened, or brought to the front; $FF: the ones
; still marked open (after INIT or CLEAR closed every window)
open:   cpx #$FF
        bne open1
        ldx #NACC - 1
@l:     stx D3
        lda OPENF,x
        beq @n
        jsr open1
@n:     ldx D3
        dex
        bpl @l
        rts
open1:  cpx #NACC
        bcs @r
        lda ACCWIN,x
        bmi @new
        tax
        TK TK_FRONT
@r:     rts
@new:   stx D2
        txa                     ; 16 bytes each in wrect
        asl
        asl
        asl
        asl
        tay
        ldx #0
@c:     lda wrect,y             ; r0-r3 and r4 = the title
        sta r0,x
        iny
        inx
        cpx #10
        bne @c
        TK TK_OPENWIN
        bcs @r
        txa
        ldx D2
        sta ACCWIN,x
        lda #1
        sta OPENF,x
        rts
wrect:  .word 476, 36, 616, 80, s_clock
        .byte 0, 0, 0, 0, 0, 0
        .word 436, 110, 612, 312, s_calc
s_clock: .byte "Clock", 0
s_calc:  .byte "Calculator", 0

; An event for one of our windows
event:  stx CWIN
        ldy #0                  ; which accessory?
        cpx ACCWIN
        beq @y
        iny
@y:     cmp #EV_CLOSE
        bne @n1
        lda #$FF                ; closed: not open next time either
        sta ACCWIN,y
        lda #0
        sta OPENF,y
        TK TK_CLOSEWIN          ; (X = its window still)
        rts
@n1:    cmp #EV_UPDATE
        bne @n2
        cpy #0
        bne @calc
        jmp clock
@calc:  jmp calc
@n2:    cpy #1                  ; the rest is for the calculator
        bne @r
        cmp #EV_CLICK
        bne @n3
        jmp cclick
@n3:    cmp #EV_KEY
        bne @r
        lda ACCKEY
        beq @r
        jmp ckey
@r:     rts

; The clock shows the new second
idle:   ldx ACCWIN
        bmi @r
        lda CLOCKS
        cmp LASTSEC
        beq @r
        sta LASTSEC
        TK TK_INVAL
@r:     rts

; --- building strings in SBUF ------------------------------------------------------------
sbegin: lda #0
        sta SLEN
        rts
sput:   ldx SLEN
        sta SBUF,x
        inc SLEN
        lda #0
        sta SBUF+1,x
        rts
; the string at XA
sstr:   sta DQ
        stx DQ+1
        ldy #0
@l:     lda (DQ),y
        beq @e
        sty CNT
        jsr sput
        ldy CNT
        iny
        bne @l
@e:     rts

; --- clock ------------------------------------------------------------------------------------
clock:  TK TK_SETPORT           ; r0-r3 = its contents
        jsr sbegin
        lda CLOCKH
        jsr s2dig
        lda #':'
        jsr sput
        lda CLOCKM
        jsr s2dig
        lda #':'
        jsr sput
        lda CLOCKS
        jsr s2dig
        lda r0                  ; centred: (x0 + x1) / 2 - 32
        clc
        adc r2
        sta D0
        lda r0+1
        adc r2+1
        lsr
        ror D0
        sta D0+1
        SUBW D0, D0, 32
        lda D0
        sta BX0
        lda D0+1
        sta BX0H
        ADDW D1, r1, 4
        lda D1
        sta BY0
        lda D1+1
        sta BY0H
        lda #0
        sta ROP
        lda #S_BOLD + S_OPAQUE
        sta STYLE
        ldx #0
@c:     lda SBUF,x
        beq @e
        sta CHOUT
        inx
        bne @c
@e:     lda #0
        sta STYLE
        rts
s2dig:  ldx #'0'
@t:     cmp #10
        bcc @o
        sbc #10
        inx
        bne @t
@o:     pha
        txa
        jsr sput
        pla
        ora #'0'
        jmp sput

; --- calculator ------------------------------------------------------------------------------
; 32-bit whole numbers: + - * /, = (or Enter), C clears, Backspace erases a
; digit. Keys or clicks on its buttons.

calc:   TK TK_SETPORT           ; everything: display and buttons
        jsr display
        lda #0
        sta D3
@b:     jsr btnrect
        lda #0
        sta ROP
        lda #1
        sta BCOL
        lda #C_BOX
        sta BCMD
        ADDW D0, D0, 15         ; the label in the middle
        ADDW D1, D1, 7
        lda D0
        sta BX0
        lda D0+1
        sta BX0H
        lda D1
        sta BY0
        lda D1+1
        sta BY0H
        lda #S_BOLD
        sta STYLE
        ldx D3
        lda labels,x
        sta CHOUT
        lda #0
        sta STYLE
        inc D3
        lda D3
        cmp #16
        bne @b
        rts
labels: .byte "789/456*123-C0=+"

; Blitter X0..Y1 = button D3 (D0, D1 = its top left)
btnrect:
        lda D3
        and #3
        tax
        lda r0
        clc
        adc bxo,x
        sta D0
        sta BX0
        lda r0+1
        adc #0
        sta D0+1
        sta BX0H
        lda D3
        lsr
        lsr
        tax
        lda r1
        clc
        adc byo,x
        sta D1
        sta BY0
        lda r1+1
        adc #0
        sta D1+1
        sta BY0H
        ADDW D2, D0, 36
        lda D2
        sta BX1
        lda D2+1
        sta BX1H
        ADDW D2, D1, 29
        lda D2
        sta BY1
        lda D2+1
        sta BY1H
        rts
bxo:    .byte 9, 49, 89, 129
byo:    .byte 40, 74, 108, 142

; The number display (r0-r3 = the window's contents)
display:
        lda #0
        sta ROP
        sta PATON
        ADDW D0, r0, 8
        ADDW D1, r1, 6
        SUBW D2, r2, 8
        lda D0
        sta BX0
        lda D0+1
        sta BX0H
        lda D1
        sta BY0
        lda D1+1
        sta BY0H
        lda D2
        sta BX1
        lda D2+1
        sta BX1H
        ADDW D1, r1, 28
        lda D1
        sta BY1
        lda D1+1
        sta BY1H
        lda #0
        sta BCOL
        lda #C_BOXF
        sta BCMD
        lda #1
        sta BCOL
        lda #C_BOX
        sta BCMD
        jsr sbegin              ; the number (or "Error")
        lda ERR
        beq @num
        lda #<s_error
        ldx #>s_error
        jsr sstr
        jmp @show
@num:   ldx #3
        lda ENT
        bne @cur
@acc:   lda ACC,x
        sta A32,x
        dex
        bpl @acc
        bmi @p
@cur:   lda CUR,x
        sta A32,x
        dex
        bpl @cur
@p:     jsr print32
@show:  lda SLEN                ; right-aligned: x = r2 - 12 - len * 8
        asl
        asl
        asl
        sta D2
        SUBW D0, r2, 12
        lda D0
        sec
        sbc D2
        sta BX0
        lda D0+1
        sbc #0
        sta BX0H
        ADDW D1, r1, 9
        lda D1
        sta BY0
        lda D1+1
        sta BY0H
        lda #S_BOLD
        sta STYLE
        ldx #0
@c:     lda SBUF,x
        beq @e
        sta CHOUT
        inx
        bne @c
@e:     lda #0
        sta STYLE
        rts
s_error: .byte "Error", 0

; A click: which button?
cclick: stx CWIN
        SUBW D0, r0, 9          ; column: (x - 9) / 40, inside the first 37
        bmi @r
        lda D0+1
        bne @r
        lda D0
        ldx #0
@c:     cmp #40
        bcc @cd
        sbc #40
        inx
        cpx #4
        bne @c
        rts
@cd:    cmp #37
        bcs @r
        stx D3
        SUBW D1, r1, 40         ; row: (y - 40) / 34, inside the first 30
        bmi @r
        lda D1+1
        bne @r
        lda D1
        ldx #0
@w:     cmp #34
        bcc @wd
        sbc #34
        inx
        cpx #4
        bne @w
        rts
@wd:    cmp #30
        bcs @r
        txa
        asl
        asl
        ora D3
        sta D3
        ldx CWIN                ; the button blinks
        TK TK_SETPORT
        jsr btnrect
        jsr invbtn
        ldy #5
@wt:    lda FRAME
@wf:    cmp FRAME
        beq @wf
        dey
        bne @wt
        jsr btnrect
        jsr invbtn
        ldx D3
        lda labels,x
        ldx CWIN
        jmp ckey
@r:     rts
invbtn: lda #R_INV
        sta ROP
        lda #C_BOXF
        sta BCMD
        lda #R_SET
        sta ROP
        rts

; A key (A) for the calculator in window X
ckey:   stx CWIN
        cmp #'c'
        beq @clr
        cmp #'C'
        beq @clr
        cmp #27
        beq @clr
        cmp #13
        bne @k1
        lda #'='
@k1:    cmp #'0'
        bcc @op
        cmp #'9'+1
        bcs @op
        and #$0F                ; a digit: CUR = CUR * 10 + d
        pha
        lda ERR
        bne @pd
        lda ENT
        bne @more
        jsr curzero
        lda #1
        sta ENT
@more:  ldx #3
@cp:    lda CUR,x
        sta A32,x
        dex
        bpl @cp
        lda #10
        jsr setb
        jsr mul32
        pla
        clc
        adc A32
        sta CUR
        ldx #1
@cy:    lda A32,x
        adc #0
        sta CUR,x
        inx
        cpx #4
        bne @cy
        jmp redisp
@pd:    pla
        rts
@clr:   lda #0
        sta ERR
        sta ENT
        sta OP
        jsr curzero
        ldx #3
@z:     sta ACC,x
        dex
        bpl @z
        jmp redisp
@op:    cmp #8                  ; Backspace: CUR / 10
        bne @o2
        lda ENT
        beq @rts
        jsr cur2a
        lda #10
        jsr setb
        jsr div32
        jsr a2cur
        jmp redisp
@o2:    ldx #5
@f:     dex
        bmi @rts
        cmp ops,x
        bne @f
        pha
        jsr apply               ; the pending operation first
        pla
        cmp #'='
        bne @set
        lda #0
@set:   sta OP
        jmp redisp
@rts:   rts
ops:    .byte "+-*/="

; ACC = ACC (OP) CUR if a number was typed; = also comes here
apply:  lda ENT
        beq @r
        lda #0
        sta ENT
        lda OP
        bne @calc
        ldx #3                  ; no operation yet: ACC = CUR
@c:     lda CUR,x
        sta ACC,x
        dex
        bpl @c
@r:     rts
@calc:  ldx #3
@a:     lda ACC,x
        sta A32,x
        lda CUR,x
        sta B32,x
        dex
        bpl @a
        lda OP
        cmp #'+'
        bne @n1
        jsr add32
        jmp @done
@n1:    cmp #'-'
        bne @n2
        jsr sub32
        jmp @done
@n2:    cmp #'*'
        bne @n3
        jsr mul32
        jmp @done
@n3:    jsr div32
@done:  ldx #3
@d:     lda A32,x
        sta ACC,x
        dex
        bpl @d
        rts

redisp: ldx CWIN
        TK TK_SETPORT
        jmp display

curzero:
        lda #0
        ldx #3
@z:     sta CUR,x
        dex
        bpl @z
        rts
cur2a:  ldx #3
@c:     lda CUR,x
        sta A32,x
        dex
        bpl @c
        rts
a2cur:  ldx #3
@c:     lda A32,x
        sta CUR,x
        dex
        bpl @c
        rts
setb:   sta B32
        lda #0
        sta B32+1
        sta B32+2
        sta B32+3
        rts

; --- 32-bit arithmetic on A32, B32 -------------------------------------------------------
add32:  clc
        ldx #0
@l:     lda A32,x
        adc B32,x
        sta A32,x
        inx
        txa
        eor #4
        bne @l
        rts
sub32:  sec
        ldx #0
@l:     lda A32,x
        sbc B32,x
        sta A32,x
        inx
        txa
        eor #4
        bne @l
        rts
; A32 = A32 * B32 (the low 32 bits: right for signed numbers too)
mul32:  ldx #3
@c:     lda A32,x
        sta R32,x
        lda #0
        sta A32,x
        dex
        bpl @c
        lda #32
        sta CNT
@l:     lsr R32+3               ; next bit of the multiplier
        ror R32+2
        ror R32+1
        ror R32
        bcc @n
        clc
        ldx #0
@a:     lda A32,x
        adc B32,x
        sta A32,x
        inx
        txa
        eor #4
        bne @a
@n:     asl B32
        rol B32+1
        rol B32+2
        rol B32+3
        dec CNT
        bne @l
        rts
; A32 = A32 / B32 (signed, towards 0); B32 = 0 sets ERR
div32:  lda B32
        ora B32+1
        ora B32+2
        ora B32+3
        bne @ok
        lda #1
        sta ERR
        rts
@ok:    lda A32+3
        eor B32+3
        sta SIGN
        lda A32+3
        bpl @ap
        jsr negA
@ap:    lda B32+3
        bpl @bp
        jsr negB
@bp:    lda #0                  ; unsigned: A32 = quotient, R32 = remainder
        sta R32
        sta R32+1
        sta R32+2
        sta R32+3
        lda #32
        sta CNT
@l:     asl A32
        rol A32+1
        rol A32+2
        rol A32+3
        rol R32
        rol R32+1
        rol R32+2
        rol R32+3
        sec                     ; R32 - B32
        lda R32
        sbc B32
        tax
        lda R32+1
        sbc B32+1
        tay
        lda R32+2
        sbc B32+2
        pha
        lda R32+3
        sbc B32+3
        bcc @no                 ; (the pushed byte is dropped)
        sta R32+3
        pla
        sta R32+2
        sty R32+1
        stx R32
        inc A32
        bne @nx
@no:    pla
@nx:    dec CNT
        bne @l
        lda SIGN
        bpl @r
        jsr negA
@r:     rts
negA:   ldx #A32
        bne neg
negB:   ldx #B32
neg:    sec
        lda #0
        sbc 0,x
        sta 0,x
        lda #0
        sbc 1,x
        sta 1,x
        lda #0
        sbc 2,x
        sta 2,x
        lda #0
        sbc 3,x
        sta 3,x
        rts

; A32 as signed decimal into SBUF
print32:
        lda A32+3
        bpl @pos
        lda #'-'
        jsr sput
        jsr negA
@pos:   lda #0                  ; digits backwards onto the stack
        sta DIGN
@d:     lda #10                 ; (positive now)
        jsr setb
        jsr div32
        lda R32                 ; the remainder is the digit
        ora #'0'
        pha
        inc DIGN
        lda A32
        ora A32+1
        ora A32+2
        ora A32+3
        bne @d
@o:     pla
        jsr sput
        dec DIGN
        bne @o
        rts



; --- variables -----------------------------------------------------------------------------
OPENF:  .byte 0, 0              ; open (shown again after CLEAR)
LASTSEC: .byte 0
SLEN:   .byte 0
CWIN:   .byte 0
ACC:    .byte 0, 0, 0, 0
CUR:    .byte 0, 0, 0, 0
OP:     .byte 0
ENT:    .byte 0
ERR:    .byte 0
DIGN:   .byte 0
SBUF:   .res 16
ZPSAVE: .res $30
        .assert * <= $F000, error, "ACC must fit in its bank"
