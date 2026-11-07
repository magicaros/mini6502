mini6502 BASIC extensions
=========================

BASIC has no room left for new keywords, so new commands live in banks
$00-$07, C64 wedge style: a statement that starts with "!" is handed to
the extensions. Everything else is plain BASIC, untouched.
Part of mini6502 BASIC, derived from EhBASIC (c) Lee Davison: free for
personal, non-commercial use only (see basic/README.txt).
mini6502 additions Copyright (C) 2026 Benoit Colson, with the help of Claude AI.

  L /BASIC/GFX E000 00  load the extension (DESKTOP.TXT does it)
then start BASIC (A000R), or, if BASIC is already running, go to the
monitor (SYSTEM), load it, and come back with G: BASIC looks for
extensions at every cold and warm start.

  10 !SCREEN 2:!CLG 0:!COLOR 14
  20 FOR I=0 TO 159 STEP 4:!LINE 80,100,I,0:NEXT
  30 !SOUND 1,60,15,1,20
  40 !MOUSE X,Y,B:IF B=0 THEN 40
  50 !SCREEN 0

GFX (bank $00): graphics, sound, the mouse
------------------------------------------
Numbers can be any expressions; [ ] = may be left out.
  !SCREEN m               0 text, 1 graphics (160 x 200), 2 graphics with
                          the text on top, 3 hires (640 x 400), 4 hires
                          with the text on top
  !CLG [c]                clear the drawing page (with colour c, else 0)
  !COLOR c                the colour of PLOT, LINE, BOX, FILL: graphics
                          0-31 (+32 DIM), hires 1 ink / 0 paper
  !PLOT x,y               a point
  !LINE x0,y0,x1,y1       a line
  !BOX x0,y0,x1,y1        a rectangle
  !FILL x0,y0,x1,y1       a filled rectangle
  !PIXEL x,y,V            the variable V = the pixel at x,y
  !PALETTE i,r,g,b        palette entry i (0-31) = red, green, blue 0-255
  !PAGE show[,draw]       the page shown and the page drawn on (0-1)
  !SPRITE n,x,y[,i[,f]]   sprite n (0-31) at x,y, image i, flags f (2 flip
                          across, 4 flip down, 8 double, 16 behind, 32
                          shadow); it is switched on
  !SPROFF n               sprite n off
  !SPRDEF n,a             sprite image n (0-255) = the 256 bytes at a
                          (16 rows of 16 pixel bytes; 128 = see-through)
  !SOUND v,n[,vol[,w[,d]]]  voice v (1-4) plays note n (60 = middle C,
                          0 = off), volume 0-15, wave (0 square, 1
                          triangle, 2 saw, 3 noise; voice 4: 0 white
                          noise, 1 metallic), duration in frames (0 held)
  !SHAPE v,d[,s[,p]]      voice v's DECAY, SWEEP (-128..127), PULSE
  !QUIET                  all four voices off
  !MUSIC b                play the song in bank b (the music engine, bank
                          $12, must be loaded); !MUSIC 0 stops it
  !MOUSE X,Y,B            the variables X, Y = where the mouse is (text:
                          column 0-79, row 0-24; graphics: 0-159, 0-199;
                          hires: 0-639, 0-399), B = its buttons (1 left, 2
                          right, 4 middle)
  !WAIT n                 wait n frames (1/60 s)
  !POINTER n              the mouse pointer on (1) or off (0)
  !BLOAD "name",a[,b]     load a file at address a (bank b at $E000)
  !BSAVE "name",a,e[,b]   save the bytes a..e (e included)
  !HELP                   list the commands and functions of every
                          extension loaded (GFX's, DOS's...)
  !FLUSH                  throw away the keys waiting to be read (as
                          POKE 198,0 on a C64)
