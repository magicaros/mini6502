mini6502 desktop toolkit
========================

Menus, windows, dialogs, controls and a file dialog for hires (640 x 400)
programs.
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

  banks $10-$11   the toolkit (TK1, TK2 on the disk)
  banks $17-$19   its controls and file dialog (TK3, TK4, TK5)
  bank $1A        the file dialog's directory
  entry 16        of the far-call table ($CC88) leads to it
  banks $D0-$DC   hold the caller's RAM while a toolkit program runs
  bank $20        TKTEST or CTLTEST, the test programs

Trying it
---------
From the monitor, the script does it all:
  T /DESKTOP/DESKTEST.TXT
which types (the toolkit's files are in the disk's DESKTOP folder):
  L /DESKTOP/TK1 E000 10  ... TK2 11, TK3 17, TK4 18, TK5 19, ACC 1B
  V 10 10 E000
  L /DESKTOP/TKTEST E000 20    D020: 20    E000R
To keep entry 16 in your far-call table, save the table again afterwards:
  S VECTORS CC00.CEFF   (the table and its names, not the bank map)
TKTEST: drag the windows by their titles, click a window behind to bring it
to the front, click in a window (it remembers the spots), type a key, use
the menus (File/New window asks for a name), Ctrl+N / Ctrl+W / Ctrl+Q /
Ctrl+K / Ctrl+T, the close box asks first. File/Quit (Ctrl+Q) puts
everything back as it was before.
CTLTEST (on the desktop: double-click it): one of each control. The line
at the bottom tells what the last event was; Open... and Save... show the
file dialog; List on/off greys the list out; Tab moves between the field
and the list; File/Quit (Ctrl+Q) or Esc quits. Both test programs have
the clock and the calculator in their mini6502 menu.

Needs the monitor from this version (its FARCALL now reads its 3 inline
bytes before switching banks, so code in one bank can call another).

Calling it
----------
        lda #<arg : sta r0 ... (arguments in X, Y and r0-r5)
        lda #function
        jsr $CC88
Results come back in A, X, Y, r0-r3; carry set means an error. Addresses
you pass may point into your own bank ($E000-$EFFF: the toolkit reads them
there) or into the fixed RAM.

While a toolkit program runs (between INIT and EXIT) the whole fixed RAM
is the toolkit's and the program's:
  $00-$7F    toolkit zero page; r0-r5 are $02-$0D (2 bytes each)
  $80-$FF    yours
  $0100      stack
  $0200-$07FF toolkit (windows, menus, controls)
  $0800-$BFFF yours (46K)
  $C000-$C2FF toolkit (dialog text)
  $C300-$CBFF yours
Port B is the toolkit's; port A is yours. Interrupts: a handler in the
caller's fixed RAM is turned off from INIT to EXIT (that RAM is swapped
out); one in a bank keeps running (see demos/irq/README.txt). Banks $10-$1F are the system's,
$20-$7F programs', $80-$CF documents', $D0-$FF the swaps'.

Functions
---------
 0 INIT       hires, grey desktop, empty menu bar, the pointer on. The
              caller's RAM ($0000-$CBFF: BASIC, its program...) is saved
              in banks $D0-$DC. Call it from your main routine.
 1 EXIT       everything back as before INIT (RAM, text screen, MODE 0),
              then returns to you: RTS from the routine that called INIT
              (if you call EXIT from a subroutine, PLA PLA its return
              address away first: the stack is as it was at INIT).
 2 MENUBAR    r0 = menu definition (see below); draws the bar.
 3 MENUITEM   X = menu, Y = item, r0 = 1 enable / 0 disable (greyed).
 4 OPENWIN    r0-r3 = x0, y0, x1, y1 (the outer frame), r4 = title (22
              characters at most). X = the window (0-7), in front; carry
              set if all 8 are open. It gets an UPDATE.
 5 CLOSEWIN   X = window. What it covered gets UPDATEs.
 6 GETEVENT   waits for the next event (A, see below).
 7 POLLEVENT  the same but returns EV_NONE (0) at once if there is none.
 8 SETPORT    X = window: the clip rectangle = its contents, r0-r3 = the
              contents rectangle (x0, y0, x1, y1, screen coordinates).
 9 ALERT      r0 = message (CR = new line), r1 = buttons "OK|Cancel" (up
              to 3; 0 = just OK). A = the button chosen. Enter = the first
              (thick frame), Esc = the last.
