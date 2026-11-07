"""mini6502 graphics for simtest.py: the same registers, blitter, sprites and
collisions as mini6502.bas, plus a PNG of the picture (SIMPNG=file.png).
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING."""
W, H, PAGE, NSPR = 160, 200, 32000, 32
HW, HH = 640, 400
ARROW_M = "C000E000F000F800FC00FE00FF00FF80FFC0FE00EF00CF000780078003000000"
ARROW_I = "000040006000700078007C007E007F007C006C00460006000300030000000000"
def _font():
    """8x16 glyphs (rough: PIL's default font) - only for the simulator."""
    from PIL import Image, ImageDraw, ImageFont
    f = ImageFont.load_default(); bits = bytearray(4096)
    for c in range(32, 127):
        im = Image.new("1", (8, 16)); ImageDraw.Draw(im).text((1, 2), chr(c), fill=1, font=f)
        for r in range(16):
            bits[c * 16 + r] = sum(128 >> k for k in range(8) if im.getpixel((k, r)))
    return bits
FONT = _font()
RGB = ("000000 0000AA 00AA00 00AAAA AA0000 AA00AA AA5500 AAAAAA "
       "555555 5555FF 55FF55 55FFFF FF5555 FF55FF FFFF55 FFFFFF "
       "202020 404040 606060 808080 A0A0A0 C0C0C0 E0E0E0 FF8000 "
       "FFC090 804000 006000 80C0FF 000060 800040 FFC000 C080FF").split()

