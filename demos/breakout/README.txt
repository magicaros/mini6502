mini6502 Breakout
=================

A small Breakout: 12 x 6 bricks, a paddle on the mouse, 3 lives, each
level a little faster. 160x200 graphics with the text layer on top for
the score line.
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

Playing
-------
  from the desktop     double-click BREAKOUT (it comes back when you quit)
  from the monitor     L BREAKOUT, then 0800R
Move the mouse: the paddle follows. Click to launch the ball. Where the
ball lands on the paddle sets its angle (the ends send it out sideways).
Points: 10 for a bottom-row brick up to 60 for the top row. Esc quits;
after GAME OVER a click starts again.

How it is made
--------------
  graphics   MODE 2: the bricks and the walls are drawn with the blitter
             (filled boxes; a hit brick is drawn again in black), the ball
             and the paddle are sprites (0, and 1 + 2 for the 20-pixel
             paddle), their images written through port A at $FD0000
  text       row 0: the score line (white on blue); row 13: the messages,
             yellow on a see-through background
  mouse      $D550: X in 160x200 pixels, $D506: clicks
  sound      voice 1 (square) for walls and bricks, voice 2 (triangle) for
             the paddle and a new level
  timing     one step per frame (FRAME, $D001)
The ball moves in 8.8 fixed point; it bounces off the brick under its
centre. Memory: $0800-$0F83, no zero page, so it can be CALLed and return.

Files: breakout.asm, breakout.cfg, build.sh (needs cc65), breakout.bin /
.hex, BREAKOUT (disk file, load address $0800).
