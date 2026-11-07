PIXEL - a colour pixel editor for pictures and sprites
=====================================================

A full-screen editor for 160 x 200 pictures in 31 colours and
transparency: the whole screen is the picture, the menus come up over it.
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

Starting it
-----------
On the desktop: double-click PIXEL (in the disk's PIXEL folder), or a .PIX
picture: it opens in PIXEL. It comes back to the desktop when you quit.
PIXEL needs PIXEL2 too (it loads it when it starts): both live in the
disk's PIXEL folder. From the monitor: L /PIXEL/PIXEL E000 20, D020: 20,
E000R (or, with a name at $EF80 in that bank, E006R to open it). It is not
a toolkit program: no menu bar, no windows.

Drawing
-------
The mouse draws with the tool in use, in the colour in use:
  P pencil     E eraser (paints transparent)    K picker
  F fill       L line    R rectangle    B box (filled)
  O oval       D disc (filled oval)
The right button takes the colour under the mouse, whatever the tool.
Lines and shapes follow the mouse until you let go. Fill paints the area
of the clicked pixel's colour (it stops at any other colour).
  Space   the tool menu: the tools (a letter or a click), G grid, U undo,
          Tab the colours, and the files: 1 New, 2 Open, 3 Save, 4 Save
          as, 5 Sprites, 0 Quit. Space or Esc: back to the picture.
  Tab     the colour menu: the 31 colours as swatches, the transparent one
          (shaded) first. Arrows or a click choose, Enter (or Tab, Space)
          takes it, Esc leaves it as it was. Q / A, W / S, E / D: the chosen
          colour's red, green, blue up / down by 8; every pixel of that
          colour changes at once.
  U, Ctrl+Z   undo the last change (and again: put it back)
  G       the grid: a frame round the 16 x 16 cell under the mouse (the
          cells are the sprites PIXEL saves)
  the tools' letters choose them without the menu.
The tool and colour menus are in the text layer: the picture shows round
them.

Transparent
-----------
Transparent pixels are stored as $80 (bit 7): sprites, COPY 7 and STAMP do
not draw them. On the screen they show palette colour 0 (black at first;
its red, green, blue can be changed in the colour menu like the others,
to see them better), and the eraser paints them. A new picture is all
transparent.

Files
-----
Open, Save and Save as ask for a name in the text layer (Enter: OK, Esc:
cancel); the name shown first is selected, so typing replaces it (an arrow
keeps it). .PIX is added when the name has no dot.
  .PIX   the 32,000 pixels (one byte each, 160 a row: exactly VRAM page
         0), then "PAL" and the 32 colours' red, green, blue (96 bytes).
         Saved with the load address $4000. Opening one sets the palette
         too. To show one in a program: load it at $4000, copy 32,000 bytes
         to VRAM $FE0000 with the DMA, write the 96 bytes after "PAL" to
         the palette (PALIDX = 0, then R, G, B for each), MODE 1.
  Sprites (5)  the picture cut into 120 sprite images, 10 across and 12
         down (rows 0-191): 120 x 256 bytes, each image 16 rows of 16
         bytes, in reading order, load address $4000. A program loads the
         file and copies image n to $FD0000 + (first + n) * 256 for its
         sprites; set the palette from the .PIX too.

Quitting puts the video back as at power-on (the palette too).

Inside
------
pixel.asm makes two parts (pixel.cfg, build.sh, needs cc65; the ovals use
../paint/paint_oval.inc):
  PIXEL   for a bank ($E000): a loader, started like EDIT ($E000, or
          $E006 with a name at $EF80); it loads PIXEL2 and runs it
  PIXEL2  main RAM $0800-$1FFF: the editor ($0800 empty, $0803 open the
          name at $0806)
The picture is VRAM page 0 itself, the blitter draws on it; page 1 is the
undo copy (the shapes being dragged are drawn over a copy of it each time).
Fill works on a copy in main RAM ($4000, a byte a pixel, seeds at $2000)
and copies it back. The swatches are sprites 1-31 (images 200-230), the
frame sprite 0 (image 231).
