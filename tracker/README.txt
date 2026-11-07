TRACKER - songs for the music engine
====================================

A music tracker for the desktop, built on the toolkit: it writes the .MUS
songs the music engine plays (bank $12, see ../music/README.txt).
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

Starting it
-----------
On the desktop: double-click TRACKER, or a song (.MUS, the note icon): it
opens in TRACKER. TRACKER needs TRACKER2 too (it loads it when it starts):
both live in the disk's TRACKER folder (the desktop and TRACKER look there,
or at the top). The music engine must be loaded (DESKTOP.TXT does it).
By hand: the toolkit, ACC, MUSIC and VECTORS loaded (DESKTOP.TXT's L lines),
then
  L /TRACKER/TRACKER E000 20   D020: 20   E000R      an empty song
or, with a name at $EF80 in that bank (ending with 0), E006R to open it.
Quitting stops the music.

The screen
----------
  line 1     the title, speed, rows, the loop order, the octave and the
             instrument the piano keys use, PLAYING
  line 2     the order shown and how many there are, each voice's pattern
  on the left  the order list: each order's number and its three patterns
             (the one shown inverted; click one to show it)
  the grid   one row per line, in hex, and the three voices of the order
             shown. A cell is  NOTE INSTRUMENT EFFECT:
               C-4 01 A37     C-4 (C#4, ---: nothing, ===: note off),
                              instrument 01-20 (..: the voice's last one),
                              effect letter and its byte (...: none)
             The cursor is on one field of a cell (inverted). While a song
             plays, > marks the row playing and the view follows it.
             The scroll bar on the right (or the mouse wheel, 3 rows a
             step) scrolls the grid without moving the cursor; the next
             key brings the view back to it.
  last line  a reminder of the keys

The keys
--------
  arrows, PgUp, PgDn,     move (Tab: the next voice); with Shift held the
  Home, End               block grows from where the cursor was
  Ctrl + Left / Right     the previous / next order
  Ctrl + Up / Down        this voice's pattern number in this order, +1 / -1
  on a note               the keyboard is a piano, by where the keys are (an
                          AZERTY keyboard plays the same notes as a QWERTY):
                          the bottom row  Z S X D C V G B H N J M ,  is one
                          octave from C, the row above  Q 2 W 3 E R 5 T 6 Y 7
                          U I 9 O 0  the next one; 1 = note off. The note
                          gets the current instrument, sounds, and the
                          cursor goes down a row.
  + / -                   the octave of the piano (0-8)
  on the instrument or    hex digits (0-9, A-F)
  the effect's byte
  on the effect           its letter (below), "." for none
  Enter                   type the whole cell: "C-4 01 A37", "--- .. ..."
                          (the empty parts can be left out: "D#5")
  Delete                  this field emptied (a note: note and instrument);
                          with a block: the block emptied
  Esc                     no block
  Insert / Backspace      a row inserted / deleted in this voice's pattern
  Space                   play from this order / stop
Typing into a voice whose pattern is 0 (silence) gives it a new pattern of
its own first.

The mouse: a click puts the cursor on that field; drag to select a block
(above or below the grid it scrolls); Shift+click makes the block go from
the cursor to there. A click in the order list shows that order.

Blocks
------
A block is a rectangle of whole cells: some rows of one, two or three
voices, shown inverted. Moving without Shift, or typing a note, ends it.
Copy (Ctrl+C) keeps it (without a block: the cursor's cell); Paste
(Ctrl+V) puts it back with its top left cell at the cursor, in this order
or any other (what would fall below the last row or right of voice 3 is
left out; a voice on pattern 0 gets a new pattern). The copied block stays
while TRACKER runs, across New and Open, so a block can go from one song
to another. A pattern is shared by every order that uses its number:
pasting into it changes all of them (New pattern, Ctrl+W, gives a voice
its own).

The menus
---------
  File        New (Ctrl+N), Open... (Ctrl+O), Save (Ctrl+S), Save as...,
              Quit (Ctrl+Q). New, Open and Quit ask first if there are
              unsaved changes (* after the name in the title).
  Edit        Cut (Ctrl+X), Copy (Ctrl+C), Paste (Ctrl+V), Clear: the block
              (or the cursor's cell); Select all (Ctrl+A): every row of the
              three voices; Transpose +1 (Ctrl+U) / -1 (Ctrl+B): the
              block's notes a semitone up / down; Insert row, Delete row
              (this voice's pattern, at the cursor)
  Song        Settings... (Ctrl+G): the title, the speed (frames a row),
              the rows of every pattern (1-64), the order the song loops to
              (empty: it stops at the end). Insert order (a silent one
              here), Duplicate order (Ctrl+D), Delete order, New pattern
              (Ctrl+W: this voice gets a pattern nothing uses)
  Instrument  Edit... (Ctrl+E): the current instrument's wave (square,
              triangle, saw, noise), volume, duration (frames, 0: held
              until the next note), decay, sweep, pulse width, vibrato speed
              and depth; Test plays it, Prev / Next go through the 32.
              Next (Ctrl+K), Previous (Ctrl+L): the piano's instrument.
  Play        Song (Ctrl+P), From this order (Ctrl+R), Pattern (Ctrl+T:
              this order over and over), Stop (Ctrl+Y)

The effects (the engine's, see ../music/README.txt): A arpeggio, S slide,
V vibrato, L volume, T speed, J jump to an order, B break to the next
order, P pulse width.

Files
-----
The .MUS format of ../music/README.txt, with all 32 instruments. TRACKER
saves it with the load address $7000 (where it builds it); give an address
when loading a song by hand anyway: L SONG.MUS E000 80, then the engine
plays it from bank $80. Songs made with mus.py open in TRACKER too.
Up to 255 orders and 64 patterns (pattern 0 is always silence).

Inside
------
tracker.asm makes two parts (tracker.cfg, build.sh, needs cc65):
  TRACKER   for a bank ($E000-$EF7F): the menus, files, the dialogs
  TRACKER2  main RAM $0800-$1FFF: the song, the screen, the keys, playing
While it runs the main RAM holds the song: $2000 the instruments, $2100
the order list, $2400 the title, $2500-$27FF the copied block, $2800 the
screen's line buffers, $3000-$6FFF the patterns (256 bytes each), and
$7000-$BFFF the .MUS image built to save or to play. To play,
the image is copied (DMA) into 5 banks of the documents zone TRACKER asks
for when it starts (BALLOC, freed by the desktop when it ends) and the
engine plays it from there; the screen follows the engine's STATUS.
