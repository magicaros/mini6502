mini6502 sound demo: Brahms' Lullaby
====================================

Plays the melody of Brahms' Lullaby (Wiegenlied, Op. 49 No. 4, 1868 - the
music is in the public domain) on the three sound voices, with a small
display showing what each voice plays.
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

Run it (it is on the disk as LULLABY):
  L LULLABY E000 08     load into bank 8 (any bank works)
  D020: 08              select it
  E000R                 play; any key stops it and returns to the monitor

What it shows off
  voice 1  melody   triangle, volume 15
  voice 2  bass     triangle, volume 10, one note per bar
  voice 3  harmony  sawtooth, volume 5, chord tones on beats 2 and 3
  Notes start with a DUR a few frames shorter than their length, so they
  fade out cleanly before the next one. Tempo: 18 frames per eighth note
  (about 100 quarter notes a minute). The tune loops until a key is pressed.

Timing uses the FRAME counter ($D001, new in mini6502: +1 every 1/60 s), so
the tempo is the same whatever CPU_HZ is set to.

Files
  lullaby.asm   the player (961 bytes)
  song.py       writes song.inc from the melody and chord list in it; edit
                the notes there to play another tune
  song.inc      the generated note streams
  build.sh      builds lullaby.bin / lullaby.hex / LULLABY (needs cc65)

Memory: $E000-$E3C0 in its bank, $E2-$E3 of the zero page, $02A0-$02AD.
RAM, BASIC and the monitor are left alone.
