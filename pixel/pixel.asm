;=============================================================================
; pixel.asm - PIXEL, a full-screen colour pixel editor (160 x 200, 31
; colours and transparency) for pictures and sprites
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
;
; A main-RAM program ($0800), not a toolkit one: the whole screen is the
; picture (graphics, MODE 1). Space shows the tool menu and Tab the colours
; in the text layer over it (MODE 2: text on the see-through colour 0 lets
; the picture show). The picture is VRAM page 0 itself, page 1 its undo
; copy. Transparent pixels are $80 (bit 7: sprites, COPY 7 and STAMP skip
; them); they show palette colour 0.
; Main RAM: $0800 the program, $2000-$3FFF the bucket's stack,
; $4000-$BFFF loading, saving, the bucket's copy.
;=============================================================================

        .include "mini6502.inc"
        .macpack longbranch

WORK    = $4000
PICSZ   = 32000
PAGE1   = $7D00                 ; VRAM page 1: the undo copy
FSTK    = $2000                 ; the bucket's seeds (x, y)
FSTKEND = $3FFE
SPRSZ   = 120 * 256             ; the sprites file: 10 x 12 cells of 16 x 16
SIMG    = 200                   ; sprite images: 200-230 the colours'
FIMG    = 231                   ;   swatches, 231 the 16 x 16 frame
TBOX    = $1F                   ; the menus' colours: white on blue
THI     = $4F                   ;   chosen: white on red
CR      = 13

T_PENCIL = 0                    ; the tools
T_ERASE = 1
T_PICK  = 2
T_FILL  = 3
T_LINE  = 4
T_RECT  = 5
T_BOX   = 6
T_OVAL  = 7
T_DISC  = 8
NTOOL   = 9

; zero page
P0      = $80
P1      = $82
DS      = $84                   ; DMA: source, destination (3 bytes),
DD      = $87                   ; length
DL      = $8A
TOOL    = $8C
CUR     = $8D                   ; the colour (0 = transparent, 1-31)
CB      = $8E                   ; the byte it paints
GRID    = $8F
DIRTY   = $90
MX      = $91                   ; the mouse (160 x 200)
MY      = $92
LX      = $93
LY      = $94
SX      = $95
SY      = $96
X0      = $97
Y0      = $98
X1      = $99
Y1      = $9A
TMP     = $9B
TMP2    = $9C
CNT     = $9D
SAVSP   = $9E
KCH     = $9F
KEXT    = $A0
TARGET  = $A1
XL      = $A2
XR      = $A3
FY      = $A4
NY      = $A5
INRUN   = $A6
RXO     = $A7
RYO     = $A8
CXC     = $A9
CYC     = $AA
DYC     = $AB
PDX     = $AC
CDX     = $AD
TACC    = $AE                   ; 2 bytes
TSTEP   = $B0                   ; 2 bytes
N0      = $B2                   ; 2 bytes
PREVX0  = $B4                   ; the rubber band's last box
PREVY0  = $B5
PREVX1  = $B6
PREVY1  = $B7
SEL     = $B8                   ; the colour menu's choice
OLDMODE = $B9
FLEN    = $BA
CNT2    = TMP2
FSELN   = $BB

;=============================================================================
; PIXEL: the bank part, a loader. The desktop starts it as it does EDIT:
; $E000 an empty picture, $E006 the picture named at $EF80. It loads
; PIXEL2 (here, at the top, or in /PIXEL) and runs it.
;=============================================================================
NAMEIN  = $EF80
        .segment "BANK"
        jmp sstart              ; $E000 an empty picture
        .byte "PX", 0           ; (not a toolkit program)
        jmp sfile               ; $E006 the picture named at NAMEIN
sstart: lda #0
        sta NAMEIN
sfile:  lda #<s_p2
        ldx #>s_p2
        jsr sload
        beq @ok
        lda #<s_p2p
        ldx #>s_p2p
        jsr sload
        beq @ok
        ldx #0                  ; not there: said in text, a key, back
@m:     lda s_nop2,x
        beq @k
        sta DSP
        inx
        bne @m
@k:     lda KBDCR
        bpl @k
        lda KBD
        rts
@ok:    lda NAMEIN
        bne @f
        jmp start               ; (it returns here, then we do)
@f:     ldx #0
@c:     lda NAMEIN,x
        sta NAMEB,x
        beq @go
        inx
        cpx #40
        bne @c
        lda #0
        sta NAMEB,x
@go:    jmp startname
sload:  sta DNAME
        stx DNAME+1
        lda #0
        sta DNLEN
        sta DEND
        sta DEND+1
        lda #1
        sta DCMD
        lda DSTAT
        rts
s_p2:   .byte "PIXEL2", 0
s_p2p:  .byte "/PIXEL/PIXEL2", 0
s_nop2: .byte 13, "PIXEL2 is not on the disk: PIXEL needs it.", 13
        .byte "Press a key.", 0

;=============================================================================
; PIXEL2: the program, in main RAM ($0800)
;=============================================================================
        .segment "CODE"
        jmp start               ; $0800 an empty picture
        jmp startname           ; $0803 the picture named in NAMEB
NAMEB:  .res 44                 ; $0806
startname:
        tsx
        stx SAVSP
        jsr init
        jsr newpic
        jsr openname
        jmp loop
start:  tsx
        stx SAVSP
        jsr init
        jsr newpic
loop:   jsr frame
        jsr grid                ; the frame round the 16 x 16 cell
        lda KBDCR
        bpl @m
        jsr getkey
        jsr key
        jmp loop
@m:     lda CLICKS
        sta TMP
        and #2                  ; right button: the colour under it
        beq @l
        jsr mouse
        jsr pickat
        jmp loop
@l:     lda TMP
        and #1
        beq loop
        jsr mouse
        jsr snapshot
        lda TOOL
        asl
        tax
        lda tooltab+1,x
        pha
        lda tooltab,x
        pha
        rts                     ; the tool (it returns to loop)
