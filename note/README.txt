NOTE - the desktop's text editor
================================

A text editor for the desktop, built on the toolkit: menus, a window with a
scroll bar, the mouse, selections, the clipboard, Find. (EDIT, the
text-mode editor, is still there for BASIC.)
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

Starting it
-----------
On the desktop: double-click NOTE, or a text file (.TXT): it opens in
NOTE. Without NOTE on the disk, text files open in EDIT as before.
NOTE needs NOTE2 too (it loads it when it starts): both live in the disk's
NOTE folder (the desktop and NOTE look there, or at the top).
By hand: the toolkit and ACC loaded (DESKTOP.TXT's L lines), then
  L /NOTE/NOTE E000 20   D020: 20   E000R      an empty text
or, with a name at $EF80 in that bank (ending with 0), E006R to open it.

Using it
--------
  typing                 goes in at the caret (the selection, if any, is
                         replaced); Enter, Backspace, Delete, Tab (spaces
                         to the next column of 8)
  arrows, Home, End,     move the caret; with Shift held, the selection
  PgUp, PgDn             grows from where it was
  click                  puts the caret there; Shift+click selects up to
                         there; drag to select (above or below the window
                         it scrolls); double-click selects a word
  scroll bar, wheel      scroll without moving the caret
  the status line        under the text: the caret's line and column, the
                         room left (characters), Modified / Unmodified
                         (since opened or saved), CAPS on / off (F6; read
                         from the machine's KBDFLAGS register)
  File    New (Ctrl+N), Open... (Ctrl+O), Save (Ctrl+S), Save as...,
          Quit (Ctrl+Q). New, Open and Quit ask first if there are
          unsaved changes (shown as * after the name in the title).
  Edit    Cut (Ctrl+X), Copy (Ctrl+C), Paste (Ctrl+V), Clear (deletes the
          selection), Select all (Ctrl+A)
  Search  Find... (Ctrl+F): asks for a word and selects the next place it
          is, after the caret, going round from the top; capitals or not
          does not matter. Find next (Ctrl+G) looks again.
mini6502 has F6 (CAPS) on at power-on, so letters come out in capitals:
press F6 for lower case.

The clipboard
-------------
Cut and Copy put the text in the system's clipboard, banks $1C-$1F, which
every program can use: at $1C:E000 its length (2 bytes, low first), then
the text (lines end with CR), 16,382 characters at most. Linear address
$01C000 for the ports and the DMA. Paste takes it from there, so text
copied in one program can be pasted in another.

Files
-----
Plain text, lines ending with CR; when a file is opened, LF and CR LF
become CR. Saved with its load address $1800 in front (where NOTE keeps
the text); EDIT and NOTE both ignore it when loading. Up to 43,008
characters.

Inside
------
note.asm makes two parts (note.cfg, build.sh, needs cc65):
  NOTE   for a bank ($E000-$EF7F): the menus, files, Find, the clipboard
  NOTE2  main RAM $0800-$17FF: the text: editing, moving, the selection,
         drawing
The text is at $1800-$BFFF in the main RAM (the program's while it
runs); insertions and deletions move the rest of the text with the DMA,
so they are instant whatever its size. Only the lines that changed are
drawn again when the caret moves or a character is typed on a line.
21 lines of 76 columns are shown, with the status line below them.
