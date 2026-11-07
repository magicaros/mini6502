'=============================================================================
' mini6502.bas - a minimal 6502 machine around the Fake6502 QB64 core
'-----------------------------------------------------------------------------
' Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
' Free software under the GNU General Public License, version 3 or
' (at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
' A small fantasy 6502 machine with its own monitor ROM
' (monitor.asm), compatible with programs written for the Woz Monitor.
'
' Memory map   (made by hw/gen.py from hw/mini6502.def: edit that, not this)
'   $0000-$CBFF  RAM (fixed)
'   $CC00-$CFFF  the SYSTEM PAGE, fixed RAM that no program swaps out: the
'                far-call table, the service names and the bank map (see
'                "System page" below)
'   $D000-$DFFF  I/O space (unused addresses read 0, writes are ignored)
'     $D000  SYSCTL write: 1 quit the emulator (at the end of the frame)
'                          2 clear the screen (current COLOR), cursor home
'                          3 reset the video (MODE 0, palette, sprites, pointer,
'                            blitter), the sound and the interrupts as at
'                            power-on
'                        $FF cold reset: RAM $0000-$CFFF is set to 0 (the
'                            banked RAM is kept), then RESET as with F1
'                   other values are ignored
'                   read: 1 once after power-on or a $FF cold reset (the
'                   monitor then boots the file BOOT), else 0; reading
'                   clears it, F1 does not set it
'     $D001  FRAME  read: frame counter, +1 every 1/60 s (wraps at 255);
'                   for steady timing whatever CPU_HZ is
'     $D004-$D006 CLOCK  read: the PC's time of day: hours (0-23), minutes,
'                   seconds
'     $D007  IRQEN  interrupts wanted, one bit per source (0 at power-on,
'                   F1, SYSCTL 3):  1 FRAME  at the start of every frame
'                   (60 Hz)   2 KEY  a key was typed   4 MOUSE  a button
'                   was pressed. A source sets its bit in IRQFLAGS only
'                   while enabled; the IRQ line is held while IRQEN AND
'                   IRQFLAGS is not 0, and the CPU takes it when its I
'                   flag is clear (CLI). The monitor's IRQ code (see
'                   monitor.asm) saves A, X, Y and BANK, selects IRQBANK,
'                   reads IRQFLAGS into A and JSRs to IRQVEC; the handler
'                   ends with RTS.
'     $D008  IRQFLAGS read: the sources that fired since the last read;
'                   reading clears them (and releases the IRQ line)
'     $D009  IRQBANK  bank selected while the handler runs (read/write)
'     $D00A  IRQVEC   handler address, low / high byte (read/write)
'     $D002  WARMLO  warm start address, low byte  } set by a program (BASIC
'     $D003  WARMHI  warm start address, high byte } does) so that the
'                   monitor's G command can go back to it; read back as
'                   written. Kept by F1; 0 at power-on and after $FF.
'     $D010  KBD    read: last key OR $80; reading clears the ready flag
'     $D011  KBDCR  read: bit 7 = 1 when a key is waiting   (writes ignored)
'     $D012  DSP    write: character to the terminal; read: 0 (never busy)
'     $D013  DSPCR  read: 0                                 (writes ignored)
'     $D014  KBDPEEK read: the waiting key OR $80 (like KBD) but the key
'                   stays waiting; 0 if there is none      (writes ignored)
'     $D015  CURX   cursor column 0-79   } read: where the next character goes
'     $D016  CURY   cursor row 0-24      } write: move the cursor there (values
'                                          past the edge stop at the edge)
'     $D017  VCHR   the character in the cell under the cursor, read/write;
'                   the cursor does not move. Any of the 256 characters of the
'                   font can be written, including the graphics ones
'     $D018  VCOL   the COLOR of the cell under the cursor, read/write
'     $D019  KBDEXT read: when KBD gives $80 (a NUL), the key was one of these:
'                   1 Up  2 Down  3 Left  4 Right  5 Home  6 End  7 PgUp
'                   8 PgDn  9 Insert  10 Delete      (0 for ordinary keys)
'                   Programs that ignore NUL (the monitor, BASIC) ignore them
'     $D01A  KEYSEL  a key code, read/write: KEYHELD says whether that key
'                   is held down right now (for games: no auto-repeat, and
'                   several keys at once). Codes: the key's character in
'                   capitals (A-Z, 0-9, 32 Space, 13 Enter, 27 Esc, 8
'                   Backspace, 9 Tab, and the other printable keys), 129
'                   Up 130 Down 131 Left 132 Right 133 Home 134 End 135
'                   PgUp 136 PgDn 137 Insert 138 Delete (128 + the KBDEXT
'                   code), 140 Shift, 141 Ctrl, 142 Alt
'     $D01B  KEYHELD read: 1 if the KEYSEL key is held down, else 0
'     $D01C  KEYPOS  a key POSITION, read/write: POSHELD says whether the
'                   key in that place is held down, whatever is printed on
'                   it (WASD games on any layout). Positions are PC
'                   scancodes, named after a US keyboard: 1 Esc, 2-11 the
'                   digits 1-9 0, 14 Backspace, 15 Tab, 16-25 Q W E R T Y
'                   U I O P, 28 Enter, 29 Ctrl, 30-38 A S D F G H J K L,
'                   42 left Shift, 44-50 Z X C V B N M, 54 right Shift, 56
'                   Alt, 57 Space, 59-68 F1-F10, 71 Home, 72 Up, 73 PgUp,
'                   75 Left, 77 Right, 79 End, 80 Down, 81 PgDn, 82 Insert,
'                   83 Delete
'     $D01D  POSHELD read: 1 if the key at KEYPOS is held down, else 0
'     $D01E  KBDFLAGS bit 0: CAPS (letters typed come out in capitals; F6
'                   switches it). Read: 1 on, 0 off. Write: 1 on, 0 off
'     $D020  BANK   write: select the RAM bank seen at $E000-$EFFF (0-255)
'                   read: the bank currently selected; RESET selects bank 0
'     $D021  COLOR  write: colors for the characters printed from now on
'                   high nibble = background, low nibble = character
'                   ($0F = white on black, $1E = yellow on blue...)
'                   read: the current value; RESET sets $07 (light grey on black)
'     $D030-$D03F   SOUND: 4 voices, 4 registers each (voice 1 at $D030,
'                   voice 2 at $D034, voice 3 at $D038, voice 4 at $D03C);
'                   all read back. Voices 1-3 are for music; voice 4 is a
'                   noise voice for sound effects (see WAVE)
'       +0  NOTE    MIDI note number (60 = C4, 69 = A4 = 440 Hz, 127 max).
'                   Writing 1-127 starts the note (a voice already playing
'                   changes pitch at once, without a click); 0 releases it.
'       +1  VOL     volume 0-15 (RESET: 15)
'       +2  WAVE    0 square, 1 triangle, 2 sawtooth, 3 noise (RESET: 0).
'                   Voice 4 is always noise: WAVE 0 white noise (hiss,
'                   explosions), 1 metallic (a short repeating noise: bells,
'                   engines); its NOTE sets how fast the noise changes
'                   (low = rumble, high = hiss)
'       +3  DUR     length in 1/60 s, used by the next NOTE write;
'                   0 = hold until NOTE 0 is written (RESET: 0)
'                   Notes fade in over 5 ms and out over 30 ms, so they do
'                   not click; VOL changes fade the same way.
'     $D050-$D05F   SOUND SHAPING: 4 registers per voice (voice 1 at $D050,
'                   2 at $D054, 3 at $D058, 4 at $D05C); all read back, 0 at
'                   power-on except PULSE
'       +0  DECAY   0 none; 1-255: from each NOTE write on, the volume goes
'                   down by 1 every DECAY frames, and at 0 the note ends
'                   (plucked strings, drums, explosions)
'       +1  SWEEP   signed: the pitch moves by SWEEP/16 of a semitone every
'                   frame from each NOTE write on (+ up, - down; 0 none)
'       +2  PULSE   square wave width, 0-15: (PULSE+1)/32 of the cycle is
'                   high; 15 = a plain square (power-on), lower = thinner
'       +3  BEND    signed: the pitch is moved by BEND/8 of a semitone, at
'                   once and without starting the note again (vibrato,
'                   arpeggios: the music engine uses it); 0 = none
'     $D200-$D21B  EXTENDED MEMORY: the whole 1 MB (and the CPU space)
'                   without switching banks. Extended addresses: 3 bytes,
'                   $000000-$0FFFFF = banked RAM (bank * 4096 + offset, so
'                   bank 5 $E123 is $005123), $FF0000-$FFFFFF = the CPU's
'                   address space as it is now ($FFxxxx: I/O reads 0 and
'                   is not written, nor is the ROM).
'       $D200-$D202  PORT A address, low / middle / high byte (read/write)
'       $D203        PORT A data: read or write the byte at the address,
'                    which then moves on by STEP (wraps within its space)
'       $D204        PORT A STEP, 0-255 (1 at power-on; 0 = stay put)
'       $D208-$D20C  PORT B: the same, a second independent port
'       $D210-$D212  DMA source address        } a write to $D219 does the
'       $D213-$D215  DMA destination address   } whole job at once:
'       $D216-$D218  DMA length (up to 1 MB)   }  1 COPY source -> destination
'       $D219        DMA command               }    (overlap is fine)
'       $D21A        DMA fill value            }  2 FILL destination with it
'       $D21B        DMA status: 0 ok, 1 unknown command, 2 bad address
'     $D300-$D33F   GRAPHICS: 160 x 200 pixels, 32 colours + DIM, or 640 x 400
'                   in 2 colours (hires) (see below)
'     $D400-$D4FF   SPRITES: 32 hardware sprites, 8 registers each
'     $D500-$D553   MOUSE and POINTER (see below)
'     $D100  BEEP   write: any value plays a short beep (880 Hz, 1/8 s)
'                   read: 1 while the beep sounds, else 0
'                   Printing $07 (BEL) to DSP beeps too.
'     $D040-$D048   DISK: files in the "disk" folder next to the program,
'                   and in its folders, two levels deep at most. Each file
'                   is a 2-byte load address (low, high) + data.
'       $D040  CMD     write to run a command (done at once):
'                      1 LOAD at the file's own address
'                      2 SAVE START..END-1
'                      3 LOAD at START
'                      4 DIR: list the current folder on the terminal
'                      5 DELETE the file NAME
'                      6 TYPE the file NAME: its text goes into the keyboard
'                        queue as if typed (a script). A 2-byte load address
'                        at the start (files saved by EDIT) is skipped; CR,
'                        LF and CR LF all become Enter
'                      7 DIR into memory at START: the current folder's
'                        folders, then its files, each in name order: the
'                        name, 0, size (3 bytes: $FFFFFE a folder, $FFFFFF
'                        no load address), load address (2 bytes, 0 for a
'                        folder); then one more 0. END: in = limit (0 =
'                        $D000), out = after the last 0. Status 3 (nothing
'                        written) if too big
'                      8 RENAME the file (or folder) NAME to the name at
'                        START (ending with 0 or CR); status 4 if that name
'                        exists. A path there ("/GAMES/X") moves a file to
'                        that folder
'                      9 FOLDER: the current folder becomes NAME: a folder
'                        in it, ".." (one up), "/" (the top) or a path
'                        ("/GAMES/SAVES")
'                     10 NEW FOLDER NAME
'                     11 DELETE FOLDER NAME (status 4 unless it is empty)
'                     12 COPY the file NAME to the name or path at START
'                     13 WHERE: the current folder's path ("/", "/GAMES",
'                        "/GAMES/SAVES") at START, 0 after it; END = after
'       $D041  STATUS  0 ok, 1 not found, 2 bad name, 3 does not fit,
'                      4 file error / name taken / folder not empty, 5
'                      unknown command, 6 bad range, 7 too deep (a third
'                      level of folders)
'       $D042  START   (2 bytes) LOAD: in for 3, out = where it went
'       $D044  END     (2 bytes) end+1. SAVE: in. LOAD: in = limit (0 =
'                      none), out = end+1 of what was loaded
'       $D046  NAME    (2 bytes) address of the file name
'       $D048  NAMELEN length of the name, or 0 if it ends with $00 or CR
'                      Names: up to 64 of A-Z a-z 0-9 . _ - , looked up in
'                      the current folder (as given, then in upper and in
'                      lower case); "/A/B/NAME" is a path from the top. A
'                      LOAD that does not find a plain name in the current
'                      folder tries the top of the disk too (programs' own
'                      parts, EDIT, scripts). Cold start: the top.
'                      LOAD skips I/O and ROM addresses; SAVE reads memory
'                      without I/O side effects.
'   $E000-$EFFF  banked RAM: 256 banks of 4K (1 MB), chosen through BANK
'
' Graphics (the host's own video memory, reached with the ports and the DMA)
'   Extended addresses (as for the ports / DMA above):
'     $FE0000-$FE7CFF  VRAM page 0, $FE7D00-$FEF9FF page 1: one byte per
'                      pixel, row by row: page + Y * 160 + X
'     $FD0000-$FDFFFF  sprite images: 256 images of 16 x 16 bytes, image N
'                      at $FD0000 + N * 256, row by row
'   Pixel byte: bits 0-4 colour 0-31 (palette), bit 5 DIM (shown at the
'     INTENS brightness), bit 6 unused, bit 7 TRANSPARENT (in sprite images,
'     COPY 7 and STAMP: the pixel is not drawn). Colour 0 is the background
'     for BEHIND sprites and background collisions.
'   The picture is scaled x4 / x2 to the 640x400 window: one text cell is
'   2 x 8 pixels.
'     $D300  MODE    0 text (power-on), 1 graphics, 2 graphics with the text
'                    on top (cells whose background is TRANSP show through),
'                    3 hires, 4 hires with the text on top (see HIRES below)
'     $D301  SHOW    page shown, 0-1
'     $D302  DRAW    page the blitter draws on (and PIXEL reads), 0-1
'     $D303  INTENS  brightness of DIM pixels in 16ths, 0-31: 8 = half
'                    (power-on), 0 = black, 16 = no change, above 16 = brighter
'     $D304  MASTER  brightness of the graphics and sprites in 16ths, 0-16
'                    (16 at power-on; the text layer is not affected)
'     $D305  TRANSP  text background colour (0-15) that is see-through in
'                    MODE 2 (0 at power-on)
'     $D306  INK     hires: palette entry of the 1 bits (0 = black)
'     $D307  PAPER   hires: palette entry of the 0 bits (15 = white)
'     $D308  PALIDX  palette entry 0-31 that $D309-$D30B read and write
'     $D309-$D30B    R, G, B of that entry, 0-255; writing B moves PALIDX on
'                    by 1. Power-on: 0-15 the 16 text colours, 16-22 greys,
'                    23-31 orange, skin, brown, dark green, sky blue, navy,
'                    plum, gold, lavender
'     $D310-$D319    BLITTER (done at once when CMD is written; coordinates
'                    are clipped to the screen)
'       $D310 X0  $D311 Y0  $D312 X1  $D313 Y1  $D314 COLOR (a pixel byte)
'       $D315 DX  $D316 DY  (COPY destination)  $D317 SRC page for COPY
'       $D318 CMD  1 CLEAR the DRAW page with COLOR   2 PSET X0,Y0
'                  3 LINE X0,Y0-X1,Y1    4 BOX    5 filled BOX
'                  6 COPY X0,Y0-X1,Y1 of SRC to DX,DY on DRAW
'                  7 the same, skipping TRANSPARENT pixels
'                  8 DIM the box (sets bit 5)    9 UNDIM it (clears bit 5)
'                 10 STAMP sprite image number COLOR at X0,Y0 (skipping
'                    TRANSPARENT pixels): tiles, fonts...
'       $D319 PIXEL read: the pixel at X0,Y0 on the DRAW page
'       $D31A-$D31F  hires: high bytes of X0, Y0, X1, Y1, DX, DY
'     $D320-$D323    sprite-sprite collisions, one bit per sprite (sprite 0
'                    = bit 0 of $D320 ... sprite 31 = bit 7 of $D323)
'     $D324-$D327    sprite-background collisions (an opaque sprite pixel on
'                    a pixel of colour 1-31). Both are gathered every frame
'                    and cleared by reading.
'   HIRES (MODE 3, 4): 640 x 400, 1 bit per pixel, in the same pages: 80
'   bytes a row, bit 7 = leftmost pixel; pixel X,Y of page 0 is bit
'   7 - (X AND 7) of $FE0000 + Y * 80 + X \ 8. 1 bits show INK, 0 bits PAPER
'   (and MASTER). No sprites, no DIM; the pointer works. The blitter then
'   works on bits, with 16-bit coordinates, through the ROP and the clip
'   rectangle; the source bit is the PATTERN if it is on, else COLOR bit 0.
'   Commands: 1 CLEAR (whole page, no clip), 2 PSET, 3 LINE, 4 BOX, 5 filled
'   BOX, 6 COPY (source bits), 7 COPY only the 1 bits, 10 STAMP sprite image
'   COLOR (bit 0 of each byte, $80 skipped), 11 CHAR. PIXEL reads 0 or 1.
'     $D328  ROP     0 SET (copy), 1 OR, 2 AND, 3 XOR, 4 INVERT (ignores the
'                    source), 5 CLEAR where the source is 1
'     $D329  PATON   1: the source is the PATTERN
'     $D32A  CHR     character for CHAR (CMD 11)
'     $D32B  STYLE   CHAR style: 1 bold, 2 underline, 4 italic, 8 inverse,
'                    16 opaque (the rest of the 8x16 cell draws source 0)
'     $D32C  CHAROUT write: sets CHR and draws it at once (as CMD 11)
'                    CHAR draws at X0,Y0 and moves X0 on by 8
'     $D330-$D337    PATTERN, 8 rows (bit 7 = left), repeating every 8
'                    pixels across and down. Power-on: 50% grey
'     $D338-$D33F    CLIP rectangle: X0, Y0, X1, Y1, 2 bytes each (low,
'                    high). Power-on: the whole screen
'   MOUSE and POINTER (all modes; positions in 640 x 400 pixels)
'     $D500/$D501  mouse X, $D502/$D503 mouse Y         (read only)
'     $D504  BUTTONS  1 left, 2 right, 4 middle, while held
'     $D505  WHEEL    steps since the last read (signed; + = towards you)
'     $D506  CLICKS   buttons pressed since the last read (as BUTTONS)
'     $D508  PTR      1 show the pointer, 2 it follows the mouse by itself
'     $D509/$D50A pointer X, $D50B/$D50C pointer Y (where its hot spot is)
'     $D50D/$D50E  HOTX / HOTY: the hot spot inside the 16x16 shape
'     $D510-$D52F  IMAGE: 16 rows of 2 bytes (bit 7 of the first = left)
'     $D530-$D54F  MASK: the same; mask 1 + image 1 = INK, mask 1 + image 0
'                  = PAPER, mask 0 = see-through. Power-on: an arrow.
'     $D550/$D551  mouse X (0-159) / Y (0-199) in 160 x 200 pixels (read)
'     $D552/$D553  mouse column (0-79) / row (0-24) in text cells (read)
'   Sprite N at $D400 + N * 8 (sprite 0 is drawn on top; all are under the
'   text layer):
'       +0 X, +1 Y   position + 16: X=16,Y=16 is the top left corner, so a
'                    sprite can slide in from any edge (screen = X-16, Y-16)
'       +2 IMAGE     sprite image 0-255
'       +3 FLAGS     bit 0 ON, 1 flip left-right, 2 flip upside down,
'                    3 double size (32 x 32), 4 BEHIND (hidden by pixels of
'                    colour 1-31), 5 SHADOW (dims what is under its opaque
'                    pixels instead of drawing them; no collisions)
'       +4..+7       free, read back as written
'   RESET (F1) sets MODE 0 and all video registers, the palette, the
'   sprites and the pointer as at power-on; the VRAM and the images are kept.
'   Banks: 256 of 4K at $E000-$EFFF (BANK), in zones:
'     $00-$07  BASICEXT  BASIC extensions, "!" commands (basicx/README.txt)
'     $08-$0F  USER      yours: load by hand; never handed out
'     $10-$1F  SYSTEM    the system's programs
'     $20-$7F  PROGRAMS  programs (the allocator hands these out)
'     $80-$BF  DOCUMENTS documents, songs, data (handed out too)
'     $C0-$FF  SWAP      the fixed RAM's copies while programs swap it
'   Banks with a fixed use:
'     $00      GFX       the BASIC extension GFX: !commands (DESKTOP.TXT loads
'                        it)
'     $01      DOS       the BASIC extension DOS: folders and files
'                        (DESKTOP.TXT loads it)
'     $08      LULLABY   the lullaby demo (BOOT.TXT loads it)
'     $10      TK1       the toolkit, part 1 (TK1)
'     $11      TK2       the toolkit, part 2 (TK2)
'     $12      MUSIC     the music engine (MUSIC)
'     $13      EDIT      the editor (EDIT)
'     $14      DESK1     the desktop, part 1 (DESK1)
'     $15      DESK2     the desktop, part 2 (DESK2)
'     $16      DESK3     the desktop, part 3: icons (DESK3)
'     $17      TK3       the toolkit, part 3: controls (TK3)
'     $18      TK4       the toolkit, part 4: controls' clicks and keys (TK4)
'     $19      TK5       the toolkit, part 5: the file dialog (TK5)
'     $1A      TKDIR     the file dialog's directory and names
'     $1B      ACC       the desk accessories: clock, calculator (ACC)
'     $1C-$1F  CLIP      the clipboard every program shares: its length (2
'                        bytes), then the text
'     $20      LAUNCH    where the desktop loads bank programs
'     $C0-$CC  DESKSAVE  the desktop's RAM while a program runs
'     $D0-$DC  TKSWAP    the caller's RAM while a toolkit program runs
'     $E0-$EC  EDITIMG   the editor's RAM while away
'     $F0-$FC  EDITWORLD the caller's RAM while editing
'   System page ($CC00-$CFFF, never swapped out):
'     $CC00  "VT", then the number of entries in use, 5 bytes reserved
'     $CC08  far-call entries $00-$27, 8 bytes each: JSR $FFD0 / bank /
'            address / 2 spare bytes. Entry NN is at $CC08 + 8 * NN: JSR
'            there, or CALL 52232+8*NN in BASIC (V lists them, V NN BB
'            HHHH NAME sets one)
'     $CD48  their names, 8 bytes each (0 = none, else up to 8
'            characters, 0 after shorter ones): VFIND looks them up
'     $CE88  the system calls' variables (8 bytes), then reserved
'     $CF00  BANK MAP: one byte per bank, its owner:
'              $00 FREE   free
'              $FD MAIN   a main-RAM program (started from the desktop)
'              $FE HAND   loaded by hand (L ... BB in the monitor)
'              $FF SYSTEM reserved: zones and banks that are never handed out
'              $01-$FCthe bank of the program that owns it
'            Set at power-on (zones $00-$1F and $C0-$FF reserved); the
'            monitor's B command lists it. Save the table (not the map)
'            with S VECTORS CC00.CEFF.
'   Far-call entries:
'     $00 $CC08 LULLABY  bank $08 $E000  plays the lullaby
'     $01 $CC10 EDITNEW  bank $13 $E000  the editor, with an empty text
'     $02 $CC18 EDIT     bank $13 $E003  the editor, with the text as it was
'                        (BASIC: CALL EDIT)
'     $10 $CC88 TOOLKIT  bank $10 $E000  the toolkit: LDA #function, JSR
'     $11 $CC90 DESKTOP  bank $14 $E000  the desktop (BASIC: CALL DESKTOP)
'     $12 $CC98 RESUME   the desktop: back from a program (G after F1)
'     $13 $CCA0 LAUNCH   the desktop: calls a program, then RESUME (2 entries)
'     $15 $CCB0 TARGET   the desktop: the program being started
'     $16 $CCB8 BANKLD   the desktop: disk LOAD into the launch bank (2
'                        entries)
'     $19 $CCD0 MUSIC    bank $12 $E000  the music engine: LDA #function, LDX
'                        #arg, JSR
'     $1A $CCD8 MUSICB   bank $12 $E003  the music engine from BASIC (mailbox
'                        $CCDE)
'   $F000-$FFFF  ROM, 4K - the mini6502 monitor. It is built into this
'                program (the DATA lines after the main program); a
'                monitor.bin in the current folder replaces it. A file
'                shorter than 4K is placed so that it ends at $FFFF, and the
'                rest of the ROM reads $FF.
'   System calls in the ROM (JSR, from anywhere; banks: see the bank map):
'     $FFB0 BALLOC   A = owner, X = how many banks (next to each other), Y = 0
'                    programs zone, 1 documents zone: A = the first bank; carry
'                    set if there is no room
'     $FFB3 BFREE    A = bank: free again
'     $FFB6 BFREEALL A = owner: every bank it owns is free again
'     $FFB9 BCLAIM   A = owner, X = bank: it is the owner's now; carry set (and
'                    nothing done) if another owner has it
'     $FFBC VFIND    X/Y = address of a name (low, high; up to 8 characters,
'                    ending with 0, CR or a space): A = the entry, X/Y = its
'                    address; carry set if there is none
'     $FFBF BOWNER   A = bank: A = its owner ($00 free)
'
' The keyboard and display registers sit where the Woz Monitor had them, but
' they are plain registers, not a 6821 PIA: no data-direction registers, no
' handshaking.
'
' Loading (F5, command line) and dumping (F4) see memory as the CPU would
' right now: $E000-$EFFF means the bank currently selected.
'
' Terminal: 80 x 25 characters, 8x16 font, 640x400 pixels at 1:1.
'   The window can be resized freely; the picture keeps its aspect ratio.
'   Upper and lower case are shown as sent. Bit 7 of each character is
'   ignored. Control codes understood:
'     $07 BEL     beep             $0A LF  new line (ignored right after CR)
'     $08 BS      cursor left      $0C FF  clear screen, cursor home
'     $09 TAB     next 8th column  $0D CR  new line
'     $7F DEL     ignored
'   Every cell keeps the COLOR it was printed with; clearing the screen and
'   scrolling fill the new blank cells with the current COLOR.
'   Palette (the 16 CGA colors):
'     0 black      4 red          8 dark grey     C light red
'     1 blue       5 magenta      9 light blue    D light magenta
'     2 green      6 brown        A light green   E yellow
'     3 cyan       7 light grey   B light cyan    F white
'
' Keys
'   F1  RESET (memory is kept)       F5  LOAD a hex file into memory
'   F2  CLEAR SCREEN                 F6  CAPS: send letters upper case (on)
'   F3  or Ctrl+V  paste clipboard   F7  scaling: fit window / whole steps
'   F4  DUMP memory to a hex file    F8  window back to 1:1 (640x400)
'   Alt+Enter  full screen (QB64 built-in)
'   Backspace sends $08 (BACKSPACE_CHAR), Esc sends $1B.
'
' Command line (files are relative to the folder you start from)
'   mini6502 prog.hex        loads a hex dump straight into memory
'   mini6502 prog.txt        types the file in as keystrokes
'   mini6502 prog.bin@0300   loads a binary at $0300
'   (any number of each, processed in order)
'
' Hex files use the monitor's format, 8 bytes per line:
'   6000: 4C 0A 60 00 00 00 00 00
'=============================================================================

' Set to 1 for a console-only build that reads keystrokes from the files on
' the command line and prints the final screen (used for testing).
$LET HEADLESS = 0

$IF HEADLESS = 1 THEN
    $CONSOLE:ONLY
$ELSE
    $RESIZE:ON
$END IF
OPTION _EXPLICIT

'$INCLUDE:'fake6502.bi'

CONST CPU_HZ = 1000000 ' 1 MHz; raise freely, the core manages ~15 MHz
CONST FPS = 60
CONST COLS = 80
CONST ROWS = 25
CONST CHAR_W = 8
CONST CHAR_H = 16
CONST IO_START = &HD000& ' I/O space is $D000-$DFFF
CONST BANK_START = &HE000& ' banked window is $E000-$EFFF
CONST BANK_SIZE = &H1000& ' 4K per bank
CONST BANK_END = BANK_START + BANK_SIZE ' first address after the window
CONST NUM_BANKS = 256
CONST ROM_START = &HF000& ' ROM is $F000-$FFFF
CONST ROM_SIZE = &H1000&
CONST BACKSPACE_CHAR = 8 ' sent for the Backspace key (95 "_" suits the Woz Monitor)
CONST DEFAULT_COLOR = &H07 ' COLOR after RESET: light grey on black
CONST NUM_VOICES = 4 ' sound voices at $D030 (voice 4 = noise); voice(NUM_VOICES) is the beep
CONST BEEP_HZ = 880
CONST BEEP_FRAMES = 8 ' 1/8 s at 60 frames per second
CONST ATTACK_S = 0.005 ' fade-in time in seconds
CONST RELEASE_S = 0.03 ' fade-out time in seconds
CONST SND_AHEAD = 0.05 ' seconds of audio kept queued ahead
CONST GFX_W = 160 ' graphics: 160 x 200 pixels, 2 pages
CONST GFX_H = 200
CONST GFX_PAGE = 32000
CONST NUM_SPRITES = 32
CONST HI_W = 640 ' hires: 640 x 400, 1 bit per pixel, in the same pages
CONST HI_H = 400

' Memory: mem() holds the fixed RAM and the ROM; $E000-$EFFF live in banks()
DIM SHARED mem(0 TO 65535) AS _UNSIGNED _BYTE
DIM SHARED banks(0 TO NUM_BANKS * BANK_SIZE - 1) AS _UNSIGNED _BYTE
DIM SHARED bank AS LONG ' bank currently selected
DIM SHARED bankbase AS LONG ' bank * BANK_SIZE - BANK_START, ready to add to an address

' I/O registers
DIM SHARED kbd_char AS LONG, kbd_ready AS LONG
DIM SHARED kbd_ext AS LONG ' code of the extended key being read (KBDEXT), else 0
DIM SHARED kbd_queue AS STRING

' Sound
TYPE SoundVoice
    note AS LONG ' registers, as written by the 6502
    vol AS LONG
    wave AS LONG
    dur AS LONG
    gate AS LONG ' -1 while the note is held
    remain AS LONG ' frames until the note releases; 0 = held forever
    phase AS DOUBLE ' 0 to 1, position in the current wave cycle
    inc AS DOUBLE ' phase step per sample (frequency / sample rate)
    level AS DOUBLE ' current loudness 0 to 1, fades toward the target
    noise AS DOUBLE ' current noise value, changed once per cycle
    decay AS LONG ' shaping registers ($D050 + 4 * voice)
    sweep AS LONG
    pulse AS LONG
    bend AS LONG
    env AS LONG ' volume now (0-15): VOL, lowered by DECAY
    dcount AS LONG ' frames until the next DECAY step
    semis AS DOUBLE ' SWEEP so far, in semitones
    hz AS DOUBLE ' frequency of the note as written
    lfsr AS LONG ' noise shift register (voice 4)
END TYPE
DIM SHARED voice(0 TO NUM_VOICES) AS SoundVoice
DIM SHARED srate AS LONG: srate = 44100 ' replaced by _SNDRATE in the windowed build
DIM SHARED atkstep AS DOUBLE, relstep AS DOUBLE
' Interrupts ($D007-$D00B)
CONST IRQ_FRAME = 1
CONST IRQ_KEY = 2
CONST IRQ_MOUSE = 4
DIM SHARED irqen AS LONG, irqflags AS LONG, irqbank AS LONG, irqvec AS LONG
DIM SHARED keysel AS LONG ' KEYSEL ($D01A): the key KEYHELD reports on
DIM SHARED keypos AS LONG ' KEYPOS ($D01C): the key position POSHELD reports on
DIM SHARED posheld(0 TO 127) AS LONG ' physical keys held, by PC scancode

' Disk
DIM SHARED dskreg(0 TO 8) AS LONG ' $D040-$D048
DIM SHARED coldflag AS LONG: coldflag = 1 ' SYSCTL read: 1 after power-on / cold reset
DIM SHARED warmvec AS LONG ' $D002/$D003: where the monitor's G goes back to

' Extended memory access ($D200 page): 2 data ports and a DMA engine.
' Extended addresses are 24-bit: $000000-$0FFFFF = the 1 MB of banks
' (bank * 4096 + offset), $FF0000-$FFFFFF = the CPU address space as the CPU
' sees it now ($FFxxxx, with the current bank at $E000; I/O and ROM are not
' written, I/O reads 0). Anything else is not memory.
DIM SHARED portadr(0 TO 1) AS LONG ' current address of port A / B
DIM SHARED portstep(0 TO 1) AS LONG: portstep(0) = 1: portstep(1) = 1
DIM SHARED dmareg(0 TO 11) AS LONG ' $D210-$D21B

' Graphics
DIM SHARED vram(0 TO 2 * GFX_PAGE - 1) AS _UNSIGNED _BYTE ' 2 pages ($FE0000)
DIM SHARED sprimg(0 TO 65535) AS _UNSIGNED _BYTE ' sprite images ($FD0000)
DIM SHARED vreg(0 TO 15) AS LONG ' $D300-$D30F (palette R G B: palr/g/b)
DIM SHARED palr(0 TO 31) AS LONG, palg(0 TO 31) AS LONG, palb(0 TO 31) AS LONG
DIM SHARED blt(0 TO 15) AS LONG ' $D310-$D31F
DIM SHARED hreg(0 TO 23) AS LONG ' $D328-$D33F: ROP, PATON, CHR, STYLE, PATTERN, CLIP
DIM SHARED hcx0 AS LONG, hcy0 AS LONG, hcx1 AS LONG, hcy1 AS LONG ' clip, in use
DIM SHARED fontbits(0 TO 4095) AS _UNSIGNED _BYTE ' the 8x16 font, for CHAR
DIM SHARED drow0 AS LONG, drow1 AS LONG ' hires rows to draw again (none if drow0 > drow1)
DIM SHARED preg(0 TO &H4F) AS LONG ' $D500-$D54F: mouse and pointer
DIM SHARED mousex AS LONG, mousey AS LONG, mbtn AS LONG, mwheel AS LONG, mclick AS LONG
DIM SHARED coll(0 TO 7) AS LONG ' $D320-$D327
DIM SHARED spr(0 TO NUM_SPRITES * 8 - 1) AS LONG ' $D400-$D4FF
DIM SHARED gfxidx(0 TO GFX_PAGE - 1) AS _UNSIGNED _BYTE ' this frame: colour numbers 0-63
DIM SHARED owner(0 TO GFX_PAGE - 1) AS _UNSIGNED _BYTE ' sprite + 1 on each pixel (collisions)
DIM SHARED lut(0 TO 63) AS _UNSIGNED LONG ' windowed build: RGB of colour numbers

' Terminal
DIM SHARED scr(0 TO COLS - 1, 0 TO ROWS - 1) AS _UNSIGNED _BYTE
DIM SHARED attr(0 TO COLS - 1, 0 TO ROWS - 1) AS _UNSIGNED _BYTE ' COLOR of each cell
DIM SHARED curx AS LONG, cury AS LONG, lastout AS LONG
DIM SHARED curcolor AS LONG: curcolor = DEFAULT_COLOR ' the COLOR register
DIM SHARED pal(0 TO 15) AS _UNSIGNED LONG ' windowed build only

' Settings and platform state
DIM SHARED caps AS LONG: caps = -1
DIM SHARED curdir AS STRING ' the disk's current folder ("", "A" or "A/B")
DIM SHARED rp_dir AS STRING, rp_name AS STRING, rp_depth AS LONG ' ResolvePath's results
DIM SHARED intscale AS LONG
DIM SHARED frame AS LONG, quit AS LONG
DIM SHARED idle_frames AS LONG ' headless build only
DIM SHARED textimg AS LONG ' windowed build only
DIM SHARED gfximg AS LONG, frameimg AS LONG ' windowed build: 160x200, 640x400
DIM SHARED hiresimg AS LONG ' windowed build: the hires page as drawn last

'-----------------------------------------------------------------------------
' Main program
'-----------------------------------------------------------------------------

InitPlatform
ClearScreen
LoadRom
ProcessCommandLine

MachineReset
DO
    IrqRaise IRQ_FRAME
    exec6502 CPU_HZ \ FPS
    VideoFrame
    PlatformFrame
    frame = frame + 1
LOOP UNTIL quit
SYSTEM

'-----------------------------------------------------------------------------
' Built-in monitor ROM, made from monitor.bin by monitor/rom2data.py.
' Each line is "ADDR:" followed by bytes in hex; lines of all $FF are left out.
'-----------------------------------------------------------------------------
MonitorRom:
' --- BEGIN MONITOR ROM ---
DATA "F000:D8A2FF9AA90D8D8002A95EA2F92092F8AD00D0F060205BF5AD11D03058A9FD8D"
DATA "F020:46D0A9FC8D47D0A9008D48D08D44D08D45D0A9018D40D0AD41D0F016C901D00F"
DATA "F040:A9028D46D0A9FD8D47D0A9068D40D04C75F0AD42D085E8AD43D085E9A90BA2FD"
DATA "F060:2092F8A5E9206BF8A5E8206BF8A90D207EF84C6AF1D8A2FF9A2085F8A93E207E"
DATA "F080:F8A00020ABF8C90DF045C91BF039C908F028C97FF024C92090E9C9619006C97B"
DATA "F0A0:B00229DFC07EB00A990002C8207EF84C83F0A907207EF84C83F0C000F0C588A9"
DATA "F0C0:08207EF84C83F0A95C207EF84C75F0990002207EF8A0008C8102B90002C90DF0"
DATA "F0E0:94C92EF06DC93AF06DC952F07DC93FF06EC953D0034C31F2C94CD0034C80F2C9"
DATA "F100:24D0034C3CF3C954D0034CE0F2C94BD0034CF4F2C957D00EA9028D00D0A90D8D"
DATA "F120:8002C84CDAF0C947D0034C4CF3C956D0034CB1F3C958D0034C6AF3C94DD0034C"
DATA "F140:70F5C950D0034C12F320EEF1B025C84CDAF0A901D002A9028D8102C84CDAF0C8"
DATA "F160:A982A2F92092F84CDAF02070F14C75F06CE800AD8102C902D00EAD8202C90390"
DATA "F180:37A9008D8102F004C901F03BA5EC85E885EAA5ED85E985EB204DF8A5E929F0C9"
DATA "F1A0:D0D00F98482020F8B90002AA68A8E03AF003205FF84CDAF0A5ECA20081EAE6EA"
DATA "F1C0:D002E6EB4CDAF0A5E8C5ECA5E9E5EDB015E6E8D002E6E9A5E82907D003204DF8"
DATA "F1E0:205FF84CC7F1A9008D81024CDAF0A90085EC85ED8D8202B90002C930902DC93A"
DATA "F200:900DC9419025C947B021E9364C11F2290F8D8302A20406EC26EDCAD0F9A5EC0D"
DATA "F220:830285ECEE8202C84CF7F1AD8202C90160C8202BF890462020F820EEF1903EA5"
DATA "F240:EC8D42D0A5ED8D43D0B90002C92ED02DC820EEF1902718A5EC69018D44D0A5ED"
DATA "F260:69008D45D0207CF3A9022094F320C1F72085F8A91CA2FD2092F84CF7F74CEAF7"
DATA "F280:C8202BF890572020F8A9008D44D08D45D020EEF19011A5EC8D42D0A5ED8D43D0"
DATA "F2A0:207CF3A903D007A9008D8902A9012094F320C1F7AD8902F00DAE8802BD00CFD0"
DATA "F2C0:05A9FE9D00CFAD42D085E8AD43D085E92085F8A92BA2FD2092F84CF7F74CEAF7"
DATA "F2E0:C8202BF8900BA9068D40D020C1F74C75F04CEAF7C8202BF89015A9058D40D020"
DATA "F300:C1F72085F8A923A2FD2092F84C75F04CEAF7C8202BF89008A9098D40D020C1F7"
DATA "F320:A9008D42D0A9018D43D0A90D8D40D02085F8A900A2012092F84C75F0A9048D40"
DATA "F340:D0A90D8D800220C1F74C75F0AD02D085E8AD03D085E905E8D00D2085F8A9E2A2"
DATA "F360:FC2092F84C75F04C6AF12085F8A9F0A2FB2092F8A9018D00D04C79F3A9008D89"
DATA "F380:022020F820EEF1900AA5EC8D8802A9018D89026048AD20D08D8A02AD8902F006"
DATA "F3A0:AD88028D20D0688D40D0AD8A028D20D060C82020F820EEF1B0034C72F4A5ECC9"
DATA "F3C0:2890034C65F48D8B022020F820EEF1B0034C65F4A5EC482020F820EEF1B0034C"
DATA "F3E0:64F4A5EC8D8C02A5ED8D8D028C83022046F5AD8B022019F5A000A92091ECC8A9"
DATA "F400:D091ECC8A9FF91ECC86891ECC8AD8C0291ECC8AD8D0291ECC8A90091ECC891EC"
DATA "F420:AD8B022008F5AE8302BD0002C920D003E8D0F6A000BD0002C921900A91ECE8C8"
DATA "F440:C008D0F1F009A90091ECC8C008D0F9AE8B02E8EC02CC90038E02CCAD8B022098"
DATA "F460:F44C75F0682085F8A9F5A2FB2092F84C75F02039F5D014A200EC02CCB00A8A48"
DATA "F480:2098F468AAE8D0F14C75F02085F8A99FA2FC2092F84C75F08D8B0220BCF4AD8B"
DATA "F4A0:022008F5A000B1ECF011A920207EF8B1ECF008207EF8C8C008D0F460482085F8"
DATA "F4C0:6848206BF8A920207EF8682019F5A5ED206BF8A5EC206BF8A9D0A2FC2092F8A0"
DATA "F4E0:00B1ECC920D019A003B1EC206BF8A920207EF8A005B1EC206BF888B1EC4C6BF8"
DATA "F500:A9D8A2FC2092F8602019F518A5EC694085ECA5ED690185ED6085ECA90085ED06"
DATA "F520:EC26ED06EC26ED06EC26ED18A5EC690885ECA5ED69CC85ED60AD00CCC956D005"
DATA "F540:AD01CCC954602039F5F00FA9568D00CCA9548D01CCA9008D02CC60A200A9FFE0"
DATA "F560:209006E0C0B002A9009D00CFE8D0EE60C82020F820EEF19022A5EC482020F820"
DATA "F580:EEF1689009AAA5EC9D00CF4C9BF52085F8A939A2FC2092F84C75F0A2008E8C02"
DATA "F5A0:BD00CF8D8B02E0FFF00BBD01CFCD8B02D003E8D0F18E8D022085F8AD8C02206B"
DATA "F5C0:F8AD8D02CD8C02F00EA92D207EF8AD8D02206BF84CDEF5A96DA2FC2092F8A971"
DATA "F5E0:A2FC2092F8AD8B02D00AA974A2FC2092F84C2BF6C9FFD00AA979A2FC2092F84C"
DATA "F600:2BF6C9FED00AA980A2FC2092F84C2BF6C9FDD00AA988A2FC2092F84C2BF6A999"
DATA "F620:A2FC2092F8AD8B02206BF8AE8D02E0FFF004E84C9DF54C75F08D88CE8E89CEC9"
DATA "F640:00F040E000F03CA220A980C000F004A280A9C08D8ACE8E8BCEAC89CEEC8ACEB0"
DATA "F660:22BD00CFD019E888D0F2AE8BCEAC89CEAD88CE9D00CFE888D0F9AD8BCE1860E8"
DATA "F680:4C56F63860AABD00CFC9FFF007A9009D00CF18603860C900F019C9FFF0158D88"
DATA "F6A0:CEA200BD00CFCD88CED005A9009D00CFE8D0F018608D88CEBD00CFF007CD88CE"
DATA "F6C0:F0023860AD88CE9D00CF1860AABD00CF1860A5E648A5E74886E684E7A000B1E6"
DATA "F6E0:C921B0034C79F7A9008D8CCEAD8CCE0A0A0AAAA9008D8ACEA8AD8ACED015B1E6"
DATA "F700:C9619006C97BB00229DFC921B007A9018D8ACEA9008D89CEAD8CCEC920B006BD"
DATA "F720:48CD4C28F7BD48CECD89CED03FE8C8C008D0C6AD8CCE8D8BCEA9008D89CEAD8C"
DATA "F740:CE0A2E89CE0A2E89CE0A2E89CE1869088D88CEAD89CE69CC8D89CE6885E76885"
DATA "F760:E6AE88CEAC89CEAD8BCE1860EE8CCEAD8CCEC928B0034CECF66885E76885E638"
DATA "F780:6085E486EE84E56885E26885E3AD20D048A9F748A9B748A003B1E2AA88B1E238"
DATA "F7A0:E901B001CAA88A489848A001B1E28D20D0A5E4A6EEA4E56085E4688D20D0A5E4"
DATA "F7C0:60AD41D0D00160482085F8A97FA2FD2092F86838E901C907B00DAABDF8FD48BD"
DATA "F7E0:FFFDAA682092F84C75F02085F8A933A2FD2092F84C75F0AD43D0206BF8AD42D0"
DATA "F800:206BF8A97DA2FD2092F838AD44D0E901AAAD45D0E900206BF88A206BF84C75F0"
DATA "F820:B90002C920D003C8D0F6602020F88C46D0A9028D47D0A200B90002C920F008C9"
DATA "F840:0DF004C8E8D0F18E48D0E001602085F8A5E9206BF8A5E8206BF8A93A4C7EF8A9"
DATA "F860:20207EF8A200A1E84C6BF8484A4A4A4A2074F868290F0930C93A900269068D12"
DATA "F880:D08D800260AD8002C90DF005A90D4C7EF86085E686E79848A000B1E6F00A207E"
DATA "F8A0:F8C8D0F6E6E7D0F268A860AD11D010FBAD10D0297F60488A48BABD03012910D0"
DATA "F8C0:209848AD20D048D8AD09D08D20D0AD08D020DEF8688D20D068A868AA68406C0A"
DATA "F8E0:D068AA688D84028E85028C8602688D87026838E90285E868E90085E92085F8A9"
DATA "F900:D3A2FB2092F8A5E9206BF8A5E8206BF8A9DBA2FB2092F8AD8402206BF8A9E0A2"
DATA "F920:FB2092F8AD8502206BF8A9E4A2FB2092F8AD8602206BF8A9E8A2FB2092F8AD87"
DATA "F940:02206BF8A9ECA2FB2092F8BA8A206BF8AD87022904D001584C75F04C75F00D6D"
DATA "F960:696E6936353032206D6F6E69746F7220312E30202D203F20666F722068656C70"
DATA "F980:0D000D4848484820202020202020202073686F77206120627974650D48484848"
DATA "F9A0:2E484848482020202073686F7720612072616E6765202020282E484848482063"
DATA "F9C0:6F6E74696E756573290D484848483A204242202E2E202073746F726520627974"
DATA "F9E0:657320202020283A20424220636F6E74696E756573290D484848482052202020"
DATA "FA00:2020202072756E2C205254532072657475726E7320686572650D53204E414D45"
DATA "FA20:20484848482E48484848205B42425D20207361766520204C204E414D45205B48"
DATA "FA40:484848205B42425D5D20206C6F6164202842423A2062616E6B290D2420202020"
DATA "FA60:20202020202020206C6973742074686520666F6C6465722020204B204E414D45"
DATA "FA80:202064656C65746520612066696C650D50205B4E414D455D2020202020746865"
DATA "FAA0:206469736B277320666F6C64657220284E414D452C202E2E2075702C202F2074"
DATA "FAC0:6F70290D54204E414D452020202020202074797065206120746578742066696C"
DATA "FAE0:652061732061207363726970740D57202020202020202020202020636C656172"
DATA "FB00:207468652073637265656E202058202065786974206D696E69363530320D4720"
DATA "FB20:2020202020202020202020676F206261636B20746F207468652070726F677261"
DATA "FB40:6D202842415349432E2E2E290D56205B4E4E2042422048484848205B4E414D45"
DATA "FB60:5D5D20206661722D63616C6C207461626C652061742043433030202846415243"
DATA "FB80:414C4C2069732046464430290D4D205B4242204F4F5D20202020746865206261"
DATA "FBA0:6E6B206D617020287365742062616E6B2042422773206F776E6572290D457363"
DATA "FBC0:2063616E63656C7320746865206C696E650D0042524B20617420002020413D00"
DATA "FBE0:20583D0020593D0020503D0020533D004279650D003F2075736167653A205620"
DATA "FC00:20206F7220202056204E4E2042422048484848205B4E414D455D202028656E74"
DATA "FC20:72792030302D32372C2062616E6B2C206164647265737329003F207573616765"
DATA "FC40:3A204D2020206F722020204D204242204F4F20202862616E6B2C206F776E6572"
DATA "FC60:3B203030203D2066726565290020202000202000667265650073797374656D00"
DATA "FC80:62792068616E64006D61696E2D52414D2070726F6772616D0062616E6B20006E"
DATA "FCA0:6F20766563746F72207461626C652061742043433030202856204E4E20424220"
DATA "FCC0:48484848206D616B6573206F6E6529003A2062616E6B20002D2D20756E757365"
DATA "FCE0:64003F206E6F2070726F6772616D20746F20676F206261636B20746F00424F4F"
DATA "FD00:5400424F4F542E54585400426F6F74696E6720424F4F54206174200053617665"
DATA "FD20:64200044656C65746564004C6F6164656420003F2075736167653A2053204E41"
DATA "FD40:4D4520484848482E48484848205B42425D2020204C204E414D45205B48484848"
DATA "FD60:205B42425D5D2020204B204E414D4520202054204E414D4520202024002E003F"
DATA "FD80:206469736B3A200066696C65206E6F7420666F756E64006261642066696C6520"
DATA "FDA0:6E616D6500646F6573206E6F74206669740066696C65206572726F7200756E6B"
DATA "FDC0:6E6F776E20636F6D6D616E64006261642072616E676500746F6F206465657020"
DATA "FDE0:2874776F206C6576656C73206F6620666F6C6465727329008897A5B2BDCDD7FD"
DATA "FE00:FDFDFDFDFDFDFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
DATA "FF00:4C00F0FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF4C"
DATA "FF20:75F0FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
DATA "FFA0:FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF4C39F64C85F64C96F64CB5F64CD2F64C"
DATA "FFC0:CCF6FFFFFFFFFFFFFFFFFFFFFFFFFFFF4C81F7FFFFFFFFFFFFFFFFFF4C6BF8FF"
DATA "FFE0:FFFFFFFFFF4C74F8FFFFFFFFFFFFFF4C7EF8FFFFFFFFFFFFFFFF5BF900F0B6F8"
' --- END MONITOR ROM ---
DATA "END"

'-----------------------------------------------------------------------------
' Loading and saving
'-----------------------------------------------------------------------------

' monitor.bin (up to 4K, placed to end at $FFFF) if present, else the
' built-in ROM from the DATA lines
SUB LoadRom
    DIM buf AS STRING, ln AS STRING, i AS LONG, addr AS LONG
    FOR i = ROM_START TO 65535
        mem(i) = 255
    NEXT
    IF _FILEEXISTS("monitor.bin") THEN
        buf = ReadFile$("monitor.bin")
        IF LEN(buf) > 0 AND LEN(buf) <= ROM_SIZE THEN
            FOR i = 1 TO LEN(buf)
                mem(65536 - LEN(buf) + i - 1) = ASC(buf, i)
            NEXT
            EXIT SUB
        END IF
    END IF
    RESTORE MonitorRom
    DO
        READ ln
        IF ln = "END" THEN EXIT DO
        addr = VAL("&H" + LEFT$(ln, 4) + "&")
        FOR i = 6 TO LEN(ln) STEP 2
            mem(addr) = VAL("&H" + MID$(ln, i, 2))
            addr = addr + 1
        NEXT
    LOOP
END SUB

' Reads "ADDR: BB BB ..." lines into memory (ROM protection bypassed).
' Lines that are not hex data (prompts, commands) are skipped.
' Returns the number of bytes loaded.
FUNCTION LoadHexDump& (filename AS STRING)
    DIM ln AS STRING, p AS LONG, addr AS LONG, n AS LONG, tok AS STRING
    OPEN filename FOR INPUT AS #1
    DO UNTIL EOF(1)
        LINE INPUT #1, ln
        p = INSTR(ln, ":")
        IF p > 0 THEN
            tok = UCASE$(_TRIM$(LEFT$(ln, p - 1)))
            IF IsHex(tok) = 0 THEN _CONTINUE
            addr = VAL("&H" + tok + "&")
            ln = _TRIM$(MID$(ln, p + 1)) + " "
            DO WHILE LEN(ln) > 1
                p = INSTR(ln, " ")
                tok = UCASE$(LEFT$(ln, p - 1))
                ln = LTRIM$(MID$(ln, p + 1))
                IF LEN(tok) > 0 AND LEN(tok) <= 2 AND IsHex(tok) THEN
                    PokeMem addr AND &HFFFF&, VAL("&H" + tok)
                    addr = addr + 1
                    n = n + 1
                END IF
            LOOP
        END IF
    LOOP
    CLOSE #1
    LoadHexDump& = n
END FUNCTION

' Writes start..finish as a monitor style hex dump, 8 bytes per line,
' lines aligned to 8-byte boundaries. Reads memory directly (no I/O effects).
SUB SaveHexDump (start AS LONG, finish AS LONG, filename AS STRING)
    DIM addr AS LONG, ln AS STRING
    OPEN filename FOR OUTPUT AS #1
    FOR addr = start TO finish
        IF addr = start OR (addr AND 7) = 0 THEN
            IF LEN(ln) THEN PRINT #1, ln
            ln = Hex4$(addr) + ":"
        END IF
        ln = ln + " " + RIGHT$("0" + HEX$(PeekMem(addr)), 2)
    NEXT
    IF LEN(ln) THEN PRINT #1, ln
    CLOSE #1
END SUB

FUNCTION Hex4$ (v AS LONG)
    Hex4$ = RIGHT$("000" + HEX$(v), 4)
END FUNCTION

FUNCTION IsHex& (t AS STRING)
    DIM i AS LONG
    IF LEN(t) < 1 OR LEN(t) > 4 THEN EXIT FUNCTION
    FOR i = 1 TO LEN(t)
        IF INSTR("0123456789ABCDEF", MID$(t, i, 1)) = 0 THEN EXIT FUNCTION
    NEXT
    IsHex& = -1
END FUNCTION

' Parses "6000.7FFF" (or a single address) into start and finish.
FUNCTION ParseRange& (t AS STRING, start AS LONG, finish AS LONG)
    DIM p AS LONG, a AS STRING, b AS STRING
    t = UCASE$(_TRIM$(t))
    p = INSTR(t, ".")
    IF p THEN a = LEFT$(t, p - 1): b = MID$(t, p + 1) ELSE a = t: b = t
    IF IsHex(a) = 0 OR IsHex(b) = 0 THEN EXIT FUNCTION
    start = VAL("&H" + a + "&")
    finish = VAL("&H" + b + "&")
    IF start > finish THEN EXIT FUNCTION
    ParseRange& = -1
END FUNCTION

SUB ProcessCommandLine
    DIM i AS LONG, arg AS STRING, p AS LONG, addr AS LONG, buf AS STRING, j AS LONG
    FOR i = 1 TO _COMMANDCOUNT
        arg = COMMAND$(i)
        p = _INSTRREV(arg, "@")
        IF p > 0 THEN
            addr = VAL("&H" + MID$(arg, p + 1) + "&")
            arg = FullPath(LEFT$(arg, p - 1))
            IF _FILEEXISTS(arg) THEN
                buf = ReadFile$(arg)
                FOR j = 1 TO LEN(buf)
                    PokeMem (addr + j - 1) AND &HFFFF&, ASC(buf, j)
                NEXT
            END IF
        ELSEIF LCASE$(RIGHT$(arg, 4)) = ".hex" THEN
            arg = FullPath(arg)
            IF _FILEEXISTS(arg) THEN j = LoadHexDump(arg)
        ELSE
            arg = FullPath(arg)
            IF _FILEEXISTS(arg) THEN TypeText ReadFile$(arg)
        END IF
    NEXT
END SUB

FUNCTION ReadFile$ (f AS STRING)
    DIM buf AS STRING
    OPEN f FOR BINARY AS #1
    buf = SPACE$(LOF(1))
    GET #1, 1, buf
    CLOSE #1
    ReadFile$ = buf
END FUNCTION

FUNCTION FullPath$ (f AS STRING)
    IF LEFT$(f, 1) = "/" OR LEFT$(f, 1) = "\" OR MID$(f, 2, 1) = ":" THEN
        FullPath$ = f
    ELSE
        FullPath$ = _STARTDIR$ + "/" + f
    END IF
END FUNCTION

'-----------------------------------------------------------------------------
' Keyboard queue
'-----------------------------------------------------------------------------

' Makes the next queued key the waiting one (KBDCR / KBDPEEK). An extended
' key is queued as CHR$(0) + its code.
SUB KbdFetch
    IF kbd_ready = 0 AND LEN(kbd_queue) > 0 THEN
        kbd_char = ASC(kbd_queue, 1)
        kbd_ext = 0
        IF kbd_char = 0 AND LEN(kbd_queue) >= 2 THEN
            kbd_ext = ASC(kbd_queue, 2)
            kbd_queue = MID$(kbd_queue, 3)
        ELSE
            kbd_queue = MID$(kbd_queue, 2)
        END IF
        kbd_ready = -1
    END IF
END SUB

' Queues an extended key (arrows etc.), code 1-10 as listed under KBDEXT
SUB QueueExt (code AS LONG)
    kbd_queue = kbd_queue + CHR$(0) + CHR$(code)
    IrqRaise IRQ_KEY
END SUB

SUB QueueKey (c AS LONG)
    IF caps AND c >= 97 AND c <= 122 THEN c = c - 32
    kbd_queue = kbd_queue + CHR$(c)
    IrqRaise IRQ_KEY
END SUB

' Queue text as keystrokes; LF, CR and CRLF line ends all become one CR
SUB TypeText (t AS STRING)
    DIM i AS LONG, c AS LONG, prev AS LONG
    FOR i = 1 TO LEN(t)
        c = ASC(t, i)
        SELECT CASE c
            CASE 13: QueueKey 13
            CASE 10: IF prev <> 13 THEN QueueKey 13
            CASE 9: QueueKey 32
            CASE 32 TO 126: QueueKey c
        END SELECT
        prev = c
    NEXT
END SUB

'-----------------------------------------------------------------------------
' The bus
'-----------------------------------------------------------------------------

FUNCTION read6502~%% (address AS _UNSIGNED INTEGER)
    IF address < IO_START THEN
        read6502~%% = mem(address)
    ELSEIF address < BANK_START THEN
        read6502~%% = IORead(address AND &HFFF)
    ELSEIF address < BANK_END THEN
        read6502~%% = banks(bankbase + address)
    ELSE
        read6502~%% = mem(address)
    END IF
END FUNCTION

SUB write6502 (address AS _UNSIGNED INTEGER, value AS _UNSIGNED _BYTE)
    IF address < IO_START THEN
        mem(address) = value
    ELSEIF address < BANK_START THEN
        IOWrite address AND &HFFF, value
    ELSEIF address < BANK_END THEN
        banks(bankbase + address) = value
    ELSEIF address < ROM_START THEN
        mem(address) = value
    END IF ' writes to the ROM are ignored
END SUB

' Memory as seen from outside the CPU (loader, dumper): the current bank at
' $E000-$EFFF, no I/O side effects, and PokeMem can write the ROM.
FUNCTION PeekMem& (address AS LONG)
    IF address >= BANK_START AND address < BANK_END THEN
        PeekMem& = banks(bankbase + address)
    ELSE
        PeekMem& = mem(address)
    END IF
END FUNCTION

SUB PokeMem (address AS LONG, value AS LONG)
    IF address >= BANK_START AND address < BANK_END THEN
        banks(bankbase + address) = value
    ELSE
        mem(address) = value
    END IF
END SUB

SUB SelectBank (b AS LONG)
    bank = b AND (NUM_BANKS - 1)
    bankbase = bank * BANK_SIZE - BANK_START
END SUB

' RESET line: bank 0 and the default COLOR are selected again, then the CPU
' restarts. RAM and the screen are kept.
SUB MachineReset
    SelectBank 0
    curcolor = DEFAULT_COLOR
    SoundReset
    VideoReset
    IrqReset
    reset6502
END SUB

'-----------------------------------------------------------------------------
' Interrupts: sources latch their bit in irqflags while enabled in irqen; the
' CPU core takes the IRQ while f65_irqline is set (and its I flag is clear)
'-----------------------------------------------------------------------------

SUB IrqReset
    irqen = 0: irqflags = 0: irqbank = 0: irqvec = 0
    IrqLine
END SUB

SUB IrqRaise (bit AS LONG)
    IF irqen AND bit THEN irqflags = irqflags OR bit: IrqLine
END SUB

SUB IrqLine
    f65_irqline = (irqflags AND irqen) <> 0
END SUB

'-----------------------------------------------------------------------------
' Extended memory: ports and DMA
'-----------------------------------------------------------------------------

' Byte at extended address a (no I/O side effects)
FUNCTION ExtRead& (a AS LONG)
    SELECT CASE a \ 65536
        CASE &HFF: ExtRead& = PeekMem(a AND &HFFFF&)
        CASE &HFE: IF (a AND &HFFFF&) < 2 * GFX_PAGE THEN ExtRead& = vram(a AND &HFFFF&)
        CASE &HFD: ExtRead& = sprimg(a AND &HFFFF&)
        CASE 0 TO NUM_BANKS * BANK_SIZE \ 65536 - 1: ExtRead& = banks(a)
    END SELECT
END FUNCTION

SUB ExtWrite (a AS LONG, v AS LONG)
    SELECT CASE a \ 65536
        CASE &HFF: DiskPoke a AND &HFFFF&, v ' RAM only: I/O and ROM are left alone
        CASE &HFE
            IF (a AND &HFFFF&) < 2 * GFX_PAGE THEN
                vram(a AND &HFFFF&) = v AND &HFF
                HDirty ((a AND &HFFFF&) MOD GFX_PAGE) \ 80, ((a AND &HFFFF&) MOD GFX_PAGE) \ 80
            END IF
        CASE &HFD: sprimg(a AND &HFFFF&) = v AND &HFF
        CASE 0 TO NUM_BANKS * BANK_SIZE \ 65536 - 1: banks(a) = v AND &HFF
    END SELECT
END SUB

' a + n, wrapping within a's space (the 1 MB, the CPU space, the VRAM...)
FUNCTION ExtNext& (a AS LONG, n AS LONG)
    SELECT CASE a \ 65536
        CASE &HFF, &HFD: ExtNext& = (a AND &HFF0000) OR ((a + n) AND &HFFFF&)
        CASE &HFE: ExtNext& = &HFE0000 OR (((a AND &HFFFF&) + n) MOD (2 * GFX_PAGE))
        CASE ELSE: ExtNext& = (a + n) AND &HFFFFF
    END SELECT
END FUNCTION

FUNCTION ExtValid& (a AS LONG)
    SELECT CASE a \ 65536
        CASE &HFF, &HFD: ExtValid& = -1
        CASE &HFE: ExtValid& = (a AND &HFFFF&) < 2 * GFX_PAGE
        CASE 0 TO NUM_BANKS * BANK_SIZE \ 65536 - 1: ExtValid& = -1
    END SELECT
END FUNCTION

' r = offset from $D200: port A at 0-4, port B at 8-12
FUNCTION PortRead& (r AS LONG)
    DIM p AS LONG
    p = r \ 8
    SELECT CASE r AND 7
        CASE 0: PortRead& = portadr(p) AND &HFF
        CASE 1: PortRead& = (portadr(p) \ 256) AND &HFF
        CASE 2: PortRead& = (portadr(p) \ 65536) AND &HFF
        CASE 3
            PortRead& = ExtRead(portadr(p))
            portadr(p) = ExtNext(portadr(p), portstep(p))
        CASE 4: PortRead& = portstep(p)
    END SELECT
END FUNCTION

SUB PortWrite (r AS LONG, value AS LONG)
    DIM p AS LONG, v AS LONG
    p = r \ 8
    v = value AND &HFF
    SELECT CASE r AND 7
        CASE 0: portadr(p) = (portadr(p) AND &HFFFF00) OR v
        CASE 1: portadr(p) = (portadr(p) AND &HFF00FF) OR (v * 256)
        CASE 2: portadr(p) = (portadr(p) AND &HFFFF&) OR (v * 65536)
        CASE 3
            ExtWrite portadr(p), v
            portadr(p) = ExtNext(portadr(p), portstep(p))
        CASE 4: portstep(p) = v
    END SELECT
END SUB

FUNCTION DmaAdr& (i AS LONG)
    DmaAdr& = dmareg(i) + dmareg(i + 1) * 256 + dmareg(i + 2) * 65536
END FUNCTION

' The DMA command just written to $D219 (dmareg(9))
SUB DmaRun
    DIM src AS LONG, dst AS LONG, n AS LONG, i AS LONG, buf AS STRING
    src = DmaAdr(0)
    dst = DmaAdr(3)
    n = DmaAdr(6)
    IF n > NUM_BANKS * BANK_SIZE THEN n = NUM_BANKS * BANK_SIZE
    SELECT CASE dmareg(9)
        CASE 1 ' COPY (through a buffer, so overlapping blocks are fine)
            IF ExtValid(src) = 0 OR ExtValid(dst) = 0 THEN dmareg(11) = 2: EXIT SUB
            buf = SPACE$(n)
            FOR i = 1 TO n
                ASC(buf, i) = ExtRead(src)
                src = ExtNext(src, 1)
            NEXT
            FOR i = 1 TO n
                ExtWrite dst, ASC(buf, i)
                dst = ExtNext(dst, 1)
            NEXT
        CASE 2 ' FILL
            IF ExtValid(dst) = 0 THEN dmareg(11) = 2: EXIT SUB
            FOR i = 1 TO n
                ExtWrite dst, dmareg(10)
                dst = ExtNext(dst, 1)
            NEXT
        CASE ELSE
            dmareg(11) = 1: EXIT SUB
    END SELECT
    dmareg(11) = 0
END SUB

'-----------------------------------------------------------------------------
' Graphics: 160x200, 32 colours + DIM, 2 pages, blitter, 32 sprites
'-----------------------------------------------------------------------------

' Power-on / RESET state of the video registers (VRAM and images are kept)
SUB VideoReset
    DIM i AS LONG, v AS STRING, rgb AS STRING
    FOR i = 0 TO 15: vreg(i) = 0: NEXT
    vreg(3) = 8 ' INTENS: DIM pixels at half brightness
    vreg(4) = 16 ' MASTER: full brightness
    vreg(6) = 0 ' INK: black
    vreg(7) = 15 ' PAPER: white
    FOR i = 0 TO 15: blt(i) = 0: NEXT
    FOR i = 0 TO 7: coll(i) = 0: NEXT
    FOR i = 0 TO 255: spr(i) = 0: NEXT
    FOR i = 0 TO 23: hreg(i) = 0: NEXT
    FOR i = 0 TO 7 ' PATTERN: 50% grey
        hreg(8 + i) = &HAA
        IF i AND 1 THEN hreg(8 + i) = &H55
    NEXT
    hreg(20) = (HI_W - 1) AND 255: hreg(21) = (HI_W - 1) \ 256 ' CLIP: whole screen
    hreg(22) = (HI_H - 1) AND 255: hreg(23) = (HI_H - 1) \ 256
    rgb = "000000 0000AA 00AA00 00AAAA AA0000 AA00AA AA5500 AAAAAA "
    rgb = rgb + "555555 5555FF 55FF55 55FFFF FF5555 FF55FF FFFF55 FFFFFF "
    rgb = rgb + "202020 404040 606060 808080 A0A0A0 C0C0C0 E0E0E0 FF8000 "
    rgb = rgb + "FFC090 804000 006000 80C0FF 000060 800040 FFC000 C080FF "
    FOR i = 0 TO 31
        v = MID$(rgb, i * 7 + 1, 6)
        palr(i) = VAL("&H" + MID$(v, 1, 2))
        palg(i) = VAL("&H" + MID$(v, 3, 2))
        palb(i) = VAL("&H" + MID$(v, 5, 2))
    NEXT
    ' mouse pointer: off, an arrow, hot spot at its tip
    FOR i = 0 TO &H4F: preg(i) = 0: NEXT
    v = "C000E000F000F800FC00FE00FF00FF80FFC0FE00EF00CF000780078003000000"
    rgb = "000040006000700078007C007E007F007C006C00460006000300030000000000"
    FOR i = 0 TO 31
        preg(&H30 + i) = VAL("&H" + MID$(v, i * 2 + 1, 2)) ' mask
        preg(&H10 + i) = VAL("&H" + MID$(rgb, i * 2 + 1, 2)) ' image
    NEXT
    HDirty 0, HI_H - 1
END SUB

' reg = offset from $D300: $00-$0F video, $10-$1F blitter, $20-$27
' collisions, $28-$3F hires blitter extras
FUNCTION VideoRead& (reg AS LONG)
    DIM p AS LONG
    SELECT CASE reg
        CASE &H9: VideoRead& = palr(vreg(8))
        CASE &HA: VideoRead& = palg(vreg(8))
        CASE &HB: VideoRead& = palb(vreg(8))
        CASE 0 TO &HF: VideoRead& = vreg(reg)
        CASE &H19 ' PIXEL: the pixel at X0,Y0 on the DRAW page
            p = (vreg(2) AND 1) * GFX_PAGE
            IF vreg(0) >= 3 THEN
                IF BltX0 < HI_W AND BltY0 < HI_H THEN VideoRead& = HGet(p, BltX0, BltY0)
            ELSEIF blt(0) < GFX_W AND blt(1) < GFX_H THEN
                VideoRead& = vram(p + blt(1) * GFX_W + blt(0))
            END IF
        CASE &H10 TO &H1F: VideoRead& = blt(reg - &H10)
        CASE &H20 TO &H27 ' COLLISIONS: reading clears
            VideoRead& = coll(reg - &H20)
            coll(reg - &H20) = 0
        CASE &H28 TO &H3F: VideoRead& = hreg(reg - &H28)
    END SELECT
END FUNCTION

SUB VideoWrite (reg AS LONG, value AS LONG)
    DIM v AS LONG
    v = value AND &HFF
    IF reg < &HC THEN HDirty 0, HI_H - 1 ' the hires picture is drawn again
    SELECT CASE reg
        CASE 0: vreg(0) = v: IF v > 4 THEN vreg(0) = 0 ' MODE
        CASE 1, 2: vreg(reg) = v AND 1 ' SHOW, DRAW
        CASE 3: vreg(3) = v AND 31 ' INTENS
        CASE 4: vreg(4) = v: IF v > 16 THEN vreg(4) = 16 ' MASTER
        CASE 5: vreg(5) = v AND 15 ' TRANSP
        CASE 6, 7, 8: vreg(reg) = v AND 31 ' INK, PAPER, PALIDX
        CASE 9: palr(vreg(8)) = v
        CASE &HA: palg(vreg(8)) = v
        CASE &HB: palb(vreg(8)) = v: vreg(8) = (vreg(8) + 1) AND 31 ' B: next entry
        CASE &H10 TO &H17, &H1A TO &H1F: blt(reg - &H10) = v
        CASE &H18: blt(8) = v: BlitRun ' CMD
        CASE &H28 TO &H3F
            hreg(reg - &H28) = v
            IF reg = &H2C THEN hreg(2) = v: HChar ' CHAROUT
    END SELECT
END SUB

' 16-bit blitter coordinates (hires): low byte + high byte
FUNCTION BltX0&
    BltX0& = blt(0) + 256 * blt(10)
END FUNCTION

FUNCTION BltY0&
    BltY0& = blt(1) + 256 * blt(11)
END FUNCTION

'--- hires: 640 x 400, 1 bit per pixel (80 bytes a row, bit 7 = left) ---

' Hires rows y0..y1 have changed: they are drawn again at the next frame
SUB HDirty (y0 AS LONG, y1 AS LONG)
    IF y0 < drow0 THEN drow0 = y0
    IF y1 > drow1 THEN drow1 = y1
END SUB

' Bit at x,y of the page starting at p (no clipping: the caller checks)
FUNCTION HGet& (p AS LONG, x AS LONG, y AS LONG)
    IF vram(p + y * 80 + x \ 8) AND _SHR(128, x AND 7) THEN HGet& = 1
END FUNCTION

' Draws source bit sb at x,y through the clip rectangle and the ROP
SUB HPlot (p AS LONG, x AS LONG, y AS LONG, sb AS LONG)
    DIM i AS LONG, m AS LONG, d AS LONG, r AS LONG
    IF x < hcx0 OR x > hcx1 OR y < hcy0 OR y > hcy1 THEN EXIT SUB
    i = p + y * 80 + x \ 8
    m = _SHR(128, x AND 7)
    IF vram(i) AND m THEN d = 1
    SELECT CASE hreg(0)
        CASE 1: r = d OR sb ' OR
        CASE 2: r = d AND sb ' AND
        CASE 3: r = d XOR sb ' XOR
        CASE 4: r = 1 - d ' INVERT
        CASE 5: r = d AND (1 - sb) ' CLEAR where the source is 1
        CASE ELSE: r = sb ' SET (copy)
    END SELECT
    IF r THEN vram(i) = vram(i) OR m ELSE vram(i) = vram(i) AND (255 - m)
    IF y < drow0 THEN drow0 = y
    IF y > drow1 THEN drow1 = y
END SUB

' Source bit of the drawing commands at x,y: the PATTERN when it is on,
' else bit 0 of COLOR
FUNCTION HSrc& (x AS LONG, y AS LONG)
    IF hreg(1) AND 1 THEN
        IF hreg(8 + (y AND 7)) AND _SHR(128, x AND 7) THEN HSrc& = 1
    ELSE
        HSrc& = blt(4) AND 1
    END IF
END FUNCTION

' The clip rectangle, limited to the screen, into hcx0..hcy1
SUB HClip
    hcx0 = hreg(16) + 256 * hreg(17): hcy0 = hreg(18) + 256 * hreg(19)
    hcx1 = hreg(20) + 256 * hreg(21): hcy1 = hreg(22) + 256 * hreg(23)
    IF hcx1 > HI_W - 1 THEN hcx1 = HI_W - 1
    IF hcy1 > HI_H - 1 THEN hcy1 = HI_H - 1
END SUB

' The blitter in the hires modes (MODE 3 and 4)
SUB HBlitRun
    DIM x0 AS LONG, y0 AS LONG, x1 AS LONG, y1 AS LONG, p AS LONG, sp AS LONG
    DIM x AS LONG, y AS LONG, dx AS LONG, dy AS LONG, c AS LONG, v AS LONG
    DIM ex AS LONG, ey AS LONG, sx AS LONG, sy AS LONG, er AS LONG, e2 AS LONG
    DIM w AS LONG, h AS LONG, buf AS STRING, i AS LONG
    x0 = blt(0) + 256 * blt(10): y0 = blt(1) + 256 * blt(11)
    x1 = blt(2) + 256 * blt(12): y1 = blt(3) + 256 * blt(13)
    dx = blt(5) + 256 * blt(14): dy = blt(6) + 256 * blt(15)
    c = blt(4): p = (vreg(2) AND 1) * GFX_PAGE: sp = (blt(7) AND 1) * GFX_PAGE
    HClip
    SELECT CASE blt(8)
        CASE 1 ' CLEAR: the whole page, without the clip rectangle
            IF (hreg(1) AND 1) = 0 AND hreg(0) = 0 THEN
                v = 0: IF c AND 1 THEN v = 255
                FOR i = 0 TO GFX_PAGE - 1: vram(p + i) = v: NEXT
                HDirty 0, HI_H - 1
            ELSE
                hcx0 = 0: hcy0 = 0: hcx1 = HI_W - 1: hcy1 = HI_H - 1
                FOR y = 0 TO HI_H - 1
                    FOR x = 0 TO HI_W - 1: HPlot p, x, y, HSrc(x, y): NEXT
                NEXT
            END IF
        CASE 2 ' PSET
            HPlot p, x0, y0, HSrc(x0, y0)
        CASE 3 ' LINE
            ex = ABS(x1 - x0): sx = SGN(x1 - x0)
            ey = -ABS(y1 - y0): sy = SGN(y1 - y0)
            er = ex + ey: x = x0: y = y0
            DO
                HPlot p, x, y, HSrc(x, y)
                IF x = x1 AND y = y1 THEN EXIT DO
                e2 = 2 * er
                IF e2 >= ey THEN er = er + ey: x = x + sx
                IF e2 <= ex THEN er = er + ex: y = y + sy
            LOOP
        CASE 4 ' BOX
            IF x0 > x1 THEN SWAP x0, x1
            IF y0 > y1 THEN SWAP y0, y1
            FOR x = x0 TO x1
                HPlot p, x, y0, HSrc(x, y0)
                IF y1 <> y0 THEN HPlot p, x, y1, HSrc(x, y1)
            NEXT
            FOR y = y0 + 1 TO y1 - 1
                HPlot p, x0, y, HSrc(x0, y)
                IF x1 <> x0 THEN HPlot p, x1, y, HSrc(x1, y)
            NEXT
        CASE 5 ' filled BOX
            IF x0 > x1 THEN SWAP x0, x1
            IF y0 > y1 THEN SWAP y0, y1
            IF x0 < hcx0 THEN x0 = hcx0
            IF y0 < hcy0 THEN y0 = hcy0
            IF x1 > hcx1 THEN x1 = hcx1
            IF y1 > hcy1 THEN y1 = hcy1
            FOR y = y0 TO y1
                FOR x = x0 TO x1: HPlot p, x, y, HSrc(x, y): NEXT
            NEXT
        CASE 6, 7 ' COPY X0,Y0-X1,Y1 of SRC to DX,DY (7: only the 1 bits)
            IF x0 > x1 THEN SWAP x0, x1
            IF y0 > y1 THEN SWAP y0, y1
            IF x0 >= HI_W OR y0 >= HI_H THEN EXIT SUB
            IF x1 >= HI_W THEN x1 = HI_W - 1
            IF y1 >= HI_H THEN y1 = HI_H - 1
            w = x1 - x0 + 1: h = y1 - y0 + 1
            buf = STRING$(w * h, 0) ' through a buffer: overlapping is fine
            FOR y = 0 TO h - 1
                FOR x = 0 TO w - 1
                    IF HGet(sp, x0 + x, y0 + y) THEN ASC(buf, y * w + x + 1) = 1
                NEXT
            NEXT
            FOR y = 0 TO h - 1
                FOR x = 0 TO w - 1
                    v = ASC(buf, y * w + x + 1)
                    IF blt(8) = 6 OR v = 1 THEN HPlot p, dx + x, dy + y, v
                NEXT
            NEXT
        CASE 10 ' STAMP sprite image COLOR: bit 0 of each byte, $80 = skip
            FOR y = 0 TO 15
                FOR x = 0 TO 15
                    v = sprimg(c * 256 + y * 16 + x)
                    IF (v AND 128) = 0 THEN HPlot p, x0 + x, y0 + y, v AND 1
                NEXT
            NEXT
        CASE 11 ' CHAR
            HChar
    END SELECT
END SUB

' Draws character CHR ($D32A) at X0,Y0 in STYLE ($D32B), then moves X0 on
' by 8. Glyph pixels draw source 1, the rest source 0 if STYLE has OPAQUE.
SUB HChar
    DIM x0 AS LONG, y0 AS LONG, r AS LONG, k AS LONG, b AS LONG, st AS LONG
    DIM sh AS LONG, p AS LONG
    IF vreg(0) < 3 THEN EXIT SUB
    x0 = blt(0) + 256 * blt(10): y0 = blt(1) + 256 * blt(11)
    st = hreg(3): p = (vreg(2) AND 1) * GFX_PAGE
    HClip
    FOR r = 0 TO 15
        b = fontbits(hreg(2) * 16 + r)
        IF st AND 1 THEN b = b OR _SHR(b, 1) ' BOLD
        IF (st AND 2) AND r = 14 THEN b = 255 ' UNDERLINE
        IF st AND 8 THEN b = 255 - b ' INVERSE
        sh = 0: IF st AND 4 THEN sh = (15 - r) \ 4 ' ITALIC: the top leans right
        FOR k = 0 TO 7
            IF b AND _SHR(128, k) THEN
                HPlot p, x0 + k + sh, y0 + r, 1
            ELSEIF st AND 16 THEN
                HPlot p, x0 + k + sh, y0 + r, 0 ' OPAQUE
            END IF
        NEXT
    NEXT
    x0 = x0 + 8
    blt(0) = x0 AND 255: blt(10) = (x0 \ 256) AND 255
END SUB

SUB BltPlot (p AS LONG, x AS LONG, y AS LONG, c AS LONG)
    IF x >= 0 AND x < GFX_W AND y >= 0 AND y < GFX_H THEN vram(p + y * GFX_W + x) = c
END SUB

' Puts X0..X1 and Y0..Y1 in order and inside the screen; 0 if nothing is left
FUNCTION BltRect& (x0 AS LONG, y0 AS LONG, x1 AS LONG, y1 AS LONG)
    IF x0 > x1 THEN SWAP x0, x1
    IF y0 > y1 THEN SWAP y0, y1
    IF x0 >= GFX_W OR y0 >= GFX_H THEN EXIT FUNCTION
    IF x1 >= GFX_W THEN x1 = GFX_W - 1
    IF y1 >= GFX_H THEN y1 = GFX_H - 1
    BltRect& = -1
END FUNCTION

' The blitter command just written to $D318 (blt(8)); done at once
SUB BlitRun
    DIM x0 AS LONG, y0 AS LONG, x1 AS LONG, y1 AS LONG, c AS LONG, p AS LONG
    DIM x AS LONG, y AS LONG, i AS LONG, dx AS LONG, dy AS LONG, sp AS LONG
    DIM ex AS LONG, ey AS LONG, sx AS LONG, sy AS LONG, er AS LONG, e2 AS LONG
    DIM w AS LONG, h AS LONG, buf AS STRING, v AS LONG
    x0 = blt(0): y0 = blt(1): x1 = blt(2): y1 = blt(3): c = blt(4)
    dx = blt(5): dy = blt(6): sp = (blt(7) AND 1) * GFX_PAGE
    IF vreg(0) >= 3 THEN HBlitRun: EXIT SUB
    p = (vreg(2) AND 1) * GFX_PAGE
    SELECT CASE blt(8)
        CASE 1 ' CLEAR the DRAW page with COLOR
            FOR i = 0 TO GFX_PAGE - 1: vram(p + i) = c: NEXT
        CASE 2 ' PSET X0,Y0
            BltPlot p, x0, y0, c
        CASE 3 ' LINE X0,Y0 - X1,Y1
            ex = ABS(x1 - x0): sx = SGN(x1 - x0)
            ey = -ABS(y1 - y0): sy = SGN(y1 - y0)
            er = ex + ey: x = x0: y = y0
            DO
                BltPlot p, x, y, c
                IF x = x1 AND y = y1 THEN EXIT DO
                e2 = 2 * er
                IF e2 >= ey THEN er = er + ey: x = x + sx
                IF e2 <= ex THEN er = er + ex: y = y + sy
            LOOP
        CASE 4 ' BOX outline (edges off the screen are not drawn)
            IF x0 > x1 THEN SWAP x0, x1
            IF y0 > y1 THEN SWAP y0, y1
            FOR x = x0 TO x1: BltPlot p, x, y0, c: BltPlot p, x, y1, c: NEXT
            FOR y = y0 TO y1: BltPlot p, x0, y, c: BltPlot p, x1, y, c: NEXT
        CASE 5, 8, 9 ' BOX filled, DIM, UNDIM
            IF BltRect(x0, y0, x1, y1) = 0 THEN EXIT SUB
            FOR y = y0 TO y1
                FOR x = x0 TO x1
                    i = p + y * GFX_W + x
                    SELECT CASE blt(8)
                        CASE 5: vram(i) = c
                        CASE 8: vram(i) = vram(i) OR 32
                        CASE 9: vram(i) = vram(i) AND (255 - 32)
                    END SELECT
                NEXT
            NEXT
        CASE 6, 7 ' COPY X0,Y0-X1,Y1 of the SRC page to DX,DY (7: skip bit 7)
            IF BltRect(x0, y0, x1, y1) = 0 THEN EXIT SUB
            w = x1 - x0 + 1: h = y1 - y0 + 1
            buf = SPACE$(w * h) ' through a buffer: overlapping is fine
            FOR y = 0 TO h - 1
                FOR x = 0 TO w - 1
                    ASC(buf, y * w + x + 1) = vram(sp + (y0 + y) * GFX_W + x0 + x)
                NEXT
            NEXT
            FOR y = 0 TO h - 1
                FOR x = 0 TO w - 1
                    v = ASC(buf, y * w + x + 1)
                    IF blt(8) = 6 OR (v AND 128) = 0 THEN BltPlot p, dx + x, dy + y, v
                NEXT
            NEXT
        CASE 10 ' STAMP sprite image COLOR (16x16) at X0,Y0, skipping bit 7
            FOR y = 0 TO 15
                FOR x = 0 TO 15
                    v = sprimg(c * 256 + y * 16 + x)
                    IF (v AND 128) = 0 THEN BltPlot p, x0 + x, y0 + y, v
                NEXT
            NEXT
    END SELECT
END SUB

' Mouse ($D500 + r): position in hires pixels, buttons, wheel, clicks
FUNCTION MouseRead& (r AS LONG)
    SELECT CASE r
        CASE 0: MouseRead& = mousex AND 255
        CASE 1: MouseRead& = mousex \ 256
        CASE 2: MouseRead& = mousey AND 255
        CASE 3: MouseRead& = mousey \ 256
        CASE 4: MouseRead& = mbtn
        CASE 5: MouseRead& = mwheel AND 255: mwheel = 0 ' steps since the last read
        CASE 6: MouseRead& = mclick: mclick = 0 ' buttons pressed since the last read
        CASE &H50: MouseRead& = mousex \ 4 ' in 160 x 200 pixels
        CASE &H51: MouseRead& = mousey \ 2
        CASE &H52: MouseRead& = mousex \ CHAR_W ' in text cells
        CASE &H53: MouseRead& = mousey \ CHAR_H
        CASE ELSE: MouseRead& = preg(r)
    END SELECT
END FUNCTION

SUB SetColl (k AS LONG, n AS LONG)
    coll(k + n \ 8) = coll(k + n \ 8) OR _SHL(1, n MOD 8)
END SUB

' Once per frame (graphics modes): the SHOW page with the sprites on it, as
' colour numbers (bits 0-4 + DIM) in gfxidx(), and the collisions
SUB VideoFrame
    DIM i AS LONG, n AS LONG, f AS LONG, sx AS LONG, sy AS LONG, img AS LONG
    DIM sz AS LONG, px AS LONG, py AS LONG, x AS LONG, y AS LONG, ix AS LONG, iy AS LONG
    DIM v AS LONG, bg AS LONG, pbase AS LONG
    IF vreg(0) = 0 OR vreg(0) >= 3 THEN EXIT SUB
    pbase = (vreg(1) AND 1) * GFX_PAGE
    FOR i = 0 TO GFX_PAGE - 1
        gfxidx(i) = vram(pbase + i) AND 63
        owner(i) = 0
    NEXT
    FOR n = NUM_SPRITES - 1 TO 0 STEP -1 ' sprite 0 ends up on top
        f = spr(n * 8 + 3)
        IF f AND 1 THEN
            sx = spr(n * 8) - 16: sy = spr(n * 8 + 1) - 16: img = spr(n * 8 + 2) * 256
            sz = 1: IF f AND 8 THEN sz = 2
            FOR py = 0 TO 16 * sz - 1
                y = sy + py
                IF y >= 0 AND y < GFX_H THEN
                    iy = py \ sz: IF f AND 4 THEN iy = 15 - iy
                    FOR px = 0 TO 16 * sz - 1
                        x = sx + px
                        IF x >= 0 AND x < GFX_W THEN
                            ix = px \ sz: IF f AND 2 THEN ix = 15 - ix
                            v = sprimg(img + iy * 16 + ix)
                            IF (v AND 128) = 0 THEN
                                i = y * GFX_W + x
                                ' a SHADOW sprite dims what is under it
                                IF f AND 32 THEN
                                    gfxidx(i) = gfxidx(i) OR 32
                                ELSE
                                    bg = vram(pbase + i) AND 31
                                    IF bg <> 0 THEN SetColl 4, n
                                    IF owner(i) THEN SetColl 0, n: SetColl 0, owner(i) - 1
                                    owner(i) = n + 1
                                    IF (f AND 16) = 0 OR bg = 0 THEN gfxidx(i) = v AND 63
                                END IF
                            END IF
                        END IF
                    NEXT
                END IF
            NEXT
        END IF
    NEXT
END SUB

' RGB of the 64 colour numbers (32 + their DIM version), with MASTER
SUB VideoLut
    DIM k AS LONG, r AS LONG, g AS LONG, b AS LONG, s AS LONG
    FOR k = 0 TO 63
        r = palr(k AND 31): g = palg(k AND 31): b = palb(k AND 31)
        IF k AND 32 THEN
            s = vreg(3)
            r = r * s \ 16: g = g * s \ 16: b = b * s \ 16
            IF r > 255 THEN r = 255
            IF g > 255 THEN g = 255
            IF b > 255 THEN b = 255
        END IF
        s = vreg(4)
        lut(k) = _RGB32(r * s \ 16, g * s \ 16, b * s \ 16)
    NEXT
END SUB

' SYSCTL $FF: clears the fixed RAM (not the banks), then RESET. Called from
' inside the CPU's store instruction: that is its last step, so the new PC
' set by reset6502 is not overwritten.
SUB ColdReset
    DIM i AS LONG
    FOR i = 0 TO IO_START - 1
        mem(i) = 0
    NEXT
    coldflag = 1 ' boots like a power-on
    curdir = "" ' the top of the disk
    warmvec = 0 ' whatever set it was in the RAM just cleared
    MachineReset
END SUB

' reg is the offset into the I/O space, $000-$FFF
FUNCTION IORead& (reg AS LONG)
    SELECT CASE reg
        CASE &H20 ' BANK
            IORead& = bank
        CASE &H21 ' COLOR
            IORead& = curcolor
        CASE &H30 TO &H3F ' SOUND
            IORead& = SoundRead(reg - &H30)
        CASE &H50 TO &H5F ' SOUND SHAPING
            IORead& = SoundShapeRead(reg - &H50)
        CASE &H007: IORead& = irqen ' IRQEN
        CASE &H008 ' IRQFLAGS: cleared by reading
            IORead& = irqflags: irqflags = 0: IrqLine
        CASE &H009: IORead& = irqbank ' IRQBANK
        CASE &H00A: IORead& = irqvec AND 255 ' IRQVEC
        CASE &H00B: IORead& = irqvec \ 256
        CASE &H200 TO &H204, &H208 TO &H20C ' PORT A / B
            IORead& = PortRead(reg - &H200)
        CASE &H210 TO &H21B ' DMA
            IORead& = dmareg(reg - &H210)
        CASE &H300 TO &H33F ' GRAPHICS
            IORead& = VideoRead(reg - &H300)
        CASE &H400 TO &H4FF ' SPRITES
            IORead& = spr(reg - &H400)
        CASE &H500 TO &H553 ' MOUSE and POINTER
            IORead& = MouseRead(reg - &H500)
        CASE &H100 ' BEEP
            IF voice(NUM_VOICES).gate THEN IORead& = 1
        CASE &H40 TO &H48 ' DISK
            IORead& = dskreg(reg - &H40)
        CASE &H000 ' SYSCTL: cold start flag, cleared by reading
            IORead& = coldflag
            coldflag = 0
        CASE &H001 ' FRAME
            IORead& = frame AND &HFF
        CASE &H004 TO &H006 ' CLOCK: hours, minutes, seconds of the PC's time
            IORead& = VAL(MID$(TIME$, (reg - 4) * 3 + 1, 2))
        CASE &H002 ' WARMLO
            IORead& = warmvec AND &HFF
        CASE &H003 ' WARMHI
            IORead& = warmvec \ 256
        CASE &H10 ' KBD
            IORead& = kbd_char OR &H80
            kbd_ready = 0
        CASE &H11 ' KBDCR
            KbdFetch
            IF kbd_ready THEN IORead& = &H80
        CASE &H15 ' CURX
            IORead& = curx
        CASE &H16 ' CURY
            IORead& = cury
        CASE &H17 ' VCHR
            IORead& = scr(curx, cury)
        CASE &H18 ' VCOL
            IORead& = attr(curx, cury)
        CASE &H14 ' KBDPEEK: look at the waiting key without taking it
            KbdFetch
            IF kbd_ready THEN IORead& = kbd_char OR &H80
        CASE &H19 ' KBDEXT: code of an extended key (KBD reads $80 for it)
            IORead& = kbd_ext
        CASE &H1A: IORead& = keysel ' KEYSEL
        CASE &H1B: IORead& = KeyHeld(keysel) ' KEYHELD
        CASE &H1C: IORead& = keypos ' KEYPOS
        CASE &H1D: IF posheld(keypos AND 127) THEN IORead& = 1 ' POSHELD
        CASE &H1E: IF caps THEN IORead& = 1 ' KBDFLAGS: bit 0 CAPS
    END SELECT ' everything else reads 0
END FUNCTION

SUB IOWrite (reg AS LONG, value AS LONG)
    SELECT CASE reg
        CASE &H000 ' SYSCTL
            SELECT CASE value
                CASE 1: quit = -1 ' quit
                CASE 2: ClearScreen ' clear the screen
                CASE 3: VideoReset: SoundReset: IrqReset ' video, sound, interrupts as at power-on
                CASE &HFF: ColdReset ' wipe RAM and reset
            END SELECT
        CASE &H002: warmvec = (warmvec AND &HFF00&) OR (value AND &HFF) ' WARMLO
        CASE &H003: warmvec = (warmvec AND &HFF&) OR ((value AND &HFF) * 256) ' WARMHI
        CASE &H12: TermPut value ' DSP
        CASE &H15: curx = value: IF curx > COLS - 1 THEN curx = COLS - 1 ' CURX
            lastout = 0 ' (an LF right after a move is a new line, not ignored)
        CASE &H16: cury = value: IF cury > ROWS - 1 THEN cury = ROWS - 1 ' CURY
            lastout = 0
        CASE &H17: scr(curx, cury) = value AND &HFF ' VCHR
        CASE &H18: attr(curx, cury) = value AND &HFF ' VCOL
        CASE &H20: SelectBank value ' BANK
        CASE &H21: curcolor = value AND &HFF ' COLOR
        CASE &H1A: keysel = value AND &HFF ' KEYSEL
        CASE &H1C: keypos = value AND &HFF ' KEYPOS
        CASE &H1E: caps = ((value AND 1) <> 0) ' KBDFLAGS: bit 0 CAPS
        CASE &H30 TO &H3F: SoundWrite reg - &H30, value ' SOUND
        CASE &H50 TO &H5F: SoundShapeWrite reg - &H50, value ' SOUND SHAPING
        CASE &H007: irqen = value AND 7: irqflags = irqflags AND irqen: IrqLine ' IRQEN
        CASE &H009: irqbank = value AND 255 ' IRQBANK
        CASE &H00A: irqvec = (irqvec AND &HFF00&) OR (value AND 255) ' IRQVEC
        CASE &H00B: irqvec = (irqvec AND 255) OR ((value AND 255) * 256)
        CASE &H100: StartBeep ' BEEP
        CASE &H200 TO &H204, &H208 TO &H20C: PortWrite reg - &H200, value ' PORT A / B
        CASE &H210 TO &H218, &H21A: dmareg(reg - &H210) = value AND &HFF ' DMA
        CASE &H219: dmareg(9) = value AND &HFF: DmaRun ' DMA command
        CASE &H300 TO &H33F: VideoWrite reg - &H300, value ' GRAPHICS
        CASE &H400 TO &H4FF: spr(reg - &H400) = value AND &HFF ' SPRITES
        CASE &H508 TO &H54F: preg(reg - &H500) = value AND &HFF ' POINTER
        CASE &H40: DiskCommand value ' DISK CMD
        CASE &H41 TO &H48: dskreg(reg - &H40) = value AND &HFF ' DISK registers
    END SELECT ' everything else is ignored
END SUB

'-----------------------------------------------------------------------------
' Disk: LOAD / SAVE / DIR on files in the "disk" folder
'-----------------------------------------------------------------------------

SUB DiskCommand (cmd AS LONG)
    DIM st AS LONG
    dskreg(0) = cmd AND &HFF
    SELECT CASE cmd
        CASE 1: st = DiskLoad(0)
        CASE 2: st = DiskSave
        CASE 3: st = DiskLoad(-1)
        CASE 4: st = DiskDir
        CASE 5: st = DiskDelete
        CASE 6: st = DiskType
        CASE 7: st = DiskDirMem
        CASE 8: st = DiskRename
        CASE 9: st = DiskChFolder
        CASE 10: st = DiskNewFolder
        CASE 11: st = DiskDelFolder
        CASE 12: st = DiskCopy
        CASE 13: st = DiskWhere
        CASE ELSE: st = 5
    END SELECT
    dskreg(1) = st
END SUB

FUNCTION DskWord& (i AS LONG)
    DskWord& = dskreg(i) + 256 * dskreg(i + 1)
END FUNCTION

SUB SetDskWord (i AS LONG, v AS LONG)
    dskreg(i) = v AND &HFF
    dskreg(i + 1) = (v \ 256) AND &HFF
END SUB

FUNCTION DiskFolder$
    DIM d AS STRING
    d = _STARTDIR$ + "/disk"
    IF _DIREXISTS(d) = 0 THEN MKDIR d
    DiskFolder$ = d
END FUNCTION

' Folders: the disk folder, its folders, and theirs (two levels). curdir is
' the current one ("", "GAMES" or "GAMES/SAVES"): plain names are looked up
' there. A name starting with "/" is a path from the top of the disk.

' A string in memory at a: n characters, or (n = 0) up to a 0 or CR
FUNCTION MemStr$ (a AS LONG, n AS LONG)
    DIM i AS LONG, c AS LONG, s AS STRING
    DO
        IF n > 0 AND i >= n THEN EXIT DO
        c = PeekMem((a + i) AND &HFFFF&)
        IF n = 0 AND (c = 0 OR c = 13) THEN EXIT DO
        s = s + CHR$(c)
        IF LEN(s) > 200 THEN EXIT DO
        i = i + 1
    LOOP
    MemStr$ = s
END FUNCTION

' The name at NAME / NAMELEN, as given
FUNCTION DiskRaw$
    DiskRaw$ = MemStr$(DskWord(6), dskreg(8))
END FUNCTION

' One name: A-Z a-z 0-9 . _ - (not "." or ".."), 64 at most
FUNCTION NameOk& (s AS STRING)
    DIM i AS LONG
    IF s = "" OR s = "." OR s = ".." OR LEN(s) > 64 THEN EXIT FUNCTION
    FOR i = 1 TO LEN(s)
        IF INSTR("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-", MID$(s, i, 1)) = 0 THEN EXIT FUNCTION
    NEXT
    NameOk& = -1
END FUNCTION

' The host path of nm in the disk's folder fd ("" = the top)
FUNCTION DiskPath$ (fd AS STRING, nm AS STRING)
    DIM d AS STRING
    d = DiskFolder$
    IF fd <> "" THEN d = d + "/" + fd
    IF nm <> "" THEN d = d + "/" + nm
    DiskPath$ = d
END FUNCTION

' The rl name of the file (kind 1) or folder (kind 2) nm in fd: as
' given, in upper case or in lower case; "" if there is none
FUNCTION FindIn$ (fd AS STRING, nm AS STRING, kind AS LONG)
    DIM v AS STRING, i AS LONG
    FOR i = 1 TO 3
        SELECT CASE i
            CASE 1: v = nm
            CASE 2: v = UCASE$(nm)
            CASE 3: v = LCASE$(nm)
        END SELECT
        IF kind = 1 THEN
            IF _FILEEXISTS(DiskPath$(fd, v)) THEN FindIn$ = v: EXIT FUNCTION
        ELSE
            IF _DIREXISTS(DiskPath$(fd, v)) THEN FindIn$ = v: EXIT FUNCTION
        END IF
    NEXT
END FUNCTION

' A name or path -> rp_dir (its folder, rl names; "" = the top), rp_name
' (its last part), rp_depth (folders in rp_dir: 0-2). 0 ok, 1 a folder on
' the way is not there, 2 not a valid name, 7 too deep
FUNCTION ResolvePath& (raw AS STRING)
    DIM fd AS STRING, rest AS STRING, p AS LONG, part AS STRING, rl AS STRING, depth AS LONG
    IF LEFT$(raw, 1) = "/" THEN
        rest = MID$(raw, 2)
    ELSE
        fd = curdir: rest = raw
        IF fd <> "" THEN depth = 1: IF INSTR(fd, "/") THEN depth = 2
    END IF
    DO
        p = INSTR(rest, "/")
        IF p = 0 THEN EXIT DO
        part = LEFT$(rest, p - 1): rest = MID$(rest, p + 1)
        IF NameOk(part) = 0 THEN ResolvePath& = 2: EXIT FUNCTION
        IF depth >= 2 THEN ResolvePath& = 7: EXIT FUNCTION
        rl = FindIn$(fd, part, 2)
        IF rl = "" THEN ResolvePath& = 1: EXIT FUNCTION
        IF fd = "" THEN fd = rl ELSE fd = fd + "/" + rl
        depth = depth + 1
    LOOP
    IF NameOk(rest) = 0 THEN ResolvePath& = 2: EXIT FUNCTION
    rp_dir = fd: rp_name = rest: rp_depth = depth
END FUNCTION

' NAME -> the host path of an existing file (st = 0), or "" (st = 1 not
' found, 2 bad name, 7 too deep)
FUNCTION FileOf$ (st AS LONG)
    DIM rl AS STRING
    st = ResolvePath(DiskRaw$)
    IF st THEN EXIT FUNCTION
    rl = FindIn$(rp_dir, rp_name, 1)
    IF rl = "" THEN st = 1: EXIT FUNCTION
    FileOf$ = DiskPath$(rp_dir, rl)
END FUNCTION

' A byte written by a LOAD: RAM only (no I/O side effects, ROM protected)
SUB DiskPoke (address AS LONG, value AS LONG)
    IF address >= IO_START AND address < BANK_START THEN EXIT SUB
    IF address >= ROM_START THEN EXIT SUB
    PokeMem address, value
END SUB

FUNCTION DiskLoad& (tostart AS LONG)
    DIM f AS STRING, buf AS STRING, addr AS LONG, size AS LONG, st AS LONG
    DIM lim AS LONG, i AS LONG, rl AS STRING
    f = FileOf$(st)
    ' not in the current folder: the top of the disk (where programs keep
    ' their other parts, EDIT, the scripts...)
    IF st = 1 AND curdir <> "" AND INSTR(DiskRaw$, "/") = 0 THEN
        rl = FindIn$("", rp_name, 1)
        IF rl <> "" THEN f = DiskPath$("", rl): st = 0
    END IF
    IF st THEN DiskLoad& = st: EXIT FUNCTION
    buf = ReadFile$(f)
    IF LEN(buf) < 2 THEN DiskLoad& = 4: EXIT FUNCTION
    IF tostart THEN addr = DskWord(2) ELSE addr = ASC(buf, 1) + 256 * ASC(buf, 2)
    size = LEN(buf) - 2
    lim = DskWord(4)
    IF lim = 0 THEN lim = 65536
    IF addr + size > lim THEN DiskLoad& = 3: EXIT FUNCTION
    FOR i = 0 TO size - 1
        DiskPoke addr + i, ASC(buf, 3 + i)
    NEXT
    SetDskWord 2, addr
    SetDskWord 4, addr + size
    DiskLoad& = 0
END FUNCTION

FUNCTION DiskSave&
    DIM s AS LONG, e AS LONG, buf AS STRING, i AS LONG, f AS STRING, st AS LONG, rl AS STRING
    st = ResolvePath(DiskRaw$)
    IF st THEN DiskSave& = st: EXIT FUNCTION
    IF FindIn$(rp_dir, rp_name, 2) <> "" THEN DiskSave& = 4: EXIT FUNCTION ' a folder
    s = DskWord(2)
    e = DskWord(4)
    IF e = 0 THEN e = 65536
    IF e <= s THEN DiskSave& = 6: EXIT FUNCTION
    buf = CHR$(s AND &HFF) + CHR$(s \ 256) + SPACE$(e - s)
    FOR i = 0 TO e - s - 1
        ASC(buf, 3 + i) = PeekMem(s + i)
    NEXT
    rl = FindIn$(rp_dir, rp_name, 1) ' replace the existing file, whatever its case
    IF rl = "" THEN rl = rp_name
    f = DiskPath$(rp_dir, rl)
    WriteFile f, buf
    DiskSave& = 0
END FUNCTION

SUB WriteFile (f AS STRING, buf AS STRING)
    DIM h AS LONG
    IF _FILEEXISTS(f) THEN KILL f
    h = FREEFILE
    OPEN f FOR BINARY AS #h
    PUT #h, 1, buf
    CLOSE #h
END SUB

' Types the file NAME into the keyboard queue (a script). The 2-byte load
' address that files saved by mini6502 programs start with is skipped: rl
' text never starts with control characters other than tab / CR / LF.
FUNCTION DiskType&
    DIM f AS STRING, buf AS STRING, i AS LONG, c AS LONG, hdr AS LONG, st AS LONG
    f = FileOf$(st)
    IF st THEN DiskType& = st: EXIT FUNCTION
    buf = ReadFile$(f)
    IF LEN(buf) >= 2 THEN
        FOR i = 1 TO 2
            c = ASC(buf, i)
            IF c < 32 AND c <> 9 AND c <> 10 AND c <> 13 THEN hdr = -1
        NEXT
        IF hdr THEN buf = MID$(buf, 3)
    END IF
    TypeText buf
    DiskType& = 0
END FUNCTION

' Deletes the file NAME (found as given, in upper or in lower case)
FUNCTION DiskDelete&
    DIM f AS STRING, st AS LONG
    f = FileOf$(st)
    IF st THEN DiskDelete& = st: EXIT FUNCTION
    KILL f
    DiskDelete& = 0
END FUNCTION

' The destination at START (a name, or a path from the top with "/"):
' rp_dir / rp_name; 4 if something has that name already
FUNCTION DiskDest& (st AS LONG)
    st = ResolvePath(MemStr$(DskWord(2), 0))
    IF st THEN DiskDest& = st: EXIT FUNCTION
    IF FindIn$(rp_dir, rp_name, 1) <> "" OR FindIn$(rp_dir, rp_name, 2) <> "" THEN st = 4
    DiskDest& = st
END FUNCTION

' Renames the file NAME to the name at START (ending with 0 or CR). With a
' path ("/GAMES/X"), the file moves to that folder. A folder can be renamed
' too (in its own folder).
FUNCTION DiskRename&
    DIM f AS STRING, st AS LONG, rl AS STRING, d AS LONG
    f = FileOf$(st)
    IF st = 1 THEN ' a folder?
        rl = FindIn$(rp_dir, rp_name, 2)
        IF rl = "" THEN DiskRename& = 1: EXIT FUNCTION
        f = DiskPath$(rp_dir, rl): st = 0
        IF INSTR(MemStr$(DskWord(2), 0), "/") THEN DiskRename& = 2: EXIT FUNCTION
    END IF
    IF st THEN DiskRename& = st: EXIT FUNCTION
    d = DiskDest(st)
    IF st THEN DiskRename& = st: EXIT FUNCTION
    NAME f AS DiskPath$(rp_dir, rp_name)
    DiskRename& = 0
END FUNCTION

' Copies the file NAME to the name or path at START
FUNCTION DiskCopy&
    DIM f AS STRING, st AS LONG, d AS LONG
    f = FileOf$(st)
    IF st THEN DiskCopy& = st: EXIT FUNCTION
    d = DiskDest(st)
    IF st THEN DiskCopy& = st: EXIT FUNCTION
    WriteFile DiskPath$(rp_dir, rp_name), ReadFile$(f)
    DiskCopy& = 0
END FUNCTION

' The current folder = NAME: a folder in it, ".." (one up), "/" (the top)
' or a path from the top ("/GAMES/SAVES"). 7 if it would be a third level.
FUNCTION DiskChFolder&
    DIM raw AS STRING, st AS LONG, rl AS STRING, p AS LONG
    raw = DiskRaw$
    IF raw = "/" OR raw = "" THEN curdir = "": EXIT FUNCTION
    IF raw = ".." THEN
        p = _INSTRREV(curdir, "/")
        IF p THEN curdir = LEFT$(curdir, p - 1) ELSE curdir = ""
        EXIT FUNCTION
    END IF
    IF RIGHT$(raw, 1) = "/" THEN raw = LEFT$(raw, LEN(raw) - 1)
    st = ResolvePath(raw)
    IF st THEN DiskChFolder& = st: EXIT FUNCTION
    rl = FindIn$(rp_dir, rp_name, 2)
    IF rl = "" THEN DiskChFolder& = 1: EXIT FUNCTION
    IF rp_depth >= 2 THEN DiskChFolder& = 7: EXIT FUNCTION
    IF rp_dir = "" THEN curdir = rl ELSE curdir = rp_dir + "/" + rl
END FUNCTION

' A new folder NAME (4 if the name is taken, 7 if it would be a third level)
FUNCTION DiskNewFolder&
    DIM st AS LONG
    st = ResolvePath(DiskRaw$)
    IF st THEN DiskNewFolder& = st: EXIT FUNCTION
    IF rp_depth >= 2 THEN DiskNewFolder& = 7: EXIT FUNCTION
    IF FindIn$(rp_dir, rp_name, 1) <> "" OR FindIn$(rp_dir, rp_name, 2) <> "" THEN DiskNewFolder& = 4: EXIT FUNCTION
    MKDIR DiskPath$(rp_dir, rp_name)
END FUNCTION

' Deletes the folder NAME if it is empty (4 if it is not)
FUNCTION DiskDelFolder&
    DIM st AS LONG, rl AS STRING, d AS STRING, f AS STRING
    st = ResolvePath(DiskRaw$)
    IF st THEN DiskDelFolder& = st: EXIT FUNCTION
    rl = FindIn$(rp_dir, rp_name, 2)
    IF rl = "" THEN DiskDelFolder& = 1: EXIT FUNCTION
    d = DiskPath$(rp_dir, rl)
    f = _FILES$(d + "/*")
    DO WHILE LEN(f)
        SELECT CASE f
            CASE ".", "..", "./", "../", ".\", "..\"
            CASE ELSE: DiskDelFolder& = 4: EXIT FUNCTION
        END SELECT
        f = _FILES$
    LOOP
    IF curdir = rl OR LEFT$(curdir, LEN(rl) + 1) = rl + "/" THEN curdir = rp_dir
    RMDIR d
END FUNCTION

' The current folder's path ("/", "/GAMES", "/GAMES/SAVES") at START, with
' a 0 after it; END = the address after the 0
FUNCTION DiskWhere&
    DIM s AS STRING, a AS LONG, i AS LONG
    s = "/" + curdir + CHR$(0)
    a = DskWord(2)
    FOR i = 1 TO LEN(s)
        DiskPoke a + i - 1, ASC(s, i)
    NEXT
    SetDskWord 4, a + LEN(s)
END FUNCTION

' The current folder's entries: folders (names, sorted) in fo(), files in
' fi(); counts nfo / nfi
SUB DiskList (fo() AS STRING, nfo AS LONG, fi() AS STRING, nfi AS LONG)
    DIM d AS STRING, f AS STRING, c AS STRING
    nfo = 0: nfi = 0
    d = DiskPath$(curdir, "")
    IF _DIREXISTS(d) = 0 THEN curdir = "": d = DiskPath$("", "")
    f = _FILES$(d + "/*")
    DO WHILE LEN(f)
        c = RIGHT$(f, 1)
        IF c = "/" OR c = "\" THEN
            f = LEFT$(f, LEN(f) - 1)
            IF NameOk(f) THEN
                IF nfo > UBOUND(fo) THEN REDIM _PRESERVE fo(0 TO nfo * 2) AS STRING
                fo(nfo) = f: nfo = nfo + 1
            END IF
        ELSEIF f <> "." AND f <> ".." THEN
            IF nfi > UBOUND(fi) THEN REDIM _PRESERVE fi(0 TO nfi * 2) AS STRING
            fi(nfi) = f: nfi = nfi + 1
        END IF
        f = _FILES$
    LOOP
    SortNames fo(), nfo
    SortNames fi(), nfi
END SUB

SUB SortNames (a() AS STRING, n AS LONG)
    DIM i AS LONG, j AS LONG, f AS STRING
    FOR i = 1 TO n - 1
        f = a(i): j = i - 1
        DO WHILE j >= 0
            IF a(j) <= f THEN EXIT DO
            a(j + 1) = a(j): j = j - 1
        LOOP
        a(j + 1) = f
    NEXT
END SUB

' Lists the current folder on the terminal: its folders, then each file's
' name, size in bytes and load address
FUNCTION DiskDir&
    DIM i AS LONG, h AS LONG, hdr AS STRING, sz AS LONG, nfo AS LONG, nfi AS LONG
    REDIM fo(0 TO 49) AS STRING, fi(0 TO 99) AS STRING
    DiskList fo(), nfo, fi(), nfi
    IF curx > 0 THEN TermNewLine
    IF curdir <> "" THEN TermString "Folder /" + curdir: TermNewLine
    FOR i = 0 TO nfo - 1
        TermString LEFT$(fo(i) + SPACE$(24), 24) + "  (folder)": TermNewLine
    NEXT
    FOR i = 0 TO nfi - 1
        h = FREEFILE
        OPEN DiskPath$(curdir, fi(i)) FOR BINARY AS #h
        sz = LOF(h) - 2
        hdr = "  "
        IF sz >= 0 THEN GET #h, 1, hdr
        CLOSE #h
        TermString LEFT$(fi(i) + SPACE$(24), 24)
        IF sz >= 0 THEN
            TermString RIGHT$(SPACE$(6) + STR$(sz), 6) + " bytes at $" + Hex4$(ASC(hdr, 1) + 256 * ASC(hdr, 2))
        ELSE
            TermString "     (not a mini6502 file)"
        END IF
        TermNewLine
    NEXT
    IF nfo + nfi = 0 THEN TermString "(no files)": TermNewLine
    DiskDir& = 0
END FUNCTION

' DIR into memory: from START, for each entry of the current folder
' (folders first, then files, each in name order): the name, 0, the size
' (3 bytes: $FFFFFE for a folder, $FFFFFF for a file without a load
' address), the load address (2 bytes, 0 for a folder); then a single 0.
' END in = limit (0 = up to $D000), out = the address after the final 0.
' Nothing is written if it does not fit (3).
FUNCTION DiskDirMem&
    DIM i AS LONG, h AS LONG, nfo AS LONG, nfi AS LONG
    DIM lst AS STRING, hdr AS STRING, sz AS LONG, a AS LONG, lim AS LONG
    REDIM fo(0 TO 49) AS STRING, fi(0 TO 99) AS STRING
    DiskList fo(), nfo, fi(), nfi
    FOR i = 0 TO nfo - 1
        lst = lst + fo(i) + CHR$(0) + CHR$(&HFE) + CHR$(&HFF) + CHR$(&HFF) + CHR$(0) + CHR$(0)
    NEXT
    FOR i = 0 TO nfi - 1
        h = FREEFILE
        OPEN DiskPath$(curdir, fi(i)) FOR BINARY AS #h
        sz = LOF(h) - 2
        hdr = CHR$(0) + CHR$(0)
        IF sz >= 0 THEN GET #h, 1, hdr ELSE sz = &HFFFFFF
        CLOSE #h
        lst = lst + fi(i) + CHR$(0) + CHR$(sz AND 255) + CHR$((sz \ 256) AND 255) + CHR$((sz \ 65536) AND 255) + hdr
    NEXT
    lst = lst + CHR$(0)
    a = DskWord(2): lim = DskWord(4): IF lim = 0 THEN lim = IO_START
    IF a + LEN(lst) > lim THEN DiskDirMem& = 3: EXIT FUNCTION
    FOR i = 1 TO LEN(lst)
        DiskPoke a + i - 1, ASC(lst, i)
    NEXT
    SetDskWord 4, a + LEN(lst)
    DiskDirMem& = 0
END FUNCTION

'-----------------------------------------------------------------------------
' Sound card: 3 music voices + 1 noise voice + beep, synthesized here and
' played by the platform
'-----------------------------------------------------------------------------

SUB SoundReset
    DIM i AS LONG
    FOR i = 0 TO NUM_VOICES
        voice(i).note = 0
        voice(i).vol = 15
        voice(i).wave = 0
        voice(i).dur = 0
        voice(i).gate = 0 ' sounding notes fade out instead of stopping dead
        voice(i).remain = 0
        voice(i).decay = 0
        voice(i).sweep = 0
        voice(i).pulse = 15
        voice(i).bend = 0
        voice(i).env = 15
        voice(i).semis = 0
        voice(i).lfsr = 1
    NEXT
    atkstep = 1 / (ATTACK_S * srate)
    relstep = 1 / (RELEASE_S * srate)
END SUB

' r = offset from $D030
FUNCTION SoundRead& (r AS LONG)
    DIM v AS LONG
    v = r \ 4
    SELECT CASE r AND 3
        CASE 0: SoundRead& = voice(v).note
        CASE 1: SoundRead& = voice(v).vol
        CASE 2: SoundRead& = voice(v).wave
        CASE 3: SoundRead& = voice(v).dur
    END SELECT
END FUNCTION

SUB SoundWrite (r AS LONG, value AS LONG)
    DIM v AS LONG
    v = r \ 4
    SELECT CASE r AND 3
        CASE 0
            voice(v).note = value AND 127
            IF voice(v).note THEN
                voice(v).env = voice(v).vol
                voice(v).dcount = voice(v).decay
                voice(v).semis = 0
                IF v = 3 THEN ' the noise voice: noise changes 4 times faster
                    NoteOn v, 1760# * 2# ^ ((voice(v).note - 69) / 12#), voice(v).dur
                ELSE
                    NoteOn v, 440# * 2# ^ ((voice(v).note - 69) / 12#), voice(v).dur
                END IF
            ELSE
                voice(v).gate = 0
            END IF
        CASE 1: voice(v).vol = value AND 15: voice(v).env = voice(v).vol
        CASE 2: voice(v).wave = value AND 3
        CASE 3: voice(v).dur = value AND 255
    END SELECT
END SUB

' r = offset from $D050: DECAY, SWEEP, PULSE, (free)
FUNCTION SoundShapeRead& (r AS LONG)
    DIM v AS LONG
    v = r \ 4
    SELECT CASE r AND 3
        CASE 0: SoundShapeRead& = voice(v).decay
        CASE 1: SoundShapeRead& = voice(v).sweep AND 255
        CASE 2: SoundShapeRead& = voice(v).pulse
        CASE 3: SoundShapeRead& = voice(v).bend AND 255
    END SELECT
END FUNCTION

SUB SoundShapeWrite (r AS LONG, value AS LONG)
    DIM v AS LONG
    v = r \ 4
    value = value AND 255
    SELECT CASE r AND 3
        CASE 0: voice(v).decay = value
        CASE 1: IF value > 127 THEN voice(v).sweep = value - 256 ELSE voice(v).sweep = value
        CASE 2: voice(v).pulse = value AND 15
        CASE 3: IF value > 127 THEN voice(v).bend = value - 256 ELSE voice(v).bend = value
            VoicePitch v
    END SELECT
END SUB

' The voice's frequency now: the note, moved by SWEEP so far and by BEND
SUB VoicePitch (v AS LONG)
    DIM hz AS DOUBLE
    hz = voice(v).hz * 2# ^ ((voice(v).semis + voice(v).bend / 8#) / 12#)
    IF hz < 8 THEN hz = 8
    voice(v).inc = hz / srate
    IF voice(v).inc > 1 THEN voice(v).inc = 1
END SUB

' The phase is kept, so a note played over a sounding one changes pitch without a click
SUB NoteOn (v AS LONG, hz AS DOUBLE, frames AS LONG)
    voice(v).hz = hz
    VoicePitch v
    voice(v).gate = -1
    voice(v).remain = frames
END SUB

SUB StartBeep
    voice(NUM_VOICES).env = 15
    NoteOn NUM_VOICES, BEEP_HZ, BEEP_FRAMES
END SUB

' Called once per frame: note durations, DECAY and SWEEP
SUB SoundTick
    DIM i AS LONG
    FOR i = 0 TO NUM_VOICES
        IF voice(i).gate THEN
            IF voice(i).remain > 0 THEN
                voice(i).remain = voice(i).remain - 1
                IF voice(i).remain = 0 THEN voice(i).gate = 0
            END IF
            IF voice(i).decay > 0 THEN
                voice(i).dcount = voice(i).dcount - 1
                IF voice(i).dcount <= 0 THEN
                    voice(i).dcount = voice(i).decay
                    voice(i).env = voice(i).env - 1
                    IF voice(i).env <= 0 THEN voice(i).env = 0: voice(i).gate = 0
                END IF
            END IF
            IF voice(i).sweep <> 0 THEN
                voice(i).semis = voice(i).semis + voice(i).sweep / 16#
                IF voice(i).semis > 96 THEN voice(i).semis = 96
                IF voice(i).semis < -96 THEN voice(i).semis = -96
                VoicePitch i
            END IF
        END IF
    NEXT
END SUB

' Next output sample, -1 to 1: every voice's wave times its fading level
FUNCTION SoundSample#
    DIM i AS LONG, target AS DOUBLE, p AS DOUBLE, s AS DOUBLE, mix AS DOUBLE, b AS LONG
    FOR i = 0 TO NUM_VOICES
        target = 0
        IF voice(i).gate THEN target = voice(i).env / 15
        IF voice(i).level < target THEN
            voice(i).level = voice(i).level + atkstep
            IF voice(i).level > target THEN voice(i).level = target
        ELSEIF voice(i).level > target THEN
            voice(i).level = voice(i).level - relstep
            IF voice(i).level < target THEN voice(i).level = target
        END IF
        IF voice(i).level > 0 THEN
            p = voice(i).phase + voice(i).inc
            IF p >= 1 THEN
                p = p - INT(p)
                IF i = 3 THEN ' noise voice: a 15-bit shift register (white or metallic)
                    IF voice(i).wave AND 1 THEN
                        b = (voice(i).lfsr XOR (voice(i).lfsr \ 64)) AND 1
                    ELSE
                        b = (voice(i).lfsr XOR (voice(i).lfsr \ 2)) AND 1
                    END IF
                    voice(i).lfsr = (voice(i).lfsr \ 2) OR (b * 16384)
                    IF voice(i).lfsr AND 1 THEN voice(i).noise = 1 ELSE voice(i).noise = -1
                ELSE
                    voice(i).noise = RND * 2 - 1
                END IF
            END IF
            voice(i).phase = p
            IF i = 3 THEN
                s = voice(i).noise
            ELSE
                SELECT CASE voice(i).wave
                    CASE 0: IF p < (voice(i).pulse + 1) / 32 THEN s = 1 ELSE s = -1
                    CASE 1: s = 4 * ABS(p - 0.5) - 1
                    CASE 2: s = 2 * p - 1
                    CASE ELSE: s = voice(i).noise
                END SELECT
            END IF
            mix = mix + s * voice(i).level
        END IF
    NEXT
    mix = mix / NUM_VOICES ' (the beep rarely plays over all four)
    IF mix > 1 THEN mix = 1
    IF mix < -1 THEN mix = -1
    SoundSample# = mix
END FUNCTION

'-----------------------------------------------------------------------------
' Terminal
'-----------------------------------------------------------------------------

SUB ClearScreen
    DIM x AS LONG, y AS LONG
    FOR y = 0 TO ROWS - 1
        FOR x = 0 TO COLS - 1
            scr(x, y) = 32
            attr(x, y) = curcolor
        NEXT
    NEXT
    curx = 0: cury = 0
END SUB

SUB TermNewLine
    DIM x AS LONG, y AS LONG
    curx = 0
    cury = cury + 1
    IF cury >= ROWS THEN
        FOR y = 1 TO ROWS - 1
            FOR x = 0 TO COLS - 1
                scr(x, y - 1) = scr(x, y)
                attr(x, y - 1) = attr(x, y)
            NEXT
        NEXT
        FOR x = 0 TO COLS - 1
            scr(x, ROWS - 1) = 32
            attr(x, ROWS - 1) = curcolor
        NEXT
        cury = ROWS - 1
    END IF
END SUB

SUB TermPut (value AS LONG)
    DIM c AS LONG
    c = value AND &H7F
    SELECT CASE c
        CASE 7: StartBeep
        CASE 13: TermNewLine
        CASE 10: IF lastout <> 13 THEN TermNewLine
        CASE 8: IF curx > 0 THEN curx = curx - 1: scr(curx, cury) = 32: attr(curx, cury) = curcolor
        CASE 9: curx = (curx \ 8 + 1) * 8: IF curx >= COLS THEN TermNewLine
        CASE 12: ClearScreen
        CASE 32 TO 126
            scr(curx, cury) = c
            attr(curx, cury) = curcolor
            curx = curx + 1
            IF curx >= COLS THEN TermNewLine
    END SELECT
    lastout = c
END SUB

SUB TermString (s AS STRING)
    DIM i AS LONG
    FOR i = 1 TO LEN(s)
        TermPut ASC(s, i)
    NEXT
END SUB

FUNCTION ScreenRow$ (y AS LONG)
    DIM s AS STRING, x AS LONG
    s = SPACE$(COLS)
    FOR x = 0 TO COLS - 1
        ASC(s, x + 1) = scr(x, y)
    NEXT
    ScreenRow$ = s
END FUNCTION

'-----------------------------------------------------------------------------
' Platform: window, rendering and keyboard
'-----------------------------------------------------------------------------

$IF HEADLESS = 1 THEN

    SUB InitPlatform
    END SUB

    FUNCTION KeyHeld& (c AS LONG)
        KeyHeld& = 0 ' (no keyboard state in the console build)
    END FUNCTION

    ' Runs until all queued keys are consumed (plus one second), then prints
    ' the screen.
    SUB PlatformFrame
        DIM y AS LONG
        IF LEN(kbd_queue) = 0 THEN idle_frames = idle_frames + 1
        IF idle_frames > FPS OR frame > FPS * 600 THEN
            FOR y = 0 TO ROWS - 1
                PRINT RTRIM$(ScreenRow$(y))
            NEXT
            PRINT "-- PC=$"; HEX$(cpu6502.pc); " cycles:"; cpu6502.clockticks
            quit = -1
        END IF
    END SUB

$ELSE

    ' KEYHELD: is the key with mini6502 code c (see KEYSEL) held down now?
    FUNCTION KeyHeld& (c AS LONG)
        DIM k AS LONG, k2 AS LONG
        SELECT CASE c
            CASE 65 TO 90: k = c + 32: k2 = c ' a letter, either case
            CASE 129: k = 18432 ' Up
            CASE 130: k = 20480 ' Down
            CASE 131: k = 19200 ' Left
            CASE 132: k = 19712 ' Right
            CASE 133: k = 18176 ' Home
            CASE 134: k = 20224 ' End
            CASE 135: k = 18688 ' PgUp
            CASE 136: k = 20736 ' PgDn
            CASE 137: k = 20992 ' Insert
            CASE 138: k = 21248 ' Delete
            CASE 140: k = 100304: k2 = 100303 ' Shift (left, right)
            CASE 141: k = 100306: k2 = 100305 ' Ctrl
            CASE 142: k = 100308: k2 = 100307 ' Alt
            CASE 1 TO 127: k = c
        END SELECT
        IF k <> 0 THEN
            IF _KEYDOWN(k) THEN KeyHeld& = 1
        END IF
        IF k2 <> 0 THEN
            IF _KEYDOWN(k2) THEN KeyHeld& = 1
        END IF
    END FUNCTION

    SUB InitPlatform
        SCREEN _NEWIMAGE(COLS * CHAR_W, ROWS * CHAR_H, 32)
        textimg = _NEWIMAGE(COLS * CHAR_W, ROWS * CHAR_H, 32)
        _DEST textimg
        _FONT 16
        _PRINTMODE _FILLBACKGROUND
        _CONTROLCHR OFF ' characters 0-31 written with VCHR show as their glyphs
        _DEST 0
        gfximg = _NEWIMAGE(GFX_W, GFX_H, 32)
        frameimg = _NEWIMAGE(COLS * CHAR_W, ROWS * CHAR_H, 32)
        _DEST frameimg ' MODE 2 and 4: the text is printed over the graphics here
        _FONT 16
        _DEST 0
        hiresimg = _NEWIMAGE(HI_W, HI_H, 32)
        InitFont
        InitPalette
        srate = _SNDRATE
        UpdateTitle
    END SUB

    ' Keeps SND_AHEAD seconds of audio queued, then advances note durations
    SUB SoundFrame
        DIM k AS LONG
        DO WHILE _SNDRAWLEN < SND_AHEAD
            FOR k = 1 TO 256
                _SNDRAW SoundSample
            NEXT
        LOOP
        SoundTick
    END SUB

    ' The 16 CGA colors, indexed by the nibbles of the COLOR register
    SUB InitPalette
        DIM i AS LONG, v AS STRING, rgb AS STRING
        rgb = "000000 0000AA 00AA00 00AAAA AA0000 AA00AA AA5500 AAAAAA "
        rgb = rgb + "555555 5555FF 55FF55 55FFFF FF5555 FF55FF FFFF55 FFFFFF "
        FOR i = 0 TO 15
            v = MID$(rgb, i * 7 + 1, 6)
            pal(i) = _RGB32(VAL("&H" + MID$(v, 1, 2)), VAL("&H" + MID$(v, 3, 2)), VAL("&H" + MID$(v, 5, 2)))
        NEXT
    END SUB

    SUB UpdateTitle
        DIM t AS STRING
        t = "mini6502  F1 Reset F2 Clear F3 Paste F4 Dump F5 Load"
        IF caps THEN t = t + "  [CAPS]"
        IF intscale THEN t = t + "  [whole-step scaling]"
        _TITLE t
    END SUB

    SUB SetWindowSize (w AS LONG, h AS LONG)
        DIM old AS LONG
        old = _DISPLAY
        SCREEN _NEWIMAGE(w, h, 32)
        _FREEIMAGE old
    END SUB

    SUB PlatformFrame
        STATIC lastsc AS LONG, lastcaps AS LONG
        DIM k AS STRING, c AS LONG, img AS LONG
        DIM w AS LONG, h AS LONG, s AS DOUBLE, dw AS LONG, dh AS LONG, x0 AS LONG, y0 AS LONG

        ' CAPS changed by a program (KBDFLAGS): the title shows it
        IF caps <> lastcaps THEN lastcaps = caps: UpdateTitle

        ' window resized by the user
        IF _RESIZE THEN
            w = _RESIZEWIDTH: h = _RESIZEHEIGHT
            IF w >= 160 AND h >= 100 AND (w <> _WIDTH(0) OR h <> _HEIGHT(0)) THEN SetWindowSize w, h
        END IF

        ' physical keys (POSHELD): QB64's port $60 queue of PC scancodes,
        ' presses and releases (+128), the same whatever the keyboard layout
        DO
            c = INP(&H60)
            IF c = lastsc THEN EXIT DO
            lastsc = c
            IF c AND 128 THEN posheld(c AND 127) = 0 ELSE posheld(c) = -1
        LOOP
        IF _WINDOWHASFOCUS = 0 THEN
            FOR c = 0 TO 127: posheld(c) = 0: NEXT
        END IF

        ' keyboard
        DO
            k = INKEY$
            IF k = "" THEN EXIT DO
            IF LEN(k) = 2 THEN
                SELECT CASE ASC(k, 2)
                    CASE 59: MachineReset ' F1
                    CASE 60: ClearScreen ' F2
                    CASE 61: TypeText _CLIPBOARD$ ' F3
                    CASE 62: DumpDialog ' F4
                    CASE 63: LoadDialog ' F5
                    CASE 64: caps = NOT caps: UpdateTitle ' F6
                    CASE 65: intscale = NOT intscale: UpdateTitle ' F7
                    CASE 66: SetWindowSize COLS * CHAR_W, ROWS * CHAR_H ' F8
                    CASE 72: QueueExt 1 ' Up
                    CASE 80: QueueExt 2 ' Down
                    CASE 75: QueueExt 3 ' Left
                    CASE 77: QueueExt 4 ' Right
                    CASE 71: QueueExt 5 ' Home
                    CASE 79: QueueExt 6 ' End
                    CASE 73: QueueExt 7 ' PgUp
                    CASE 81: QueueExt 8 ' PgDn
                    CASE 82: QueueExt 9 ' Insert
                    CASE 83: QueueExt 10 ' Delete
                END SELECT
            ELSE
                c = ASC(k)
                SELECT CASE c
                    CASE 8: QueueKey BACKSPACE_CHAR
                    CASE 22: TypeText _CLIPBOARD$ ' Ctrl+V
                    CASE 1 TO 31, 32 TO 126: QueueKey c
                END SELECT
            END IF
        LOOP

        SoundFrame

        ' where the 640x400 picture goes in the window (keeping the aspect ratio)
        w = _WIDTH(0): h = _HEIGHT(0)
        s = w / (COLS * CHAR_W)
        IF h / (ROWS * CHAR_H) < s THEN s = h / (ROWS * CHAR_H)
        IF intscale AND s >= 1 THEN s = INT(s)
        dw = INT(COLS * CHAR_W * s): dh = INT(ROWS * CHAR_H * s)
        x0 = (w - dw) \ 2: y0 = (h - dh) \ 2

        MouseFrame x0, y0, s

        ' the picture: text (MODE 0), lores graphics (1, 2) or hires (3, 4),
        ' with the text on top in MODE 2 and 4, then the mouse pointer
        SELECT CASE vreg(0)
            CASE 0: DrawText textimg: img = textimg
            CASE 1, 2: DrawGraphics: img = frameimg
            CASE ELSE: DrawHires: img = frameimg
        END SELECT
        IF vreg(0) = 2 OR vreg(0) = 4 THEN DrawText frameimg
        DrawPointer img

        _DEST 0
        CLS , _RGB32(0, 0, 0)
        _PUTIMAGE (x0, y0)-(x0 + dw - 1, y0 + dh - 1), img, 0
        _DISPLAY
        _LIMIT FPS
        IF _EXIT THEN quit = -1
    END SUB

    ' Mouse: position in 640x400 picture pixels, buttons, wheel, clicks; the
    ' pointer follows it if asked; the system's arrow is hidden over the
    ' picture while the mini6502 pointer is shown
    SUB MouseFrame (x0 AS LONG, y0 AS LONG, s AS DOUBLE)
        STATIC hidden AS LONG
        DIM b AS LONG, mx AS LONG, my AS LONG, inside AS LONG
        DO WHILE _MOUSEINPUT
            mwheel = mwheel + _MOUSEWHEEL
        LOOP
        IF mwheel > 127 THEN mwheel = 127
        IF mwheel < -128 THEN mwheel = -128
        mx = INT((_MOUSEX - x0) / s): my = INT((_MOUSEY - y0) / s)
        inside = mx >= 0 AND mx < HI_W AND my >= 0 AND my < HI_H
        IF mx < 0 THEN mx = 0
        IF mx > HI_W - 1 THEN mx = HI_W - 1
        IF my < 0 THEN my = 0
        IF my > HI_H - 1 THEN my = HI_H - 1
        mousex = mx: mousey = my
        IF _MOUSEBUTTON(1) THEN b = 1
        IF _MOUSEBUTTON(2) THEN b = b OR 2
        IF _MOUSEBUTTON(3) THEN b = b OR 4
        mclick = mclick OR (b AND NOT mbtn)
        IF b AND NOT mbtn THEN IrqRaise IRQ_MOUSE
        mbtn = b
        IF preg(8) AND 2 THEN ' FOLLOW
            preg(9) = mx AND 255: preg(10) = mx \ 256
            preg(11) = my AND 255: preg(12) = my \ 256
        END IF
        IF (preg(8) AND 1) <> 0 AND inside THEN
            IF hidden = 0 THEN _MOUSEHIDE: hidden = -1
        ELSE
            IF hidden THEN _MOUSESHOW: hidden = 0
        END IF
    END SUB

    ' The 16x16 pointer over the picture: mask 1 + image 1 = INK, mask 1 +
    ' image 0 = PAPER, mask 0 = see-through
    SUB DrawPointer (img AS LONG)
        DIM r AS LONG, k AS LONG, m AS LONG, b AS LONG, px AS LONG, py AS LONG
        DIM ink AS _UNSIGNED LONG, paper AS _UNSIGNED LONG
        IF (preg(8) AND 1) = 0 THEN EXIT SUB
        ink = _RGB32(palr(vreg(6)), palg(vreg(6)), palb(vreg(6)))
        paper = _RGB32(palr(vreg(7)), palg(vreg(7)), palb(vreg(7)))
        px = preg(9) + 256 * preg(10) - preg(13)
        py = preg(11) + 256 * preg(12) - preg(14)
        _DEST img
        FOR r = 0 TO 15
            m = preg(&H30 + r * 2) * 256 + preg(&H31 + r * 2)
            b = preg(&H10 + r * 2) * 256 + preg(&H11 + r * 2)
            FOR k = 0 TO 15
                IF m AND _SHR(32768, k) THEN
                    IF b AND _SHR(32768, k) THEN PSET (px + k, py + r), ink ELSE PSET (px + k, py + r), paper
                END IF
            NEXT
        NEXT
        _DEST 0
    END SUB

    ' The hires page (MODE 3, 4) into frameimg: only the rows that changed
    ' (VRAM writes) are drawn again, all of them after a video register write
    SUB DrawHires
        DIM x AS LONG, y AS LONG, b AS LONG, k AS LONG, p AS LONG, ms AS LONG
        DIM ink AS _UNSIGNED LONG, paper AS _UNSIGNED LONG
        IF drow0 < 0 THEN drow0 = 0
        IF drow1 > HI_H - 1 THEN drow1 = HI_H - 1
        IF drow0 <= drow1 THEN
            ms = vreg(4)
            ink = _RGB32(palr(vreg(6)) * ms \ 16, palg(vreg(6)) * ms \ 16, palb(vreg(6)) * ms \ 16)
            paper = _RGB32(palr(vreg(7)) * ms \ 16, palg(vreg(7)) * ms \ 16, palb(vreg(7)) * ms \ 16)
            p = (vreg(1) AND 1) * GFX_PAGE
            _DEST hiresimg
            LINE (0, drow0)-(HI_W - 1, drow1), paper, BF
            FOR y = drow0 TO drow1
                FOR x = 0 TO 79
                    b = vram(p + y * 80 + x)
                    IF b = 255 THEN
                        LINE (x * 8, y)-(x * 8 + 7, y), ink
                    ELSEIF b THEN
                        FOR k = 0 TO 7
                            IF b AND _SHR(128, k) THEN PSET (x * 8 + k, y), ink
                        NEXT
                    END IF
                NEXT
            NEXT
            _DEST 0
            drow0 = HI_H: drow1 = -1
        END IF
        _PUTIMAGE (0, 0), hiresimg, frameimg
    END SUB

    ' The 8x16 font as bits, for the hires CHAR command
    SUB InitFont
        DIM f AS LONG, c AS LONG, r AS LONG, k AS LONG, b AS LONG
        f = _NEWIMAGE(16, 16, 32)
        _DEST f
        _FONT 16
        _PRINTMODE _FILLBACKGROUND
        COLOR _RGB32(255, 255, 255), _RGB32(0, 0, 0)
        _SOURCE f
        FOR c = 0 TO 255
            _PRINTSTRING (0, 0), CHR$(c)
            FOR r = 0 TO 15
                b = 0
                FOR k = 0 TO 7
                    IF _RED32(POINT(k, r)) > 127 THEN b = b OR _SHR(128, k)
                NEXT
                fontbits(c * 16 + r) = b
            NEXT
        NEXT
        _SOURCE 0
        _DEST 0
        _FREEIMAGE f
    END SUB

    ' The text screen into img: textimg, or over the graphics in frameimg
    ' (MODE 2: cells with the TRANSP background only draw their character)
    SUB DrawText (img AS LONG)
        DIM y AS LONG, x AS LONG, x1 AS LONG, a AS LONG, row AS STRING
        _DEST img
        FOR y = 0 TO ROWS - 1
            row = ScreenRow$(y)
            x = 0
            DO WHILE x < COLS
                a = attr(x, y)
                x1 = x + 1
                DO WHILE x1 < COLS
                    IF attr(x1, y) <> a THEN EXIT DO
                    x1 = x1 + 1
                LOOP
                IF vreg(0) = 2 AND (a \ 16) = vreg(5) THEN
                    _PRINTMODE _KEEPBACKGROUND
                    COLOR pal(a AND 15)
                ELSE
                    _PRINTMODE _FILLBACKGROUND
                    COLOR pal(a AND 15), pal(a \ 16)
                END IF
                _PRINTSTRING (x * CHAR_W, y * CHAR_H), MID$(row, x + 1, x1 - x)
                x = x1
            LOOP
        NEXT
        IF (frame \ 16) MOD 2 = 0 THEN
            LINE (curx * CHAR_W, cury * CHAR_H + CHAR_H - 3)-STEP(CHAR_W - 1, 1), pal(curcolor AND 15), BF
        END IF
        _DEST 0
    END SUB

    ' The graphics (made by VideoFrame) scaled into frameimg
    SUB DrawGraphics
        DIM x AS LONG, y AS LONG, i AS LONG
        VideoLut
        _DEST gfximg
        FOR y = 0 TO GFX_H - 1
            FOR x = 0 TO GFX_W - 1
                PSET (x, y), lut(gfxidx(i))
                i = i + 1
            NEXT
        NEXT
        _DEST 0
        _PUTIMAGE (0, 0)-(COLS * CHAR_W - 1, ROWS * CHAR_H - 1), gfximg, frameimg
    END SUB

    SUB DumpDialog
        STATIC lastrange AS STRING
        DIM r AS STRING, f AS STRING, a AS LONG, b AS LONG
        IF lastrange = "" THEN lastrange = "0300.03FF"
        r = _INPUTBOX$("Dump memory", "Address range to save (start.end in hex):", lastrange)
        IF r = "" THEN EXIT SUB
        IF ParseRange(r, a, b) = 0 THEN
            _MESSAGEBOX "Dump memory", "Not a valid range: " + r + CHR$(10) + "Use start.end in hex, e.g. 6000.7FFF", "error"
            EXIT SUB
        END IF
        lastrange = r
        f = _SAVEFILEDIALOG$("Save hex dump", _STARTDIR$ + "/dump_" + Hex4$(a) + ".hex", "*.hex|*.txt", "Hex dump")
        IF f = "" THEN EXIT SUB
        SaveHexDump a, b, f
        _MESSAGEBOX "Dump memory", "Saved $" + Hex4$(a) + "-$" + Hex4$(b) + " (" + _TRIM$(STR$(b - a + 1)) + " bytes)" + CHR$(10) + f, "info"
    END SUB

    SUB LoadDialog
        DIM f AS STRING, n AS LONG
        f = _OPENFILEDIALOG$("Load hex dump", _STARTDIR$ + "/", "*.hex|*.txt", "Hex dump")
        IF f = "" THEN EXIT SUB
        n = LoadHexDump(f)
        _MESSAGEBOX "Load hex dump", "Loaded" + STR$(n) + " bytes from" + CHR$(10) + f, "info"
    END SUB

$END IF

'$INCLUDE:'fake6502.bm'