tooltab:
        .word t_pencil-1, t_pencil-1, t_pick-1, t_fill-1, t_shape-1
        .word t_shape-1, t_shape-1, t_shape-1, t_shape-1

; The next frame
frame:  lda FRAME
@w:     cmp FRAME
        beq @w
        rts
; MX, MY = the mouse; carry set if the left button is up
mouse:  lda MOUSELX
        sta MX
        lda MOUSELY
        sta MY
        lda BUTTONS
        and #1
        eor #1
        lsr
        rts

; KCH, KEXT = the key
getkey: lda KBD
        and #$7F
        sta KCH
        lda #0
        sta KEXT
        lda KCH
        bne @r
        lda KBDEXT
        sta KEXT
@r:     rts

; --- start, quit --------------------------------------------------------------
init:   lda #1                  ; graphics, page 0
        sta MODE
        lda #0
        sta SHOW
        sta DRAW
        sta TRANSP
        sta GRID
        sta DIRTY
        sta FNAME
        lda #T_PENCIL
        sta TOOL
        lda #15
        jsr setcur
        ldx #31                 ; the pointer: a cross
@p:     lda ptrimg,x
        sta PTRIMG,x
        lda ptrmask,x
        sta PTRMASK,x
        dex
        bpl @p
        lda #7
        sta HOTX
        sta HOTY
        lda #3
        sta PTR
        lda #0                  ; the swatches: images 200-230 = colours
        sta PADR                ; 1-31 (12 x 12 inside 16 x 16), 231 the
        lda #SIMG               ; frame
        sta PADR+1
        lda #$FD
        sta PADR+2
        lda #1
        sta PSTEP
        sta CNT
@s:     ldy #0
@sr:    ldx #0
@sc:    lda #$80
        cpy #2
        bcc @sp
        cpy #14
        bcs @sp
        cpx #2
        bcc @sp
        cpx #14
        bcs @sp
        lda CNT
@sp:    sta PDATA
        inx
        cpx #16
        bne @sc
        iny
        cpy #16
        bne @sr
        inc CNT
        lda CNT
        cmp #32
        bne @s
        ldy #0                  ; the frame (white, 1 pixel)
@fr:    ldx #0
@fc:    lda #$80
        cpy #0
        beq @fw
        cpy #15
        beq @fw
        cpx #0
        beq @fw
        cpx #15
        bne @fp
@fw:    lda #15
@fp:    sta PDATA
        inx
        cpx #16
        bne @fc
        iny
        cpy #16
        bne @fr
        ldx #0                  ; no sprites on
        lda #0
@so:    sta SPR+3,x
        txa
        clc
        adc #8
        tax
        lda #0
        cpx #0
        bne @so
        lda #0                  ; the text layer: all see-through
        sta COLOR
        lda #2
        sta SYSCTL
        rts

; Quit (after asking if there are unsaved changes): the video as at
; power-on, back to whoever started us
quit:   jsr askchanges
        bcs @r
        lda #3                  ; video, sound, interrupts reset
        sta SYSCTL
        ldx SAVSP
        txs
        rts
@r:     rts

; A new picture: all transparent, the power-on palette
newpic: lda #$80
        sta DMAFILL
        lda #0
        sta DMASRC+3
        sta DMASRC+4
        sta DMASRC+8
        lda #$FE
        sta DMASRC+5
        lda #<PICSZ
        sta DMASRC+6
        lda #>PICSZ
        sta DMASRC+7
        lda #2
        sta DMACMD
        jsr snapshot
        lda #0
        sta DIRTY
        sta FNAME
        rts

; CUR = A; CB = the byte it paints
setcur: sta CUR
        cmp #0
        bne @c
        lda #$80
@c:     sta CB
        rts

; --- DMA ----------------------------------------------------------------------
dma:    ldx #2
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
; DS / DD = VRAM page 0, page 1, main RAM WORK
dspg0:  lda #0
        sta DS
        sta DS+1
        beq dsfe
dspg1:  lda #<PAGE1
        sta DS
        lda #>PAGE1
        sta DS+1
dsfe:   lda #$FE
        sta DS+2
        rts
ddpg0:  lda #0
        sta DD
        sta DD+1
        beq ddfe
ddpg1:  lda #<PAGE1
        sta DD
        lda #>PAGE1
        sta DD+1
ddfe:   lda #$FE
        sta DD+2
        rts
dswork: lda #<WORK
        sta DS
        lda #>WORK
        sta DS+1
        lda #$FF
        sta DS+2
        rts
ddwork: lda #<WORK
        sta DD
        lda #>WORK
        sta DD+1
        lda #$FF
        sta DD+2
        rts
dlpic:  lda #<PICSZ
        sta DL
        lda #>PICSZ
        sta DL+1
        rts

; The picture -> its undo copy (before a change)
snapshot:
        jsr dspg0
        jsr ddpg1
        jsr dlpic
        jmp dma
; Undo: the picture and its copy swapped (so Undo again puts it back)
undo:   jsr dspg0
        jsr ddwork
        jsr dlpic
        jsr dma
        jsr dspg1
        jsr ddpg0
        jsr dma
        jsr dswork
        jsr ddpg1
        jsr dma
        lda #1
        sta DIRTY
        rts

; --- the tools ----------------------------------------------------------------
; Blitter: X0, Y0 (and X1, Y1) from the zero page bytes X / Y
bxy0:   lda 0,x
        sta BX0
        lda 0,y
        sta BY0
        lda #0
        sta BX0H
        sta BY0H
        rts
bxy1:   lda 0,x
        sta BX1
        lda 0,y
        sta BY1
        lda #0
        sta BX1H
        sta BY1H
        rts

