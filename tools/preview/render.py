# RIFTVEIL panel preview. Renders the info panel outside the game from the
# script's own drawing code, to check a layout change before loading it.
#
#   cd tools/preview
#   python3 metrics.py && lua5.3 drive.lua && python3 render.py
#   -> out/panel_preview.png   (needs Pillow and DejaVu fonts)
#
# Step 3: rasterizes the recorded draw calls. Fonts are stand-ins (DejaVu
# for Verdana, 8px DejaVu Bold without anti-aliasing for gamesense's pixel
# font); geometry, colours and layout are exactly what the Lua drew.
import os
import re
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

NORM = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
SMALL = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 8)
SCALE = 3
MARGIN = 14

def load(path):
    calls = []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line:
            calls.append(line.split("\t"))
    return calls

def bounds(calls):
    xs, ys = [], []
    for c in calls:
        if c[0] in ("R", "G"):
            x, y, w, h = map(float, c[1:5])
            xs += [x, x + w]; ys += [y, y + h]
    return min(xs), min(ys), max(xs), max(ys)

def blend(img, box, rgba):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rectangle(box, fill=rgba)
    img.alpha_composite(layer)

def draw_scene(calls, ox, oy, size):
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    for c in calls:
        k = c[0]
        if k == "R":
            x, y, w, h = [float(v) for v in c[1:5]]
            r, g, b, a = [int(float(v)) for v in c[5:9]]
            if w <= 0 or h <= 0:
                continue
            blend(img, [x - ox, y - oy, x - ox + w - 1, y - oy + h - 1], (r, g, b, a))
        elif k == "G":
            x, y, w, h = [float(v) for v in c[1:5]]
            c1 = [int(float(v)) for v in c[5:9]]
            c2 = [int(float(v)) for v in c[9:13]]
            horiz = c[13] == "true"
            w, h = int(w), int(h)
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            n = w if horiz else h
            for i in range(max(n, 1)):
                t = i / max(n - 1, 1)
                col = tuple(int(c1[j] + (c2[j] - c1[j]) * t) for j in range(4))
                if horiz:
                    d.line([x - ox + i, y - oy, x - ox + i, y - oy + h - 1], fill=col)
                else:
                    d.line([x - ox, y - oy + i, x - ox + w - 1, y - oy + i], fill=col)
            img.alpha_composite(layer)
        elif k == "T":
            x, y = float(c[1]), float(c[2])
            base = tuple(int(float(v)) for v in c[3:7])
            flags, text = c[7], c[8] if len(c) > 8 else ""
            small = "-" in flags
            font = SMALL if small else NORM
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            d.fontmode = "1" if small else "L"
            cx = x - ox
            col = base
            for part in re.split(r"(\x07[0-9A-Fa-f]{8})", text):
                if part.startswith("\x07"):
                    h = part[1:]
                    col = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4, 6))
                    continue
                if not part:
                    continue
                if small:
                    # gamesense draws its pixel font with a 1px dark outline
                    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        d.text((cx + dx, y - oy + dy), part, font=font, fill=(0, 0, 0, col[3]))
                d.text((cx, y - oy), part, font=font, fill=col)
                cx += font.getlength(part)
            img.alpha_composite(layer)
    return img

scenes = [
    ("a_resolved.txt", "RESOLVED  ·  hit memory, 2v2 alt row"),
    ("b_vuln.txt",     "VULN WINDOW  ·  long Cyrillic name fitted"),
    ("c_building.txt", "BUILDING  ·  menu open (drag outline), lag spike"),
    ("d_idle.txt",     "IDLE  ·  no target"),
]
tiles = []
for path, caption in scenes:
    calls = load(os.path.join(OUT, path))
    x0, y0, x1, y1 = bounds(calls)
    ox, oy = x0 - MARGIN, y0 - MARGIN
    w, h = int(x1 - x0 + MARGIN * 2), int(y1 - y0 + MARGIN * 2)
    # muted in-game backdrop
    bg = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    bd = ImageDraw.Draw(bg)
    for i in range(h):
        t = i / max(h - 1, 1)
        bd.line([0, i, w, i], fill=(int(58 + 20 * t), int(62 + 16 * t), int(66 + 8 * t), 255))
    scene = draw_scene(calls, ox, oy, (w, h))
    bg.alpha_composite(scene)
    tiles.append((bg, caption))

W = max(t[0].width for t in tiles) * SCALE
cap_h = 34
H = sum(t[0].height * SCALE + cap_h for t in tiles) + 20
sheet = Image.new("RGBA", (W + 40, H + 40), (14, 14, 14, 255))
sd = ImageDraw.Draw(sheet)
cap_font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
y = 20
for tile, caption in tiles:
    sd.text((20, y + 6), caption, font=cap_font, fill=(150, 150, 150, 255))
    y += cap_h
    big = tile.resize((tile.width * SCALE, tile.height * SCALE), Image.NEAREST)
    sheet.alpha_composite(big, (20, y))
    y += big.height
dest = os.path.join(OUT, "panel_preview.png")
sheet.convert("RGB").save(dest)
print(dest, sheet.size)
