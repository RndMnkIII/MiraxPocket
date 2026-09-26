#!/usr/bin/env python3
# ============================================================================
#  rom_build.py  -  Pack the Mirax romset into per-region blobs for the core.
# ----------------------------------------------------------------------------
#  Produces region .bin + $readmemh .hex matching the ioctl_index load map in
#  mirax_top.sv, using the exact MAME misc/mirax.cpp offsets. Targets 'miraxa'
#  (set 2 = your CT805-3 board) and falls back to set 1 ('mirax') filenames.
#
#  Usage:  python3 rom_build.py <romdir> <outdir>
#  <romdir> holds the individual ROM files (any of the known name variants).
# ============================================================================
import sys, os

# region -> ordered list of (candidate filenames, offset, length)
# Program (region maincpu / data_code) : ENCRYPTED, loaded as-is, 48K
PROG = [
    (["mx_p5_43v.p5","mxp5-42.rom","10.p5"], 0x0000, 0x4000),
    (["mx_r5_43v.r5","mxr5-4v.rom","11.r5"], 0x4000, 0x4000),
    (["mx_s5_43v.s5","mxs5-4v.rom","12.s5"], 0x8000, 0x4000),
]
AUDIO = [ (["mxr2-4v.rom","13.r5"], 0x0000, 0x2000) ]                  # 8K
# tiles region: 3 planes x 16K, order = plane0,plane1,plane2
TILES = [
    (["mxe3-4v.rom","4.e3"], 0x0000, 0x4000),
    (["mxh3-4v.rom","6.h3"], 0x4000, 0x4000),
    (["mxk3-4v.rom","8.k3"], 0x8000, 0x4000),
]
# sprites region 0x18000: exact MAME offsets so planes end up 0/1/2 contiguous
SPRITES = [
    (["mxf3-4v.rom","5.f3"], 0x00000, 0x4000),
    (["mxe2-4v.rom","1.e2"], 0x04000, 0x4000),
    (["mxi3-4v.rom","7.i3"], 0x08000, 0x4000),
    (["mxf2-4v.rom","2.f2"], 0x0c000, 0x4000),
    (["mxl3-4v.rom","9.l3"], 0x10000, 0x4000),
    (["mxh2-4v.rom","3.h2"], 0x14000, 0x4000),
]
PROMS = [
    (["mra3.prm"], 0x00, 0x20),
    (["mrb3.prm"], 0x20, 0x20),
]

def find(romdir, cands):
    for c in cands:
        p = os.path.join(romdir, c)
        if os.path.isfile(p): return p
    # case-insensitive retry
    low = {f.lower(): f for f in os.listdir(romdir)}
    for c in cands:
        if c.lower() in low: return os.path.join(romdir, low[c.lower()])
    return None

def build(romdir, spec, size):
    blob = bytearray([0]*size)
    for cands, off, length in spec:
        p = find(romdir, cands)
        if not p:
            print(f"  !! missing: {cands[0]} (offset {off:#x})"); continue
        data = open(p,'rb').read()
        if len(data) != length:
            print(f"  ~~ {os.path.basename(p)} is {len(data)} bytes, expected {length}")
        blob[off:off+len(data)] = data[:length]
        print(f"  ok {os.path.basename(p):16s} -> {off:#07x}..{off+length:#07x}")
    return blob

def write_out(outdir, name, blob):
    os.makedirs(outdir, exist_ok=True)
    open(os.path.join(outdir, name+".bin"),'wb').write(blob)
    with open(os.path.join(outdir, name+".hex"),'w') as f:
        for byte in blob: f.write(f"{byte:02x}\n")
    print(f"  wrote {name}.bin / {name}.hex ({len(blob)} bytes)")

def write_planes(outdir, name, blob):
    # split a plane-major blob into 3 equal planes -> name_p0/p1/p2.hex
    sz = len(blob)//3
    for p in range(3):
        with open(os.path.join(outdir, f"{name}_p{p}.hex"),'w') as f:
            for byte in blob[p*sz:(p+1)*sz]: f.write(f"{byte:02x}\n")
    print(f"  split {name} -> {name}_p0/p1/p2.hex ({sz} bytes each)")

def main():
    if len(sys.argv)!=3:
        print("usage: rom_build.py <romdir> <outdir>"); sys.exit(1)
    romdir, outdir = sys.argv[1], sys.argv[2]
    for name, spec, size, planes in [
        ("prog",    PROG,    0xC000,  False),
        ("audio",   AUDIO,   0x2000,  False),
        ("tiles",   TILES,   0xC000,  True),
        ("sprites", SPRITES, 0x18000, True),
        ("proms",   PROMS,   0x40,    False),
    ]:
        print(f"[{name}]"); blob=build(romdir, spec, size); write_out(outdir, name, blob)
        if planes: write_planes(outdir, name, blob)
    print("done. Note: prog.* is the ENCRYPTED image (decrypted live by the core).")

if __name__=="__main__": main()
