#!/usr/bin/env python3
"""Trace the authored Aldreth reference images into runtime masks.

Inputs  (data/world/source/, all 1672x941, pixel-aligned):
  aldreth_biomes_clean.png  - biome colours on plain ocean (land shape + biomes)
  elevation.png             - traversability bands (Easy..Blocked) = elevation
  rivers and lakes.png      - biome map with rivers/lakes drawn in blue

Outputs (data/world/masks/):
  aldreth_land.png          - binary land/ocean (white=land)
  aldreth_biomes.png        - grayscale, pixel value = index into biomePalette
  aldreth_elev.png          - grayscale 0..255 elevation
  aldreth_rivers.png        - binary river/lake water (white=water)
  *_preview.png             - human-checkable recolours
  aldreth_mask.json         - palette + bounds + atlas size

Biome classification: scribble-seed segmentation. Seeds are labelled points
(fraction of image + biome); each pixel is assigned the nearest seed in a
combined colour+position metric, then majority-filtered to clean speckle.
"""
import json, math, os
from collections import Counter
from PIL import Image

SRC = "data/world/source"
OUT = "data/world/masks"
BIOMES = os.path.join(SRC, "aldreth_biomes_clean.png")
ELEV   = os.path.join(SRC, "elevation.png")
RIVERS = os.path.join(SRC, "rivers and lakes.png")
TRACE  = os.path.join(SRC, "trace-map.png")   # crisp coastline outline (preferred)

# ---- biome palette (index order is stable; written to mask.json) ----
# index 0 must be ocean (land mask handles water; this is the land fallback list)
PALETTE = ["forest","plains","boreal_forest","alpine","tundra","volcanic",
           "rocky_hills","swamp","jungle","desert","savanna","badlands",
           "salt_marsh","flower_meadow"]
PIDX = {b:i for i,b in enumerate(PALETTE)}

# canonical preview colours (close to the reference, for eyeballing)
PCOL = {
 "forest":(49,81,53),"plains":(140,150,90),"boreal_forest":(40,70,55),
 "alpine":(232,236,237),"tundra":(180,188,180),"volcanic":(60,45,42),
 "rocky_hills":(150,146,140),"swamp":(86,104,70),"jungle":(60,96,46),
 "desert":(195,150,90),"savanna":(175,160,95),"badlands":(150,95,60),
 "salt_marsh":(212,210,196),"flower_meadow":(150,120,150),
}

# Seeds: (fx, fy, biome). Placed by eye over the reference layout.
SEEDS = [
 # NW snow alps + NE snow island
 (0.25,0.11,"alpine"),(0.30,0.09,"alpine"),(0.21,0.15,"alpine"),(0.27,0.17,"alpine"),
 (0.895,0.12,"alpine"),(0.875,0.18,"alpine"),(0.915,0.15,"alpine"),
 # boreal conifer band below NW snow
 (0.255,0.25,"boreal_forest"),(0.30,0.22,"boreal_forest"),(0.205,0.28,"boreal_forest"),
 (0.33,0.27,"boreal_forest"),
 # tundra fringe between snow and boreal
 (0.18,0.21,"tundra"),(0.35,0.14,"tundra"),
 # western forests + bottom forest isles
 (0.22,0.45,"forest"),(0.18,0.55,"forest"),(0.28,0.40,"forest"),(0.25,0.62,"forest"),
 (0.11,0.84,"forest"),(0.19,0.80,"forest"),
 # far-west island (green w/ purple flower meadows)
 (0.075,0.42,"forest"),(0.05,0.34,"flower_meadow"),(0.085,0.55,"forest"),
 # central plains / heartland
 (0.45,0.32,"plains"),(0.50,0.40,"plains"),(0.42,0.46,"plains"),(0.55,0.30,"plains"),
 (0.40,0.30,"plains"),(0.48,0.25,"plains"),
 # NE volcanic + bottom volcanic isle
 (0.65,0.16,"volcanic"),(0.70,0.13,"volcanic"),(0.62,0.22,"volcanic"),(0.73,0.20,"volcanic"),
 (0.315,0.82,"volcanic"),
 # rocky hills skirting the volcanic NE
 (0.70,0.34,"rocky_hills"),(0.66,0.30,"rocky_hills"),(0.60,0.34,"rocky_hills"),
 # southern swamp/fens
 (0.52,0.56,"swamp"),(0.56,0.60,"swamp"),(0.48,0.52,"swamp"),(0.60,0.55,"swamp"),
 # southern jungle + bottom jungle isle
 (0.58,0.66,"jungle"),(0.54,0.70,"jungle"),(0.62,0.64,"jungle"),(0.535,0.85,"jungle"),
 # SE savanna (upper dry) -> desert (mid) -> salt pan (lower pale)
 (0.80,0.46,"savanna"),(0.83,0.42,"savanna"),(0.78,0.50,"savanna"),
 (0.87,0.55,"desert"),(0.90,0.62,"desert"),(0.84,0.58,"desert"),(0.92,0.50,"desert"),
 (0.85,0.68,"badlands"),(0.88,0.66,"badlands"),
 (0.90,0.83,"salt_marsh"),(0.92,0.80,"salt_marsh"),(0.88,0.86,"salt_marsh"),
]