; Pencil (and eraser: CB = transparent): lines following the mouse
t_pencil:
        lda CB
        ldx TOOL
        cpx #T_ERASE
        bne @c
        lda #$80
@c:     sta BCOL
        jsr mtol
@seg:   ldx #LX
        ldy #LY
        jsr bxy0
        ldx #MX
        ldy #MY
        jsr bxy1
        lda #C_LINE
        sta BCMD
        jsr mtol
@l:     jsr frame
        jsr mouse
        bcs @up
        lda MX
        cmp LX
        bne @seg
        lda MY
        cmp LY
        bne @seg
        beq @l
@up:    jmp done
mtol:   lda MX
        sta LX
        lda MY
        sta LY
        rts
; After a change: the click read (the release is not one), marked changed
done:   lda CLICKS
        lda #1
        sta DIRTY
        jmp loop

; Picker: the colour under the mouse
t_pick: jsr pickat
@w:     jsr mouse               ; (till the button is up)
        bcc @w
        lda CLICKS
        jmp loop
pickat: ldx #MX
        ldy #MY
        jsr bxy0
        lda BPIXEL
        bmi @t
        and #31
        jmp setcur
@t:     lda #0
        jmp setcur

; Line, rectangles, ovals: drawn as the mouse moves, the picture as it
; was (page 1) put back under the last one each time
t_shape:
        lda MX
        sta SX
        lda MY
        sta SY
        jsr mtol
        lda #0
        sta PREVX0
        sta PREVY0
        sta PREVX1
        sta PREVY1
        jsr shape
@l:     jsr frame
        jsr mouse
        bcs @up
        lda MX
        cmp LX
        bne @mv
        lda MY
        cmp LY
        beq @l
@mv:    jsr mtol
        jsr restore
        jsr shape
        jmp @l
@up:    jmp done

; The last shape's box back from page 1
restore:
        lda PREVX0
        sta BX0
        sta BDX
        lda PREVY0
        sta BY0
        sta BDY
        lda PREVX1
        sta BX1
        lda PREVY1
        sta BY1
        lda #0
        sta BX0H
        sta BY0H
        sta BX1H
        sta BY1H
        sta BDXH
        sta BDYH
        lda #1
        sta BSRC
        lda #C_COPY
        sta BCMD
        lda #0
        sta BSRC
        rts

; X0..Y1 = SX, SY .. LX, LY in order
order:  lda SX
        ldx LX
        cmp LX
        bcc @x
        stx X0
        sta X1
        bcs @y
@x:     sta X0
        stx X1
@y:     lda SY
        ldx LY
        cmp LY
        bcc @y2
        stx Y0
        sta Y1
        bcs @r
@y2:    sta Y0
        stx Y1
@r:     rts

; The tool's shape from S to L, in CB; its box kept for restore
shape:  jsr order
        lda X0
        sta PREVX0
        lda Y0
        sta PREVY0
        lda X1
        sta PREVX1
        lda Y1
        sta PREVY1
        lda CB
        sta BCOL
        lda TOOL
        cmp #T_LINE
        bne @n1
        ldx #SX
        ldy #SY
        jsr bxy0
        ldx #LX
        ldy #LY
        jsr bxy1
        lda #C_LINE
        sta BCMD
        rts
@n1:    cmp #T_RECT
        bne @n2
        lda #C_BOX
        bne @box
@n2:    cmp #T_BOX
        bne @n3
        lda #C_BOXF
@box:   pha
        ldx #X0
        ldy #Y0
        jsr bxy0
        ldx #X1
        ldy #Y1
        jsr bxy1
        pla
        sta BCMD
        rts
@n3:    jmp oval                ; T_OVAL, T_DISC

; The oval in X0..Y1: outline (T_OVAL) or filled (T_DISC), row by row
oval:   lda X1
        sec
        sbc X0
        lsr
        sta RXO
        clc
        adc X0
        sta CXC
        lda Y1
        sec
        sbc Y0
        lsr
        sta RYO
        clc
        adc Y0
        sta CYC
        lda #0
        sta TACC
        sta TACC+1
        sta DYC
        lda RXO
        sta PDX
        lda RYO                 ; TSTEP = 65535 / RYO
        beq @row
        lda #$FF
        sta N0
        sta N0+1
        lda RYO
        jsr div16
        lda N0
        sta TSTEP
        lda N0+1
        sta TSTEP+1
@row:   lda DYC
        cmp RYO
        bne @w
        lda #0
        ldx RYO
        bne @h
        lda RXO
        jmp @h
@w:     ldx TACC+1              ; CDX = RXO - RXO * shrink[t] / 256
        lda shrink,x
        jsr mul8                ; A = RXO * A / 256
        sta TMP
        lda RXO
        sec
        sbc TMP
@h:     sta CDX
        lda CYC
        clc
        adc DYC
        jsr ospan
        lda DYC
        beq @nx
        lda CYC
        sec
        sbc DYC
        jsr ospan
@nx:    lda CDX
        sta PDX
        lda TACC
        clc
        adc TSTEP
        sta TACC
        lda TACC+1
        adc TSTEP+1
        sta TACC+1
        lda DYC
        cmp RYO
        beq @r
        inc DYC
        jmp @row
@r:     rts
; Row A of the oval
ospan:  sta BY0
        sta BY1
        lda #0
        sta BX0H
        sta BY0H
        sta BX1H
        sta BY1H
        lda TOOL
        cmp #T_DISC
        bne @o
        lda CXC                 ; filled: CXC - CDX .. CXC + CDX
        sec
        sbc CDX
        sta BX0
        lda CXC
        clc
        adc CDX
        sta BX1
        lda #C_LINE
        sta BCMD
        rts
@o:     lda CDX                 ; the outline: CDX .. max(CDX, PDX - 1)
        sta TMP                 ; on each side
        lda DYC
        beq @s
        ldx PDX
        dex
        cpx TMP
        bcc @s
        stx TMP
