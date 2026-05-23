#!/usr/bin/env python3
"""Generate a simple gradient app icon (512x512 PNG) for 任务板."""
import struct, zlib, math, os

SIZE = 512
CORNER = SIZE * 0.22  # rounded corner radius

def lerp(a, b, t): return a + (b - a) * t

def pixel(x, y):
    # Diagonal gradient: purple (#b07fd4) → sky blue (#7bb8e8)
    t = (x + y) / (SIZE * 2)
    r = int(lerp(176, 123, t))
    g = int(lerp(127, 184, t))
    b = int(lerp(212, 232, t))

    # Rounded rect mask
    cx, cy = SIZE / 2, SIZE / 2
    dx = abs(x - cx)
    dy = abs(y - cy)
    inner_x = cx - CORNER
    inner_y = cy - CORNER
    if dx > inner_x and dy > inner_y:
        dist = math.hypot(dx - inner_x, dy - inner_y)
        if dist > CORNER:
            return (0, 0, 0, 0)

    # Subtle inner highlight at top-left
    glow = max(0, 1 - math.hypot(x - SIZE*0.25, y - SIZE*0.2) / (SIZE * 0.4))
    r = min(255, r + int(glow * 30))
    g = min(255, g + int(glow * 20))
    b = min(255, b + int(glow * 15))

    return (r, g, b, 255)

# Build raw image data
rows = []
for y in range(SIZE):
    row = bytearray([0])  # filter = None
    for x in range(SIZE):
        row.extend(pixel(x, y))
    rows.append(bytes(row))

raw = b''.join(rows)
compressed = zlib.compress(raw, 9)

def chunk(tag, data):
    c = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', c)

png = (
    b'\x89PNG\r\n\x1a\n'
    + chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0))
    + chunk(b'IDAT', compressed)
    + chunk(b'IEND', b'')
)

out = '/tmp/taskboard_icon.png'
with open(out, 'wb') as f:
    f.write(png)
print(out)
