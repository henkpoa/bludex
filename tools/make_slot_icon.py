#!/usr/bin/env python3
"""Generate icons/ui/slot-empty-64.png -- the empty-slot ring for the Sets
grid: a soft blue-grey circle sized against the 64px spell halos, nothing
inside it. Pure stdlib (zlib + struct); no PIL dependency.

Run from anywhere:  python bludex/tools/make_slot_icon.py
"""
import os
import struct
import zlib

SIZE = 64
CX = CY = (SIZE - 1) / 2.0
RADIUS = 26.0        # ring radius -- visually matches the spell halo circles
HALF_T = 1.6         # ring half-thickness in pixels
SOFT = 1.4           # anti-alias falloff beyond the ring edge
COLOR = (140, 168, 205)   # soft blue-grey, sits quietly on the navy theme
ALPHA = 110               # peak alpha; the UI tints it further


def chunk(tag, data):
    raw = tag + data
    return struct.pack('>I', len(data)) + raw + struct.pack('>I', zlib.crc32(raw) & 0xFFFFFFFF)


rows = []
for y in range(SIZE):
    row = bytearray([0])                       # PNG filter type 0 per scanline
    for x in range(SIZE):
        d = ((x - CX) ** 2 + (y - CY) ** 2) ** 0.5
        t = abs(d - RADIUS) - HALF_T
        cover = 1.0 if t <= 0 else max(0.0, 1.0 - t / SOFT)
        row += bytes((*COLOR, int(ALPHA * cover)))
    rows.append(bytes(row))

ihdr = struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0)   # 8-bit RGBA
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', ihdr)
       + chunk(b'IDAT', zlib.compress(b''.join(rows), 9))
       + chunk(b'IEND', b''))

out = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'icons', 'ui', 'slot-empty-64.png'))
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'wb') as f:
    f.write(png)
print('wrote %s (%d bytes)' % (out, len(png)))
