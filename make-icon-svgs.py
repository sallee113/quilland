#!/usr/bin/env python3
"""Makes the two square icon drawings from Resources/AppIcon.svg (the author's drawing):
Resources/AppIcon-full.svg   quill, mountain and the word QUILLAND, for 128 pixels and up;
Resources/AppIcon-small.svg  quill and mountain only, bigger and with a heavier line, for 64 pixels and below."""
import re, pathlib

root = pathlib.Path(__file__).parent / "Resources"
source = (root / "AppIcon.svg").read_text()
d = re.search(r'<path fill="url\(#gold\)"[^>]* d="([^"]+)"', source).group(1)
parts = [p for p in re.split(r'(?<=Z)(?=M)', d) if p.strip()]

def bbox(path):
    nums = [float(n) for n in re.findall(r'-?\d+\.?\d*', path)]
    xs, ys = nums[0::2], nums[1::2]
    return min(xs), min(ys), max(xs), max(ys)

# The lettering sits at the bottom (y above 415); the quill and the mountain are above it.
art = [p for p in parts if bbox(p)[3] < 415]
text = [p for p in parts if bbox(p)[1] >= 415]
assert art and text, (len(art), len(text))

def union(paths):
    boxes = [bbox(p) for p in paths]
    return min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)

SIZE = 600
def drawing(paths, target_height, stroke):
    x0, y0, x1, y1 = union(paths)
    w, h = x1 - x0, y1 - y0
    scale = target_height / h
    if w * scale > SIZE * 0.78: scale = SIZE * 0.78 / w
    tx = SIZE / 2 - (x0 + w / 2) * scale
    ty = SIZE / 2 - (y0 + h / 2) * scale
    extra = f' stroke="url(#gold)" stroke-width="{stroke}" stroke-linejoin="round"' if stroke else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#16717F"/><stop offset="0.55" stop-color="#0D4F5C"/><stop offset="1" stop-color="#073341"/></linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.12" r="0.75"><stop offset="0" stop-color="#2A8C98" stop-opacity="0.45"/><stop offset="1" stop-color="#2A8C98" stop-opacity="0"/></radialGradient>
    <linearGradient id="frame" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F8E0AE"/><stop offset="0.5" stop-color="#CDAE76"/><stop offset="1" stop-color="#A2803F"/></linearGradient>
    <linearGradient id="gold" gradientUnits="userSpaceOnUse" x1="0" y1="{y0}" x2="0" y2="{y1}"><stop offset="0" stop-color="#F0D9A6"/><stop offset="0.5" stop-color="#D2B47C"/><stop offset="1" stop-color="#B39158"/></linearGradient>
  </defs>
  <rect width="{SIZE}" height="{SIZE}" rx="{SIZE * 0.2237}" fill="url(#bg)"/>
  <rect width="{SIZE}" height="{SIZE}" rx="{SIZE * 0.2237}" fill="url(#glow)"/>
  <rect x="4" y="4" width="{SIZE - 8}" height="{SIZE - 8}" rx="{SIZE * 0.2237 - 4}" fill="none" stroke="url(#frame)" stroke-width="8"/>
  <g transform="translate({tx:.2f} {ty:.2f}) scale({scale:.4f})"><path fill="url(#gold)" fill-rule="evenodd"{extra} d="{''.join(paths)}"/></g>
</svg>
'''

(root / "AppIcon-full.svg").write_text(drawing(art + text, SIZE * 0.70, 0))
(root / "AppIcon-small.svg").write_text(drawing(art, SIZE * 0.72, 5))
print(f"{len(art)} pieces of art, {len(text)} of lettering")
