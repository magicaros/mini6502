;=============================================================================
; hidemo.asm - mini6502 hires test: a desktop-like screen  (bank RAM $E000-$EFFF)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Draws a patterned desktop, a menu bar, a window listing the
; disk (DIR into memory, clipped to the window), a window of text styles and
; fill patterns, two icons; the mouse pointer follows the mouse, its position
; shows in the menu bar, and dragging with the left button draws an XOR
; rubber band box. Any key goes back to text.
;
;   L HIDEMO E000 0A      load into bank $0A (any bank works)
;   D020: 0A              select it
;   E000R                 run (or CALL $E000 from BASIC)
;
; Most of the screen is a "display list": pairs of (register - $D300, value)
; written in order, so a whole drawing is data. Zero page: $E2-$E3 only.
;=============================================================================


        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

PTRZ    = $E2           ; zero page pointer

; display list registers (offset from $D300)
R_X0 = $10
R_Y0 = $11
R_X1 = $12
R_Y1 = $13
R_COL = $14
R_CMD = $18
R_X0H = $1A
R_Y0H = $1B
R_X1H = $1C
R_Y1H = $1D
R_ROP = $28
R_PATON = $29
R_STYLE = $2B
R_OUT = $2C
R_PAT = $30
R_CLIP = $38
D_END = $FF


S_BOLD = 1
S_UNDER = 2
S_ITALIC = 4
S_INV = 8
S_OPAQUE = 16

BUF     = $EA00         ; the directory, in this bank (after the code)

.macro  DPOS px, py
        .byte R_X0, <(px), R_X0H, >(px), R_Y0, <(py), R_Y0H, >(py)
.endmacro
.macro  DRECT x0, y0, x1, y1
        DPOS x0, y0
        .byte R_X1, <(x1), R_X1H, >(x1), R_Y1, <(y1), R_Y1H, >(y1)
.endmacro
.macro  DCMD c, col
        .byte R_COL, col, R_CMD, c
.endmacro
.macro  DTEXT px, py, style, str
        DPOS px, py
        .byte R_STYLE, style
        .repeat .strlen(str), i
        .byte R_OUT, .strat(str, i)
        .endrep
.endmacro
.macro  DPATTERN p0, p1, p2, p3, p4, p5, p6, p7
        .byte R_PAT, p0, R_PAT+1, p1, R_PAT+2, p2, R_PAT+3, p3
        .byte R_PAT+4, p4, R_PAT+5, p5, R_PAT+6, p6, R_PAT+7, p7
.endmacro
.macro  DCLIP x0, y0, x1, y1
        .byte R_CLIP, <(x0), R_CLIP+1, >(x0), R_CLIP+2, <(y0), R_CLIP+3, >(y0)
        .byte R_CLIP+4, <(x1), R_CLIP+5, >(x1), R_CLIP+6, <(y1), R_CLIP+7, >(y1)
.endmacro
; a window: shadow, white body, frame, striped title bar, close box, title
.macro  DWINDOW x0, y0, x1, y1, title
        .byte R_ROP, 0, R_PATON, 0
        DRECT x0+3, y0+3, x1+3, y1+3
        DCMD C_BOXF, 1
        DRECT x0, y0, x1, y1
        DCMD C_BOXF, 0
        DCMD C_BOX, 1
        DRECT x0, y0+20, x1, y0+20
        DCMD C_LINE, 1
        DPATTERN $FF, $00, $FF, $00, $FF, $00, $FF, $00
        .byte R_PATON, 1
        DRECT x0+2, y0+3, x1-2, y0+17
        DCMD C_BOXF, 1
        .byte R_PATON, 0
        DRECT x0+8, y0+5, x0+20, y0+15
        DCMD C_BOXF, 0
        DCMD C_BOX, 1
        DTEXT (x0+x1)/2-(.strlen(title)+2)*4, y0+2, S_OPAQUE, .concat(" ", title, " ")
.endmacro

        .org $E000

start:
        lda #3                  ; hires
        sta MODE
        jsr icons
        lda #<scene
        ldx #>scene
        jsr dlist
        jsr dirwin
        lda #<fullclip
        ldx #>fullclip
        jsr dlist
        lda #3                  ; pointer on, following the mouse
        sta PTR
        lda #0
        sta banding

; --- main loop ----------------------------------------------------------------------
loop:
        lda FRAME
@wait:  cmp FRAME
        beq @wait
        jsr showxy
        jsr band
        lda KBDCR
        bpl loop
        lda KBD
        lda banding             ; a band still drawn: rub it out
        beq @quit
        jsr xorbox
@quit:  lda #0
        sta PTR
        sta MODE
        rts

; --- display list: pairs (register - $D300, value), ends with $FF -------------
dlist:
        sta PTRZ
        stx PTRZ+1
        ldy #0
@next:  lda (PTRZ),y
        cmp #D_END
        beq @done
        tax
        iny
        bne @val
        inc PTRZ+1
