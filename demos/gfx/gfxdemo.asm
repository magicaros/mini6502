;=============================================================================
; gfxdemo.asm - mini6502 graphics demo                    (bank RAM $E000-$EFFF)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; Shows the 160x200 graphics: a landscape drawn with the
; blitter, 8 bouncing balls with SHADOW sprites, 4 of them BEHIND the
; scenery, a drifting cloud and its shadow, collision counters in the text
; layer on top (MODE 2).
;
;   L GFXDEMO E000 09     load into bank 9 (any bank works)
;   D020: 09              select it
;   E000R                 run (CALL $E000 from BASIC)
; Keys: N night (MASTER brightness) on/off, anything else stops it.
; Uses no zero page: the variables live in this bank, so BASIC can CALL it.
;=============================================================================




        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

F_ON    = 1
F_DBL   = 8
F_BEHIND = 16
F_SHADOW = 32

NBALLS  = 8
GROUND  = 160           ; first ground row
BALLY   = GROUND        ; ball sprite Y when it touches the ground (Y-16+16)

; blitter: CMD with x0,y0,x1,y1,colour
.macro  BLIT cmd, x0, y0, x1, y1, col
        lda #x0
        sta BX0
        lda #y0
        sta BY0
        lda #x1
        sta BX1
        lda #y1
        sta BY1
        lda #col
        sta BCOL
        lda #cmd
        sta BCMD
.endmacro

        .org $E000

start:
        lda COLOR
        sta oldcol
        lda #$0F                ; white on black: black is see-through
        sta COLOR
        lda #2
        sta SYSCTL              ; clear the text screen

; palette 0 = sky blue: the sky is colour 0, the "background" that BEHIND
; sprites show in front of
        lda #0
        sta PALIDX
        lda #$64
        sta PALR
        lda #$AA
        sta PALG
        lda #$FF
        sta PALB

; the sprite images to $FD0000 with the DMA: this bank is at extended
; address BANK * $1000, so images is at BANK * $1000 + (images - $E000)
        lda #<(images - $E000)
        sta DMASRC
        lda BANK
        asl
        asl
        asl
        asl
        ora #>(images - $E000)
        sta DMASRC+1
        lda BANK
        lsr
        lsr
        lsr
        lsr
        sta DMASRC+2
        lda #$00                ; destination $FD0000
        sta DMASRC+3
        sta DMASRC+4
        lda #$FD
        sta DMASRC+5
        lda #<(images_end - images)
        sta DMASRC+6
        lda #>(images_end - images)
        sta DMASRC+7
        lda #0
        sta DMASRC+8
        lda #1                  ; COPY
        sta DMACMD

        jsr scenery
        jsr status
        jsr initballs
        lda #2                  ; graphics with the text on top
        sta MODE

; --- main loop: once per frame ---------------------------------------------------
mainloop:
        lda FRAME
@wait:  cmp FRAME
        beq @wait
        jsr moveballs
        jsr movecloud
        lda COLLSS              ; balls touching each other this frame?
        beq @nohit
        inc hits
        bne @nohit
        inc hits+1
@nohit: lda COLLBG              ; balls touching the scenery?
        beq @notouch
        inc touch
        bne @notouch
        inc touch+1
@notouch:
        jsr counters
        lda KBDCR
        bpl mainloop
        lda KBD
        and #$5F                ; upper case
        cmp #'N'
        bne quit
        lda MASTER              ; night: 7/16 of the brightness, or back to 16
        cmp #16
        beq @night
        lda #16
        bne @set
@night: lda #7
@set:   sta MASTER
        jmp mainloop

quit:
        lda #0
        sta MODE                ; back to text
        ldx #0                  ; sprites off
@off:   sta SPR+3,x
        inx
        inx
        inx
        inx
        inx
        inx
        inx
        inx
        bne @off
        sta PALIDX              ; palette 0 black again
        sta PALR
        sta PALG
        sta PALB
        lda #16
        sta MASTER
        lda oldcol
        sta COLOR
        lda #2
        sta SYSCTL
        rts

