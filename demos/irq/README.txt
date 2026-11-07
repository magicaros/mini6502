mini6502 interrupts and the noise voice
=======================================

IRQTUNE plays a short tune in the background from the frame interrupt:
the melody, bass and arpeggio on the three music voices, the drums on the
noise voice (voice 4). It keeps playing while you type in BASIC or the
monitor, and in the desktop.

  L IRQTUNE E000 0B     load it into bank $0B (any bank works)
  D020: 0B              select it
  E000R                 start it; E003R stops it
From BASIC: POKE $D020,11:CALL $E000 (stop: POKE $D020,11:CALL $E003).
Files: irqtune.asm, build.sh (needs cc65), irqtune.bin / .hex, IRQTUNE.
Memory: $E000-$E12F in its bank; no zero page, nothing in the fixed RAM.

Interrupts
----------
  $D007  IRQEN     the sources wanted: 1 FRAME (every 1/60 s), 2 KEY (a key
                   was typed), 4 MOUSE (a button was pressed)
  $D008  IRQFLAGS  read: the sources that fired; reading clears them
  $D009  IRQBANK   the bank selected while the handler runs
  $D00A  IRQVEC    the handler's address (low, high)
To use them: set IRQVEC and IRQBANK, then IRQEN, then CLI. The monitor's
IRQ code saves A, X, Y and BANK, clears D, selects IRQBANK, reads IRQFLAGS
into A and JSRs to your handler, which ends with RTS (not RTI). Your
handler may use A, X and Y; anything else it uses must not be used by what
it interrupts, so keep its variables in its own bank (or in memory only it
uses) and stay out of the zero page.
Off again: IRQEN 0 (or SEI). F1 and SYSCTL 3 turn the interrupts off.
A BRK still stops in the monitor, and leaves the interrupts as they were.

Where the handler lives matters:
  in a bank ($E000-$EFFF, IRQBANK = that bank): it keeps running under
     BASIC, the editor and the desktop (they swap the fixed RAM, not the
     banks). That is how a background music player works.
  in the fixed RAM: the editor and the desktop turn it off while they have
     swapped your RAM out, and back on when they put it back.
A program started from the desktop gets the interrupts off (as the video
and the sound), and the desktop turns them off again when it comes back.

The sound, as it is now
-----------------------
  $D030-$D03F  4 voices, 4 registers each: NOTE, VOL, WAVE, DUR (voice 1 at
               $D030, 2 at $D034, 3 at $D038, 4 at $D03C)
  Voices 1-3 are for music (WAVE 0 square, 1 triangle, 2 sawtooth, 3 noise).
  Voice 4 is the noise voice for sound effects: WAVE 0 white noise, 1
  metallic; its NOTE sets how fast the noise changes (low = rumble, high =
  hiss). Keep it for effects and a game never steals a note from the music.
  $D050-$D05F  shaping, 4 registers per voice (voice 1 at $D050 ... 4 at
               $D05C):
    +0 DECAY   the volume goes down by 1 every DECAY frames from each NOTE
               on, and the note ends at 0 (0 = none)
    +1 SWEEP   signed: the pitch moves SWEEP/16 of a semitone every frame
               (+ up, - down; 0 = none)
    +2 PULSE   square width 0-15: (PULSE+1)/32 high; 15 = plain square
    +3 BEND    signed: the pitch moved by BEND/8 of a semitone, at once and
               without starting the note again (vibrato, arpeggios)
  An explosion: noise, slowly fading, falling:
    POKE $D03D,15:POKE $D03E,0:POKE $D05C,4:POKE $D05D,252:POKE $D03C,60
  (VOL 15, white, DECAY 4, SWEEP -4, NOTE 60.) A laser: square on a music
  voice with SWEEP -40; a coin: two quick NOTEs with DECAY 1.