@val:   lda (PTRZ),y
        sta VID,x
        iny
        bne @next
        inc PTRZ+1
        bne @next
@done:  rts

; --- the icons to sprite images 0-1 ($FD0000) with the DMA ---------------------
icons:
        lda #<(iconimg - $E000)
        sta DMASRC
        lda BANK
        asl
        asl
        asl
        asl
        ora #>(iconimg - $E000)
        sta DMASRC+1
        lda BANK
        lsr
        lsr
        lsr
        lsr
        sta DMASRC+2
        lda #0
        sta DMASRC+3
        sta DMASRC+4
        sta DMASRC+8
        lda #$FD
        sta DMASRC+5
        lda #<(iconend - iconimg)
        sta DMASRC+6
        lda #>(iconend - iconimg)
        sta DMASRC+7
        lda #1
        sta DMACMD
        rts

; --- the disk window's file list ---------------------------------------------------
dirwin:
        lda #<BUF               ; DIR into memory at BUF, up to $EFFF
        sta DSTART
        lda #>BUF
        sta DSTART+1
        lda #$00
        sta DEND
        lda #$F0
        sta DEND+1
        lda #7
        sta DCMD
        lda DSTAT
        beq @ok
        rts
@ok:    lda #<BUF
        sta PTRZ
        lda #>BUF
        sta PTRZ+1
        lda #<108               ; first row
        sta rowy
        lda #>108
        sta rowy+1
@file:  ldy #0
        lda (PTRZ),y
        bne @name
        rts                     ; the final 0
@name:  lda #<56
        ldx #>56
        jsr setx
        lda #0                  ; plain text
        sta VID+R_STYLE
@ch:    lda (PTRZ),y            ; the name
        beq @size
        sta VID+R_OUT
        iny
        bne @ch
@size:  iny                     ; size: 3 bytes (only 2 shown)
        lda (PTRZ),y
        sta num
        iny
        lda (PTRZ),y
        sta num+1
        iny
        lda (PTRZ),y            ; $FF: not a mini6502 file
        sta big
        iny
        lda (PTRZ),y            ; load address
        sta load
        iny
        lda (PTRZ),y
        sta load+1
        iny
        tya                     ; next record
        clc
        adc PTRZ
        sta PTRZ
        bcc @x
        inc PTRZ+1
@x:     lda #<236
        ldx #>236
        jsr setx
        lda big
        bne @nosize
        ldy #0                  ; 5 digits
        jsr decout
        lda #<300
        ldx #>300
        jsr setx
        lda #'$'
        sta VID+R_OUT
        lda load+1
        jsr hexout
        lda load
        jsr hexout
@nosize:
        lda rowy                ; next row, 18 pixels down
        clc
        adc #18
        sta rowy
        bcc @y
        inc rowy+1