10 ASK        r0 = prompt, r1 = your buffer (its text is shown to edit),
              r2 = maximum length (1-40). Carry clear = OK: the buffer has
              the answer. Carry set = Cancel.
11 TEXT       r0 = string: drawn at the blitter's X0,Y0 (CHAROUT).
12 INVAL      X = window: its contents will get an UPDATE.
13 FRONT      X = window: to the front. X = 8 or more only asks. Returns
              X = the window in front ($FF if none).
14 CLEAR      the screen as after INIT (no windows, empty menu bar), for a
              program that started another one which has now finished.
15 SETTITLE   X = window, r0 = its new title.
16 DESKEVENTS r0 = 1: the desktop gets UPDATE events too (X = $FF, r0-r3
              = the area to redraw, the clip already set), before the
              windows, so you can draw icons on it. One comes at once for
              the whole desktop. INIT and CLEAR turn it off.
17 INVALRECT  r0-r3 = a rectangle of the screen: redrawn (desktop UPDATE,
              then the windows over it).
18 NEWCTL     X = window, Y = kind (below), r0-r3 = x0, y0, x1, y1 inside
              the window's contents, r4 / r5 as the kind says. X = the
              control (0-15, 16 in all); carry set if none is free. It is
              drawn at once.
19 DISPOSECTL X = control: gone (not erased: INVAL the window). X = $80 +
              window: all of that window's. CLOSEWIN disposes of a window's
              controls by itself.
20 SETVALUE   X = control, r0 = its value (kept in range); drawn again.
21 GETVALUE   X = control: r0 = its value (A = the low byte).
22 ENABLECTL  X = control, Y = 1 enabled / 0 disabled (greyed, ignores the
              mouse and the keys).
23 SETDATA    X = control, r0 = its new text / buffer / items, r1 = its
              number (a field's maximum length, a list's count, a scroll
              bar's maximum). A new list has nothing chosen. Drawn again.
24 FILEDIALOG Y = 0 Open / 1 Save, r0 = the prompt, r1 = your buffer for
              the name (in: the name to start with; out: the chosen one,
              up to 40 characters), r2 = an extension to list only ("TXT",
              0 = every file). Carry clear = OK, carry set = Cancel (or
              Esc). A list of the disk's files, the name field, Open / Save
              and Cancel: a double click or Enter on a name chooses it.
              Folders are listed first ("NAME/", and ".." to go up): a
              double click or Enter goes in; the current folder's path is
              shown bottom left. OK leaves that folder as the current one
              (the name is in it); Cancel goes back to where it started.
              Your controls and focus are left as they were.
              In Save, the suggested name starts selected (inverted): the
              first character typed (or Backspace) replaces it, an arrow
              or a click in the field keeps it. A name taken from the list
              is selected the same way.
25 FOCUS      X = the field or list that gets the keys ($FF none). Tab
              also moves it, among the window's fields and lists.
26 ACCESSORY  X = a desk accessory (0 Clock, 1 Calculator): its window
              opens (or comes to the front). X = $FF: the ones that were
              open the last time (the desktop calls this after CLEAR).
              Carry set if the accessories are not loaded.

Controls
--------
Kinds (Y for NEWCTL), and what r4 / r5 are:
  1 BUTTON  r4 = its label. Clicked: CONTROL (it shows pressed while the
            button is held, and only counts if released over it).
  2 CHECK   r4 = its label. Value 0 / 1, flips when clicked.
  3 RADIO   r4 = its label, r5 = a group number: clicking one sets it to 1
            and the others of the group in that window to 0.
  4 SCROLL  a vertical scroll bar: r4 = the page step, r5 = the maximum;
            value 0..maximum. Arrows (held: they repeat), page areas,
            the thumb can be dragged.
  5 FIELD   r4 = your buffer (its text is shown and edited in place),
            r5 = the maximum length (1-60). Typing, Backspace; Enter gives
            CONTROL with Y = 13. Clicking it gives it the keys.
  6 LIST    r4 = the items (strings, each ending with 0, one after the
            other), r5 = how many (up to 255). Value = the chosen one ($FFFF
            none). Rows of 16 pixels; its own scroll bar when they don't
            all fit. Up / Down when it has the keys, the wheel scrolls it.
  7 LABEL   r4 = a text; nothing to click. SETDATA changes it.
Texts and buffers are read where you pass them (your bank or the fixed
RAM), each time the control is drawn: change one, then SETDATA (or
SETVALUE) to show it.

The event: 7 CONTROL, X = the control, Y = what happened (1 clicked /
changed, 13 Enter in a field or list, $81 a double click in a list), r0 =
its value. Controls are drawn by the toolkit, after you drew the window's
UPDATE and whenever they change: don't draw over them.

Programs started from other toolkit programs (the desktop): INIT sees the
toolkit already running (its mark "TK" at $07FE) and only clears the
screen; EXIT then just returns. Put JMP start / .byte "TK" at $E000 so the
desktop knows it is a toolkit program and leaves the screen in hires.

Events
------
 0 NONE
 1 KEY     X = the character (Ctrl+letter shortcuts become MENU); X = 0
           for arrows and such, Y = their KBDEXT code (1 Up ... 10 Del)
 2 MENU    X = menu, Y = item (from 0)
 3 CLICK   X = window ($FF = the desktop), Y = buttons (1 left, 2 right;
           $81 = a double click: the second left click in the same window
           within 24 frames),
           r0/r1 = x/y inside the window's contents (screen x/y for the
           desktop). Only the window in front gets clicks: a click on one
           behind brings it to the front.
 4 UPDATE  X = window: draw its contents now. The clip rectangle is already
           set (so drawing the whole contents is fine: only what needs it
           changes), r0-r3 = its contents rectangle. Draw nothing else.
 5 CLOSE   X = window: its close box was clicked. Close it (CLOSEWIN) or
           not, as you like.
 6 WHEEL   X = the window in front, Y = steps (signed, + = towards you)
           (a list with the keys takes them instead)
 7 CONTROL X = control, Y = what, r0 = its value (see Controls)

