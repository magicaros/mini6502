#!/bin/sh
# Builds the desktop: DESK1, DESK2, DESK3 (banks $14-$16) and the desk
# accessories ACC (bank $1B), with the icons
# from icons.py. Needs cc65 (ca65, ld65) and python3; the toolkit's files
# (../toolkit/tk.inc, common.inc, bank.cfg) are used too.
set -e
cd "$(dirname "$0")"
python3 icons.py
for f in desk1 desk2 desk3 acc; do
    ca65 -I ../hw $f.asm -o $f.o -l $f.lst
    ld65 -C ../toolkit/bank.cfg $f.o -o $f.bin -m $f.map
    python3 ../basic/bin2hex.py $f.bin E000 > $f.hex
    rm -f $f.o
done
python3 -c "
for f, n in (('desk1', 'DESK1'), ('desk2', 'DESK2'), ('desk3', 'DESK3'), ('acc', 'ACC')):
    d = open(f + '.bin', 'rb').read()
    assert len(d) <= 4096, f + ' is over 4K'
    open(n, 'wb').write(bytes([0, 0xE0]) + d)
    print(n, len(d), 'bytes')
"