; --- the landscape, drawn once on page 0 ----------------------------------------
scenery:
        BLIT C_CLEAR, 0, 0, 0, 0, 0             ; sky
; two mountains, one vertical line per column: top = the lower of
; 90 + |x - 40| and 100 + |x - 110|; the side left of a peak is DIM (shade)
        lda #0
        sta xx
@col:   lda xx
        sec
        sbc #40
        bcs @p1
        eor #$FF
        adc #1
@p1:    clc
        adc #90
        sta t1
        lda xx
        sec
        sbc #110
        bcs @p2
        eor #$FF
        adc #1
@p2:    clc
        adc #100
        cmp t1
        bcc @second             ; mountain 2 is higher here
        lda xx                  ; mountain 1
        cmp #40
        lda t1
        jmp @draw
@second:
        sta t1
        lda xx
        cmp #110
        lda t1
@draw:  sta BY0                 ; carry clear: left of the peak
        lda #19                 ; grey
        bcs @lit
        ora #$20                ; DIM
@lit:   sta BCOL
        lda xx
        sta BX0
        sta BX1
        lda #GROUND - 1
        sta BY1
        lda #C_LINE
        sta BCMD
        inc xx
        lda xx
        cmp #160
        bne @col
        BLIT C_BOXF, 0, GROUND, 159, 199, 26    ; ground
        BLIT C_LINE, 0, GROUND, 159, GROUND, 10 ; grass edge
        BLIT C_BOXF, 70, 128, 74, GROUND - 1, 25 ; tree trunk
        BLIT C_BOXF, 60, 104, 84, 130, 2        ; foliage
        BLIT C_DIM, 77, 104, 84, 130, 0         ; its shaded side
        BLIT C_STAMP, 128, 10, 0, 0, 5          ; the sun: image 5
        rts

; --- the text layer: two opaque lines, the rest see-through ----------------------
status:
        lda #$1F                ; white on blue
        sta COLOR
        ldx #0
        stx CURX
        stx CURY
        jsr puts80
        .byte " mini6502 160x200 graphics: blitter, sprites, SHADOW, BEHIND, collisions", 0
        lda #0
        sta CURX
        lda #24
        sta CURY
        jsr puts80
        .byte "sprite hits 00000   scenery touches 00000      N night on/off, other key: stop", 0
        rts

; Prints the string after the JSR, then spaces up to column 79 (not 80: the
; cursor would wrap and scroll)
puts80:
        pla
        sta sptr
        pla
        sta sptr+1
@loop:  inc sptr
        bne @get
        inc sptr+1
@get:   lda sptr
        sta @ld+1
        lda sptr+1
        sta @ld+2
@ld:    lda $FFFF               ; (self-modified: no zero page needed)
        beq @pad
        sta DSP
        bne @loop
@pad:   lda CURX
        cmp #79
        bcs @done
        lda #' '
        sta DSP
        bne @pad
@done:  lda sptr+1              ; return after the 0
        pha
        lda sptr
        pha
        rts

; The two counters in the bottom line
counters:
        lda #$1F
        sta COLOR
        lda #24
        sta CURY
        lda #12
        sta CURX
        lda hits
        ldx hits+1
        jsr dec5
        lda #36
        sta CURX
        lda touch
        ldx touch+1
        jmp dec5

; Prints XA (X high) as 5 decimal digits
dec5:
        sta num
        stx num+1
        ldy #0                  ; power of ten index
@digit: ldx #'0'
@sub:   lda num
        sec
        sbc p10lo,y
        sta t1
        lda num+1
        sbc p10hi,y
        bcc @out
        sta num+1
        lda t1
        sta num
        inx
        bne @sub
@out:   stx DSP
        iny
        cpy #5
        bne @digit
        rts
p10lo:  .byte <10000, <1000, <100, <10, <1
p10hi:  .byte >10000, >1000, >100, >10, >1

; --- balls ------------------------------------------------------------------------
initballs:
        ldx #NBALLS - 1
