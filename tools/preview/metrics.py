# Step 1 of the panel preview (see render.py for the full usage).
# Writes out/metrics.lua: per-character advance widths for the two stand-in
# fonts the rasterizer uses, so the Lua panel code measures text exactly as
# the image will draw it.
import os
from PIL import ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

NORM = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
SMALL = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 8)

chars = [chr(c) for c in range(32, 127)]
chars += [chr(c) for c in range(0x410, 0x450)]  # Cyrillic
chars += ["…", "·", "°"]

def esc(ch):
    return "".join("\\%d" % b for b in ch.encode("utf-8"))

out = ["return {"]
for name, font in (("norm", NORM), ("small", SMALL)):
    out.append("  %s = {" % name)
    for ch in chars:
        out.append('    ["%s"] = %d,' % (esc(ch), round(font.getlength(ch))))
    out.append("  },")
asc, desc = NORM.getmetrics()
out.append("  norm_h = %d," % (asc + desc))
asc, desc = SMALL.getmetrics()
out.append("  small_h = %d," % (asc + desc))
out.append("}")
open(os.path.join(OUT, "metrics.lua"), "w").write("\n".join(out) + "\n")
print("metrics.lua written")