@s:     lda CXC
        clc
        adc CDX
        sta BX0
        lda CXC
        clc
        adc TMP
        sta BX1
        lda #C_LINE
        sta BCMD
        lda CXC
        sec
        sbc TMP
        sta BX0
        lda CXC
        sec
        sbc CDX
        sta BX1
        lda #C_LINE
        sta BCMD
        rts

; N0 = N0 / A
div16:  sta TMP
        lda #0
        ldx #16
@l:     asl N0
        rol N0+1
        rol a
        bcs @s
        cmp TMP
        bcc @n
@s:     sbc TMP
        inc N0
@n:     dex
        bne @l
        rts
; A = RXO * A / 256
mul8:   sta TMP
        lda #0
        sta TMP2
        ldx #8
@l:     lsr TMP
        bcc @n
        clc
        adc RXO
@n:     ror a
        ror TMP2
        dex
        bne @l
        rts

; --- the bucket ----------------------------------------------------------------
; The area of the clicked pixel's byte, filled with CB: worked on a copy of
; the picture in WORK (a byte a pixel), then copied back
t_fill: jsr dspg0
        jsr ddwork
        jsr dlpic
        jsr dma
        ldy MY
        jsr rowp                ; P0 = row MY
        ldy MX
        lda (P0),y
        sta TARGET
        cmp CB
        jeq @end                ; already that colour
        lda #<FSTK
        sta P1
        lda #>FSTK
        sta P1+1
        ldx MX
        ldy MY
        jsr push
@pop:   lda P1
        cmp #<FSTK
        bne @go
        lda P1+1
        cmp #>FSTK
        beq @back
@go:    lda P1
        sec
        sbc #2
        sta P1
        bcs @g1
        dec P1+1
@g1:    ldy #1
        lda (P1),y
        sta FY
        dey
        lda (P1),y
        sta XL
        ldy FY
        jsr rowp
        ldy XL
        lda (P0),y
        cmp TARGET
        bne @pop
@sl:    cpy #0                  ; left
        beq @sld
        dey
        lda (P0),y
        cmp TARGET
        beq @sl
        iny
@sld:   sty XL
        ldy XL
@sr:    cpy #159                ; right
        beq @srd
        iny
        lda (P0),y
        cmp TARGET
        beq @sr
        dey
@srd:   sty XR
        lda CB                  ; the span
        ldy XL
@f:     sta (P0),y
        cpy XR
        beq @fd
        iny
        bne @f
@fd:    lda FY                  ; the rows above and below
        beq @b
        sec
        sbc #1
        jsr seeds
@b:     lda FY
        cmp #199
        beq @p2
        clc
        adc #1
        jsr seeds
@p2:    jmp @pop
@back:  jsr dswork
        jsr ddpg0
        jsr dlpic
        jsr dma
@end:   jmp done
; Seeds on row A within XL..XR: the start of each run of TARGET
seeds:  sta NY
        tay
        jsr rowp
        lda #0
        sta INRUN
        ldy XL
@l:     lda (P0),y
        cmp TARGET
        bne @no
        lda INRUN
        bne @nx
        tya
        tax
        sty TMP2
        ldy NY
        jsr push
        ldy TMP2
        lda #1
        sta INRUN
        bne @nx
@no:    lda #0
        sta INRUN
@nx:    cpy XR
        beq @r
        iny
        bne @l
@r:     rts
; X, Y -> the stack (if there is room)
push:   lda P1
        cmp #<FSTKEND
        lda P1+1
        sbc #>FSTKEND
        bcs @r
        tya
        pha
        txa
        ldy #0
        sta (P1),y
        pla
        iny
        sta (P1),y
        lda P1
        clc
        adc #2
        sta P1
        bcc @r
        inc P1+1
@r:     rts
; P0 = WORK + Y * 160
rowp:   lda #0
        sta P0+1
        tya
        asl                     ; * 32
        rol P0+1
        asl
        rol P0+1
        asl
        rol P0+1
        asl
        rol P0+1
        asl
        rol P0+1
        sta P0
        lda P0+1
        sta TMP
        lda P0                  ; + * 128 (= * 32 * 4)
        asl
        rol TMP
        asl
        rol TMP
        clc
        adc P0
        sta P0
        lda TMP
        adc P0+1
        sta P0+1
        lda P0
        clc
        adc #<WORK
        sta P0
        lda P0+1
        adc #>WORK
        sta P0+1
        rts

; --- the 16 x 16 grid: sprite 0 frames the cell under the mouse ---------------
grid:   lda GRID
        beq @off
        lda MOUSELX
        and #$F0
        clc
        adc #16
        sta SPR
        lda MOUSELY
        and #$F0
        clc
        adc #16
        sta SPR+1
        lda #FIMG
        sta SPR+2
        lda #1
        sta SPR+3
        rts
@off:   lda #0
        sta SPR+3
        rts

; --- keys -------------------------------------------------------------------------
key:    lda KCH
        cmp #' '
        bne @n1
        jmp toolmenu
@n1:    cmp #9
        bne @n2
        jmp colmenu
@n2:    cmp #$1A                ; Ctrl+Z, U: undo
        beq @u
        and #$DF
        cmp #'U'
        bne @n3
@u:     jmp undo
@n3:    cmp #'G'
        bne @n4
        lda GRID
        eor #1
        sta GRID
        rts
@n4:    jsr toolkey             ; a tool's letter
        rts

; A tool's letter in KCH: the tool chosen; carry set if it was one
toolkey:
        lda KCH
        and #$DF
        ldx #NTOOL - 1
@f:     cmp tkeys,x
        beq @t
        dex
        bpl @f
        clc
        rts
@t:     stx TOOL
        sec
        rts
tkeys:  .byte "PEKFLRBOD"