ALPHA = 420.0   # spatial weight: higher = trust position more vs colour

# ---- world bounds (chunks). 16:9 to match the references, OSRS-large. ----
# 160x90 chunks * 16 = 2560 x 1440 tiles (~OSRS 2000x1500, a touch larger).
BOUNDS_MIN = [-80, -45]
BOUNDS_MAX = [80, 45]

def elev_value(c):
    # Shaded-relief is unreliable by brightness (slope shadows are dark everywhere),
    # so key elevation off HUE/SATURATION: only COOL desaturated tones are real relief.
    #   cool snow-white  -> peak ; cool grey rock -> mountain ; everything else flat.
    # Warm tones (tan desert, cream salt pan, orange lava) stay lowland (their biome
    # surface carries the look), so the world isn't one big terraced rockfield.
    r,g,b = c
    mx = max(c); mn = min(c)
    sat = (mx-mn)/float(max(mx,1))
    if mx > 208 and sat < 0.11 and b >= r-6:   # cool snow-white summit
        return 255
    if sat < 0.17 and 70 < mx < 208 and b >= r-10:  # cool grey blocked rock
        return 195
    return 0                                    # lowland - FLAT (0 steps => biome surface shows)

def load(p):
    im = Image.open(p).convert("RGB"); return im, im.size, im.load()

def nearest(c, anchors):
    r,g,b = c; best=1e18; bv=anchors[0][3]
    for ar,ag,ab,av in anchors:
        d=(r-ar)**2+(g-ag)**2+(b-ab)**2
        if d<best: best=d; bv=av
    return bv

def is_river(c):
    r,g,b = c
    return b-r>22 and b-g>10 and b>112 and not is_ocean(c) or (abs(r-65)+abs(g-110)+abs(b-151)<46)

def is_ocean(c):
    r,g,b = c
    # plain slate ocean ~ (103,120,151); also generic blue-dominant
    return (abs(r-103)+abs(g-120)+abs(b-151) < 40) or (b>r+18 and b>132 and r<120 and b>=g+6)

def trace_land(W, H):
    """Land mask from the traced outline: flood ocean inward from the border over
    the white background; black coastline + any enclosed white = land. Lakes drawn
    as enclosed outlines also read as land here, but the river mask paints them water."""
    from collections import deque
    tim = Image.open(TRACE).convert("L")
    assert tim.size == (W,H), "trace-map size mismatch"
    # Seal sub-pixel gaps in the hand-traced outline: thicken ink (MinFilter grows
    # dark pixels) so the flood can't leak through breaks in the coastline.
    from PIL import ImageFilter
    tim = tim.filter(ImageFilter.MinFilter(5))   # ~2px ink dilation
    tp = tim.load()
    WHITE = 128   # >= is background (passable to flood); < is an ink line (blocks)
    land = bytearray(b"\xff" * (W*H))   # default land
    seen = bytearray(W*H)
    dq = deque()
    for x in range(W):
        for y in (0, H-1):
            if tp[x,y] >= WHITE and not seen[y*W+x]:
                seen[y*W+x]=1; dq.append((x,y))
    for y in range(H):
        for x in (0, W-1):
            if tp[x,y] >= WHITE and not seen[y*W+x]:
                seen[y*W+x]=1; dq.append((x,y))
    while dq:
        x,y = dq.popleft()
        land[y*W+x] = 0   # reachable white = ocean
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx,ny=x+dx,y+dy
            if 0<=nx<W and 0<=ny<H and not seen[ny*W+nx] and tp[nx,ny]>=WHITE:
                seen[ny*W+nx]=1; dq.append((nx,ny))
    return land

