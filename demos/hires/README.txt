mini6502 hires, mouse and pointer
=================================

Hires is 640 x 400 in two colours, for desktop-style programs. It uses
the same two VRAM pages as the 160 x 200 graphics. The full register
list is at the top of mini6502.bas; this is the short version.

The demo (this folder)
----------------------
  L HIDEMO E000 0A      load it into bank $0A (any bank works)
  D020: 0A              select it
  E000R                 run it (CALL $E000 from BASIC)
It draws a grey patterned desktop, a menu bar, a "Disk" window that lists
the disk (DIR into memory, clipped to the window), a "Styles" window with
the CHAR styles and three fill patterns, and two icons. The pointer follows
the mouse, the menu bar shows its position, and dragging with the left
button draws an XOR rubber band box. Any key goes back to text.
Most of the picture is a "display list": pairs of (register - $D300,
value) that a 20-byte loop writes in order (dlist in hidemo.asm).
Files: hidemo.asm, icons.py (writes icons.inc), build.sh, hidemo.bin /
.hex, HIDEMO (disk file). Memory: $E000-$E952 in its bank, the directory
at $EA00-$EFFF, zero page $E2-$E3.

The picture
-----------
  POKE $D300,3       hires (4 = hires with the text layer on top)
1 bit per pixel, 80 bytes a row, bit 7 is the leftmost pixel:
  pixel X,Y of page 0 = bit 7-(X AND 7) of $FE0000 + Y*80 + X\8
(page 1 at $FE7D00). 1 bits show INK ($D306, palette entry, power-on 0
= black), 0 bits PAPER ($D307, power-on 15 = white). No sprites or DIM in
hires; the mouse pointer replaces them.

The blitter in hires
--------------------
Same registers as in 160 x 200, but coordinates are 16-bit: the high bytes
of X0, Y0, X1, Y1, DX, DY are at $D31A-$D31F. Every pixel it draws goes
through:
  the source bit  the PATTERN if PATON ($D329) is 1, else COLOR bit 0
  the ROP ($D328) 0 SET, 1 OR, 2 AND, 3 XOR, 4 INVERT, 5 CLEAR where the
                  source is 1
  the CLIP rectangle ($D338-$D33F: X0, Y0, X1, Y1, low/high bytes)
CMD ($D318): 1 CLEAR (the whole page, no clip), 2 PSET, 3 LINE, 4 BOX,
5 filled BOX, 6 COPY (X0,Y0-X1,Y1 of page SRC to DX,DY), 7 COPY only the
1 bits, 10 STAMP sprite image COLOR (each byte: 0 paper, 1 ink, $80
see-through: icons), 11 CHAR. PIXEL ($D319) reads 0 or 1 at X0,Y0.
XOR draws each pixel once, so drawing the same box, line or text twice
rubs it out: rubber bands, dragged outlines, blinking cursors.
PATTERN ($D330-$D337): 8 rows of 8 pixels, bit 7 left, repeated over the
screen (it stays in place when shapes move). Power-on: 50% grey.

Text: CHAR draws a character of the 8x16 font at X0,Y0 (any pixel, not
just on the text grid) and moves X0 on by 8. Writing a character to
CHAROUT ($D32C) does it at once, so a string is one write per letter.
STYLE ($D32B): 1 bold, 2 underline, 4 italic, 8 inverse, 16 opaque (the
whole 8x16 cell is drawn, so text replaces what was under it).

Mouse and pointer ($D500, all modes, even text)
-----------------------------------------------
  $D500/$D501  mouse X 0-639     $D502/$D503  mouse Y 0-399
  $D504  buttons held: 1 left, 2 right, 4 middle
  $D505  wheel steps since the last read (+ towards you)
  $D506  buttons pressed since the last read (a quick click is never
         missed)
  $D508  pointer: 1 shown, 2 follows the mouse by itself (3 = both)
  $D509-$D50C  pointer X, Y (low, high); $D50D/$D50E its hot spot
  $D510-$D52F  shape image, $D530-$D54F mask: 16 rows of 2 bytes;
         mask 1 + image 1 = INK, mask 1 + image 0 = PAPER, mask 0 = see-
         through. Power-on: an arrow with its hot spot at the tip.
The system's own arrow is hidden over the picture while the pointer is
shown. Ready-made: $D550 / $D551 = X / Y in 160 x 200 pixels,
$D552 / $D553 = column / row in text cells.

Disk: DIR into memory
---------------------
Disk command 7 ($D040) writes the directory at START ($D042): for each
file, in name order, its name, 0, the size (3 bytes; $FFFFFF if it has
no load address), the load address (2 bytes); then one more 0. END
($D044) is the limit going in (0 = $D000) and the address after the last
0 coming out; status 3 and nothing written if it does not fit.

From BASIC (keep lines under about 70 characters)
-------------------------------------------------
  10 V=$D300:B=$D310:POKE V,3:POKE B+4,0:POKE B+8,1   hires, clear
  20 POKE B,0:POKE B+10,1:POKE B+1,143:POKE B+11,1    X0=256 Y0=399
  30 POKE B+2,127:POKE B+12,2:POKE B+3,0:POKE B+13,0   X1=639 Y1=0
  40 POKE B+4,1:POKE B+8,3                            LINE
  50 POKE B,100:POKE B+10,0:POKE B+1,50:POKE B+11,0
  60 FOR I=1 TO 5:POKE V+44,ASC(MID$("HELLO",I,1)):NEXT
  70 POKE $D508,3                                     pointer on
  80 GET A$:IF A$="" THEN 80
  90 POKE $D508,0:POKE V,0