; --- the text layer -----------------------------------------------------------
; Text at row Y, column X, colour A: the string after the JSR (ends with 0)
print:  sta COLOR
        stx CURX
        sty CURY
        pla
        sta P1
        pla
        sta P1+1
        ldy #1
@l:     lda (P1),y
        beq @e
        sta DSP
        iny
        bne @l
@e:     tya
        clc
        adc P1
        tax
        lda P1+1
        adc #0
        pha
        txa
        pha
        rts
; The string at P1 (ends with 0) where the cursor is
prstr:  ldy #0
@l:     lda (P1),y
        beq @r
        sta DSP
        iny
        bne @l
@r:     rts
; A box: X0..X1 columns, Y0..Y1 rows, colour A, spaces inside
box:    sta COLOR
        lda Y0
        sta CNT
@r:     lda X0
        sta CURX
        lda CNT
        sta CURY
        ldx X0
@c:     lda #' '
        sta DSP
        cpx X1
        beq @n
        inx
        bne @c
@n:     lda CNT
        cmp Y1
        beq @e
        inc CNT
        bne @r
@e:     rts
; A in decimal (3 places) where the cursor is
pdec:   ldx #'0' - 1
        sec
@h:     inx
        sbc #100
        bcs @h
        adc #100
        stx DSP
        ldx #'0' - 1
        sec
@t:     inx
        sbc #10
        bcs @t
        adc #10
        stx DSP
        ora #'0'
        sta DSP
        rts
; The terminal's blinking cursor hidden: at the box's top left corner (X0,
; Y0), in a colour A whose ink is its paper
hidecur:
        sta COLOR
        lda X0
        sta CURX
        lda Y0
        sta CURY
        rts
; The text layer: all see-through again, graphics alone
textoff:
        lda #0
        sta COLOR
        lda #2
        sta SYSCTL
        lda #1
        sta MODE
        rts

; --- the tool menu (Space) -------------------------------------------------------
toolmenu:
        lda #0
        sta SPR+3               ; (no grid frame meanwhile)
@draw:  lda #2
        sta MODE
        lda #24
        sta X0
        lda #55
        sta X1
        lda #3
        sta Y0
        lda #20
        sta Y1
        lda #TBOX
        jsr box
        ldx #26
        ldy #3
        lda #TBOX
        jsr print
        .byte "PIXEL  (Space: back)", 0
        lda #0                  ; the tools, the one in use marked
        sta CNT
@t:     lda CNT
        clc
        adc #5
        sta CURY
        lda #27
        sta CURX
        lda #TBOX
        ldx CNT
        cpx TOOL
        bne @tc
        lda #THI
@tc:    sta COLOR
        lda CNT
        asl
        asl
        asl
        asl
        clc
        adc #<tnames
        sta P1
        lda #>tnames
        adc #0
        sta P1+1
        jsr prstr
        inc CNT
        lda CNT
        cmp #NTOOL
        bne @t
        ldx #27
        ldy #15
        lda #TBOX
        jsr print
        .byte "G  grid: ", 0
        lda GRID
        bne @g1
        jsr print2
        .byte "off", 0
        jmp @g2
@g1:    jsr print2
        .byte "on ", 0
@g2:    ldx #27
        ldy #16
        lda #TBOX
        jsr print
        .byte "U  undo   Tab colours", 0
        ldx #27
        ldy #17
        lda #TBOX
        jsr print
        .byte "1 New     2 Open", 0
        ldx #27
        ldy #18
        lda #TBOX
        jsr print
        .byte "3 Save    4 Save as", 0
        ldx #27
        ldy #19
        lda #TBOX
        jsr print
        .byte "5 Sprites 0 Quit", 0
        ldx #27
        ldy #20
        lda #TBOX
        jsr print
        .byte "File: ", 0
        lda FNAME
        bne @fn
        jsr print2
        .byte "(none)", 0
        jmp @wait
@fn:    lda #<FNAME
        sta P1
        lda #>FNAME
        sta P1+1
        jsr prstr
@wait:  lda #TBOX & $F0 | TBOX >> 4
        jsr hidecur
        lda CLICKS              ; (old clicks forgotten)
@k:     jsr frame
        lda CLICKS
        and #1
        jne @click
        lda KBDCR
        bpl @k
        jsr getkey
        lda KCH
        cmp #' '
        jeq @close
        cmp #27
        jeq @close
        cmp #9
        bne @n0
        jsr textoff
        jmp colmenu
@n0:    jsr toolkey
        bcs @close
        lda KCH
        and #$DF
        cmp #'G'
        bne @n1
        lda GRID
        eor #1
        sta GRID
        jmp @draw
@n1:    cmp #'U'
        bne @n2
        jsr undo
        jmp @close
@n2:    lda KCH
        cmp #'1'
        bne @n3
        jsr textoff
        jmp f_new
@n3:    cmp #'2'
        bne @n4
        jsr textoff
        jmp f_open
@n4:    cmp #'3'
        bne @n5
        jsr textoff
        jmp f_save
@n5:    cmp #'4'
        bne @n6
        jsr textoff
        jmp f_saveas
@n6:    cmp #'5'
        bne @n7
        jsr textoff
        jmp f_sprites
@n7:    cmp #'0'
        jne @k
        jsr textoff
        jmp quit
@click: lda MOUSECOL            ; a click on a tool's line: that tool
        cmp #27
        bcc @close
        cmp #50
        bcs @close
        lda MOUSEROW
        sec
        sbc #5
        bcc @close
        cmp #NTOOL
        bcs @close
        sta TOOL
@close: jsr textoff
@cr:    jsr mouse               ; (till the button is up)
        bcc @cr
        lda CLICKS
        rts
; print, at the cursor (colour kept)
print2: pla
        sta P1
        pla
        sta P1+1
        ldy #1