@y:     lda rowy+1              ; below the window? stop (the clip rectangle
        cmp #>320               ; cuts what is past its bottom anyway)
        bcc @more
        lda rowy
        cmp #<320
        bcc @more
        rts
@more:  jmp @file

; X0 = XA (A low), Y0 = rowy
setx:   sta VID+R_X0
        stx VID+R_X0H
        lda rowy
        sta VID+R_Y0
        lda rowy+1
        sta VID+R_Y0H
        rts

; num as decimal through CHAROUT: Y = 0 for 5 digits, 2 for 3 digits
decout:
@digit: ldx #'0'
@sub:   lda num
        sec
        sbc p10lo,y
        sta tmp
        lda num+1
        sbc p10hi,y
        bcc @out
        sta num+1
        lda tmp
        sta num
        inx
        bne @sub
@out:   stx VID+R_OUT
        iny
        cpy #5
        bne @digit
        rts
p10lo:  .byte <10000, <1000, <100, <10, <1
p10hi:  .byte >10000, >1000, >100, >10, >1

; A as 2 hex digits through CHAROUT
hexout:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr @nib
        pla
        and #$0F
@nib:   cmp #10
        bcc @dig
        adc #6                  ; carry set: +7
@dig:   adc #'0'
        sta VID+R_OUT
        rts

; --- mouse position in the menu bar ------------------------------------------------
showxy:
        lda #0
        sta VID+R_ROP
        sta VID+R_PATON
        lda #S_OPAQUE
        sta VID+R_STYLE
        lda #<520
        sta VID+R_X0
        lda #>520
        sta VID+R_X0H
        lda #1
        sta VID+R_Y0
        lda #0
        sta VID+R_Y0H
        lda #'X'
        sta VID+R_OUT
        lda MOUSEX
        sta num
        lda MOUSEX+1
        sta num+1
        ldy #2
        jsr decout
        lda #' '
        sta VID+R_OUT
        lda #'Y'
        sta VID+R_OUT
        lda MOUSEY
        sta num
        lda MOUSEY+1
        sta num+1
        ldy #2
        jmp decout

; --- XOR rubber band: from where the left button went down to the mouse -------
band:
        lda banding
        bne @going
        lda BUTTONS             ; start?
        and #1
        beq @rts
        lda MOUSEX              ; anchor = current = the mouse
        sta ax
        sta cx
        lda MOUSEX+1
        sta ax+1
        sta cx+1
        lda MOUSEY
        sta ay
        sta cy
        lda MOUSEY+1
        sta ay+1
        sta cy+1
        jsr xorbox
        inc banding
@rts:   rts
@going: lda BUTTONS
        and #1
        beq @end
        lda MOUSEX              ; moved?
        cmp cx
        bne @move
        lda MOUSEX+1
        cmp cx+1
        bne @move
        lda MOUSEY
        cmp cy
        bne @move
        lda MOUSEY+1
        cmp cy+1
        beq @rts
@move:  jsr xorbox              ; rub out the old box (XOR twice = nothing)
        lda MOUSEX
        sta cx
        lda MOUSEX+1
        sta cx+1
        lda MOUSEY
        sta cy
        lda MOUSEY+1
        sta cy+1
        jmp xorbox              ; the new one
@end:   jsr xorbox              ; released: rub it out
        lda #0
        sta banding
        rts

; the box ax,ay - cx,cy in XOR
xorbox:
        lda #3                  ; XOR
        sta VID+R_ROP
        lda #0
        sta VID+R_PATON
        lda ax
        sta VID+R_X0
        lda ax+1
        sta VID+R_X0H
        lda ay
        sta VID+R_Y0
        lda ay+1
        sta VID+R_Y0H
        lda cx
        sta VID+R_X1
        lda cx+1
        sta VID+R_X1H
        lda cy
        sta VID+R_Y1
        lda cy+1
        sta VID+R_Y1H
        lda #1
        sta VID+R_COL
        lda #C_BOX
        sta VID+R_CMD
        lda #0
        sta VID+R_ROP
        rts

; --- the drawing ------------------------------------------------------------------------
scene:
        ; desktop: 50% grey (the power-on PATTERN), the whole page
        .byte R_ROP, 0, R_PATON, 1
        DCMD C_CLEAR, 1
        .byte R_PATON, 0
        ; menu bar
        DRECT 0, 0, 639, 18
        DCMD C_BOXF, 0
        DRECT 0, 19, 639, 19
        DCMD C_LINE, 1
        DTEXT 8, 1, S_BOLD, "mini6502"
        DTEXT 104, 1, 0, "File   Edit   View   Special"
        ; the disk window
        DWINDOW 32, 44, 392, 330, "Disk"
        DTEXT 56, 70, S_BOLD, "Name"
        DTEXT 236, 70, S_BOLD, " Size"
        DTEXT 300, 70, S_BOLD, "Load"
        DRECT 34, 90, 390, 90
        DCMD C_LINE, 1
        DCLIP 34, 92, 390, 328  ; the list stays inside the window
        .byte D_END

fullclip:
        DCLIP 0, 0, 639, 399
        ; the styles window
        DWINDOW 420, 70, 620, 300, "Styles"
        DTEXT 436, 100, 0, "Plain text"
        DTEXT 436, 120, S_BOLD, "Bold text"
        DTEXT 436, 140, S_UNDER, "Underlined"
        DTEXT 436, 160, S_ITALIC, "Italic text"
        DTEXT 436, 180, S_INV, "Inverse"
        DTEXT 436, 200, S_BOLD+S_UNDER, "Bold+under"
        ; three fill patterns
        DPATTERN $88, $00, $22, $00, $88, $00, $22, $00
        .byte R_PATON, 1
        DRECT 436, 230, 484, 286
        DCMD C_BOXF, 1
        DPATTERN $AA, $55, $AA, $55, $AA, $55, $AA, $55
        DRECT 496, 230, 544, 286
        DCMD C_BOXF, 1
        DPATTERN $11, $22, $44, $88, $11, $22, $44, $88
        DRECT 556, 230, 604, 286
        DCMD C_BOXF, 1
        .byte R_PATON, 0
        DRECT 436, 230, 484, 286
        DCMD C_BOX, 1
        DRECT 496, 230, 544, 286
        DCMD C_BOX, 1
        DRECT 556, 230, 604, 286
        DCMD C_BOX, 1
        ; icons on the desktop (STAMP sprite images 0 and 1)
        DPOS 452, 330
        DCMD C_STAMP, 0
        DTEXT 436, 350, S_OPAQUE, "Disk"
        DPOS 540, 330
        DCMD C_STAMP, 1
        DTEXT 516, 350, S_OPAQUE, "Notes"
        DTEXT 8, 380, S_OPAQUE, " Drag with the left button: XOR box.  Any key: back to text. "
        DPATTERN $AA, $55, $AA, $55, $AA, $55, $AA, $55
        .byte D_END

banding: .res 1
ax:     .res 2
ay:     .res 2
cx:     .res 2
cy:     .res 2
rowy:   .res 2
num:    .res 2
tmp:    .res 1
big:    .res 1
load:   .res 2

iconimg:
        .include "icons.inc"
iconend:
