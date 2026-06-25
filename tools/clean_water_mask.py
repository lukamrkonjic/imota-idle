#!/usr/bin/env python3
"""Despeckle the authored inland-water mask (aldreth_rivers.png).

The river/lake mask is hand-traced; isolated 1-few-pixel blobs are authoring
noise, and at ~1.5 world-tiles per mask pixel each one bakes into a stray 1-2
tile "random pond" sitting on dry land. This drops every water blob below a
minimum area while preserving genuine rivers/lakes (which are large connected
components — a thin river is ONE long blob, not specks).

Backs up the original to masks/_backup_pre_waterfix/ first, prints a full report
of what was removed (so a real small pond can be spared by raising the threshold),
and cross-checks the result against the elevation mask (water on raised terrain
fragments rivers into rock — see the hydrology memory). Re-bake after running:

    python3 tools/clean_water_mask.py            # default min area = 6 px
    python3 tools/clean_water_mask.py --min 4    # keep slightly smaller ponds
    python3 tools/clean_water_mask.py --dry-run  # report only, write nothing
"""
import argparse
import os
import shutil

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASKS = os.path.join(ROOT, "data/world/masks")
RIVERS = os.path.join(MASKS, "aldreth_rivers.png")
ELEV = os.path.join(MASKS, "aldreth_elev.png")
BACKUP_DIR = os.path.join(MASKS, "_backup_pre_waterfix")

# A water pixel is "on raised terrain" once the authored elevation, after the
# gamma the classifier applies (pow(v,1.8)*64), rounds above this many steps.
# Mirrors biome_classifier.mask_elev_steps; kept low so only genuine slopes flag.
ELEV_RAISED_STEPS = 3
ELEV_MAX_STEPS = 64


def elev_steps(raw: np.ndarray) -> np.ndarray:
    v = raw.astype(np.float32) / 255.0
    return np.rint(np.power(v, 1.8) * ELEV_MAX_STEPS).astype(np.int32)


def main() -> None:
    ap = argparse.ArgumentParser(description="Despeckle aldreth_rivers.png")
    ap.add_argument("--min", type=int, default=6,
                    help="drop water blobs strictly smaller than this many mask px (default 6)")
    ap.add_argument("--carve-dilate", type=int, default=2,
                    help="dilate (px) the water footprint when carving elevation to 0 (default 2)")
    ap.add_argument("--no-carve", action="store_true",
                    help="skip carving the elevation mask flat under water")
    ap.add_argument("--dry-run", action="store_true", help="report only; do not write")
    args = ap.parse_args()

    rivers = np.array(Image.open(RIVERS).convert("L"))
    water = rivers > 127
    total = int(water.sum())

    # 8-connectivity so a diagonally-stepping river stays one component.
    structure = np.ones((3, 3), dtype=int)
    labels, n = ndimage.label(water, structure=structure)
    sizes = ndimage.sum(np.ones_like(labels), labels, index=range(1, n + 1)).astype(int)
    centroids = ndimage.center_of_mass(water, labels, index=range(1, n + 1))

    small = [i for i in range(n) if sizes[i] < args.min]
    keep = [i for i in range(n) if sizes[i] >= args.min]

    print(f"[clean_water_mask] {RIVERS}")
    print(f"  water pixels: {total}  ({100*water.mean():.3f}% of {rivers.size})")
    print(f"  blobs: {n} total  ->  keep {len(keep)}  /  drop {len(small)} (< {args.min}px)")
    hist = {"1": 0, "2-5": 0, "6-50": 0, ">50": 0}
    for s in sizes:
        hist["1" if s <= 1 else "2-5" if s <= 5 else "6-50" if s <= 50 else ">50"] += 1
    print(f"  size histogram: {hist}")

    if small:
        print("  --- removed blobs (label, px, centroid row,col) ---")
        for i in sorted(small, key=lambda i: sizes[i]):
            r, c = centroids[i]
            print(f"    blob#{i+1:>3}  {sizes[i]:>3}px  @ ({r:.0f},{c:.0f})")

    # Cross-check the KEPT water against elevation: stray water on raised terrain
    # gets re-classified to rock at bake (world_generator._place_mountains) and
    # fragments the river. Report (don't auto-fix — that's an authoring decision).
    if os.path.exists(ELEV):
        steps = elev_steps(np.array(Image.open(ELEV).convert("L")))
        kept_mask = np.isin(labels, [i + 1 for i in keep])
        raised = kept_mask & (steps > ELEV_RAISED_STEPS)
        nr = int(raised.sum())
        if nr:
            ys, xs = np.where(raised)
            print(f"  WARNING: {nr} kept water px sit on raised elev (> {ELEV_RAISED_STEPS} steps) "
                  f"e.g. ({ys[0]},{xs[0]}) step={steps[ys[0],xs[0]]} — will rock-fragment at bake")
        else:
            print(f"  OK: no kept water on raised elevation (> {ELEV_RAISED_STEPS} steps)")

    if args.dry_run:
        print("  dry-run: no files written")
        return

    cleaned = water.copy()
    for i in small:
        cleaned[labels == (i + 1)] = False

    os.makedirs(BACKUP_DIR, exist_ok=True)

    def backup_once(path: str) -> None:
        dst = os.path.join(BACKUP_DIR, os.path.basename(path))
        if not os.path.exists(dst):
            shutil.copy2(path, dst)
            print(f"  backed up original -> {dst}")
        else:
            print(f"  backup already exists, left intact -> {dst}")

    backup_once(RIVERS)
    out = np.where(cleaned, 255, 0).astype(np.uint8)
    Image.fromarray(out, mode="L").save(RIVERS)
    print(f"  wrote cleaned mask: {int(cleaned.sum())} water px "
          f"({total - int(cleaned.sum())} removed).")

    # Carve the elevation mask to 0 under all (cleaned) water + a small ring, so
    # water always sits at elevation 0 (the single source of truth: water is
    # flat). This prevents stray rivers cutting through raised terrain as rock
    # ("foam indented in water" gotcha) and flattens the immediate bank.
    if not args.no_carve and os.path.exists(ELEV):
        backup_once(ELEV)
        elev_img = Image.open(ELEV).convert("L")
        elev_arr = np.array(elev_img)
        footprint = cleaned
        if args.carve_dilate > 0:
            footprint = ndimage.binary_dilation(cleaned, iterations=args.carve_dilate)
        carved = int((footprint & (elev_arr > 0)).sum())
        elev_arr[footprint] = 0
        Image.fromarray(elev_arr, mode="L").save(ELEV)
        print(f"  carved elevation to 0 under water (+{args.carve_dilate}px): {carved} px lowered.")
    print("  RE-BAKE to apply.")


if __name__ == "__main__":
    main()