@l:     lda (P1),y
        beq @e
        sta DSP
        iny
        bne @l
@e:     tya
        clc
        adc P1
        tax
        lda P1+1
        adc #0
        pha
        txa
        pha
        rts
tnames: .byte "P  pencil      ", 0
        .byte "E  eraser      ", 0
        .byte "K  picker      ", 0
        .byte "F  fill        ", 0
        .byte "L  line        ", 0
        .byte "R  rectangle   ", 0
        .byte "B  box (filled)", 0
        .byte "O  oval        ", 0
        .byte "D  disc        ", 0

; --- the colour menu (Tab) ------------------------------------------------------
; The 31 colours are sprites (images 200-230), colour 0 the see-through one;
; sprite 0 frames the one chosen. Arrows or a click choose; Q/A, W/S, E/D
; change its red, green, blue.
colmenu:
        lda CUR
        sta SEL
        lda #2
        sta MODE
        lda #6
        sta X0
        lda #73
        sta X1
        lda #2
        sta Y0
        lda #18
        sta Y1
        lda #TBOX
        jsr box
        lda #0                  ; the swatches' places: see-through
        sta COLOR
        lda #4
        sta CNT
@hole:  lda #8
        sta CURX
        lda CNT
        sta CURY
        ldx #64
@hc:    lda #' '
        sta DSP
        dex
        bne @hc
        inc CNT
        lda CNT
        cmp #12
        bne @hole
        lda #4                  ; colour 0: marked as see-through (a
        sta CURY                ; shaded block: VCHR, since DSP prints only
@sh0:   ldx #8                  ; characters 32-126)
@sh1:   stx CURX
        lda #176
        sta VCHR
        lda #$87
        sta VCOL
        inx
        cpx #16
        bne @sh1
        inc CURY
        lda CURY
        cmp #6
        bne @sh0
        ldx #8
        ldy #2
        lda #TBOX
        jsr print
        .byte "Colours  (Tab: back)", 0
        ldx #8
        ldy #14
        lda #TBOX
        jsr print
        .byte "Arrows / click: choose   Enter: take it", 0
        ldx #8
        ldy #15
        lda #TBOX
        jsr print
        .byte "Q/A red  W/S green  E/D blue  (up/down)", 0
        ldx #1                  ; sprites 1-31: colours 1-31
@sw:    txa
        asl
        asl
        asl
        tay
        txa                     ; x = 16 + 16 * (i AND 7) (+ 16)
        and #7
        asl
        asl
        asl
        asl
        clc
        adc #32
        sta SPR,y
        txa                     ; y = 32 + 16 * (i / 8) (+ 16)
        lsr
        lsr
        lsr
        asl
        asl
        asl
        asl
        clc
        adc #48
        sta SPR+1,y
        txa
        clc
        adc #SIMG - 1
        sta SPR+2,y
        lda #1
        sta SPR+3,y
        inx
        cpx #32
        bne @sw
@show:  lda SEL                 ; sprite 0: the frame on the choice
        and #7
        asl
        asl
        asl
        asl
        clc
        adc #32
        sta SPR
        lda SEL
        lsr
        lsr
        lsr
        asl
        asl
        asl
        asl
        clc
        adc #48
        sta SPR+1
        lda #FIMG
        sta SPR+2
        lda #1
        sta SPR+3
        jsr rgbline
        lda #TBOX & $F0 | TBOX >> 4
        jsr hidecur
@k:     jsr frame
        lda CLICKS
        and #1
        bne @click
        lda KBDCR
        bpl @k
        jsr getkey
        lda KCH
        beq @ext
        cmp #9
        jeq @take
        cmp #CR
        jeq @take
        cmp #27
        jeq @back
        cmp #' '
        jeq @take
        and #$DF
        ldx #5
@ck:    cmp rgbkeys,x
        beq @rgb
        dex
        bpl @ck
        bmi @k
@rgb:   jsr palchg
        jmp @show
@ext:   lda KEXT
        cmp #1
        bne @e2
        lda SEL
        sec
        sbc #8
        bcc @k
        bcs @set
@e2:    cmp #2
        bne @e3
        lda SEL
        clc
        adc #8
        cmp #32
        bcs @k
        bcc @set
@e3:    cmp #3
        bne @e4
        lda SEL
        beq @k
        sec
        sbc #1
        jmp @set
@e4:    cmp #4
        bne @k
        lda SEL
        cmp #31
        bcs @k
        adc #1
@set:   sta SEL
        jmp @show
@click: lda MOUSELX             ; on a swatch?
        sec
        sbc #16
        jcc @k
        cmp #128
        jcs @k
        lsr
        lsr
        lsr
        lsr
        sta TMP
        lda MOUSELY
        sec
        sbc #32
        jcc @k
        cmp #64
        jcs @k
        lsr
        lsr
        lsr
        lsr
        asl
        asl
        asl
        ora TMP
        jmp @set
@take:  lda SEL
        jsr setcur
@back:  ldx #0                  ; the sprites off
        lda #0
@off:   sta SPR+3,x
        txa
        clc
        adc #8
        tax
        lda #0
        cpx #0
        bne @off
        jsr textoff
@cr:    jsr mouse
        bcc @cr
        lda CLICKS
        rts
rgbkeys: .byte "QAWSED"

; The chosen colour's red, green and blue, shown
rgbline:
        ldx #8
        ldy #17
        lda #TBOX
        jsr print
        .byte "Colour ", 0
        lda SEL
        jsr pdec
        jsr print2
        .byte "   red ", 0
        lda SEL
        sta PALIDX
        lda PALR
        jsr pdec
        jsr print2
        .byte "  green ", 0
        lda PALG
        jsr pdec
        jsr print2
        .byte "  blue ", 0
        lda PALB
        jsr pdec
        rts

