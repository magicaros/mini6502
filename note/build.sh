#!/bin/sh
# Builds NOTE (for a bank, $E000) and NOTE2 (main RAM, $0800) from note.asm.
# Needs cc65 (ca65, ld65) and python3.
set -e
cd "$(dirname "$0")"
ca65 -I ../hw -I ../toolkit note.asm -o note.o -l note.lst
ld65 -C note.cfg note.o -m note.map
rm -f note.o
python3 -c "
for f, n, a in (('note.bin', 'NOTE', 0xE000), ('note2.bin', 'NOTE2', 0x0800)):
    d = open(f, 'rb').read()
    open(n, 'wb').write(bytes([a & 255, a >> 8]) + d)
    print(n, len(d), 'bytes')
"