def main():
    im,(W,H),px = load(BIOMES)
    print("size",W,H)
    # ---- land mask ----
    # The traced outline (trace_land) isn't watertight AND its coastline differs from
    # the biome image, so we derive land from the biome image's ocean colour — keeping
    # land + biomes perfectly self-consistent (one source).
    land = bytearray(W*H)
    for y in range(H):
        for x in range(W):
            land[y*W+x] = 0 if is_ocean(px[x,y]) else 255
    # seed colours sampled from image (median of a small patch)
    seeds = []
    for fx,fy,b in SEEDS:
        sx,sy = int(fx*W), int(fy*H)
        cols=[px[min(W-1,max(0,sx+dx)),min(H-1,max(0,sy+dy))]
              for dx in (-3,0,3) for dy in (-3,0,3)]
        cols.sort(key=lambda c:c[0]+c[1]+c[2]); med=cols[len(cols)//2]
        seeds.append((sx,sy,med,PIDX[b]))
    # ---- classify land pixels to nearest seed (colour + position) ----
    idx = bytearray(W*H)
    A2 = ALPHA*ALPHA
    diag2 = float(W*W+H*H)
    for y in range(H):
        row=y*W
        for x in range(W):
            if land[row+x]==0: continue
            r,g,b = px[x,y]
            best=1e18; bi=0
            for sx,sy,(sr,sg,sb),pi in seeds:
                cd=(r-sr)**2+(g-sg)**2+(b-sb)**2
                pd=((x-sx)**2+(y-sy)**2)/diag2*A2
                d=cd+pd
                if d<best: best=d; bi=pi
            idx[row+x]=bi
    # ---- majority filter (5x5) to clean speckle ----
    idx2=bytearray(idx)
    R=2
    for y in range(H):
        for x in range(W):
            if land[y*W+x]==0: continue
            c=Counter()
            for dy in range(-R,R+1):
                yy=y+dy
                if yy<0 or yy>=H: continue
                for dx in range(-R,R+1):
                    xx=x+dx
                    if xx<0 or xx>=W or land[yy*W+xx]==0: continue
                    c[idx[yy*W+xx]]+=1
            if c: idx2[y*W+x]=c.most_common(1)[0][0]
    # ---- write land + biome index + previews ----
    os.makedirs(OUT,exist_ok=True)
    Image.frombytes("L",(W,H),bytes(land)).save(os.path.join(OUT,"aldreth_land.png"))
    Image.frombytes("L",(W,H),bytes(idx2)).save(os.path.join(OUT,"aldreth_biomes.png"))
    prev=Image.new("RGB",(W,H))
    pp=prev.load()
    for y in range(H):
        for x in range(W):
            if land[y*W+x]==0: pp[x,y]=(103,120,151)
            else: pp[x,y]=PCOL[PALETTE[idx2[y*W+x]]]
    prev.save(os.path.join(OUT,"aldreth_biomes_preview.png"))

    # ---- elevation (from elevation.png, only on land) ----
    from PIL import ImageFilter
    eim,(EW,EH),epx = load(ELEV)
    assert (EW,EH)==(W,H), "elevation size mismatch"
    elev = bytearray(W*H)
    for y in range(H):
        for x in range(W):
            if land[y*W+x]:
                elev[y*W+x] = elev_value(epx[x,y])
    # Heavy blur => smooth broad relief (flat lowland, mountains rise gently), so the
    # runtime never terraces shadow-noise into a rockfield.
    eimg = Image.frombytes("L",(W,H),bytes(elev)).filter(ImageFilter.GaussianBlur(6))
    eimg.save(os.path.join(OUT,"aldreth_elev.png"))
    elev2 = eimg.tobytes()

    # ---- rivers/lakes (from 'rivers and lakes.png', water inside land) ----
    rim,(RW,RH),rpx = load(RIVERS)
    assert (RW,RH)==(W,H), "rivers size mismatch"
    riv = bytearray(W*H)
    for y in range(H):
        for x in range(W):
            if land[y*W+x]==0: continue
            if is_river(rpx[x,y]): riv[y*W+x]=255
    # despeckle: drop isolated single-pixel water; keep lines/lakes
    riv2=bytearray(riv)
    for y in range(1,H-1):
        for x in range(1,W-1):
            if riv[y*W+x]==0: continue
            nb=sum(1 for dy in(-1,0,1) for dx in(-1,0,1) if riv[(y+dy)*W+(x+dx)])
            if nb<3: riv2[y*W+x]=0
    Image.frombytes("L",(W,H),bytes(riv2)).save(os.path.join(OUT,"aldreth_rivers.png"))

    # elevation+river preview overlay
    epv=Image.new("RGB",(W,H)); ep=epv.load()
    for y in range(H):
        for x in range(W):
            if land[y*W+x]==0: ep[x,y]=(103,120,151)
            elif riv2[y*W+x]: ep[x,y]=(70,120,190)
            else:
                v=elev2[y*W+x]; ep[x,y]=(v,180-v//2,60) if v<200 else (v,v,v)
    epv.save(os.path.join(OUT,"aldreth_elev_preview.png"))

    # ---- metadata ----
    meta={"_doc":"Generated by tools/trace_world.py from the authored references.",
      "source":{"biomes":"aldreth_biomes_clean.png","elevation":"elevation.png","rivers":"rivers and lakes.png"},
      "atlasSize":[W,H],"maskSize":[W,H],
      "land":"aldreth_land.png","biomes":"aldreth_biomes.png","elev":"aldreth_elev.png","rivers":"aldreth_rivers.png",
      "biomePalette":PALETTE,
      "bounds":{"min":BOUNDS_MIN,"max":BOUNDS_MAX}}
    with open(os.path.join(OUT,"aldreth_mask.json"),"w") as f: json.dump(meta,f,indent=1)
    nriv=sum(1 for b in riv2 if b)
    print("wrote land,biomes,elev,rivers,previews,json. river px:",nriv," palette:",PALETTE)

if __name__=="__main__":
    main()
