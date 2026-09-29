#!/usr/bin/env python3
"""make-logo-assets.py: every copy of the gator mark, from one source file.

The source is the artwork Tara approved, as Alex sent it (2026-09-29, decision
0032): the gator in colour on its own navy square. Four files come out of it,
and nothing else in the repo should be edited by hand to change the logo:

  AppIcon-1024.png   the square as is, RGB with no alpha (App Store Connect
                     rejects an icon with an alpha channel, ITMS-90717)
  gator-x.png        the mark with the navy lifted out, for navy surfaces in
                     the app (launch screen, header)
  web/gator.png      the same cut-out, smaller, for navy pages on the web
  web/gator-tile.png the square with rounded corners, for light pages (the QR
                     card), where the cream racquets would vanish on cream

The cut-out is a flood fill from the border: only navy connected to the edge
goes, so the dark outlines inside the gator (eyes, nostrils) stay. The outer
outline goes with the background, which on a navy surface looks the same.

  python3 scripts/make-logo-assets.py [source]
"""
import sys
from collections import deque
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/brand/gator-2026-09-29.webp"
ASSETS = ROOT / "FXETennis/Resources/Assets.xcassets"
TOL = 60  # colour distance still counted as background navy

im = Image.open(SRC).convert("RGB")
w, h = im.size
px = im.load()
bg = px[5, 5]

def near(c):
    return sum((a - b) ** 2 for a, b in zip(c, bg)) <= TOL * TOL

mask = Image.new("L", (w, h), 255)
m = mask.load()
seen = bytearray(w * h)
q = deque()
for x in range(w):
    q.extend([(x, 0), (x, h - 1)])
for y in range(h):
    q.extend([(0, y), (w - 1, y)])
while q:
    x, y = q.popleft()
    i = y * w + x
    if seen[i]:
        continue
    seen[i] = 1
    if not near(px[x, y]):
        continue
    m[x, y] = 0
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
            q.append((nx, ny))
# Soften the cut by a pixel so the edge is not stair-stepped when scaled.
mask = mask.filter(ImageFilter.GaussianBlur(0.8))

cut = im.convert("RGBA")
cut.putalpha(mask)
cut = cut.crop(cut.getbbox())

# 1. App icon.
im.resize((1024, 1024), Image.LANCZOS).save(ASSETS / "AppIcon.appiconset/AppIcon-1024.png")
# 2. In-app mark, about the old asset's size.
cw, ch = cut.size
s = 1067 / ch
cut.resize((round(cw * s), 1067), Image.LANCZOS).save(ASSETS / "gator-x.imageset/gator-x.png")
# 3. Web cut-out.
s = 320 / ch
cut.resize((round(cw * s), 320), Image.LANCZOS).save(ROOT / "web/gator.png")
# 4. Web tile, rounded like an app icon.
tile = im.resize((320, 320), Image.LANCZOS).convert("RGBA")
r = Image.new("L", (320 * 4, 320 * 4), 0)
ImageDraw.Draw(r).rounded_rectangle((0, 0, 320 * 4 - 1, 320 * 4 - 1), radius=72 * 4, fill=255)
tile.putalpha(r.resize((320, 320), Image.LANCZOS))
tile.save(ROOT / "web/gator-tile.png")
print("wrote 4 files from", SRC.relative_to(ROOT) if SRC.is_relative_to(ROOT) else SRC)
