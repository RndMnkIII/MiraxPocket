#!/usr/bin/env python3
# ============================================================================
#  frame_compare.py  -  Compare a core frame (PPM) against a MAME reference.
# ----------------------------------------------------------------------------
#  Mirax is ROT90, and MAME snapshots are saved in *display* orientation while
#  the core dumps its raw 256x240 raster. This tool auto-tries the 4 rotations
#  (and their mirrors), picks the best alignment by mean-absolute-error, prints
#  metrics and writes a side-by-side + difference heatmap PNG.
#
#  Usage:
#    frame_compare.py core.ppm ref.png [--out cmp.png] [--rot auto|0|90|180|270]
#
#  Capturing a MAME reference (display-oriented PNG):
#    mame miraxa -snapname mirax -snapshot        # F12 in-game, or:
#    mame miraxa -video none -frames 600 -snap ... # scripted
#  Then point --ref at the saved PNG.
# ============================================================================
import sys, argparse
import numpy as np
from PIL import Image

def load_ppm(path):
    """X-safe P3/P6 loader -> HxWx3 uint8."""
    with open(path,'rb') as f: raw=f.read()
    if raw[:2]==b'P6':
        im=Image.open(path).convert('RGB'); return np.asarray(im)
    # P3 ASCII, tolerant of 'x'/'X' (unknown) tokens
    t=raw.split()
    assert t[0]==b'P3', "not P3/P6"
    W,H=int(t[1]),int(t[2]); vals=t[4:]
    def cv(b):
        try: return max(0,min(255,int(b)))
        except: return 0
    a=np.fromiter((cv(v) for v in vals[:W*H*3]),dtype=np.uint8,count=W*H*3)
    if a.size<W*H*3: a=np.concatenate([a,np.zeros(W*H*3-a.size,np.uint8)])
    return a.reshape(H,W,3)

def load_any(path):
    if path.lower().endswith('.ppm'): return load_ppm(path)
    return np.asarray(Image.open(path).convert('RGB'))

def orient(img, k, mirror):
    o=np.rot90(img,k)
    if mirror: o=o[:,::-1]
    return o

def fit(ref, shape):
    """resize ref to (H,W) of shape for pixelwise compare."""
    H,W=shape[:2]
    return np.asarray(Image.fromarray(ref).resize((W,H),Image.NEAREST))

def metrics(a,b):
    d=np.abs(a.astype(int)-b.astype(int))
    mae=d.mean(); rmse=np.sqrt((d**2).mean())
    exact=100.0*np.mean(np.all(a==b,axis=2))
    return mae,rmse,exact

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('core'); ap.add_argument('ref')
    ap.add_argument('--out',default='cmp.png')
    ap.add_argument('--rot',default='auto')
    a=ap.parse_args()
    core=load_any(a.core); ref=load_any(a.ref)

    cands=[]
    rots = [0,1,2,3] if a.rot=='auto' else [int(a.rot)//90]
    for k in rots:
        for mir in ([False,True] if a.rot=='auto' else [False]):
            r=fit(orient(ref,k,mir), core.shape)
            cands.append((metrics(core,r)[0], k*90, mir, r))
    cands.sort(key=lambda c:c[0])
    mae,deg,mir,best=cands[0]
    m,rmse,exact=metrics(core,best)
    print(f"best orientation: rot {deg}{' +mirror' if mir else ''}")
    print(f"  MAE  : {m:.2f} / 255")
    print(f"  RMSE : {rmse:.2f}")
    print(f"  exact pixel match: {exact:.2f}%")

    # side-by-side + heatmap
    diff=np.abs(core.astype(int)-best.astype(int)).sum(2)
    heat=np.zeros_like(core)
    hn=(255*diff/max(diff.max(),1)).astype(np.uint8)
    heat[...,0]=hn  # red = magnitude
    H,W=core.shape[:2]; gap=8
    canvas=np.full((H, W*3+gap*2, 3),32,np.uint8)
    canvas[:, :W]=core
    canvas[:, W+gap:2*W+gap]=best
    canvas[:, 2*W+2*gap:]=heat
    Image.fromarray(canvas).resize(((W*3+gap*2)*2,H*2),Image.NEAREST).save(a.out)
    print(f"  wrote {a.out}  (core | ref | diff-heatmap)")

if __name__=='__main__': main()
