#!/usr/bin/env python3
"""Writes images.inc: the 8 sprite images of the graphics demo (16x16, one
byte per pixel, $80 = transparent).
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
"""
T = 0x80
def blank(): return [[T] * 16 for _ in range(16)]
# A pixel is twice as wide as it is high (160x200 on a 4:3 screen), so a
# round ball is 8 pixels wide and 16 high
def ball(main, light):
    im = blank()
    for y in range(16):
        for x in range(16):
            dx, dy = (x - 7.5) * 2, y - 7.5
            if dx * dx + dy * dy <= 7.8 ** 2:
                im[y][x] = light if ((x - 6) * 2) ** 2 + (y - 5) ** 2 <= 6 else main
    im[4][6] = 15
    return im
def ellipse(cx, cy, rx, ry, c):
    im = blank()
    for y in range(16):
        for x in range(16):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1: im[y][x] = c
    return im
def cloud():
    im = blank()
    for cx, cy, r in ((5, 9, 4.5), (10, 8, 5), (8, 5, 4)):
        for y in range(16):
            for x in range(16):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r: im[y][x] = 15
    for x in range(16):
        for y in range(15, -1, -1):
            if im[y][x] != T: im[y][x] = 22; break
    return im
images = [ball(4, 12), ball(1, 9), ball(2, 10), ball(6, 14),
          ellipse(7.5, 14, 4.2, 1.6, 0),            # 4 ball shadow (SHADOW sprite)
          ball(30, 14),                              # 5 sun (STAMPed)
          cloud(),                                   # 6 cloud
          ellipse(7.5, 8, 7.5, 2.5, 0)]              # 7 cloud shadow
with open("images.inc", "w") as f:
    f.write("; made by images.py: 8 sprite images, 16x16, $80 = transparent\n")
    for n, im in enumerate(images):
        f.write(f"; image {n}\n")
        for row in im: f.write("        .byte " + ",".join(f"${c:02X}" for c in row) + "\n")
