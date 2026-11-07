mini6502 BASIC - Derived from EhBASIC
=====================================

This folder holds Enhanced BASIC (EhBASIC) 2.22p5 adapted for mini6502.

  Derived from EhBASIC

EhBASIC was written by Lee Davison. This version includes Klaus Dormann's
bug-fix patches (2.22p5): https://github.com/Klaus2m5/6502_EhBASIC_V2.22

Licence (from the EhBASIC readme):

  EhBASIC is free but not copyright free. For non commercial use there is
  only one restriction, any derivative work should include, in any binary
  image distributed, the string "Derived from EhBASIC" and in any
  distribution that includes human readable files a file that includes the
  above string in a human readable form e.g. not as a comment in an HTML
  file.

  For commercial use please contact Lee Davison at leeedavison@googlemail.com
  for conditions.

This adaptation is for personal, non-commercial use. The sign-on message
printed at start-up contains "Derived from EhBASIC", as the licence asks.
The mini6502 additions (the glue in mini6502_basic.asm, the "!" extension
wedge and its API, and the BASIC extensions in ../basicx such as GFX) are
Copyright (C) 2026 Benoit Colson, with the help of Claude AI, and are
part of this EhBASIC derivative: the same terms apply, free for personal,
non-commercial use.
The rest of mini6502 is under the GNU GPL version 3 (see ../LICENSES.txt).


Running it
----------
  mini6502 basic/basic.hex basic/basic.txt     loads BASIC and starts it
  mini6502 basic/basic.hex basic/hello.txt     ...and types in a demo

From the monitor:
  A000R   cold start: clears the screen; all of $0400-$9FFF is used (39935 bytes free)
  A003R   warm start: back into BASIC with your program kept, e.g. after F1
          (RESET) or SYSTEM
  G       the same: BASIC registers its warm start with the monitor
In BASIC, SYSTEM goes back to the monitor (also from inside a program).

Start BASIC automatically: save it to the disk as BOOT. At power-on the
monitor loads and runs BOOT (unless keys are already waiting, e.g. from a
file typed in from the command line). From the monitor:
  L EHBASIC              (or start mini6502 with basic/basic.hex)
  S BOOT A000.CAA6
F1 does not boot: it stops at the monitor, and G goes back to BASIC.

Keys: Backspace erases, Ctrl+C stops a running program. Type keywords in
upper case (F6 CAPS is on by default). Keys typed while a program runs are
kept for the next INPUT/GET or the next line.