; Key X (0-5: Q A W S E D): the chosen colour's red / green / blue +/- 8
palchg: txa
        lsr
        tay                     ; 0 red, 1 green, 2 blue
        lda SEL
        sta PALIDX
        lda PALR,y
        sta TMP
        txa
        and #1
        bne @dn
        lda TMP
        clc
        adc #8
        bcc @s
        lda #255
        bne @s
@dn:    lda TMP
        sec
        sbc #8
        bcs @s
        lda #0
@s:     sta TMP
        lda SEL                 ; (the three written back: B moves PALIDX)
        sta PALIDX
        lda PALR
        sta RGB
        lda PALG
        sta RGB+1
        lda PALB
        sta RGB+2
        lda TMP
        sta RGB,y
        lda SEL
        sta PALIDX
        lda RGB
        sta PALR
        lda RGB+1
        sta PALG
        lda RGB+2
        sta PALB
        lda #1
        sta DIRTY
        rts

; --- files ------------------------------------------------------------------------
; A .PIX file: the 32,000 pixels, "PAL", the 32 colours' red, green, blue
; (96 bytes); saved with the load address $4000
PALAT   = WORK + PICSZ

f_new:  jsr askchanges
        bcs @r
        lda #3                  ; the power-on palette back
        sta SYSCTL
        jsr init
        jsr newpic
@r:     rts

f_open: jsr askchanges
        bcs openr
        jsr askname
        bcs openr
; The picture named in NAMEB, opened
openname:
        lda #3                  ; LOAD at WORK
        jsr disk
        lda DSTAT
        bne openbad
        jsr dswork              ; the pixels -> page 0
        jsr ddpg0
        jsr dlpic
        jsr dma
        lda PALAT               ; a palette after them?
        cmp #'P'
        bne @np
        lda PALAT+1
        cmp #'A'
        bne @np
        lda PALAT+2
        cmp #'L'
        bne @np
        lda #0
        sta PALIDX
        ldx #0
@pal:   lda PALAT+3,x
        sta PALR
        lda PALAT+4,x
        sta PALG
        lda PALAT+5,x
        sta PALB                ; (PALIDX moves on)
        inx
        inx
        inx
        cpx #96
        bne @pal
@np:    jsr snapshot
        jsr keepname
        lda #0
        sta DIRTY
openr:  rts
openbad:
        jsr message
        .byte "That file could not be loaded.", 0
        rts

f_save: lda FNAME
        bne savefile
f_saveas:
        jsr askname
        bcs saver
        jsr keepname
savefile:
        jsr dspg0               ; the pixels -> WORK, the palette after
        jsr ddwork
        jsr dlpic
        jsr dma
        lda #'P'
        sta PALAT
        lda #'A'
        sta PALAT+1
        lda #'L'
        sta PALAT+2
        lda #0
        sta PALIDX
        ldx #0
@pal:   lda PALR
        sta PALAT+3,x
        lda PALG
        sta PALAT+4,x
        lda PALB
        sta PALAT+5,x
        inc PALIDX              ; (reading B does not move it)
        inx
        inx
        inx
        cpx #96
        bne @pal
        jsr setfname
        lda #<(PALAT + 99)
        sta DEND
        lda #>(PALAT + 99)
        sta DEND+1
        lda #2
        sta DCMD
        lda DSTAT
        bne savebad
        lda #0
        sta DIRTY
        clc
saver:  rts
savebad:
        jsr message
        .byte "The picture could not be saved.", 0
        sec
        rts

; Sprites: the picture as 120 sprite images (10 across, 12 down, each 16 x
; 16: 16 rows of 16 bytes), the order of reading; a program loads them and
; copies them to $FD0000 + image * 256
f_sprites:
        jsr askname
        jcs @r
        lda #<WORK
        sta DD
        lda #>WORK
        sta DD+1
        lda #$FF
        sta DD+2
        lda #16
        sta DL
        lda #0
        sta DL+1
        sta CNT2                ; cell row 0-11
@cy:    lda #0
        sta CNT                 ; cell 0-9
@cx:    lda #0
        sta XR                  ; row in the cell (rowp uses TMP)
@r16:   lda CNT2                ; source: (cy * 16 + row) * 160 + cx * 16
        asl
        asl
        asl
        asl
        ora XR
        tay
        jsr rowp                ; P0 = WORK + y * 160: the offset + WORK
        lda P0
        sec
        sbc #<WORK
        sta DS
        lda P0+1
        sbc #>WORK
        sta DS+1
        lda CNT
        asl
        asl
        asl
        asl
        clc
        adc DS
        sta DS
        bcc @c1
        inc DS+1
@c1:    lda #$FE
        sta DS+2
        jsr dma
        lda DD
        clc
        adc #16
        sta DD
        bcc @c2
        inc DD+1
@c2:    inc XR
        lda XR
        cmp #16
        bne @r16
        inc CNT
        lda CNT
        cmp #10
        bne @cx
        inc CNT2
        lda CNT2
        cmp #12
        bne @cy
        lda #<NAMEB
        sta DNAME
        lda #>NAMEB
        sta DNAME+1
        lda #0
        sta DNLEN
        lda #<WORK
        sta DSTART
        lda #>WORK
        sta DSTART+1
        lda #<(WORK + SPRSZ)
        sta DEND
        lda #>(WORK + SPRSZ)
        sta DEND+1
        lda #2
        sta DCMD
        lda DSTAT
        beq @r
        jsr message
        .byte "The sprites could not be saved.", 0
@r:     rts

; DNAME = FNAME, DSTART = WORK
setfname:
        lda #<FNAME
        sta DNAME
        lda #>FNAME
        sta DNAME+1
        lda #0
        sta DNLEN
        lda #<WORK
        sta DSTART
        lda #>WORK
        sta DSTART+1
        rts
