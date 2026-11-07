#!/bin/sh
# Builds the desktop toolkit: TK1 (bank $10), TK2 ($11), TK3-TK5 ($17-$19), plus
# the test program TKTEST (bank $20). Needs cc65 (ca65, ld65) and python3.
set -e
cd "$(dirname "$0")"
for f in tk1 tk2 tk3 tk4 tk5 tktest ctltest; do
    ca65 -I ../hw $f.asm -o $f.o -l $f.lst
    ld65 -C bank.cfg $f.o -o $f.bin -m $f.map
    python3 ../basic/bin2hex.py $f.bin E000 > $f.hex
    rm -f $f.o
done
python3 -c "
for f, n in (('tk1', 'TK1'), ('tk2', 'TK2'), ('tk3', 'TK3'), ('tk4', 'TK4'), ('tk5', 'TK5'), ('tktest', 'TKTEST'), ('ctltest', 'CTLTEST')):
    d = open(f + '.bin', 'rb').read()
    assert len(d) <= 4096, f + ' is over 4K'
    open(n, 'wb').write(bytes([0, 0xE0]) + d)
    print(n, len(d), 'bytes')
"
