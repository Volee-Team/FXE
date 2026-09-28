#!/usr/bin/env python3
"""Measure real text contrast from a simulator screenshot.

The accessibility audit (FXETennisUITests/AccessibilityAuditUITests.swift)
samples an element's whole frame, which can include the court photo around
small text and report a failure the eye would not. This settles it from the
pixels: the darkest 1% of the frame is taken as the glyphs, the median as the
background, and the WCAG contrast ratio between them is printed.

    xcrun simctl io booted screenshot /tmp/s.png
    python3 scripts/measure-contrast.py /tmp/s.png 149 616.7 104.3 44 "Create an account"

Coordinates are the element's frame in points, as the audit prints them;
the screenshot is 3x (iPhone Pro).
"""
import sys
from PIL import Image

def lum(c):
    def ch(v):
        v = v / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = c
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)

path, x, y, w, h = sys.argv[1], *map(float, sys.argv[2:6])
name = sys.argv[6] if len(sys.argv) > 6 else "element"
scale = 3
im = Image.open(path).convert("RGB")
px = [im.getpixel((i, j)) for i in range(int(x * scale), int((x + w) * scale))
      for j in range(int(y * scale), int((y + h) * scale))]
ls = sorted(lum(p) for p in px)
text, bg = ls[int(len(ls) * 0.01)], ls[len(ls) // 2]
ratio = (max(text, bg) + 0.05) / (min(text, bg) + 0.05)
print(f"{name}: {ratio:.1f}:1 ({'passes' if ratio >= 4.5 else 'FAILS'} 4.5:1)")
