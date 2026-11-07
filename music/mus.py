#!/usr/bin/env python3
"""mus.py - compiles a song written as text into a .MUS file for the
mini6502 music engine.
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

usage: python3 mus.py song.txt SONG.MUS

The text (see demo.txt):
  title  Some name               shown by players later (up to 40 characters)
  speed  7                       frames per row (1-255)
  rows   32                      rows in every pattern (1-64)
  loop   0                       order to go back to at the end, or: loop none
  instrument N name  key=value...   N = 1-32. Keys (all optional):
      wave=square|triangle|saw|noise  vol=0-15 (15)  dur=frames (0 = held)
      decay=0-255  sweep=-128..127  pulse=0-15 (15)  vib=XY (hex: speed X,
      depth Y)
  pattern NAME                   then one line per row, from row 0:
      NOTE [INSTRUMENT] [EFFECT]
      NOTE: C-4 C#4 D-4 ... B-9 (C-4 = 60, middle C), --- nothing new,
            === note off. INSTRUMENT: a number, or . for none.
      EFFECT: a letter and two hex digits:
            An empty row (--- and no effect) changes nothing: an arpeggio,
            a vibrato or a slide goes on until the voice's next note or
            effect.
            Axy arpeggio (+x, +y semitones)   Sxx slide (signed SWEEP, F0 =
            down fast)   Vxy vibrato   Lxx volume   Txx speed   Jxx jump to
            order xx   B00 break to the next order   Pxx pulse width
      A line "... N" (three dots, a number) leaves N empty rows.
  order  NAME NAME NAME          one line per order: the patterns of voices
                                 1, 2, 3 (- = silent)
# starts a comment (at the start of a line or after a space).

The file: a 2-byte load address ($E000), then
  0  "MU", version 1, speed, orders, loop ($FF none), rows, instruments,
     patterns, 0, order list offset (2), patterns offset (2), title offset (2)
  16 instruments, 8 bytes each: DECAY VOL WAVE SWEEP PULSE DUR VIB 0
     the order list, 3 bytes per order (a pattern number for each voice)
     the patterns: ROWS rows of 4 bytes (note, instrument, effect, parameter)
     the title, ending with 0
Offsets count from "MU". Load it at $E000 of a bank: L SONG.MUS E000 30.
"""
import re, sys

WAVES = {"square": 0, "triangle": 1, "tri": 1, "saw": 2, "sawtooth": 2, "noise": 3}
EFFECTS = {"A": 1, "S": 2, "V": 3, "L": 4, "T": 5, "J": 6, "B": 7, "P": 8}
NOTES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def fail(n, msg):
    sys.exit(f"line {n}: {msg}")


def note(tok, n):
    if tok in ("---", "..."):
        return 0
    if tok in ("===", "OFF"):
        return 0xFF
    if len(tok) != 3 or tok[0].upper() not in NOTES or tok[1] not in "-#b" or not tok[2].isdigit():
        fail(n, f"not a note: {tok}")
    v = 12 * (int(tok[2]) + 1) + NOTES[tok[0].upper()] + {"-": 0, "#": 1, "b": -1}[tok[1]]
    if not 1 <= v <= 127:
        fail(n, f"note out of range: {tok}")
    return v


def compile_song(text):
    title, speed, rows, loop = "", 6, 32, 0
    instr = {}
    patterns = {}
    orders = []
    cur = None
    for n, line in enumerate(text.splitlines(), 1):
        line = re.sub(r"(^|\s)#.*", "", line).rstrip()   # (C#4 is a note)
        if not line.strip():
            continue
        w = line.split()
        key = w[0].lower()
        if key == "title":
            title = line.split(None, 1)[1][:40] if len(w) > 1 else ""
        elif key == "speed":
            speed = int(w[1])
        elif key == "rows":
            rows = int(w[1])
            if not 1 <= rows <= 64:
                fail(n, "rows: 1-64")
        elif key == "loop":
            loop = 0xFF if w[1].lower() == "none" else int(w[1])
        elif key == "instrument":
            num = int(w[1])
            if not 1 <= num <= 32:
                fail(n, "instruments are 1-32")
            ins = {"wave": 0, "vol": 15, "dur": 0, "decay": 0, "sweep": 0, "pulse": 15, "vib": 0}
            for kv in w[3:]:
                k, _, v = kv.partition("=")
                if k == "wave":
                    if v not in WAVES:
                        fail(n, f"unknown wave {v}")
                    ins[k] = WAVES[v]
                elif k == "vib":
                    ins[k] = int(v, 16)
                elif k in ins:
                    ins[k] = int(v)
                else:
                    fail(n, f"unknown key {k}")
            instr[num] = ins
            cur = None
        elif key == "pattern":
            cur = w[1]
            if cur in patterns or cur == "-":
                fail(n, f"pattern {cur} again")
            patterns[cur] = []
        elif key == "order":
            if len(w) != 4:
                fail(n, "order: three pattern names")
            orders.append((n, w[1:]))
            cur = None
        elif cur is not None:
            if w[0] == "..." and len(w) == 2 and w[1].isdigit():
                patterns[cur] += [(0, 0, 0, 0)] * int(w[1])
                continue
            nt = note(w[0], n)
            ins = 0
            eff = par = 0
            for t in w[1:]:
                if t == ".":
                    continue
                if t.isdigit():
                    ins = int(t)
                    if ins not in instr:
                        fail(n, f"instrument {ins} is not defined (yet)")
                elif t[0].upper() in EFFECTS and len(t) == 3:
                    eff, par = EFFECTS[t[0].upper()], int(t[1:], 16)
                else:
                    fail(n, f"what is {t}?")
            patterns[cur].append((nt, ins, eff, par))
        else:
            fail(n, f"what is {w[0]}?")
    names = ["-"] + list(patterns)
    for name, p in patterns.items():
        if len(p) > rows:
            sys.exit(f"pattern {name}: {len(p)} rows, more than {rows}")
    olist = []
    for n, three in orders:
        for nm in three:
            if nm not in names:
                fail(n, f"no pattern {nm}")
        olist.append([names.index(nm) for nm in three])
    if not olist:
        sys.exit("no order lines")
    if loop != 0xFF and loop >= len(olist):
        sys.exit("loop: past the last order")
    nins = max(instr) if instr else 0
    hdr_len = 16
    ord_off = hdr_len + 8 * nins
    pat_off = ord_off + 3 * len(olist)
    title_off = pat_off + 4 * rows * len(names)
    out = bytearray(b"MU") + bytes([1, speed, len(olist), loop, rows, nins, len(names), 0])
    out += bytes([ord_off & 255, ord_off >> 8, pat_off & 255, pat_off >> 8, title_off & 255, title_off >> 8])
    for i in range(1, nins + 1):
        s = instr.get(i, {"wave": 0, "vol": 0, "dur": 0, "decay": 0, "sweep": 0, "pulse": 15, "vib": 0})
        out += bytes([s["decay"], s["vol"], s["wave"], s["sweep"] & 255, s["pulse"], s["dur"], s["vib"], 0])
    for o in olist:
        out += bytes(o)
    for nm in names:
        p = patterns.get(nm, [])
        p = p + [(0, 0, 0, 0)] * (rows - len(p))
        for cell in p:
            out += bytes(cell)
    out += title.encode("ascii", "replace") + b"\0"
    return bytes(out)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    data = compile_song(open(sys.argv[1]).read())
    open(sys.argv[2], "wb").write(bytes([0x00, 0xE0]) + data)
    note_ = "" if len(data) <= 4096 else "  (more than 4K: it will not fit in one bank)"
    print(f"{sys.argv[2]}: {len(data)} bytes{note_}")