; Disk command A on NAMEB (LOAD at WORK, up to $C000)
disk:   pha
        lda #<NAMEB
        sta DNAME
        lda #>NAMEB
        sta DNAME+1
        lda #0
        sta DNLEN
        lda #<WORK
        sta DSTART
        lda #>WORK
        sta DSTART+1
        lda #0
        sta DEND
        lda #$C0
        sta DEND+1
        pla
        sta DCMD
        rts
; NAMEB -> FNAME
keepname:
        ldx #0
@c:     lda NAMEB,x
        sta FNAME,x
        beq @r
        inx
        cpx #40
        bne @c
        lda #0
        sta FNAME,x
@r:     rts

; A name typed in the text layer -> NAMEB (with .PIX added if it has no
; dot); carry set if Esc or nothing
askname:
        lda #2
        sta MODE
        lda #10
        sta X0
        lda #69
        sta X1
        lda #10
        sta Y0
        lda #12
        sta Y1
        lda #TBOX
        jsr box
        ldx #12
        ldy #10
        lda #TBOX
        jsr print
        .byte "File name (Enter: OK, Esc: cancel):", 0
        ldx #0                  ; it starts with the file's name
@c:     lda FNAME,x
        sta NAMEB,x
        beq @e
        inx
        bne @c
@e:     stx FLEN
        lda #1                  ; it is selected: the first key replaces it
        sta FSELN
@show:  lda #12
        sta CURX
        lda #11
        sta CURY
        lda #$70                ; black on grey: the field (selected:
        ldx FSELN               ; white on black)
        beq @fc
        lda #$0F
        ldx FLEN
        bne @fc
        lda #$70
@fc:    sta COLOR
        ldx #0
@sh:    lda NAMEB,x
        cpx FLEN
        bcc @p
        lda #' '
        cpx FLEN
        bne @p
        lda #'_'
@p:     sta DSP
        inx
        cpx #40
        bne @sh
        lda #TBOX & $F0 | TBOX >> 4
        jsr hidecur
@k:     jsr frame
        lda KBDCR
        bpl @k
        jsr getkey
        lda KCH
        bne @kc
        sta FSELN               ; (an arrow: unselected, kept)
        jmp @show
@kc:    cmp #27
        beq @no
        cmp #CR
        beq @ok
        cmp #8
        beq @bs
        cmp #127
        beq @bs
        cmp #' ' + 1
        bcc @k
        ldx FSELN
        beq @add1
        ldx #0
        stx FLEN
        stx FSELN
@add1:  ldx FLEN
        cpx #38
        bcs @k
        sta NAMEB,x
        inc FLEN
        jmp @show
@bs:    lda FSELN
        beq @bs1
        lda #0
        sta FLEN
        sta FSELN
        jmp @show
@bs1:   lda FLEN
        beq @k
        dec FLEN
        jmp @show
@ok:    ldx FLEN
        beq @no
        lda #0
        sta NAMEB,x
        ldx #0                  ; a dot in it? else .PIX
@d:     lda NAMEB,x
        beq @add
        cmp #'.'
        beq @done
        inx
        bne @d
@add:   ldy #0
@a:     lda s_pix,y
        sta NAMEB,x
        beq @done
        inx
        iny
        bne @a
@done:  jsr textoff
        clc
        rts
@no:    jsr textoff
        sec
        rts
s_pix:  .byte ".PIX", 0

; A message in the text layer (the string after the JSR), till a key or a
; click
message:
        lda #2
        sta MODE
        lda #10
        sta X0
        lda #69
        sta X1
        lda #10
        sta Y0
        lda #12
        sta Y1
        lda #THI
        jsr box
        lda #12
        sta CURX
        lda #11
        sta CURY
        pla
        sta P1
        pla
        sta P1+1
        ldy #1
@l:     lda (P1),y
        beq @e
        sta DSP
        iny
        bne @l
@e:     tya
        clc
        adc P1
        sta P1
        bcc @w
        inc P1+1
@w:     lda #THI & $F0 | THI >> 4
        jsr hidecur
        lda CLICKS
@k:     jsr frame
        lda CLICKS
        bne @x
        lda KBDCR
        bpl @k
        jsr getkey
@x:     jsr textoff
        lda P1+1
        pha
        lda P1
        pha
        rts

; Unsaved changes? Y saves, N does not, Esc: carry set (cancel)
askchanges:
        lda DIRTY
        bne @ask
        clc
        rts
@ask:   lda #2
        sta MODE
        lda #10
        sta X0
        lda #69
        sta X1
        lda #10
        sta Y0
        lda #12
        sta Y1
        lda #THI
        jsr box
        ldx #12
        ldy #11
        lda #THI
        jsr print
        .byte "Save the changes?  Y yes   N no   Esc cancel", 0
        lda #THI & $F0 | THI >> 4
        jsr hidecur
@k:     jsr frame
        lda KBDCR
        bpl @k
        jsr getkey
        lda KCH
        cmp #27
        beq @c
        and #$DF
        cmp #'N'
        beq @n
        cmp #'Y'
        bne @k
        jsr textoff
        jsr f_save
        rts                     ; (carry from the save)
@n:     jsr textoff
        clc
        rts
@c:     jsr textoff
        sec
        rts

; --- data -------------------------------------------------------------------------
ptrimg: .byte $01,$00,$01,$00,$01,$00,$01,$00,$01,$00,$01,$00,$00,$00,$FC,$7E
        .byte $00,$00,$01,$00,$01,$00,$01,$00,$01,$00,$01,$00,$01,$00,$00,$00
ptrmask: .byte $03,$80,$03,$80,$03,$80,$03,$80,$03,$80,$03,$80,$FF,$FF,$FE,$FF
        .byte $FF,$FF,$03,$80,$03,$80,$03,$80,$03,$80,$03,$80,$03,$80,$03,$80
        .include "../paint/paint_oval.inc"

RGB:    .res 3
FNAME:  .res 42