The mini6502 hardware is reached with PEEK and POKE. EhBASIC reads $ hex
numbers anywhere a number goes, so the register addresses can be used as
they are ($D021 is the same as 53281):
  POKE $D021,$1E         COLOR: yellow on blue
  POKE $D020,5           BANK: bank 5 at $E000-$EFFF
  POKE $D031,15:POKE $D033,30:POKE $D030,60   voice 1: VOL 15, DUR 30, C4
  POKE $D100,1           BEEP
  PRINT CHR$(7)          beep too
  CLS                    clear the screen (new keyword; POKE $D000,2 does the same)
  LOCATE 12,30:PRINT "HI"   print anywhere on the screen without clearing it
                         (row 1-25, column 1-80; the column can be left out)
  POKE $D017,65          VCHR: put "A" in the cell under the cursor, without
                         moving it; PEEK($D017) reads it. Any of the 256 font
                         characters works (e.g. 219 = solid block)
  POKE $D018,$1E         VCOL: colour of that cell
  PEEK($D015) PEEK($D016)  CURX / CURY: cursor column and row, 0-based
  GET A$ / PEEK($D019)   arrows and other extended keys: GET gives CHR$(0),
                         then KBDEXT says which: 1 Up 2 Down 3 Left 4 Right
                         5 Home 6 End 7 PgUp 8 PgDn 9 Ins 10 Del
  PEEK($D001)            FRAME: +1 every 1/60 s, for steady timing
  POKE $D300,1           graphics: 160x200, 32 colours, blitter, sprites
                         (POKE $D300,0 back to text); see
                         demos/gfx/README.txt for the registers and examples
  POKE $D300,3           hires 640x400 in 2 colours, mouse and pointer: see
                         demos/hires/README.txt
  CALL DESKTOP           the desktop (DESKTOP is a constant like PI: 52368,
                         $CC90, far-call entry 17)
  CALL EDIT              the editor with its text kept (EDIT = 52248, $CC18,
                         entry 2 of your far-call table)
  CALL $E000             run machine code in the bank selected at $E000
  CALL $CC08             run entry 0 of the far-call vector table ($CC10 is
                         entry 1, then every 8 bytes): machine code in any
                         bank, whatever bank is selected (set it up with the
                         monitor's V command; see monitor/monitor.asm)


Extended memory: ports and DMA ($D200-$D21B)
--------------------------------------------
The whole 1 MB of banked RAM can also be reached without switching BANK,
with 24-bit addresses: $000000-$0FFFFF is the 1 MB (bank N is at $0N000),
and $FF0000-$FFFFFF is the 64K the CPU sees (RAM only: writes to I/O and
ROM are ignored, I/O reads 0).

Two ports, A and B. Set an address, then each PEEK/POKE of DATA reads or
writes the byte there and moves the address on by STEP (default 1):
  $D200-$D202  port A address, low / middle / high byte
  $D203        port A DATA
  $D204        port A STEP (0-255; 0 = stay on the same byte)
  $D208-$D20C  port B, the same
  10 POKE $D200,0:POKE $D201,$53:POKE $D202,0   port A at $005300 (bank 5)
  20 FOR I=1 TO 5:POKE $D203,ASC(MID$("HELLO",I,1)):NEXT
  30 POKE $D020,5:PRINT CHR$(PEEK($E300))      the same bytes, through BANK
A port wraps at the end of its space ($0FFFFF -> $000000).

DMA copies or fills a block at once (the CPU waits until it is done):
  $D210-$D212  source address          $D213-$D215  destination address
  $D216-$D218  length in bytes (up to 1 MB)
  $D219        command: write 1 = COPY, 2 = FILL (starts it)
  $D21A        FILL value
  $D21B        status: 0 ok, 1 bad command, 2 bad address
  40 POKE $D210,0:POKE $D211,$53:POKE $D212,0   source $005300
  50 POKE $D213,0:POKE $D214,$CB:POKE $D215,$FF destination $CB00 (CPU)
  60 POKE $D216,5:POKE $D217,0:POKE $D218,0     5 bytes
  70 POKE $D219,1:PRINT PEEK($D21B)             COPY; 0 = it worked
Overlapping blocks copy correctly. FILL: set the destination, length and
$D21A, then POKE $D219,2.

Keep BASIC lines under about 70 characters: longer ones are cut off when
typed in (EhBASIC's input line limit).


Disk
----
Files go in the "disk" folder next to mini6502 (created when first needed),
shared with the monitor (S, L, $ commands there).
  SAVE "NAME"      save the program
  LOAD "NAME"      load it back (clears variables, stops a running program)
  DIR  or  CAT    list the disk (CALL $A006 does the same)
  KILL "NAME"      delete a file
DIR, CAT, CLS, KILL, SYSTEM, LOCATE, DESKTOP and EDIT are new keywords, so variable names can't start with them
(DIRX or CATS would be read as DIR X / CAT S).
Any string expression works as the name: SAVE N$, LOAD "LEVEL"+STR$(L)...
Names: up to 64 of A-Z a-z 0-9 . _ - ; LOAD also finds the name in upper
or lower case. Errors: "File not found Error", "Bad file name Error",
"Program too big Error".
Use LOAD in BASIC for BASIC programs: loading one with the monitor's L does
not update BASIC's pointers.


Fixes on top of 2.22p5 (see the top of ehbasic.asm)
-------------------------------------------------
  MID$ could jump to a wrong address when an internal call ended a memory
  page (it did in this build: every MID$ gave an error).
  SWAP gave "Type mismatch" for two variables of the same type.
Quirk kept from EhBASIC: FRE(0) is a signed 16-bit number, so with more
than 32767 bytes free it shows negative (-25603 means 39933: add 65536).
PEEK, POKE and CALL take addresses up to 65535 or $FFFF either way.


Memory
------
  $00-$EF    zero page used by BASIC, except $E2-$EE ($E6-$ED is the monitor's)
  $0300-$036F  BASIC's flags, I/O vectors and input line
  $0400-$9FFF  your program, variables and strings
  $A000-$CAA6  BASIC itself (loaded into RAM)


Files
-----
  mini6502_basic.asm   start-up and keyboard/terminal glue for mini6502
  ehbasic.asm          the interpreter (EhBASIC 2.22p5, changes listed at the top)
  basic.cfg            ld65 configuration (load at $A000)
  build.sh             assembles basic.bin and basic.hex (needs cc65)
  bin2hex.py           binary -> monitor hex dump
  basic.bin, basic.hex the assembled BASIC
  basic.lst, basic.map listing and map, with every routine's address
  basic.txt            types A000R (start BASIC)
  hello.txt            starts BASIC and runs a small demo
  Enhanced_6502_BASIC_reference_manual.pdf   the EhBASIC manual

Extensions: ! commands
----------------------
Statements that start with "!" belong to BASIC extensions in banks
$00-$07, e.g. GFX (bank $00, loaded by DESKTOP.TXT) for graphics, sound and
the mouse:  !SCREEN 2:!COLOR 14:!LINE 0,0,159,199:!SOUND 1,60,15
Functions start with "!" too: X=!MOUSEX, IF !BUTTONS AND 1 THEN ...
!HELP lists the commands of the extensions present. BASIC finds them at
each cold or warm start. See basicx/README.txt, also for writing one.