class Video:
    def __init__(v):
        v.vram = bytearray(2 * PAGE); v.img = bytearray(65536); v.reset()
    def reset(v):
        v.reg = [0] * 16; v.reg[3] = 8; v.reg[4] = 16; v.reg[7] = 15
        v.h = [0] * 24; v.h[8:16] = [0xAA, 0x55] * 4; v.h[20:24] = [0x7F, 2, 0x8F, 1]
        v.p = [0] * 0x50
        for i in range(32): v.p[0x30 + i] = int(ARROW_M[i*2:i*2+2], 16); v.p[0x10 + i] = int(ARROW_I[i*2:i*2+2], 16)
        if not hasattr(v, "mouse"): v.mouse = [0, 0, 0]; v.wheel = 0; v.click = 0
        v.blt = [0] * 16; v.coll = [0] * 8; v.spr = [0] * 256; v.last = -1
        v.pal = [[int(c[i:i + 2], 16) for i in (0, 2, 4)] for c in RGB]

    # --- registers ($D300 + reg) -----------------------------------------------
    def read(v, reg, frame):
        if reg in (9, 10, 11): return v.pal[v.reg[8]][reg - 9]
        if reg < 16: return v.reg[reg]
        if reg == 0x19 and v.reg[0] >= 3:
            x, y = v.blt[0] + 256 * v.blt[10], v.blt[1] + 256 * v.blt[11]
            return v.hget((v.reg[2] & 1) * PAGE, x, y) if x < HW and y < HH else 0
        if reg == 0x19:
            x, y = v.blt[0], v.blt[1]
            return v.vram[(v.reg[2] & 1) * PAGE + y * W + x] if x < W and y < H else 0
        if 0x10 <= reg <= 0x1F: return v.blt[reg - 0x10]
        if 0x28 <= reg <= 0x3F: return v.h[reg - 0x28]
        if 0x20 <= reg <= 0x27:
            if frame != v.last: v.frame(); v.last = frame
            r = v.coll[reg - 0x20]; v.coll[reg - 0x20] = 0; return r
        return 0
    def write(v, reg, x):
        x &= 255
        if reg == 0: v.reg[0] = x if x <= 4 else 0
        elif reg in (1, 2): v.reg[reg] = x & 1
        elif reg == 3: v.reg[3] = x & 31
        elif reg == 4: v.reg[4] = min(x, 16)
        elif reg == 5: v.reg[5] = x & 15
        elif reg in (6, 7, 8): v.reg[reg] = x & 31
        elif reg in (9, 10): v.pal[v.reg[8]][reg - 9] = x
        elif reg == 11: v.pal[v.reg[8]][2] = x; v.reg[8] = (v.reg[8] + 1) & 31
        elif 0x10 <= reg <= 0x17 or 0x1A <= reg <= 0x1F: v.blt[reg - 0x10] = x
        elif reg == 0x18: v.blt[8] = x; v.blit()
        elif 0x28 <= reg <= 0x3F:
            v.h[reg - 0x28] = x
            if reg == 0x2C: v.h[2] = x; v.hchar()

    # --- mouse ($D500 + r) -------------------------------------------------------
    def mread(v, r):
        mx, my, b = v.mouse
        if r < 4: return ((mx, my)[r // 2] >> (8 * (r & 1))) & 255
        if r == 4: return b
        if r == 5: w = v.wheel & 255; v.wheel = 0; return w
        if r == 6: c = v.click; v.click = 0; return c
        if 0x50 <= r <= 0x53: return (mx // 4, my // 2, mx // 8, my // 16)[r - 0x50]
        if 9 <= r <= 12 and v.p[8] & 2: return ((mx, my)[(r - 9) // 2] >> (8 * ((r - 9) & 1))) & 255
        return v.p[r]
    def mwrite(v, r, x):
        if r >= 8: v.p[r] = x & 255

    # --- hires ---------------------------------------------------------------------
    def hget(v, p, x, y): return 1 if v.vram[p + y * 80 + x // 8] & (128 >> (x & 7)) else 0
    def clip(v):
        h = v.h; v.cl = (h[16] + 256 * h[17], h[18] + 256 * h[19], min(h[20] + 256 * h[21], HW - 1), min(h[22] + 256 * h[23], HH - 1))
    def hplot(v, p, x, y, s):
        x0, y0, x1, y1 = v.cl
        if not (x0 <= x <= x1 and y0 <= y <= y1): return
        i = p + y * 80 + x // 8; m = 128 >> (x & 7); d = 1 if v.vram[i] & m else 0
        r = {1: d | s, 2: d & s, 3: d ^ s, 4: 1 - d, 5: d & (1 - s)}.get(v.h[0], s)
        v.vram[i] = v.vram[i] | m if r else v.vram[i] & (255 - m)
    def hsrc(v, x, y):
        if v.h[1] & 1: return 1 if v.h[8 + (y & 7)] & (128 >> (x & 7)) else 0
        return v.blt[4] & 1
    def hblit(v):
        b = v.blt
        x0, y0, x1, y1 = b[0] + 256 * b[10], b[1] + 256 * b[11], b[2] + 256 * b[12], b[3] + 256 * b[13]
        dx, dy, c, cmd = b[5] + 256 * b[14], b[6] + 256 * b[15], b[4], b[8]
        p = (v.reg[2] & 1) * PAGE; sp = (b[7] & 1) * PAGE; v.clip()
        if cmd == 1:
            if not v.h[1] & 1 and v.h[0] == 0: v.vram[p:p + PAGE] = bytes([255 if c & 1 else 0]) * PAGE
            else:
                v.cl = (0, 0, HW - 1, HH - 1)
                for y in range(HH):
                    for x in range(HW): v.hplot(p, x, y, v.hsrc(x, y))
        elif cmd == 2: v.hplot(p, x0, y0, v.hsrc(x0, y0))
        elif cmd == 3:
            ex, sx = abs(x1 - x0), (x1 > x0) - (x1 < x0)
            ey, sy = -abs(y1 - y0), (y1 > y0) - (y1 < y0)
            er, x, y = ex + ey, x0, y0
            while True:
                v.hplot(p, x, y, v.hsrc(x, y))
                if x == x1 and y == y1: break
                e2 = 2 * er
                if e2 >= ey: er += ey; x += sx
                if e2 <= ex: er += ex; y += sy
        elif cmd == 4:
            x0, x1 = sorted((x0, x1)); y0, y1 = sorted((y0, y1))
            for x in range(x0, x1 + 1):
                v.hplot(p, x, y0, v.hsrc(x, y0))
                if y1 != y0: v.hplot(p, x, y1, v.hsrc(x, y1))
            for y in range(y0 + 1, y1):
                v.hplot(p, x0, y, v.hsrc(x0, y))
                if x1 != x0: v.hplot(p, x1, y, v.hsrc(x1, y))
        elif cmd == 5:
            x0, x1 = sorted((x0, x1)); y0, y1 = sorted((y0, y1))
            cx0, cy0, cx1, cy1 = v.cl
            for y in range(max(y0, cy0), min(y1, cy1) + 1):
                for x in range(max(x0, cx0), min(x1, cx1) + 1): v.hplot(p, x, y, v.hsrc(x, y))
        elif cmd in (6, 7):
            x0, x1 = sorted((x0, x1)); y0, y1 = sorted((y0, y1))
            if x0 >= HW or y0 >= HH: return
            x1, y1 = min(x1, HW - 1), min(y1, HH - 1)
            buf = [[v.hget(sp, x, y) for x in range(x0, x1 + 1)] for y in range(y0, y1 + 1)]
            for y, row in enumerate(buf):
                for x, s in enumerate(row):
                    if cmd == 6 or s: v.hplot(p, dx + x, dy + y, s)
        elif cmd == 10:
            for y in range(16):
                for x in range(16):
                    q = v.img[c * 256 + y * 16 + x]
                    if not q & 128: v.hplot(p, x0 + x, y0 + y, q & 1)
        elif cmd == 11: v.hchar()
    def hchar(v):
        if v.reg[0] < 3: return
        b = v.blt; x0, y0 = b[0] + 256 * b[10], b[1] + 256 * b[11]; st = v.h[3]
        p = (v.reg[2] & 1) * PAGE; v.clip()
        for r in range(16):
            g = FONT[v.h[2] * 16 + r]
            if st & 1: g |= g >> 1
            if st & 2 and r == 14: g = 255
            if st & 8: g = 255 - g
            sh = (15 - r) // 4 if st & 4 else 0
            for k in range(8):
                if g & (128 >> k): v.hplot(p, x0 + k + sh, y0 + r, 1)
                elif st & 16: v.hplot(p, x0 + k + sh, y0 + r, 0)
        x0 += 8; b[0] = x0 & 255; b[10] = (x0 >> 8) & 255

    # --- blitter -----------------------------------------------------------------
    def plot(v, p, x, y, c):
        if 0 <= x < W and 0 <= y < H: v.vram[p + y * W + x] = c
    @staticmethod
    def rect(x0, y0, x1, y1):
        x0, x1 = sorted((x0, x1)); y0, y1 = sorted((y0, y1))
        if x0 >= W or y0 >= H: return None
        return x0, y0, min(x1, W - 1), min(y1, H - 1)
    def blit(v):
        if v.reg[0] >= 3: return v.hblit()
        x0, y0, x1, y1, c, dx, dy, sp, cmd = v.blt[:9]
        p = (v.reg[2] & 1) * PAGE; sp = (sp & 1) * PAGE
        if cmd == 1: v.vram[p:p + PAGE] = bytes([c]) * PAGE
        elif cmd == 2: v.plot(p, x0, y0, c)
        elif cmd == 3:
            ex, sx = abs(x1 - x0), (x1 > x0) - (x1 < x0)
            ey, sy = -abs(y1 - y0), (y1 > y0) - (y1 < y0)
            er, x, y = ex + ey, x0, y0
            while True:
                v.plot(p, x, y, c)
                if x == x1 and y == y1: break
                e2 = 2 * er
                if e2 >= ey: er += ey; x += sx
                if e2 <= ex: er += ex; y += sy
        elif cmd == 4:
            x0, x1 = sorted((x0, x1)); y0, y1 = sorted((y0, y1))
            for x in range(x0, x1 + 1): v.plot(p, x, y0, c); v.plot(p, x, y1, c)
            for y in range(y0, y1 + 1): v.plot(p, x0, y, c); v.plot(p, x1, y, c)
        elif cmd in (5, 8, 9):
            r = v.rect(x0, y0, x1, y1)
            if not r: return
            x0, y0, x1, y1 = r
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    i = p + y * W + x
                    v.vram[i] = c if cmd == 5 else (v.vram[i] | 32 if cmd == 8 else v.vram[i] & ~32)
        elif cmd in (6, 7):
            r = v.rect(x0, y0, x1, y1)
            if not r: return
            x0, y0, x1, y1 = r
            buf = [[v.vram[sp + y * W + x] for x in range(x0, x1 + 1)] for y in range(y0, y1 + 1)]
            for y, row in enumerate(buf):
                for x, px in enumerate(row):
                    if cmd == 6 or not px & 128: v.plot(p, dx + x, dy + y, px)
        elif cmd == 10:
            for y in range(16):
                for x in range(16):
                    px = v.img[c * 256 + y * 16 + x]
                    if not px & 128: v.plot(p, x0 + x, y0 + y, px)

    # --- one frame: sprites and collisions ---------------------------------------
    def frame(v):
        """Returns the colour numbers (0-63) of the picture; sets collisions."""
        if v.reg[0] == 0 or v.reg[0] >= 3: return None
        base = (v.reg[1] & 1) * PAGE
        idx = bytearray(c & 63 for c in v.vram[base:base + PAGE]); owner = {}
        def coll(k, n): v.coll[k + n // 8] |= 1 << (n % 8)
        for n in range(NSPR - 1, -1, -1):
            sx, sy, im, f = v.spr[n * 8:n * 8 + 4]
            if not f & 1: continue
            sx -= 16; sy -= 16; im *= 256; sz = 2 if f & 8 else 1
            for py in range(16 * sz):
                y = sy + py
                if not 0 <= y < H: continue
                iy = py // sz
                if f & 4: iy = 15 - iy
                for px in range(16 * sz):
                    x = sx + px
                    if not 0 <= x < W: continue
                    ix = px // sz
                    if f & 2: ix = 15 - ix
                    c = v.img[im + iy * 16 + ix]
                    if c & 128: continue
                    i = y * W + x
                    if f & 32: idx[i] |= 32; continue
                    bg = v.vram[base + i] & 31
                    if bg: coll(4, n)
                    if i in owner: coll(0, n); coll(0, owner[i])
                    owner[i] = n
                    if not f & 16 or not bg: idx[i] = c & 63
        return idx
    def rgb(v, k):
        r, g, b = v.pal[k & 31]
        if k & 32:
            s = v.reg[3]; r, g, b = (min(255, q * s // 16) for q in (r, g, b))
        s = v.reg[4]; return tuple(q * s // 16 for q in (r, g, b))

    def png(v, path, text, attrs):
        from PIL import Image, ImageDraw
        im = Image.new("RGB", (640, 400))
        idx = v.frame()
        if idx is not None:
            g = Image.new("RGB", (W, H)); g.putdata([v.rgb(k) for k in idx])
            im = g.resize((640, 400), Image.NEAREST)
        col = lambda n: tuple(q * v.reg[4] // 16 for q in v.pal[n])
        if v.reg[0] >= 3:
            p = (v.reg[1] & 1) * PAGE; ink, paper = col(v.reg[6]), col(v.reg[7])
            im.putdata([ink if v.hget(p, x, y) else paper for y in range(HH) for x in range(HW)])
        if v.reg[0] in (0, 2, 4):
            d = ImageDraw.Draw(im)
            for y in range(25):
                for x in range(80):
                    a = attrs[y][x]; ch = text[y][x]
                    if not (v.reg[0] in (2, 4) and a >> 4 == v.reg[5]):
                        d.rectangle([x * 8, y * 16, x * 8 + 7, y * 16 + 15], fill="#" + RGB[a >> 4])
                    if 32 < ch < 127: d.text((x * 8, y * 16 + 2), chr(ch), fill="#" + RGB[a & 15])
        if v.p[8] & 1:
            ink = tuple(v.pal[v.reg[6]]); paper = tuple(v.pal[v.reg[7]])
            px = v.mread(9) + 256 * v.mread(10) - v.p[13]; py = v.mread(11) + 256 * v.mread(12) - v.p[14]
            for r in range(16):
                m = v.p[0x30 + 2 * r] << 8 | v.p[0x31 + 2 * r]; b = v.p[0x10 + 2 * r] << 8 | v.p[0x11 + 2 * r]
                for k in range(16):
                    if m & (0x8000 >> k) and 0 <= px + k < HW and 0 <= py + r < HH:
                        im.putpixel((px + k, py + r), ink if b & (0x8000 >> k) else paper)
        im.save(path)