@init:  lda startx,x
        sta bx,x
        lda startdx,x
        sta bdx,x
        lda starty,x
        sta byh,x
        lda #0
        sta byl,x
        sta bvl,x
        sta bvh,x
        txa                     ; sprite x: ball, image x AND 3
        asl
        asl
        asl
        tay
        txa
        and #3
        sta SPR+2,y
        lda #F_ON
        cpx #4
        bcc @front
        lda #F_ON | F_BEHIND    ; balls 4-7 pass behind the scenery
@front: sta SPR+3,y
        lda #4                  ; its shadow: sprite x + 8, image 4
        sta SPR+64+2,y
        lda #F_ON | F_SHADOW
        sta SPR+64+3,y
        lda #GROUND + 2         ; on the ground
        sta SPR+64+1,y
        dex
        bpl @init
        lda #6                  ; cloud: sprite 16, image 6, double size
        sta SPR+128+2
        lda #F_ON | F_DBL
        sta SPR+128+3
        lda #46
        sta SPR+128+1
        lda #7                  ; its shadow: sprite 17, image 7, double size
        sta SPR+136+2
        lda #F_ON | F_DBL | F_SHADOW
        sta SPR+136+3
        lda #GROUND + 2
        sta SPR+136+1
        lda #0
        sta hits
        sta hits+1
        sta touch
        sta touch+1
        sta cloudx
        rts

; Gravity, bouncing on the ground and on the sides; updates the sprites
moveballs:
        ldx #NBALLS - 1
@ball:  lda bvl,x               ; speed += 0.125 pixel/frame
        clc
        adc #$20
        sta bvl,x
        lda bvh,x
        adc #0
        sta bvh,x
        lda byl,x               ; y += speed
        clc
        adc bvl,x
        sta byl,x
        lda byh,x
        adc bvh,x
        sta byh,x
        cmp #BALLY              ; on the ground (or below)?
        bcc @air
        lda bvh,x               ; only when falling
        bmi @air
        lda byl,x               ; mirror the overshoot back above the
        sta t1                  ; ground: y = BALLY - (y - BALLY). Just
        lda byh,x               ; stopping at BALLY would lose a little
        sec                     ; height at every bounce
        sbc #BALLY
        sta t2
        lda #0
        sec
        sbc t1
        sta byl,x
        lda #BALLY
        sbc t2
        sta byh,x
        lda #0                  ; speed = -speed: bounces forever
        sec
        sbc bvl,x
        sta bvl,x
        lda #0
        sbc bvh,x
        sta bvh,x
@air:   lda bx,x                ; x += dx, bounce on the sides
        clc
        adc bdx,x
        sta bx,x
        cmp #12                 ; the ball is columns 4-11 of its image
        beq @flip
        cmp #164
        bne @spr
@flip:  lda #0
        sec
        sbc bdx,x
        sta bdx,x
@spr:   txa
        asl
        asl
        asl
        tay
        lda bx,x
        sta SPR,y
        sta SPR+64,y            ; the shadow follows below
        lda byh,x
        sta SPR+1,y
        dex
        bmi @done
        jmp @ball
@done:  rts

; The cloud drifts right every 4th frame; its shadow is on the ground below
movecloud:
        lda FRAME
        and #3
        bne @done
        inc cloudx
@done:  lda cloudx
        sta SPR+128
        sta SPR+136
        rts

; start positions (sprite coordinates: screen + 16)
startx:  .byte 20, 50, 90, 140, 35, 75, 115, 155
startdx: .byte 1, $FF, 1, $FF, 1, 1, $FF, $FF
starty:  .byte 40, 70, 100, 55, 85, 120, 65, 30

; variables
bx:     .res NBALLS
bdx:    .res NBALLS
byl:    .res NBALLS
byh:    .res NBALLS
bvl:    .res NBALLS
bvh:    .res NBALLS
hits:   .res 2
touch:  .res 2
num:    .res 2
cloudx: .res 1
xx:     .res 1
t1:     .res 1
t2:     .res 1
sptr:   .res 2
oldcol: .res 1

images:
        .include "images.inc"
images_end:
