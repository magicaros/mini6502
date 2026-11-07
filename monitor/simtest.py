"""Runs monitor.bin in py65 with mini6502-like I/O and prints the screen.
usage: simtest.py ROM [--hex file.hex]... --keys "text" [--cycles N]
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING."""
import sys, argparse
sys.path.insert(0, sys.argv.pop(1))  # py65 checkout
from py65.devices.mpu6502 import MPU
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from simvideo import Video

ap = argparse.ArgumentParser()
ap.add_argument("rom"); ap.add_argument("--hex", action="append", default=[])
ap.add_argument("--keys", default=""); ap.add_argument("--keyfile")
ap.add_argument("--cycles", type=int, default=20_000_000)
ap.add_argument("--bankhex", action="append", default=[])  # file.hex:BANK
a = ap.parse_args()

class Bus:
    def __init__(s):
        s.m = bytearray(65536); s.queue = []; s.char = 0; s.ready = False; s.out = []
        s.d = [0] * 9; s.quit = False; s.col = 0x07; s.cl = []; s.cold = int(os.environ.get("SIMCOLD", "1")); s.warm = 0
        s.g = [[32]*80 for _ in range(25)]; s.cx = 0; s.cy = 0; s.lo = 0
        s.bank = 0; s.banks = bytearray(256 * 4096); s.ext = 0; s.snd = []
        s.padr = [0, 0]; s.pstep = [1, 1]; s.dma = [0] * 12
        s.v = Video(); s.at = [[7]*80 for _ in range(25)]
        s.irqen = 0; s.irqf = 0; s.irqbank = 0; s.irqvec = 0; s.shape = [0, 0, 15, 0] * 4
        s.sndreg = [0, 15, 0, 0] * 4
        s.keysel = 0; s.held = set()        # KEYSEL / KEYHELD (SIMSCRIPT "frame H codes")
        s.keypos = 0; s.posheld = set()     # KEYPOS / POSHELD (SIMSCRIPT "frame P scancodes")
        s.caps = 1                          # KBDFLAGS bit 0 (the simulator types as given)
    def irqraise(s, bit):
        if s.irqen & bit: s.irqf |= bit
    def peek(s, a):
        if 0xE000 <= a < 0xF000: return s.banks[s.bank * 4096 + a - 0xE000]
        return s.m[a]
    def poke(s, a, v):
        if 0xE000 <= a < 0xF000: s.banks[s.bank * 4096 + a - 0xE000] = v
        else: s.m[a] = v
    def xr(s, a):
        if a >> 16 == 0xFE: return s.v.vram[a & 0xFFFF] if (a & 0xFFFF) < 64000 else 0
        if a >> 16 == 0xFD: return s.v.img[a & 0xFFFF]
        if a >> 16 == 0xFF: return s.peek(a & 0xFFFF) if not (0xD000 <= (a & 0xFFFF) < 0xE000) else 0
        return s.banks[a] if a < 0x100000 else 0
    def xw(s, a, v):
        if a >> 16 == 0xFE:
            if (a & 0xFFFF) < 64000: s.v.vram[a & 0xFFFF] = v & 0xFF
        elif a >> 16 == 0xFD: s.v.img[a & 0xFFFF] = v & 0xFF
        elif a >> 16 == 0xFF:
            c = a & 0xFFFF
            if not (0xD000 <= c < 0xE000 or c >= 0xF000): s.poke(c, v & 0xFF)
        elif a < 0x100000: s.banks[a] = v & 0xFF
    def xn(s, a, n):
        h = a >> 16
        if h in (0xFF, 0xFD): return (a & 0xFF0000) | ((a + n) & 0xFFFF)
        if h == 0xFE: return 0xFE0000 | (((a & 0xFFFF) + n) % 64000)
        return (a + n) & 0xFFFFF
    def xok(s, a): return a >> 16 in (0xFF, 0xFD) or (a >> 16 == 0xFE and (a & 0xFFFF) < 64000) or a < 0x100000
    def dmarun(s):
        d = s.dma; src = d[0] | d[1] << 8 | d[2] << 16; dst = d[3] | d[4] << 8 | d[5] << 16
        n = min(d[6] | d[7] << 8 | d[8] << 16, 0x100000)
        if d[9] == 1:
            if not (s.xok(src) and s.xok(dst)): d[11] = 2; return
            buf = []
            for i in range(n): buf.append(s.xr(src)); src = s.xn(src, 1)
            for v in buf: s.xw(dst, v); dst = s.xn(dst, 1)
        elif d[9] == 2:
            if not s.xok(dst): d[11] = 2; return
            for i in range(n): s.xw(dst, d[10]); dst = s.xn(dst, 1)
        else: d[11] = 1; return
        d[11] = 0
    def fetch(s):
        if not s.ready and s.queue:
            s.char = s.queue.pop(0); s.ext = 0
            if s.char == 0 and s.queue: s.ext = s.queue.pop(0)
            s.ready = True
    def nl(s):
        s.cx = 0; s.cy += 1
        if s.cy >= 25: s.g.pop(0); s.g.append([32]*80); s.at.pop(0); s.at.append([s.col]*80); s.cy = 24
    def put(s, v):
        c = v & 0x7F
        if c == 13: s.nl()
        elif c == 10:
            if s.lo != 13: s.nl()
        elif c == 8:
            if s.cx: s.cx -= 1; s.g[s.cy][s.cx] = 32
        elif c == 9:
            s.cx = (s.cx // 8 + 1) * 8
            if s.cx >= 80: s.nl()
        elif c == 12: s.g = [[32]*80 for _ in range(25)]; s.at = [[s.col]*80 for _ in range(25)]; s.cx = s.cy = 0
        elif 32 <= c < 127:
            s.g[s.cy][s.cx] = c; s.at[s.cy][s.cx] = s.col; s.cx += 1
            if s.cx >= 80: s.nl()
        s.lo = c
    def script(s):
        f = cpu.processorCycles // 16667
        while SCRIPT and SCRIPT[0][0] <= f:
            _, kind, arg = SCRIPT.pop(0)
            if kind == "H": s.held = set(arg); continue
            if kind == "P": s.posheld = set(arg); continue
            if kind == "W": s.v.wheel += arg[0]; continue
            if kind == "M":
                mx, my, mb = arg
                if mb & ~s.v.mouse[2]: s.irqraise(4)
                s.v.click |= mb & ~s.v.mouse[2]; s.v.mouse = [mx, my, mb]
            else: s.queue += [ord(c) for c in arg]; s.irqraise(2)
    def __getitem__(s, addr):
        if isinstance(addr, slice): return [s[i] for i in range(*addr.indices(65536))]
        if SCRIPT and (0xD500 <= addr <= 0xD50F or addr in (0xD010, 0xD011, 0xD014)): s.script()
        if addr == 0xD010: s.ready = False; return s.char | 0x80
        if addr == 0xD011:
            s.fetch()
            return 0x80 if s.ready else 0
        if addr == 0xD019: return s.ext
        if 0xD040 <= addr <= 0xD048: return s.d[addr - 0xD040]
        if addr == 0xD014:
            s.fetch()
            return s.char | 0x80 if s.ready else 0
        if addr == 0xD021: return s.col
        if 0xD300 <= addr <= 0xD33F: return s.v.read(addr - 0xD300, cpu.processorCycles // 16667)
        if 0xD400 <= addr <= 0xD4FF: return s.v.spr[addr - 0xD400]
        if 0xD500 <= addr <= 0xD553: return s.v.mread(addr - 0xD500)
        if addr == 0xD018: return s.at[s.cy][s.cx]
        if 0xD200 <= addr <= 0xD20C and (addr & 7) <= 4:
            p, r = (addr - 0xD200) >> 3, addr & 7
            if r < 3: return (s.padr[p] >> (8 * r)) & 0xFF
            if r == 4: return s.pstep[p]
            v = s.xr(s.padr[p]); s.padr[p] = s.xn(s.padr[p], s.pstep[p]); return v
        if 0xD210 <= addr <= 0xD21B: return s.dma[addr - 0xD210]
        if addr == 0xD020: return s.bank
        if 0xE000 <= addr < 0xF000: return s.banks[s.bank * 4096 + addr - 0xE000]
        if addr == 0xD000: f = s.cold; s.cold = 0; return f
        if addr == 0xD007: return s.irqen
        if addr == 0xD01A: return s.keysel
        if addr == 0xD01C: return s.keypos
        if addr == 0xD01E: return s.caps
        if addr == 0xD01D:
            if SCRIPT: s.script()
            return 1 if s.keypos in s.posheld else 0
        if addr == 0xD01B:
            if SCRIPT: s.script()
            return 1 if s.keysel in s.held else 0
        if addr == 0xD008: f = s.irqf; s.irqf = 0; return f
        if addr == 0xD009: return s.irqbank
        if addr == 0xD00A: return s.irqvec & 255
        if addr == 0xD00B: return s.irqvec >> 8
        if 0xD050 <= addr <= 0xD05F: return s.shape[addr - 0xD050]
        if 0xD030 <= addr <= 0xD03F: return s.sndreg[addr - 0xD030]
        if addr == 0xD100: return 0                      # BEEP: (no beep sounding)
        if addr == 0xD001: return (cpu.processorCycles // 16667) & 255
        if 0xD004 <= addr <= 0xD006:
            sec = 12 * 3600 + 34 * 60 + cpu.processorCycles // 1000000   # 12:34:00 at power-on
            return (sec // 3600 % 24, sec // 60 % 60, sec % 60)[addr - 0xD004]
        if addr == 0xD002: return s.warm & 255
        if addr == 0xD003: return s.warm >> 8
        if addr == 0xD015: return s.cx
        if addr == 0xD016: return s.cy
        if addr == 0xD017: return s.g[s.cy][s.cx]
        if 0xD000 <= addr <= 0xDFFF: return 0
        return s.m[addr]
    def __setitem__(s, addr, v):
        if isinstance(addr, slice):
            for i, x in zip(range(*addr.indices(65536)), v): s[i] = x
            return
        if addr == 0xD012: s.out.append(v & 0x7F); s.cl.append((chr(v & 0x7F), s.col)); s.put(v); return
        if addr == 0xD015: s.cx = min(v, 79); s.lo = 0; return
        if addr == 0xD016: s.cy = min(v, 24); s.lo = 0; return
        if addr == 0xD017: s.g[s.cy][s.cx] = v; return
        if addr == 0xD021: s.col = v & 0xFF; return
        if addr == 0xD018: s.at[s.cy][s.cx] = v & 0xFF; return
        if 0xD300 <= addr <= 0xD33F: s.v.write(addr - 0xD300, v); return
        if 0xD400 <= addr <= 0xD4FF: s.v.spr[addr - 0xD400] = v & 0xFF; return
        if 0xD500 <= addr <= 0xD54F: s.v.mwrite(addr - 0xD500, v); return
        if 0xD200 <= addr <= 0xD20C and (addr & 7) <= 4:
            p, r = (addr - 0xD200) >> 3, addr & 7
            if r < 3: s.padr[p] = (s.padr[p] & ~(0xFF << (8 * r))) | (v << (8 * r))
            elif r == 4: s.pstep[p] = v
            else: s.xw(s.padr[p], v); s.padr[p] = s.xn(s.padr[p], s.pstep[p])
            return
        if 0xD210 <= addr <= 0xD21B:
            s.dma[addr - 0xD210] = v & 0xFF
            if addr == 0xD219: s.dmarun()
            return
        if 0xD030 <= addr <= 0xD03F:
            if os.environ.get("SIMSND"):
                s.snd.append((cpu.processorCycles // 16667, (addr - 0xD030) // 4, "NVWD"[(addr - 0xD030) % 4], v))
            s.sndreg[addr - 0xD030] = (v & 127) if (addr & 3) == 0 else v & 255
            return
        if addr == 0xD100: return                        # BEEP (silent here)
        if 0xD050 <= addr <= 0xD05F:
            s.shape[addr - 0xD050] = v & 255
            if os.environ.get("SIMSND"): s.snd.append((cpu.processorCycles // 16667, (addr - 0xD050) // 4, "dspb"[(addr - 0xD050) % 4], v))
            return
        if addr == 0xD007: s.irqen = v & 7; s.irqf &= s.irqen; return
        if addr == 0xD01A: s.keysel = v & 255; return
        if addr == 0xD01C: s.keypos = v & 255; return
        if addr == 0xD01E: s.caps = v & 1; return
        if addr == 0xD009: s.irqbank = v & 255; return
        if addr == 0xD00A: s.irqvec = (s.irqvec & 0xFF00) | (v & 255); return
        if addr == 0xD00B: s.irqvec = (s.irqvec & 255) | (v & 255) << 8; return
        if addr == 0xD020: s.bank = v & 0xFF; return
        if 0xE000 <= addr < 0xF000: s.banks[s.bank * 4096 + addr - 0xE000] = v & 0xFF; return
        if addr == 0xD002: s.warm = (s.warm & 0xFF00) | v; return
        if addr == 0xD003: s.warm = (s.warm & 0xFF) | v << 8; return
        if addr == 0xD000 and v == 1: s.quit = True; return
        if addr == 0xD000 and v == 2: s.out.append(12); s.put(12); return
        if addr == 0xD000 and v == 3:
            s.v.reset(); s.irqen = s.irqf = s.irqbank = s.irqvec = 0; s.shape = [0, 0, 15, 0] * 4
            s.sndreg = [0, 15, 0, 0] * 4; return
        if addr == 0xD040: s.d[0] = v; s.d[1] = disk(s, v); return
        if 0xD041 <= addr <= 0xD048: s.d[addr - 0xD040] = v & 0xFF; return
        if 0xD000 <= addr <= 0xDFFF or addr >= 0xF000: return
        s.m[addr] = v & 0xFF
    def __len__(s): return 65536

import os, re
DISK = os.environ.get("SIMDISK", "simdisk"); os.makedirs(DISK, exist_ok=True)
CUR = []    # the current folder: [], [A] or [A, B] (as the host's curdir)
NAMEOK = re.compile(r"[A-Za-z0-9._-]{1,64}")
def okname(x): return bool(NAMEOK.fullmatch(x)) and x not in (".", "..")
def real(parts): return os.path.join(DISK, *parts)
def findin(parts, nm, kind):     # kind 1 file, 2 folder: its real name or None
    for v in (nm, nm.upper(), nm.lower()):
        p = real(parts + [v])
        if (os.path.isfile(p) if kind == 1 else os.path.isdir(p)): return v
    return None
def resolve(raw):                # -> (status, folder parts, last name)
    if raw.startswith("/"): parts, rest = [], raw[1:]
    else: parts, rest = list(CUR), raw
    bits = rest.split("/")
    for x in bits[:-1]:
        if not okname(x): return 2, None, None
        if len(parts) >= 2: return 7, None, None
        r = findin(parts, x, 2)
        if not r: return 1, None, None
        parts.append(r)
    if not okname(bits[-1]): return 2, None, None
    return 0, parts, bits[-1]
def listing():
    d = real(CUR)
    if not os.path.isdir(d): CUR.clear(); d = real(CUR)
    es = os.listdir(d)
    return (sorted(x for x in es if os.path.isdir(os.path.join(d, x)) and okname(x)),
            sorted(x for x in es if os.path.isfile(os.path.join(d, x))))
def disk(b, cmd):
    w = lambda i: b.d[i] | b.d[i + 1] << 8
    def setw(i, v): b.d[i] = v & 0xFF; b.d[i + 1] = (v >> 8) & 0xFF
    def mstr(a, n=0):
        t = ""
        while len(t) <= 200:
            if n and len(t) >= n: break
            c = b.peek((a + len(t)) & 0xFFFF)
            if not n and c in (0, 13): break
            t += chr(c)
        return t
    def put(st, data):
        for i, x in enumerate(data): b.poke(st + i, x)
    raw = mstr(w(6), b.d[8])
    if cmd == 7:
        fo, fi = listing()
        recs = b"".join(x.encode() + bytes([0, 0xFE, 0xFF, 0xFF, 0, 0]) for x in fo)
        for f in fi:
            data = open(real(CUR + [f]), "rb").read()
            sz = len(data) - 2 if len(data) >= 2 else 0xFFFFFF
            recs += f.encode() + bytes([0, sz & 255, (sz >> 8) & 255, (sz >> 16) & 255]) + (data[:2] if len(data) >= 2 else b"\0\0")
        recs += b"\0"; st, lim = w(2), w(4) or 0xD000
        if st + len(recs) > lim: return 3
        put(st, recs); setw(4, st + len(recs)); return 0
    if cmd == 4:
        fo, fi = listing()
        txt = (f"Folder /{'/'.join(CUR)}\r" if CUR else "") + "".join(f"{x:24}  (folder)\r" for x in fo)
        for f in fi:
            data = open(real(CUR + [f]), "rb").read()
            txt += f"{f:24}{len(data)-2:6} bytes at ${data[0]|data[1]<<8:04X}\r"
        b.out += [ord(c) for c in txt]; return 0
    if cmd == 13:
        t = ("/" + "/".join(CUR)).encode() + b"\0"
        put(w(2), t); setw(4, w(2) + len(t)); return 0
    if cmd == 9:
        if raw in ("", "/"): CUR.clear(); return 0
        if raw == "..":
            if CUR: CUR.pop()
            return 0
        st, parts, nm = resolve(raw.rstrip("/"))
        if st: return st
        r = findin(parts, nm, 2)
        if not r: return 1
        if len(parts) >= 2: return 7
        CUR[:] = parts + [r]; return 0
    st, parts, nm = resolve(raw)
    if st and not (st == 1 and cmd in (1, 3)): return st
    def dest():
        s2, p2, n2 = resolve(mstr(w(2)))
        if s2: return s2, None
        if findin(p2, n2, 1) or findin(p2, n2, 2): return 4, None
        return 0, real(p2 + [n2])
    if cmd == 10:
        if len(parts) >= 2: return 7
        if findin(parts, nm, 1) or findin(parts, nm, 2): return 4
        os.mkdir(real(parts + [nm])); return 0
    if cmd == 11:
        r = findin(parts, nm, 2)
        if not r: return 1
        if os.listdir(real(parts + [r])): return 4
        os.rmdir(real(parts + [r]))
        if CUR[:len(parts) + 1] == parts + [r]: CUR[:] = parts
        return 0
    if cmd == 2:
        if findin(parts, nm, 2): return 4
        s0, en = w(2), w(4) or 0x10000
        if en <= s0: return 6
        r = findin(parts, nm, 1) or nm
        open(real(parts + [r]), "wb").write(bytes([s0 & 255, s0 >> 8]) + bytes(b.peek(i) for i in range(s0, en)))
        return 0
    path = None
    if not st:
        r = findin(parts, nm, 1)
        if r: path = real(parts + [r])
    if cmd in (1, 3):
        if not path and CUR and "/" not in raw:     # the top of the disk
            nm2 = raw if okname(raw) else None
            r = nm2 and findin([], nm2, 1)
            if r: path = real([r])
        if not path: return 1
        data = open(path, "rb").read()
        addr = w(2) if cmd == 3 else data[0] | data[1] << 8
        body = data[2:]; lim = w(4) or 0x10000
        if addr + len(body) > lim: return 3
        for i, x in enumerate(body):
            ad = addr + i
            if not (0xD000 <= ad <= 0xDFFF or ad >= 0xF000): b.poke(ad, x)
        setw(2, addr); setw(4, addr + len(body)); return 0
    if cmd == 8:
        if not path:
            r = findin(parts, nm, 2)
            if not r: return 1
            if "/" in mstr(w(2)): return 2
            path = real(parts + [r])
        s2, d = dest()
        if s2: return s2
        os.rename(path, d); return 0
    if not path: return 1
    if cmd == 5:
        os.remove(path); return 0
    if cmd == 6:
        data = open(path, "rb").read()
        if len(data) >= 2 and any(c < 32 and c not in (9, 10, 13) for c in data[:2]): data = data[2:]
        t = data.decode("latin-1").replace("\r\n", "\r").replace("\n", "\r").replace("\t", " ")
        b.queue += [ord(c) for c in t if c == "\r" or 32 <= ord(c) < 127]
        return 0
    if cmd == 12:
        s2, d = dest()
        if s2: return s2
        open(d, "wb").write(open(path, "rb").read()); return 0
    return 5

SCRIPT = []   # SIMSCRIPT file: "frame M x y buttons", "frame W steps" or "frame K text" (\r = Enter)
if os.environ.get("SIMSCRIPT"):
    for ln in open(os.environ["SIMSCRIPT"]):
        p = ln.split(None, 2)
        if len(p) < 3 or ln.startswith("#"): continue
        if p[1] in ("H", "P", "W"): SCRIPT.append((int(p[0]), p[1], tuple(int(q) for q in p[2].split()))); continue
        if p[1] == "M": SCRIPT.append((int(p[0]), "M", tuple(int(q) for q in p[2].split())))
        else: SCRIPT.append((int(p[0]), "K", p[2].rstrip("\n").encode().decode("unicode_escape")))
    SCRIPT.sort(key=lambda e: e[0])
bus = Bus()
if os.environ.get("SIMMOUSE"):
    mx, my, mb = (int(q) for q in os.environ["SIMMOUSE"].split(","))
    bus.v.mouse = [mx, my, mb]; bus.v.click = mb
rom = open(a.rom, "rb").read(); bus.m[0x10000 - len(rom):] = rom
for h in a.hex:
    for ln in open(h):
        if ":" not in ln: continue
        ad, bs = ln.split(":", 1); ad = int(ad, 16)
        for t in bs.split(): bus.m[ad] = int(t, 16); ad += 1
for bh in a.bankhex:
    f, bk = bh.split(":"); bk = int(bk, 16)
    for ln in open(f):
        if ":" not in ln: continue
        ad, bs = ln.split(":", 1); ad = int(ad, 16)
        for t in bs.split(): bus.banks[bk * 4096 + ad - 0xE000] = int(t, 16); ad += 1
raw = a.keys.encode().decode("unicode_escape"); keys = ""
i = 0
while i < len(raw):                      # \0 + code = extended key (kept as is)
    if raw[i] == "\0" and i + 1 < len(raw): keys += raw[i:i+2]; i += 2
    else: keys += "\r" if raw[i] == "\n" else raw[i]; i += 1
if a.keyfile: keys += open(a.keyfile).read().replace("\r\n", "\r").replace("\n", "\r")
bus.queue = [ord(c) for c in keys]

cpu = MPU(memory=bus)
cpu.pc = bus.m[0xFFFC] | bus.m[0xFFFD] << 8
idle = 0; lastfr = 0
TRACE = os.environ.get("SIMTRACE")      # "lo-hi": stop when PC enters this range
ring = []
if TRACE:
    tr, tbk = (TRACE.split(":") + [""])[:2]
    tlo, thi = (int(q, 16) for q in tr.split("-")); tbk = int(tbk, 16) if tbk else None
while cpu.processorCycles < a.cycles and not bus.quit:
    if TRACE:
        ring.append((cpu.pc, bus.bank, cpu.a, cpu.x, cpu.y, cpu.sp)); ring = ring[-40:]
        if tlo <= cpu.pc <= thi and (tbk is None or bus.bank == tbk):
            for e in ring: print("PC=%04X bank=%02X A=%02X X=%02X Y=%02X S=%02X" % e)
            break
    fr = cpu.processorCycles // 16667
    if fr != lastfr: lastfr = fr; bus.irqraise(1)
    if bus.irqf & bus.irqen: cpu.irq()
    cpu.step()
    if not bus.queue and not bus.ready and not SCRIPT:
        idle += 1
        if idle > int(os.environ.get("SIMIDLE", "200000")): break
# render like the mini6502 terminal (CR newline, LF ignored after CR, BS)
lines = [[]]; last = 0
for c in bus.out:
    if c == 13: lines.append([])
    elif c == 10:
        if last != 13: lines.append([])
    elif c == 8:
        if lines[-1]: lines[-1].pop()
    elif c == 7: lines[-1].append("<BEL>")
    elif c == 12: lines = lines + [["<CLS>"], []] if os.environ.get("SIMKEEP") else [["<CLS>"], []]
    elif 32 <= c < 127: lines[-1].append(chr(c))
    last = c
print("\n".join("".join(l) for l in lines))
print(f"-- PC=${cpu.pc:04X} cycles={cpu.processorCycles}")
if os.environ.get("SIMSCREEN"):
    print("+" + "-" * 80 + "+")
    for row in bus.g: print("|" + "".join(chr(c) if 32 <= c < 127 else "#" for c in row) + "|")
    print("+" + "-" * 80 + "+")
if os.environ.get("SIMDUMP"):            # "lo-hi": memory shown in hex
    lo, hi = (int(q, 16) for q in os.environ["SIMDUMP"].split("-"))
    print(" ".join(f"{bus.peek(i):02X}" for i in range(lo, hi + 1)))
if os.environ.get("SIMPNG"): bus.v.png(os.environ["SIMPNG"], bus.g, bus.at)
if os.environ.get("SIMSND"):
    import json; json.dump(bus.snd, open(os.environ["SIMSND"], "w"))
if os.environ.get("SIMCOLOR"):
    print(" ".join(f"{c}{k:02X}" for c, k in bus.cl if c.isprintable()))
