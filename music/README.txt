mini6502 music engine
=====================

Plays songs (.MUS files) on the three music voices from the frame
interrupt, in the background: it keeps playing while BASIC, the monitor or
the desktop runs. The noise voice (voice 4) is never touched, so a game can
play its sound effects over the music.
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

  bank $12        the engine (MUSIC on the disk)
  entry $19       far-call entry for assembly ($CCD0)
  entry $1A       far-call entry for BASIC ($CCD8)
  songs           anywhere in the banks; one bank (4K) holds a short song

DESKTOP.TXT loads it (L MUSIC E000 12); its entries are in VECTORS.

Trying it
---------
  L DEMO.MUS E000 80                  the demo song into bank $80
then from BASIC:
  POKE 52446,0:POKE 52447,128:CALL 52440    play the song in bank 128 ($80)
  POKE 52446,1:CALL 52440                   stop
It goes on playing in the desktop (CALL DESKTOP) and back.

Calling it
----------
Assembly:   LDA #function : LDX #argument : JSR $CCD0
BASIC:      POKE 52446,function : POKE 52447,argument : CALL 52440
            (52446/52447 = $CCDE/$CCDF, two spare bytes of entry $1A; the
            results come back there: A in 52446, X in 52447)
  0 PLAY      X = the bank where the song starts. Carry set if it is not a
              song. The engine takes the interrupt (IRQVEC, IRQBANK, bit 0
              of IRQEN) and does CLI.
  1 STOP      the voices are released; the interrupt is let go (IRQEN 0)
  2 PAUSE     the voices are released; 3 CONTINUE goes on from there
  4 STATUS    A = 0 stopped, 1 playing, 2 paused; X = order, Y = row
  5 VOLUME    X = 0-15: the song's loudness, from each voice's next
              instrument or volume effect on (fades: lower it step by step)
While it plays, the engine owns the interrupt: a program can still watch
the FRAME counter ($D001) for its own timing. Inside the interrupt it uses
port B (and puts it back as it was) and the voices 1-3, nothing else: no
zero page, no fixed RAM. A program started from the desktop gets the sound
as at power-on, so the music stops there (SYSCTL 3).

Writing a song
--------------
Until there is a music program on the desktop, songs are written as text
and compiled on the PC:
  python3 mus.py demo.txt DEMO.MUS
demo.txt shows everything; the full description is at the top of mus.py.
In short: a song has instruments (wave, volume, duration, DECAY, SWEEP,
PULSE, vibrato), patterns (ROWS rows for one voice: note, instrument,
effect) and an order list (for each step of the song, a pattern for each
of the three voices, so one bass pattern can go under several melodies).
Effects: arpeggio, slide, vibrato, volume, speed, jump, break, pulse.

Songs are written with TRACKER on the desktop (../tracker/README.txt), or
as text compiled by mus.py.

The .MUS format
---------------
After the disk file's 2-byte load address ($E000):
  0   "MU", version (1), speed, orders, loop order ($FF = stop at the end),
      rows per pattern (1-64), instruments (0-32), patterns, 0,
      order list offset (2 bytes), patterns offset (2), title offset (2)
  16  instruments, 8 bytes each: DECAY VOL WAVE SWEEP PULSE DUR VIBRATO 0
      the order list: 3 bytes per order, a pattern number for voice 1, 2, 3
      the patterns, numbered from 0 (0 = silence): ROWS rows of 4 bytes:
        note (0 = nothing new, 1-127 = play, $FF = release), instrument
        (0 = keep), effect, parameter
      the title, ending with 0
  Effects: 1 arpeggio (+hi, +lo nibble semitones, a step a frame), 2 slide
  (SWEEP = parameter), 3 vibrato (speed hi nibble, depth lo nibble), 4
  volume, 5 speed (frames per row), 6 jump to order, 7 break (next order),
  8 pulse width. A row with no note and no effect changes nothing (an
  arpeggio, vibrato or slide goes on); a note or another effect ends it.
Offsets count from "MU". Every pattern is ROWS * 4 bytes, so the engine
finds pattern P at patterns offset + P * ROWS * 4.

Inside
------
music.asm: the engine. Arpeggios and vibratos use the voices' BEND
register ($D053 + 4*voice), which moves the pitch without starting the
note again; slides use SWEEP; instruments set WAVE, VOL, DUR, DECAY,
PULSE. build.sh (needs cc65 and python3) makes MUSIC and DEMO.MUS.
