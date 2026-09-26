#!/usr/bin/env python3
# ppm2png.py - convert frame*.ppm (P6 binary or P3 ascii) to PNG, batched.
#   ppm2png.py            # convert every frame*.ppm in CWD (and ./frames)
#   ppm2png.py a.ppm ...  # convert the given files
import glob, os, sys
from PIL import Image

def load_ppm(path):
    with open(path, "rb") as f: raw = f.read()
    if raw[:2] == b"P6":
        return Image.open(path).convert("RGB")
    # P3 ASCII, X-safe
    t = raw.split(); W, H = int(t[1]), int(t[2]); vals = t[4:]
    def cv(b):
        try: return max(0, min(255, int(b)))
        except: return 0
    px = [cv(v) for v in vals[:W*H*3]]; px = (px + [0]*(W*H*3))[:W*H*3]
    im = Image.new("RGB", (W, H)); im.putdata([tuple(px[i:i+3]) for i in range(0, W*H*3, 3)])
    return im

def main():
    args = sys.argv[1:]
    files = args if args else sorted(glob.glob("frame*.ppm") + glob.glob("frames/frame*.ppm"))
    if not files: sys.exit("no frame*.ppm found")
    n = 0
    for path in files:
        try:
            im = load_ppm(path)
            out = os.path.splitext(path)[0] + ".png"
            im.resize((im.width*2, im.height*2), Image.NEAREST).save(out)
            n += 1
        except Exception as e:
            print("skip", path, e)
    print(f"converted {n} file(s)")

if __name__ == "__main__": main()
