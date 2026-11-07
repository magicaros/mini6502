mini6502 EDIT - full-screen text editor
=======================================

Runs from a RAM bank at $E000. BASIC (or whatever was running) stays alive
while you edit: the editor swaps the whole fixed RAM with its own copy.
An interrupt handler in the fixed RAM is turned off meanwhile (one in a
bank, such as background music, keeps running).
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

Starting it
-----------
The disk has it as EDIT. Load it into a bank once, from the monitor:

  L EDIT E000 13     load it into bank $13, its place in the system zone
                     (BOOT.TXT does it; any bank below $E0 works)

Then, with that bank selected (D020: 13 in the monitor, POKE $D020,19 in
BASIC):

  E000R  or  CALL $E000     start with an empty text
  E003R  or  CALL $E003     carry on with the text from last time (an
                            empty one the first time)
  $E006                     (for programs such as the desktop) start
                            and load the file whose name, ending with 0,
                            is at $EF80 in the editor's bank

Esc puts everything back as it was and returns where you came from: to
BASIC after a CALL (program and variables intact), to the monitor after R.

Easiest from BASIC, whatever bank is selected: CALL EDIT (far-call entry
$02, $CC18, in VECTORS: bank $13, $E003) opens the editor with the text
from last time, CALL 52240 (entry $01, $CC10) with an empty text; Esc comes
back to BASIC with the bank it had before.

How it works: on entry the editor copies the fixed RAM $0000-$CBFF (zero
page, stack, BASIC and its program...) to banks $F0-$FC with the DMA, and
copies its own RAM image (text and state) in from banks $E0-$EC. Esc does
the reverse and returns with RTS on the caller's own stack. Each copy is
52K and instant. Don't use banks $E0-$FF for anything else; started from a
bank there, the editor just beeps and returns.

F1 while editing: the RAM still holds the editor's image, and G resumes the
editor (it points G at a small stub at $CBF0 while it runs). Esc then
returns to the original caller as usual, and G goes back to BASIC again.

Keys
----
  arrows               move (up/down keep the column)
  Home / End           start / end of the line
  PgUp / PgDn          23 lines up / down
  Enter                new line
  Backspace            delete the character before the cursor
  Delete               delete the character under the cursor
  Tab                  spaces up to the next multiple of 8
  Ctrl+S               save (asks for the name; Enter keeps the shown one)
  Ctrl+L               load
  Ctrl+N               new, empty text
  Esc                  back to BASIC / the monitor (text kept)

Ctrl+L and Ctrl+N ask for Y first when there are unsaved changes (shown as
* after the name). F6 (CAPS) is on by default in mini6502, so letters come
out in upper case: press F6 for lower case.

The status line shows the file name, line, column and the free space.

Files
-----
Plain text in the mini6502 disk folder, with the usual 2-byte load address
in front ($0400). Lines end with CR. When a file is loaded, LF and CR LF
become CR, so text written elsewhere loads fine.

Limits
------
  text           51,184 bytes ($0400-$CBEF), held as a gap buffer
  columns        up to 255 are shown; when the cursor goes past column 80
                 the whole screen scrolls sideways
  speed          about 20,000 cycles per key at most (20 ms at 1 MHz);
                 raise CPU_HZ in mini6502.bas for a snappier feel

Memory
------
In the editor's own RAM image (swapped in while it runs):
  $10-$31        zero page: editor state
  $0300-$035F    signature, file name, name being typed
  $0400-$CBEF    text
  $CBF0-$CBF7    the stub G jumps to (selects the bank, JMP $E003)
Elsewhere:
  $E000-$EB72    the editor itself, in its bank
  $EF80-$EFA8    in its bank: the file name for $E006
  $EFF0-$EFF7    in its bank: which image is in the RAM, the caller's stack
                 pointer, G address and COLOR
  banks $E0-$EC  the editor's RAM image while you are away
  banks $F0-$FC  the caller's RAM (BASIC...) while you edit
Needs the DMA ($D210-$D21B), new in mini6502 with the extended memory ports.

Building
--------
  sh build.sh          needs cc65 (ca65, ld65); makes edit.bin / edit.hex
To put a new build on the disk: start "mini6502 edit/edit.hex" (the hex
file loads into bank 0 at $E000), then in the monitor:
  S EDIT E000.EB72

Keyboard codes it uses (new in mini6502)
----------------------------------------
An arrow or other extended key reads as $80 (a NUL) in KBD ($D010), and
KBDEXT ($D019) then says which one: 1 Up, 2 Down, 3 Left, 4 Right, 5 Home,
6 End, 7 PgUp, 8 PgDn, 9 Insert, 10 Delete. The monitor and BASIC ignore
NULs, so nothing changes for them; in BASIC, GET returns CHR$(0) for such a
key and PEEK(53273) tells which one.
