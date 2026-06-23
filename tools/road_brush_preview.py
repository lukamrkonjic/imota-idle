#!/usr/bin/env python3
"""Offline preview of the proposed RoadBrush — fast iteration on the LOOK before
porting the math to GDScript + slow bakes.

Demonstrates the four fixes vs the current hard-disc stamp:
  1. natural curve        (Catmull-Rom smoothing of coarse waypoints)
  2. varying width        (half-width modulated by low-freq noise along arc length)
  3. feathered edge       (stochastic rim: dirt probability falls off past the body)
  4. auto-bridge on water (road skips water tiles; a plank deck spans the gap)

Colours match in-game: path_orange #7E5A33 / path_light #9A7544 over grass.
"""
import math, os
from PIL import Image

W, H = 1280, 460
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GRASS = (90, 107, 74)
PATH_ORANGE = (0x7E, 0x5A, 0x33)
PATH_LIGHT = (0x9A, 0x75, 0x44)
WATER = (74, 128, 158)
WATER_HI = (110, 165, 190)
PLANK = (150, 104, 60)
PLANK_DARK = (104, 70, 40)
RAIL = (86, 58, 34)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def h2(x, y):  # cheap deterministic hash -> [0,1)
    n = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65536.0


def fnoise(s):  # smooth 1-D value noise along arc length
    return (math.sin(s * 0.013) * 0.5 + math.sin(s * 0.041 + 1.7) * 0.3
            + math.sin(s * 0.007 - 0.6) * 0.2)


def edge_warp(x, y):  # coherent 2-D wobble so the road edge scallops organically
    return (math.sin(x * 0.10 + y * 0.06) * 0.5 + math.sin(x * 0.05 - y * 0.13 + 2.1) * 0.3
            + math.sin(x * 0.21 + y * 0.17 - 1.0) * 0.2)


# --- background: grass + a winding river -------------------------------------
def river_band(x):
    return 0.5 * H + 120 * math.sin(x * 0.0055 + 0.4) + 40 * math.sin(x * 0.018)


def is_water(x, y):
    cy = river_band(x)
    half = 26 + 10 * math.sin(x * 0.02)
    return abs(y - cy) < half


px = bytearray(W * H * 3)
for y in range(H):
    for x in range(W):
        i = (y * W + x) * 3
        if is_water(x, y):
            cy = river_band(x)
            t = 1.0 - min(1.0, abs(y - cy) / 36.0)
            c = lerp(WATER, WATER_HI, 0.3 * t + 0.2 * h2(x // 3, y // 3))
        else:
            c = lerp(GRASS, (104, 120, 86), 0.18 * h2(x // 2, y // 2))
        px[i], px[i + 1], px[i + 2] = c

# --- centerline: coarse waypoints -> Catmull-Rom dense polyline ---------------
WAYPTS = [(40, 120), (210, 150), (360, 300), (540, 250),
          (700, 250), (860, 360), (1010, 300), (1240, 330)]


def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return (0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
            0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3))


center = []
ext = [WAYPTS[0]] + WAYPTS + [WAYPTS[-1]]
for k in range(1, len(ext) - 2):
    for j in range(24):
        center.append(catmull(ext[k - 1], ext[k], ext[k + 1], ext[k + 2], j / 24.0))

# arc length per sample
arc = [0.0]
for k in range(1, len(center)):
    dx = center[k][0] - center[k - 1][0]
    dy = center[k][1] - center[k - 1][1]
    arc.append(arc[-1] + math.hypot(dx, dy))

BASE_HW = 15.0      # base half-width (px)
AMP = 7.0           # width swell/pinch
FEATHER = 7.0       # soft rim depth


def halfwidth(s):
    return max(3.0, BASE_HW + AMP * fnoise(s))


# --- SDF buffer: signed distance to the variable-width road ------------------
INF = 1e9
sdf = [INF] * (W * H)
on_water = []  # per-sample: is this centerline point over water
for k, (cx, cy) in enumerate(center):
    on_water.append(is_water(cx, cy))
    w = halfwidth(arc[k])
    R = int(math.ceil(w + FEATHER + 1))
    x0, x1 = max(0, int(cx) - R), min(W, int(cx) + R + 1)
    y0, y1 = max(0, int(cy) - R), min(H, int(cy) + R + 1)
    for y in range(y0, y1):
        for x in range(x0, x1):
            d = math.hypot(x - cx, y - cy) - w
            idx = y * W + x
            if d < sdf[idx]:
                sdf[idx] = d

# --- paint the road (skip water — that becomes a bridge) ---------------------
for y in range(H):
    for x in range(W):
        idx = y * W + x
        d = sdf[idx] + 1.6 * edge_warp(x, y)   # gentle organic boundary wobble
        if d >= FEATHER:
            continue
        if is_water(x, y):
            continue  # never pave water; the bridge covers it
        i = idx * 3
        bright = 0.5 + 0.5 * fnoise(x * 0.6 + y)
        body = lerp(PATH_ORANGE, PATH_LIGHT, 0.30 + 0.4 * bright)
        if d < -6.0:                           # walked-in lighter centre strip
            c = lerp(body, PATH_LIGHT, 0.30)
            c = lerp(c, (60, 42, 24), 0.07 * h2(x, y))   # faint foot-worn grain
        elif d < -2.0:                         # worn core
            c = lerp(body, PATH_ORANGE, 0.5)
            c = lerp(c, (60, 42, 24), 0.08 * h2(x, y))
        elif d < 0.5:                          # body
            c = body
        else:                                  # soft rim: smooth blend to grass
            f = (d - 0.5) / (FEATHER - 0.5)    # 0 at body -> 1 at outer edge
            c = lerp(body, GRASS, smoothstep(f) * 0.9)
            if f > 0.7 and h2(x, y) > (1.0 - f) * 2.2:
                continue                       # only the outermost band breaks up
        px[i], px[i + 1], px[i + 2] = c

# --- auto-bridge: span each contiguous run of water-crossing samples ---------
def draw_plank_bridge(a, b):
    # a,b = centerline points on land flanking the water gap
    ax, ay = a; bx, by = b
    L = math.hypot(bx - ax, by - ay)
    nx, ny = (bx - ax) / L, (by - ay) / L
    ox, oy = -ny, nx           # perpendicular (deck half-width)
    HWB = 13
    steps = int(L)
    for s in range(steps + 1):
        t = s / steps
        cx = ax + (bx - ax) * t
        cy = ay + (by - ay) * t
        plank = (s // 6) % 2 == 0
        deck = PLANK if plank else PLANK_DARK
        for o in range(-HWB, HWB + 1):
            x = int(cx + ox * o); y = int(cy + oy * o)
            if 0 <= x < W and 0 <= y < H:
                i = (y * W + x) * 3
                edge = abs(o) >= HWB - 1
                c = RAIL if edge else deck
                px[i], px[i + 1], px[i + 2] = c


k = 0
while k < len(center):
    if on_water[k]:
        start = k
        while k < len(center) and on_water[k]:
            k += 1
        a = center[max(0, start - 1)]
        b = center[min(len(center) - 1, k)]
        draw_plank_bridge(a, b)
    else:
        k += 1

img = Image.frombytes("RGB", (W, H), bytes(px))
img.save("/tmp/road_brush_preview.png")
# 2x zoom on a road section so the edge quality is visible
img.crop((360, 180, 760, 380)).resize((800, 400), Image.NEAREST).save("/tmp/road_brush_zoom.png")
print("wrote /tmp/road_brush_preview.png + /tmp/road_brush_zoom.png")
