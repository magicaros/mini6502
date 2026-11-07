;=============================================================================
; breakout.asm - a small Breakout for mini6502             (main RAM, $0800)
;-----------------------------------------------------------------------------
; Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
; Free software under the GNU General Public License, version 3 or
; (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
; 160x200 graphics with the text layer on top for the score,
; the mouse moves the paddle, a click launches the ball, Esc quits.
;
;   from the desktop: double-click BREAKOUT
;   from the monitor: L BREAKOUT  then  0800R
;   from BASIC:       LOAD with the monitor first, then CALL $0800 (it loads
;                     over BASIC's program area)
; Uses no zero page and nothing outside $0800-its end, so it can return to
; whoever called it.
;=============================================================================

        .include "mini6502.inc"     ; the registers (hw/mini6502.inc)

NOTE    = $D030         ; voice 1: NOTE, VOL, WAVE, DUR
VOL     = $D031
WAVE    = $D032
DUR     = $D033
NOTE2   = $D034         ; voice 2
VOL2    = $D035
WAVE2   = $D036
DUR2    = $D037


COLS    = 12            ; bricks: 12 x 6, 11 x 5 pixels, 12 x 6 apart
BROWS   = 6
NBRICKS = COLS * BROWS
BRX     = 8             ; first brick's left edge
BRY     = 24            ; first brick's top edge
LEFTW   = 4             ; the walls: x 0-3 and 156-159, y 8-11 at the top
RIGHTW  = 156
TOPW    = 12
PADY    = 186           ; paddle: 20 x 3 at y 186
PADW    = 20
BALLW   = 2             ; ball: 2 x 3
BALLH   = 3

        .org $0800

start:
        cld
        tsx                     ; to return from anywhere (Esc)
        stx savesp
        lda #3                  ; video and sound as at power-on
        sta SYSCTL
        lda #$0F                ; text layer cleared: see-through (black
        sta COLOR               ; background = TRANSP 0)
        lda #2
        sta SYSCTL
        jsr images
        lda #1                  ; paddle: sprites 1 and 2, images 1 and 2
        sta SPR+10
        sta SPR+11
        sta SPR+19
        lda #2
        sta SPR+18
        lda #0                  ; ball: sprite 0, image 0
        sta SPR+2
        lda #2                  ; graphics, the text layer on top
        sta MODE
        lda #12                 ; sound: voice 1 square, voice 2 triangle
        sta VOL
        sta VOL2
        lda #0
        sta WAVE
        lda #1
        sta WAVE2

newgame:
        lda #3
        sta lives
        lda #1
        sta level
        lda #0
        sta score
        sta score+1
newlevel:
        jsr setbricks
        jsr drawfield
        jsr status
        jsr serve

; --- the game loop: once a frame ---------------------------------------------------
loop:   lda FRAME
@w:     cmp FRAME
        beq @w
        lda KBDCR               ; Esc quits
        bpl @nokey
        lda KBD
        and #$7F
        cmp #27
        bne @nokey
        jmp quit
@nokey: jsr paddle
        lda stuck
        beq @move
        jsr onpaddle            ; waiting on the paddle for a click
        lda CLICKS
        and #1
        beq @show
        jsr launch
        jmp @show
@move:  jsr moveball
        lda lost
        beq @show
        jmp loseball
@show:  jsr ballspr
        lda left
        bne loop
        inc level               ; all gone: next level, a little faster
        lda #84
        jsr sound2
        jmp newlevel

; A ball lost: one life less; none left: game over
loseball:
        lda #36
        ldx #30
        jsr sound
        dec lives
        jsr status
        lda lives
        beq gameover
        jsr serve
        jmp loop

gameover:
        lda #0                  ; ball away
        sta SPR+3
        lda #<s_over
        ldx #>s_over
        ldy #24
        jsr message
        lda CLICKS
@w:     lda KBDCR
        bpl @m
        lda KBD
        and #$7F
        cmp #27
        beq quit
@m:     lda CLICKS
        and #1
        beq @w
        jsr clearmsg
        jmp newgame

quit:   ldx savesp
        txs
        lda #3                  ; everything as at power-on: text mode
        sta SYSCTL
        lda #$07
        sta COLOR
        lda #2
        sta SYSCTL              ; clear the screen
        rts

; --- the ball waiting on the paddle ----------------------------------------------------
serve:  lda #1
        sta stuck
        lda #0
        sta lost
        lda #1                  ; the ball sprite on
        sta SPR+3
        lda CLICKS              ; (forget older clicks)
        lda #<s_click
        ldx #>s_click
        ldy #31
        jmp message

onpaddle:
        lda px                  ; on the middle of the paddle
        clc
        adc #(PADW - BALLW) / 2
        sta bx+1
        lda #PADY - BALLH
        sta by+1
        lda #0
        sta bx
        sta by
        rts

launch: lda #0
        sta stuck
        jsr clearmsg
        jsr speed               ; up, a little to the right
        lda #<128
        sta vx
        lda #>128
        sta vx+1
        rts

; vy = -(1.25 + level / 4) pixels a frame (8.8), at most 3
speed:  lda level
        asl
        asl
        asl
        asl
        asl
        asl                     ; level * 64 = level / 4 in 8.8
        clc
        adc #<320
        sta vy
        lda #>320
        adc #0
        sta vy+1
        cmp #3
        bcc @ok
        lda #0
        sta vy
        lda #3
        sta vy+1
@ok:    jmp negvy               ; upwards

; --- paddle: follows the mouse ------------------------------------------------------------
paddle: lda MOUSELX
        sec
        sbc #PADW / 2
        bcs @a
        lda #0
@a:     cmp #LEFTW
        bcs @b
        lda #LEFTW
@b:     cmp #RIGHTW - PADW + 1
        bcc @c
        lda #RIGHTW - PADW
@c:     sta px
        clc                     ; sprites 1 and 2 (16 + 4 pixels)
        adc #16
        sta SPR+8
        adc #16
        sta SPR+16
        lda #PADY + 16
        sta SPR+9
        sta SPR+17
        rts

; The ball sprite at bx, by (the integer parts)
ballspr:
        lda bx+1
        clc
        adc #16
        sta SPR
        lda by+1
        clc
        adc #16
        sta SPR+1
        rts

; --- the ball moving: walls, paddle, bricks, out ----------------------------------------
moveball:
        lda bx                  ; bx += vx
        clc
        adc vx
        sta bx
        lda bx+1
        adc vx+1
        sta bx+1
        lda by                  ; by += vy
        clc
        adc vy
        sta by
        lda by+1
        adc vy+1
        sta by+1
        lda bx+1                ; left wall
        cmp #LEFTW
        bcs @r
        lda #LEFTW
        sta bx+1
        jsr posvx
        jsr tick
@r:     lda bx+1                ; right wall
        cmp #RIGHTW - BALLW + 1
        bcc @t
        lda #RIGHTW - BALLW
        sta bx+1
        jsr negvx
        jsr tick
@t:     lda by+1                ; top wall
        cmp #TOPW
        bcs @p
        lda #TOPW
        sta by+1
        jsr posvy
        jsr tick
@p:     lda vy+1                ; the paddle, if going down
        bmi @br
        lda by+1
        clc
        adc #BALLH
        cmp #PADY
        bcc @br
        cmp #PADY + 4
        bcs @out
        lda bx+1                ; ball's right > paddle's left
        clc
        adc #BALLW
        cmp px
        bcc @out
        beq @out
        lda px                  ; paddle's right > ball's left
        clc
        adc #PADW
        cmp bx+1
        bcc @out
        beq @out
        lda #PADY - BALLH       ; bounce: the angle from where it hit
        sta by+1
        jsr negvy
        lda bx+1
        clc
        adc #BALLW
        sec
        sbc px                  ; 1 .. 21
        lsr                     ; / 3 (about): 0 .. 7
        lsr
        cmp #8
        bcc @i
        lda #7
@i:     asl
        tax
        lda angles,x
        sta vx
        lda angles+1,x
        sta vx+1
        lda #60
        jsr sound2
        rts
@out:   lda by+1                ; fell below the screen?
        cmp #197
        bcc @br
        lda #1
        sta lost
        lda #0
        sta SPR+3
        rts
@br:    jmp bricks
angles: .word $FE00, $FE80, $FF00, $FF80, 128, 256, 384, 512   ; -2 .. +2

brno:   rts

; A brick under the ball's centre? It goes, the ball bounces back
bricks: lda by+1                ; row = (y + 1 - BRY) / 6, inside its 5
        clc
        adc #1
        sec
        sbc #BRY
        bcc brno
        ldx #0
@r:     cmp #6
        bcc @rd
        sbc #6
        inx
        cpx #BROWS
        bcs brno
        bne @r
@rd:    cmp #5
        bcs @no
        stx row
        lda bx+1                ; column = (x + 1 - BRX) / 12, inside its 11
        clc
        adc #1
        sec
        sbc #BRX
        bcc @no
        ldx #0
@c:     cmp #12
        bcc @cd
        sbc #12
        inx
        cpx #COLS
        bcs @no
        bne @c
@cd:    cmp #11
        bcs @no
        stx col
        lda row                 ; index = row * 12 + column
        asl
        asl
        sta tmp
        asl
        clc
        adc tmp
        adc col
        tax
        lda brick,x
        beq @no
        lda #0                  ; hit
        sta brick,x
        dec left
        jsr drawbrick           ; (colour 0: rubbed out)
        lda vy+1                ; back the other way
        bmi @down
        jsr negvy
        jmp @pts
@down:  jsr posvy
@pts:   lda #BROWS              ; points: 10 for the bottom row ... 60 at the top
        sec
        sbc row
        tax
        lda #0
@p:     clc
        adc #10
        dex
        bne @p
        clc
        adc score
        sta score
        bcc @s
        inc score+1
@s:     jsr status
        lda #84                 ; higher rows sound higher
        sec
        sbc row
        sbc row
        jmp sound1
@no:    rts

negvy:  lda vy+1
        bmi @r
        jmp negy
@r:     rts
posvy:  lda vy+1
        bpl @r
        jmp negy
@r:     rts
negy:   lda #0
        sec
        sbc vy
        sta vy
        lda #0
        sbc vy+1
        sta vy+1
        rts
negvx:  lda vx+1
        bmi @r
        jmp negx
@r:     rts
posvx:  lda vx+1
        bpl @r
        jmp negx
@r:     rts
negx:   lda #0
        sec
        sbc vx
        sta vx
        lda #0
        sbc vx+1
        sta vx+1
        rts

; --- sound -----------------------------------------------------------------------------------
tick:   lda #67
sound1: ldx #4                  ; a short note on voice 1
sound:  stx DUR
        sta NOTE
        rts
sound2: ldx #6                  ; on voice 2
        stx DUR2
        sta NOTE2
        rts

; --- drawing ---------------------------------------------------------------------------------
; All the bricks alive
setbricks:
        ldx #NBRICKS - 1
        lda #1
@b:     sta brick,x
        dex
        bpl @b
        lda #NBRICKS
        sta left
        rts

drawfield:
        lda #0                  ; black
        sta BCOL
        lda #C_CLEAR
        sta BCMD
        lda #8                  ; dark grey walls
        sta BCOL
        lda #0
        sta BX0
        sta BX1
        lda #LEFTW - 1
        sta BX1
        lda #8
        sta BY0
        lda #199
        sta BY1
        lda #C_BOXF
        sta BCMD
        lda #RIGHTW
        sta BX0
        lda #159
        sta BX1
        lda #C_BOXF
        sta BCMD
        lda #0
        sta BX0
        lda #TOPW - 1
        sta BY1
        lda #C_BOXF
        sta BCMD
        ldx #NBRICKS - 1        ; the bricks
@b:     stx tmp2
        lda brick,x
        beq @n
        jsr drawbrick
@n:     ldx tmp2
        dex
        bpl @b
        rts

; Brick X in its row's colour (or rubbed out if it is gone)
drawbrick:
        txa                     ; row = X / 12, column = X mod 12
        ldy #0
@d:     cmp #COLS
        bcc @dd
        sbc #COLS
        iny
        bne @d
@dd:    sta col
        sty row
        lda col                 ; x = BRX + column * 12
        asl
        asl
        sta tmp
        asl
        clc
        adc tmp
        adc #BRX
        sta BX0
        clc
        adc #10
        sta BX1
        lda row                 ; y = BRY + row * 6
        asl
        sta tmp
        asl
        clc
        adc tmp
        adc #BRY
        sta BY0
        clc
        adc #4
        sta BY1
        lda brick,x
        beq @off
        ldy row
        lda rowcol,y
        bne @set
@off:   lda #0
@set:   sta BCOL
        lda #C_BOXF
        sta BCMD
        rts
rowcol: .byte 12, 23, 14, 10, 9, 13     ; red, orange, yellow, green, blue, magenta

; --- the text layer: the top line, messages -------------------------------------------
status: lda #$1F                ; white on blue
        sta COLOR
        lda #0
        sta CURY
        sta CURX
        ldx #0
@s:     lda s_status,x
        beq @n
        sta DSP
        inx
        bne @s
@n:     lda #6                  ; the score
        sta CURX
        lda score
        sta num
        lda score+1
        sta num+1
        jsr dec5
        lda #20                 ; lives
        sta CURX
        lda lives
        ora #'0'
        sta DSP
        lda #30                 ; level
        sta CURX
        lda level
        sta num
        lda #0
        sta num+1
        jsr dec5
        lda #79                 ; the cursor out of the way
        sta CURX
        rts

; A message (XA) on text row 13 at column Y, yellow on see-through
message:
        sta mptr+1
        stx mptr+2
        sty CURX
        lda #13
        sta CURY
        lda #$0E
        sta COLOR
        ldx #0
mptr:   lda $FFFF,x             ; (self-modified: no zero page)
        beq @e
        sta DSP
        inx
        bne mptr
@e:     lda #0
        sta CURY
        lda #79
        sta CURX
        rts

clearmsg:
        lda #<s_blank
        ldx #>s_blank
        ldy #20
        jmp message

; num as 5 digits
dec5:   ldy #0
@d:     ldx #'0'
@s:     lda num
        sec
        sbc p10l,y
        sta tmp
        lda num+1
        sbc p10h,y
        bcc @o
        sta num+1
        lda tmp
        sta num
        inx
        bne @s
@o:     stx DSP
        iny
        cpy #5
        bne @d
        rts
p10l:   .byte <10000, <1000, <100, <10, <1
p10h:   .byte >10000, >1000, >100, >10, >1

s_status: .byte "SCORE 00000   LIVES 0   LEVEL 00000   MOUSE: PADDLE  CLICK: LAUNCH  ESC: QUIT  ", 0   ; 79 characters: no wrap
s_click:  .byte "CLICK TO LAUNCH", 0
s_over:   .byte "GAME OVER - CLICK: AGAIN  ESC: QUIT", 0
s_blank:  .byte "                                        ", 0

; --- sprite images 0-2: ball, paddle (16 + 4 pixels) ----------------------------------
images: lda #0                  ; port A -> $FD0000 (image 0)
        sta PADR
        sta PADR+1
        lda #$FD
        sta PADR+2
        lda #1
        sta PSTEP
        ldx #0                  ; 3 images, 256 bytes each
@i:     lda #$80                ; see-through by default
        ldy imgpix,x            ; ... except where the shape table says
        cpy #$FF
        beq @put
        lda imgpix,x
@put:   sta PDATA
        inx
        bne @i
        jsr @img1
        jmp @img2
@img1:  ldx #0                  ; paddle left: 16 x 3 (light cyan, white top)
@p:     lda #$80
        cpx #48
        bcs @pp
        lda #11
        cpx #16
        bcs @pp
        lda #15
@pp:    sta PDATA
        inx
        bne @p
        rts
@img2:  ldx #0                  ; paddle right: 4 x 3
@q:     lda #$80
        cpx #48
        bcs @qq
        txa
        and #15
        cmp #4
        lda #$80
        bcs @qq
        lda #11
        cpx #16
        bcs @qq
        lda #15
@qq:    sta PDATA
        inx
        bne @q
        rts
; image 0: the ball, 2 x 3 in white ($FF = see-through)
imgpix: .byte 15, 15, $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .byte 15, 15, $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .byte 15, 15, $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .res 256 - 48, $FF

; --- variables -----------------------------------------------------------------------------
savesp: .res 1
bx:     .res 2          ; ball position, 8.8 (fraction, pixel)
by:     .res 2
vx:     .res 2          ; its speed, 8.8 signed
vy:     .res 2
px:     .res 1          ; paddle's left edge
stuck:  .res 1          ; 1: the ball waits on the paddle
lost:   .res 1
lives:  .res 1
level:  .res 1
score:  .res 2
left:   .res 1          ; bricks left
row:    .res 1
col:    .res 1
tmp:    .res 1
tmp2:   .res 1
num:    .res 2
brick:  .res NBRICKS