Functions, in any expression:
  !MOUSEX  !MOUSEY        where the mouse is (in the units of !MOUSE)
  !BUTTONS                the buttons held (1 left, 2 right, 4 middle)
  !CLICKS                 the buttons pressed since the last !CLICKS, so a
                          quick click is never missed
  !FRAME                  the frame counter, 0-255, +1 every 1/60 s
  !PIXEL(x,y)             the pixel at x,y
  !KEYDOWN("W")           -1 (true) while that key is held down, else 0:
  !KEYDOWN(code)          for games, several keys at once and no auto-
                          repeat. A letter, digit or other key in quotes,
                          or a code: 32 Space, 13 Enter, 27 Esc, 129 Up
                          130 Down 131 Left 132 Right, 140 Shift, 141 Ctrl,
                          142 Alt (all of them: KEYSEL in hw/REGISTERS.txt)
                          A held key is also typed (with auto-repeat) into
                          the keyboard queue; !KEYDOWN throws those typed
                          copies away (keeping a Ctrl-C), so they don't
                          pour into BASIC when the program stops. The keys
                          are the ones printed on your keyboard: on AZERTY,
                          "W" is the W key, where QWERTY has its Z.
  !KEYAT("W")             the same, but for a key's PLACE on the keyboard,
  !KEYAT(scancode)        whatever is printed on it: "W" = where W is on a
                          US keyboard (Z on AZERTY, still W on QWERTZ), so
                          a WASD game plays the same on every layout. A
                          letter, digit or space in quotes, or a PC
                          scancode: 1 Esc, 28 Enter, 57 Space, 72 Up, 80
                          Down, 75 Left, 77 Right, 42 Shift, 29 Ctrl (all
                          of them: KEYPOS in hw/REGISTERS.txt)
  10 !SCREEN 2:X=80:Y=100
  20 !SPRITE 0,X,Y,1
  30 IF !KEYAT("A") THEN X=X-1
  40 IF !KEYAT("D") THEN X=X+1
  50 IF !KEYAT("W") THEN Y=Y-1
  60 IF !KEYAT("S") THEN Y=Y+1
  70 !WAIT 1:IF NOT !KEYDOWN(27) THEN 20
  80 !SCREEN 0
  10 !SCREEN 2:!POINTER 1
  20 IF !BUTTONS AND 1 THEN !PLOT !MOUSEX,!MOUSEY
  30 IF !CLICKS AND 2 THEN !SCREEN 0:END
  40 GOTO 20
Example: a song into a bank and playing:
  !BLOAD "DEMO.MUS",57344,128:!MUSIC 128

DOS (bank $01): folders and files
---------------------------------
  L /BASIC/DOS E000 01  load it (DESKTOP.TXT does it)
LOAD, SAVE, KILL, DIR, !BLOAD and !BSAVE work in the disk's current folder,
or with a path from the top (LOAD "/GAMES/BREAKOUT"). DOS moves around:
  !CD                     print the current folder ("/", "/GAMES"...)
  !CD "name"              go into a folder; ".." one up, "/" the top, or a
                          path "/GAMES/SAVES" (two levels of folders at most)
  !MD "name"              a new folder
  !RD "name"              delete a folder (only an empty one)
  !COPY "from","to"       copy a file; "to" may be a path ("/GAMES/X")
  !MOVE "from","to"       rename a file, or move it with a path
  !HELP                   every extension's commands (as GFX's !HELP)
Names are any string expressions (N$, "SAVE"+STR$(I)...). A folder that is
not there: File not found. A name taken, a folder not empty, a third level
of folders: File Error. A program can keep its data in its own folder:
make it once (!MD "/MYGAME"), then the program does !CD "/MYGAME" and
SAVEs there.

Spaces after the "!" are fine, and so are keywords that contain BASIC's
own (COLOR holds OR, POINTER holds INT, BLOAD holds LOAD): the extension
reads them as typed. LIST shows the lines as typed too.
One catch for extension writers: a name must not end with one of BASIC's
own functions when "(" follows it (KEYPOS( would be stored as KEY and the
POS( token), so GFX's position function is called KEYAT.

Writing an extension
--------------------
An extension is a 4K image for one of banks $00-$07 (bank $00 is GFX):
  $E000  "BX", 2          the mark BASIC looks for, and the version
  $E003  JMP statement    called for a "!" statement (see below)
  $E006  JMP init         called at every BASIC cold and warm start
  $E009  JMP function     called for a "!" inside an expression
  $E00C  its name         8 bytes: the name, then 0s
  $E014  .word            its commands' keyword list (for !HELP)
  $E016  .word            its functions' keyword list (0: none)
!HELP lists every extension loaded, with its commands and functions, from
these headers: put HELP in your keyword list and answer it with
JMP bxhelp (.include "bxhelp.inc"); whichever extension comes first in
the banks answers for all of them, so !HELP works with any of them loaded.
For each "!" statement BASIC asks the extensions in turn, from bank $00 up.
Your statement routine gets the line pointer on the first character after
the "!" (spaces skipped). Use XMATCH (bxmatch.inc) with your keyword list:
  carry clear and A = which keyword: run it with the API below, then return
  with carry clear; carry set: not yours, return with carry still set.
No extension wants it: Syntax error. A function works the same way but
returns its value in Y (low) / A (high), a signed 16-bit number, with carry
clear; an extension without functions just does SEC, RTS there. Functions
can appear inside your own commands' arguments (!PLOT !MOUSEX,!MOUSEY), so
a function must not disturb what a command may be halfway through (GFX's
!PIXEL puts the blitter's X0/Y0 back). Number results only, for now.

bx.inc lists the API, a jump table at fixed addresses in BASIC ($A009 on):
read a byte, a 16-bit number, a string, a ",", a variable to set; errors;
print; disk commands with a bank selected. An error (BASIC's or yours,
through XERROR) puts the program's bank back by itself. Zero page: $F0-$F7
belong to the matcher, $F8-$FF to you; the rest is BASIC's. Your own
variables can live in your bank. gfx.asm is the example; build.sh builds
it (needs cc65).
