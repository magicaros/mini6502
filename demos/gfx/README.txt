mini6502 graphics
=================

160 x 200 pixels, 32 colours from a palette, each also available DIM (at
an adjustable brightness), two pages, a blitter and 32 hardware sprites.
The video memory belongs to the host: the 6502 reaches it through the
extended memory ports and the DMA ($D200 page), never in its own 64K.
The full register list is at the top of mini6502.bas.
For 640 x 400 in two colours (hires), the mouse and the pointer, see
demos/hires/README.txt. The mouse works here too: $D550 / $D551 give its
X / Y in 160 x 200 pixels (one byte each), $D504 the buttons, and POKE
$D508,3 shows the pointer over the picture.

The demo (this folder)
----------------------
  L GFXDEMO E000 09     load it into bank 9 (any bank works)
  D020: 09              select it
  E000R                 run it (CALL $E000 from BASIC)
Keys: N switches night on and off (MASTER brightness), any other key stops
it and goes back to text.

It draws a landscape with the blitter (two mountains made of LINEs, their
shaded side DIM, the ground, a tree with a DIM side, the sun STAMPed from a
sprite image), then bounces 8 balls: each has a SHADOW sprite on the ground,
balls 4-7 are BEHIND (they pass behind the mountains and the tree), and a
double-size cloud drifts across with its shadow. The sky is colour 0 with
palette entry 0 set to blue: colour 0 is the "background" that BEHIND
sprites stay in front of. The text layer is on top (MODE 2): the first and
last lines have a blue background, the rest is see-through, and the bottom
line counts the frames with sprite-sprite and sprite-scenery collisions.

Files: gfxdemo.asm (the demo), images.py (writes images.inc, the 8 sprite
images), build.sh (needs cc65), gfxdemo.bin / .hex, GFXDEMO (disk file).
Memory: $E000-$ECF1 in its bank, no zero page, nothing else in RAM.

The picture
-----------
Pixels are twice as wide as they are high: the 160 x 200 picture is scaled
x4 across and x2 down to the 640 x 400 window. A round ball is 8 pixels
wide and 16 high. One text cell covers 2 x 8 pixels, so 80 x 25 text lines
up exactly with the graphics.

A pixel is one byte:
  bits 0-4  colour 0-31 (palette entry)
  bit 5     DIM: shown at INTENS/16 of its brightness (+32 = the DIM colour)
  bit 6     unused
  bit 7     TRANSPARENT: in sprite images, and for COPY 7 / STAMP, the pixel
            is not drawn
Colour 0 counts as background: BEHIND sprites show in front of it, and
sprites over it do not collide with the scenery.

Video memory (extended addresses, through the ports and the DMA):
  $FE0000  page 0, 32,000 bytes: pixel X,Y at $FE0000 + Y*160 + X
  $FE7D00  page 1, the same
  $FD0000  sprite images: 256 images of 16 x 16, image N at $FD0000 + N*256

Registers ($D300 page)
  $D300 MODE    0 text, 1 graphics, 2 graphics with the text on top
  $D301 SHOW    page shown (0-1)           $D302 DRAW  page the blitter uses
  $D303 INTENS  DIM brightness, 16ths (8)  $D304 MASTER graphics brightness (16)
  $D305 TRANSP  text background colour that is see-through in MODE 2 (0)
  $D308 PALIDX  palette entry; $D309-$D30B its R, G, B (writing B moves on)
Blitter ($D310), done at once when CMD is written, clipped to the screen:
  $D310 X0  $D311 Y0  $D312 X1  $D313 Y1  $D314 COLOR  $D315 DX  $D316 DY
  $D317 SRC page   $D318 CMD   $D319 PIXEL (read: pixel at X0,Y0)
  CMD 1 CLEAR  2 PSET  3 LINE  4 BOX  5 filled BOX  6 COPY  7 COPY skipping
      TRANSPARENT  8 DIM box  9 UNDIM box  10 STAMP image COLOR at X0,Y0
Collisions: $D320-$D323 sprite-sprite, $D324-$D327 sprite-scenery, one bit
per sprite, gathered every frame, cleared by reading.
Sprites: sprite N at $D400 + N*8: X, Y (+16: X=16,Y=16 is the top left
corner), IMAGE, FLAGS (1 on, 2 flip across, 4 flip down, 8 double size,
16 BEHIND, 32 SHADOW). Sprite 0 is drawn on top.

From BASIC
----------
Keep lines under about 70 characters (EhBASIC's input limit).
  10 V=$D300:B=$D310:POKE V,1           graphics on
  20 POKE B+4,0:POKE B+8,1              CLEAR with colour 0 (black)
  30 POKE B,10:POKE B+1,20:POKE B+2,150:POKE B+3,180
  40 POKE B+4,14:POKE B+8,3             yellow LINE 10,20 - 150,180
  50 POKE B+4,4:POKE B+8,4              red BOX around it
  60 POKE B,40:POKE B+1,60:POKE B+2,120:POKE B+3,140
  70 POKE B+4,9:POKE B+8,5              light blue filled BOX
  80 POKE B,80:POKE B+1,100:POKE B+2,159:POKE B+3,199
  90 POKE B+8,8                         DIM the bottom right corner
 100 GET A$:IF A$="" THEN 100
 110 POKE V,0                           back to text
A pixel, through port A ($FE0000 + Y*160 + X, here X=5 Y=2):
  POKE $D200,69:POKE $D201,1:POKE $D202,$FE:POKE $D203,12
(2*160+5 = 325 = $0145.) Palette entry 1 to orange:
  POKE $D308,1:POKE $D309,255:POKE $D30A,128:POKE $D30B,0