Drawing: use the blitter (hires registers, see demos/hires/README.txt) in
UPDATE, or after SETPORT in the window in front. Windows behind may be
covered: for those, call INVAL and draw at the UPDATE.

Menus
-----
Every program has the same first menu: its title is "mini6502" and its
item is "About YOURAPP..." (show an ALERT with what it is and who made
it). The toolkit adds the desk accessories under it (a line, Clock,
Calculator, from bank $1B: L ACC E000 1B) and runs them itself: their
windows' UPDATE, CLICK, KEY (while in front) and CLOSE never reach you,
nor do their menu items. The second menu is "File", with Quit (Ctrl+Q)
as its last item.
The definition: each menu's title, 0, then its items each ending with 0,
then a lone 0; after the last menu another lone 0. Up to 8 menus, 15
items in a menu, 64 in all, about 380 characters of text in all.
  "-"            a separator line
  "(Undo"        starts disabled (the "(" is not shown)
  "Quit/Q"       shortcut Ctrl+Q (shown as ^Q). Avoid H, I, J and M: they
                 are Backspace, Tab and Enter.
Example (tktest.asm):
  .byte "mini6502", 0, "About TKTEST...", 0, 0
  .byte "File", 0, "New window.../N", 0, "-", 0, "Quit/Q", 0, 0
  .byte "Edit", 0, "(Undo/Z", 0, 0
  .byte 0

The clipboard
-------------
Banks $1C-$1F hold the clipboard every program shares (B_CLIP): its
length at $1C:E000 (2 bytes, low first, 16,382 at most), then the text,
lines ending with CR. Linear address $01C000 for the ports and the DMA.
Cut / Copy write it, Paste reads it (NOTE does; see ../note/README.txt).

Inside
------
tk1.asm (bank $10): dispatcher, INIT/EXIT, windows, events, the redraw
pass, dragging. tk2.asm (bank $11): menus, dialogs. tk.inc: the numbers
above. common.inc: drawing helpers in both banks. Windows are redrawn the
classic way: the desktop is repainted in the damaged rectangle, then each
window that overlaps it gets its frame and an UPDATE, back to front, all
clipped to that rectangle. Menus and dialogs save what is under them on
VRAM page 1 and copy it back when they close.
Controls: tk3.asm (bank $17) has their functions and draws them, tk4.asm
($18) handles their clicks and keys, tk5.asm ($19) is the file dialog
(its directory goes to bank $1A); ctl.inc / ctlgeo.inc are shared. The
control records live in the toolkit's fixed RAM ($0600-$07EA), so all
three banks see them; TK1 calls TK3 to draw a window's controls after its
UPDATE and TK4 for clicks, keys, the wheel and held scroll arrows.
build.sh (needs cc65) makes TK1-TK5, TKTEST and CTLTEST.
