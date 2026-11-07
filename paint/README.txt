PAINT - black and white pictures for the desktop
================================================

A paint program in the manner of MacPaint, built on the toolkit: 640 x 400
pictures in black and white, tools and patterns down the left, FatBits.
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

Starting it
-----------
On the desktop: double-click PAINT, or a picture (.PIC, the landscape
icon): it opens in PAINT. PAINT needs PAINT2 too (it loads it when it
starts): both live in the disk's PAINT folder (the desktop and PAINT look
there, or at the top).
By hand: the toolkit and ACC loaded (DESKTOP.TXT's L lines), then
  L /PAINT/PAINT E000 20   D020: 20   E000R      an empty picture
or, with a name at $EF80 in that bank (ending with 0), E006R to open it.
It needs 24 free banks of the documents zone ($80-$CF): the picture, its
undo copy, the clipboard (16 will do, without Copy and Paste).

The window
----------
The canvas shows 560 x 352 pixels of the picture; the scroll bar, the
mouse wheel and Up / Down scroll it, Left / Right by 8 pixels, and the hand
drags it. On the left, from the top:
  the tools        click one (or type its letter)
    S select    H hand      T text      F paint bucket
    A spray     B brush     P pencil    L line
    E eraser    R rectangle G filled rectangle
    O oval      Q filled oval           Z FatBits
  the line widths  1 to 4 pixels: lines, frames, ovals; the brush is 4,
                   8, 12 or 16 pixels across
  the pattern      the one in use, large, then the 16 to choose from:
                   filled shapes, the brush, the spray and the bucket use
                   it (lines, frames and the pencil draw black)

The tools
---------
  pencil     one pixel: black, or white when you start on a black pixel
  brush      squares of the pattern; eraser: 16 x 16 white squares
  spray      dots of the pattern around the mouse while the button is held
  line, rectangle, oval
             drag from one corner to the other; it follows the mouse
             until you let go. The filled ones are the pattern inside a
             black frame.
  bucket     the area of the colour you click (as far as the canvas shows
             it) filled with the pattern. A big area takes a few seconds.
  text       click, then type: Enter starts the next line below where you
             clicked, Backspace rubs the last character out, Esc ends.
             Goodies: Plain text, Bold, Italic, Underline (each switches
             it on or off for what comes next).
  select     drag a frame round a part of the picture; drag the part to
             move it (with Shift held: a copy of it). Edit: Cut, Copy,
             Paste, Clear (or Delete), Flip horizontal, Flip vertical,
             Invert. Select all: the whole canvas. Paste puts it at the
             canvas' top left, selected, ready to be dragged.
  hand       drag the picture under the window
  FatBits    click (or Goodies: FatBits, Ctrl+B): 8 times larger, each
             pixel a square. A click turns a pixel the other colour, and
             the ones you drag over the same. The arrows move around; the
             FatBits tool clicked again, Esc or Ctrl+B: back.

Undo (Ctrl+Z) takes back the last change, and Undo again puts it back.
File: New (Ctrl+N), Open... (Ctrl+O), Save (Ctrl+S), Save as..., Quit
(Ctrl+Q): New, Open and Quit ask first if there are unsaved changes (* in
the title).

Files
-----
A .PIC file is the hires screen as it is: 32,000 bytes, 80 bytes a row
from the top, bit 7 = the leftmost pixel, 1 = black (INK). Saved with the
load address $4000 (where PAINT puts it to save). Any program can show
one: load it (L PICTURE.PIC 4000), then copy the 32,000 bytes to VRAM
$FE0000 with the DMA, in MODE 3.

Inside
------
paint.asm makes two parts (paint.cfg, build.sh, needs cc65 and python3;
icons.py draws the tools' icons, ovaltab.py the ovals' table):
  PAINT   for a bank ($E000-$EF7F): menus, files, the main loop
  PAINT2  main RAM $0800-$3FFF: the canvas, the palette, the tools
          (paint2.inc, paint3.inc)
The picture lives in banks, laid out like the screen. The tools draw on
the screen with the blitter (clipped to the canvas); when one is done, the
canvas is copied back into the picture (the DMA, a row at a time). Scrolling
and redrawing copy the other way. A selection being dragged is kept on VRAM
page 1. The bucket works on a copy of the canvas in main RAM $4000 (a span
at a time, seeds on a stack at $A600), then puts the pattern where the copy
changed. The tools' icons are sprite images 64-77 (STAMP).
