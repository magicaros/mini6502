mini6502 hardware and system table
==================================

One table, mini6502.def, describes the machine: every I/O register, the
bank zones, the banks with a fixed use, the far-call entries with their
names, the bank map's owner values and the ROM's system calls. Everything
else is made from it or checked against it.
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

  python3 hw/gen.py      after changing mini6502.def (needs python3)
makes:
  hw/mini6502.inc        equates for programs:  .include "mini6502.inc"
                         (build with ca65 -I ../hw, as every build.sh does)
  hw/REGISTERS.txt       the reference, to read
  the description at the top of mini6502.bas (don't edit it there)
  hw/VECTORS             the far-call table with its names: copy it to the
                         disk as VECTORS (BOOT.TXT and DESKTOP.TXT load it)
and then runs
  python3 hw/check.py    the host (IORead / IOWrite in mini6502.bas) and the
                         simulator (monitor/simtest.py) must decode exactly
                         the registers in the table: a register the table
                         says is read but the host does not decode, or the
                         other way round, is reported. (It would have caught
                         the hires registers the host once ignored.)

Adding a register: describe it in the text part of mini6502.def, add an
@reg line (name, address, r / w / rw, size), decode it in mini6502.bas and
in the simulator, run gen.py. Adding a system program: a @bank line, and
@entry lines for its far-call entries (with a name, up to 8 characters).

Names in mini6502.inc
---------------------
  registers     as in the table: KBD, BANK, MODE, BCMD, SPR, MOUSEX...
                (voices: V1-V4 + V_NOTE.., shaping S1-S4 + S_DECAY..)
  Z_name        bank zones (first bank; Z_name_END the last)
  B_name        fixed banks (B_EDIT = $13, B_MUSIC = $12...)
  E_name        far-call entry addresses (JSR E_MUSIC); EN_name its number
  OWN_name      bank map owners (OWN_FREE, OWN_MAIN, OWN_HAND, OWN_SYSTEM)
  BALLOC...     the system calls
A program's own label with one of these names clashes: rename the label.

Banks
-----
  $00-$07  kept free for EhBASIC extensions
  $08-$0F  yours: load what you like there by hand (the allocator never
           hands them out). LULLABY is in $08; the demos' READMEs suggest
           $09 GFXDEMO, $0A HIDEMO, $0B IRQTUNE
  $10-$1F  the system: $10-$11 toolkit, $12 music, $13 EDIT, $14-$16
           desktop, $17-$19 toolkit (controls, file dialog), $1A the file
           dialog's directory, $1B the desk accessories,
           $1C-$1F the clipboard
  $20-$7F  programs: $20 is the desktop's launch bank
  $80-$BF  documents, songs, data
  $C0-$FF  swap areas ($C0 desktop, $D0 toolkit, $E0/$F0 editor)

The bank map ($CF00-$CFFF, in the system page that nothing swaps out)
says who has each bank: $00 free, $FD a main-RAM program, $FE loaded by
hand, $FF system, otherwise the bank of the program that owns it. The
monitor sets it at power-on, M lists it, M BB OO changes it, and L NAME
HHHH BB marks a free bank as loaded by hand.

A program that needs banks asks the ROM instead of picking numbers:
        lda #owner      ; your own bank (or OWN_MAIN in the main RAM)
        ldx #2          ; how many, next to each other
        ldy #1          ; 0 programs zone, 1 documents zone
        jsr BALLOC      ; A = the first bank; carry set if there is no room
and gives them back with BFREE (A = bank) or BFREEALL (A = owner). The
desktop frees whatever a program it started still owns when it returns.

Service names
-------------
Every far-call entry can have a name (V NN BB HHHH NAME in the monitor,
@entry in the table). A program finds a service without knowing its
number:
        ldx #<name
        ldy #>name
        jsr VFIND       ; A = the entry, X/Y = its address; carry set if none
        ...             ; then JSR to it through a JMP (address) of your own
name:   .byte "MUSIC", 0
The fixed numbers stay valid too (BASIC's CALL DESKTOP and CALL EDIT).
