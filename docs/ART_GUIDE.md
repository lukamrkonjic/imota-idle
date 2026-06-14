# Isometric pixel-art guide

How Imota draws its world, ground, props, houses, structures and creatures — and
how to add a new one that matches. **Read this before authoring any art.** The
canonical "good structure" to copy is the ruin pillar
(`scripts/world/art/structures/ruin_pillar_art.gd`); it is dissected in full
below.

## The look in one paragraph

Everything is **procedural pixel art drawn in `_draw()`** — there are no sprite
images or atlases. Each piece is a `static func draw(canvas, …)` that paints a
few **pixel-snapped polygons** in **true 2:1 isometric projection**, lit by a
**single global sun from the upper-right**, using the shared **Grimbo/Aldenfall
palette**. One "art pixel" is `PixelPalette.PX` (4) screen pixels, and every
coordinate is snapped to that grid so the result stays crisp at any zoom. Solids
are built from **isometric boxes** (a diamond top + two shaded side faces), not
flat billboards, so a prop reads as a real 3D object sitting in the world.

## The coordinate contract (memorize this)

- **Origin `(0,0)` is the object's foot on the ground.** The art rises *upward*,
  i.e. into **negative Y**. A 60px-tall thing occupies `y ∈ [-60, 0]`.
- **+X is right, +Y is down** (Godot canvas). The camera is fixed isometric.
- **A ground tile is a 2:1 diamond:** half-height ≈ half-width × 0.5
  (`hh = hw * 0.5`). Keep every footprint to that ratio so bases sit flat on the
  tile grid.
- **The sun comes from the upper-right.** On a solid: the **top** is brightest,
  the **south-east** face is lit, the **south-west** face is shadowed. Shadows
  are cast down-and-left. (`PixelDraw.iso_box` already bakes this in.)
- Art is drawn at the node's local origin. `WorldEntity` (and the editor
  previewer / `tools/prop_preview.gd`) place that origin on the ground for you —
  you only ever draw relative to `(0,0)`.

## The toolbox

### `PixelPalette` (`scripts/world/art/core/pixel_palette.gd`)

| Call | Use |
|---|---|
| `PX` (=4) | screen pixels per art pixel |
| `snap(n)` | quantize a coordinate to the art grid (primitives do this for you) |
| `pal("stone_b")` | a named palette colour — **prefer these over raw hex** |
| `hex(0x5A6B4A)` | a one-off colour |
| `shade(c, f)` | multiply value for highlights (`f>1`) / shadows (`f<1`) |
| `enrich_entity(c)` | bump saturation so a prop reads against terrain |

Palette keys live in the `PAL` dict (`grass_a/b/c`, `dirt_a/b`, `stone_a/b`,
`water_a/b`, `trunk_a/b`, `snow_a`, `gold`, `shadow`, …). Build a material from
**one base colour + `shade()`** rather than picking three unrelated hues.

### `PixelDraw` (`scripts/world/art/core/pixel_draw.gd`)

| Primitive | Draws |
|---|---|
| `px_rect(c, x, y, w, h, col, a)` | a pixel-snapped filled rect |
| `px_row(c, cx, y, half_w, col, a)` | a centered 1px-tall row (roof courses, tapers) |
| `px_diamond(c, cx, cy, hw, hh, col, a)` | a 2:1 ground/top diamond |
| `px_blob(c, cx, cy, rx, ry, col, a)` | a soft ellipse (foliage, rubble) |
| **`iso_box(c, cx, cy, hw, hh, h, top, lit, shadow)`** | **the workhorse**: a 2:1 isometric prism — diamond top + SE lit face + SW shadow face, base at `(cx,cy)`, rising `h` px |
| **`iso_block(c, cx, cy, hw, hh, h, base)`** | `iso_box` from a single base colour, auto-shading the three faces |
| `draw_foliage_clump`, `draw_trunk_base` | canopy / trunk helpers |

**Solids are stacks of `iso_block`.** A column is plinth + shaft + capital; a
crate is one block; a wall is a long thin block. Reach for `iso_block` first.

### Shadows — never skip them

Every prop/character/structure casts **one** shadow through the shared sun, so
the whole world stays consistent. Call it **first**, before drawing the body, so
the object sits on top of its own shadow:

- props/structures → `PixelDraw.draw_foot_shadow(canvas, radius_x, radius_y, alpha, height)`
- characters/creatures → `PixelDraw.draw_tight_character_shadow(...)`
- trees/vegetation → `PixelDraw.draw_tree_shadow(...)`

Do **not** draw your own oval or stacked translucent blobs. See
[docs/SHADOWS.md](SHADOWS.md) for the projector and the global sun settings.

## Worked example — the ruin pillar (copy this shape)

`scripts/world/art/structures/ruin_pillar_art.gd` is the reference structure: a
broken stone column built as a **vertical stack of isometric prisms** with
variant-driven proportions and a few cheap weathering accents.

```gdscript
const HEIGHTS := [42.0, 60.0, 78.0, 30.0]

static func draw(canvas: CanvasItem, variant: int = 0) -> void:
    PixelDraw.draw_foot_shadow(canvas, 15.0, 5.0, 0.3, 60.0)   # 1. shadow FIRST
    var stone := PixelPalette.pal("stone_b")                   # 2. one base material…
    var moss := PixelPalette.pal("grass_a").lerp(stone, 0.35)  #    …+ derived accents
    var vine := PixelPalette.pal("grass_c")
    var h: float = HEIGHTS[variant % HEIGHTS.size()]           # 3. variant -> height tier
    var hw := 6.0 if variant % 2 == 0 else 7.5                 #    variant -> width
    var hh := hw * 0.5                                         #    2:1 footprint

    # 4. stack solids from the ground up (each sits on the one below)
    PixelDraw.iso_block(canvas, 0.0, 0.0,  hw + 4.0, (hw + 4.0) * 0.5, 9.0,  PixelPalette.shade(stone, 0.9))  # plinth
    var sh := h - 9.0
    PixelDraw.iso_block(canvas, 0.0, -9.0, hw, hh, sh, stone)                                                 # shaft
    PixelDraw.px_rect(canvas, 2.0, -h + 8.0, 1.5, sh - 12.0, PixelPalette.shade(stone, 0.78), 0.5)            # carved flute on the lit face
    var top_y := -9.0 - sh
    if variant % 3 == 0:
        PixelDraw.iso_block(canvas, 0.0, top_y, hw + 2.5, (hw + 2.5) * 0.5, 6.0, PixelPalette.shade(stone, 1.02))  # intact capital
    else:
        PixelDraw.iso_block(canvas, 1.5, top_y, hw * 0.72, hw * 0.36, 5.0, PixelPalette.shade(stone, 0.84))        # broken crown, knocked off-centre

    # 5. cheap weathering accents — thin alpha rects, no new geometry
    PixelDraw.px_rect(canvas, -hw + 1.0, -h * 0.5, hw + 2.0, 5.0, moss, 0.5)
    PixelDraw.px_rect(canvas, hw - 1.0, -h + 8.0, 2.0, 16.0, vine, 0.5)
```

Why it's good, and the rules it embodies:

1. **Shadow is cast first**, sized to the footprint and height.
2. **One base colour (`stone_b`) + `shade()`/`lerp()`** for every face and
   accent → the piece is colour-coherent.
3. **`variant` drives proportions deterministically** (height tier, width, and
   whether the capital survived) so a field of pillars looks varied from one
   function. Same `variant` ⇒ identical art, every time.
4. **The body is a stack of `iso_block` prisms** standing on the ground origin
   and rising in −Y — real isometric volume, not a flat sprite.
5. **Details are a handful of thin `px_rect`s with alpha**, layered on top — a
   flute seam on the *lit* face, a moss band, hanging vines. Maximum read for
   minimum geometry.

Keep that silhouette discipline: a clear base, a readable mass, 2–4 accent
strokes. If a piece needs dozens of rects to read, simplify the shape.

## The chunky low-res target (the house rule)

Every asset must look like it was drawn on a **very small pixel canvas and
enlarged with nearest-neighbour scaling** — immediately readable, simplified and
charming. The benchmark set is the **pillar, altar, tree, chest, barrel and
crate**. If a redesigned piece looks more precise, more linear, or more detailed
than those, simplify it again.

**Core rules**

- Build form from **2–4 chunky shade bands per major surface**, not smooth
  rendering. Describe volume with **visible value steps**, not thin line detail.
- Use **3–5 tones per material maximum**; keep the palette muted and derived from
  `pal()` + `shade()`/`lerp()` (one base colour, not unrelated hues).
- **Silhouette first**, internal detail second. Fewer tiny features, more bold
  geometric masses. Hard pixel edges only — no AA, blur or smooth gradients.
- **Avoid long uninterrupted straight lines**, especially on roofs, walls,
  bridges and signs. Break large surfaces into slightly irregular, chunky tonal
  groups so they feel low-res and hand-placed.
- **Large objects use larger shapes, not more detail.** A bigger asset gets
  bigger masses and bigger bands — never finer trim.

**Avoid:** thin linework, long clean diagonals, repeated roof slats, brick-by-brick
texture, tiny architectural trim, narrow supports, high-frequency detail, noisy
textures, smooth shading, glossy rendering, or art that feels like a
higher-resolution piece shrunk down.

**Large surfaces (the missing piece).** Do *not* render big planes (roofs, walls,
interior floors) as long clean surfaces with a few straight lines. Describe them
with **chunky stepped shading clusters** so the surface itself reads low-res:

- **Roofs:** a few **broad stepped tonal bands** (eave darkest → ridge lightest)
  via `_roof_plane`-style band loops, *not* parallel slats or thin course lines.
  Cap the ridge with one fat band.
- **Walls:** a big plaster/stone field broken by **two broad light/shadow
  clusters** and **2–3 fat corner/top beams** — never tidy paneling or repeated
  framing. Windows and doors are **large, blockier, iconic** shapes.
- **Floors / flat surfaces:** broad low-res tonal patches (a couple of shaded
  diamonds), not many even stripes.
- **Stone (walls, towers, gates):** big iso-block masses with a couple of broad
  shade courses and a **few fat merlons** — never a per-brick mortar grid.

The redesigned house, hall, tent, sign, bridge, wall, gate, tower, cart and anvil
(2026-06-14) are the worked examples of this target — copy their massing.

## Houses & buildings (body + roof split)

`house_art.gd` / `building_art.gd` split into **`draw_body()`** and
**`draw_roof()`** so the roof can fade as the player steps inside and reveal the
interior floor (`WorldEntity.roof_alpha`, driven by the visual controller).
Conventions:

- The body always draws the interior floor + walls + door + lit windows; the
  roof draws separately as **narrowing `px_row`s** (a pitched roof) with an eave
  and ridge cap.
- Expose `total_height(variant)` so `WorldEntity.icon_height()` and the previewer
  can frame it.
- `roof_color` themes the building so a street reads as varied; `variant` nudges
  width/height.
- **Multi-tile footprint:** `building` carries its footprint in tiles via
  `WorldEntity.display_size` (e.g. a 7-tile hall). Walls become non-walkable
  `building_wall` tiles (the bake/editor paints them), so collision comes from
  the tile layer, not an entity box.

## Sizing & registration — adding a NEW structure end-to-end

1. **Art module:** `scripts/world/art/structures/<name>_art.gd`, `class_name
   <Name>Art`, with `static func draw(canvas, variant)` (cast a shadow first,
   draw at origin). Add `total_height(variant)` if it's tall.
2. **Facade:** add a `const <Name>Art := preload(...)` and a thin
   `draw_<name>(...)` (and `<name>_height(...)`) wrapper to
   `scripts/world/art/iso_sprites.gd`. All art is reached through this facade.
3. **Entity dispatch:** add a `kind` case in `scripts/world/world_entity.gd`
   `_draw_sprite_to(canvas)` — draw onto `canvas`, NOT `self`, so the static
   sprite cache can bake it (call your `IsoSprites.draw_<name>(canvas, …)`) — and
   in `icon_height()` (return its height so labels/HP bars, the bake bounds and
   the previewer frame it). A new static (non-animated) kind is baked to a texture
   automatically; add it to `LIVE_KINDS` only if it must animate every frame.
4. **Spawning:** if it's placed by generation, map its `part` dict → entity
   properties in `scripts/world/world_entity_spawner.gd` `_spawn_poi_part()`
   (variant, colours, `display_size`, etc.).
5. **Collision:** if it's a solid free-standing object, give it a footprint in
   `FiniteWorldGenerator.footprint_radius()` (return `0` to block its own tile,
   `-1` to stay passable). Tile-backed buildings/walls return `-1`.
6. **Editor placement:** add `["Label", {"kind": "<name>", …}]` to the
   `STRUCTURES` list in `tools/world_editor.gd` so it can be painted.
7. **Preview is automatic:** once steps 2–3 are done, the editor's showcase
   panel (`tools/placeable_preview.gd`) renders it from the same art path.

`WorldEntity.display_size` means different things per kind (sprite size for
trees/props, footprint-in-tiles for `building`/`mountain`); follow the existing
case for your kind in `_spawn_poi_part`.

## Ground, biomes & decor

- **Ground tiles** are flat data-driven colours (`data/world/*.json`,
  `reg.tile_def(id)["colors"]`) rendered by the dithered terrain shader
  (`shaders/terrain_ground.gdshader`) — not procedural draw functions. Biome
  identity, tile palettes and ground-decor rules live in data; the generator
  (see [docs/WORLDGEN_GUIDE.md](WORLDGEN_GUIDE.md)) decides placement.
- **Ground clutter** (grass tufts, ferns, flowers, pebbles, reeds, mushrooms…)
  is `WorldDecor` → `scripts/world/art/ground_decor/ground_decor_art.gd`, keyed
  by `kind`. To add a clutter kind: add a `<kind>_decor.gd` drawer, a case in
  `ground_decor_art.gd`, then list it under a biome's `kinds` in the ground-decor
  data so the spawner scatters it.
- **Mountains** are terraced *terrain elevation* (the source of truth), with a
  `mountain` art massif dropped on the peaks — see `mountain_art.gd` and
  `_place_mountains` in `world_generator.gd`.

## Eyeballing your art (no full play session)

- **Editor previewer:** open `tools/world_editor.tscn`, pick a tool, and the
  showcase panel spins up one instance on an iso tile. 🎲 re-rolls the variant.
- **Headless-ish grid:** `tools/placeable_preview_shoot.tscn` and
  `tools/prop_preview.tscn` render a grid of pieces to a PNG (needs a real
  renderer, not `--headless`):
  ```
  godot --path . res://tools/prop_preview.tscn -- --out=C:/shots/
  ```

## Style Decisions

- **2026-06-14 - camp/city utility structures avoid primitive silhouettes.**
  Tents use slumped A-frame cloth panels instead of perfect pyramids; chests,
  burrows and city walls use stacked solids, organic collars, chips, roots,
  planks and sparse pixel patches. **Why:** smooth primitive shapes read as
  low-poly models beside the trees, enemies, pillars, altars and gathering
  nodes. **Consequence:** future tents, walls and utility props should change
  the silhouette first, then add texture; dithering a cone/cube is not enough.
- **2026-06-14 - all inconsistent assets redrawn chunky low-res.** The house,
  hall, tent, sign, bridge, wall/gate/tower, cart and anvil were rebuilt to the
  pillar/altar/chest/barrel/crate benchmark: 2–4 broad shade bands per surface,
  large blocky windows/doors, broad stepped roof bands (no slats), big stone
  masses (no per-brick mortar), and bold readable silhouettes. **Why:** their
  thin linework, parallel roof lines, half-timber framing and brick texture made
  them feel like higher-res art shrunk down, clashing with the rest of the set.
  **Consequence:** this supersedes the earlier "steep gables / half-timber panels
  / tile rows" guidance — see "The chunky low-res target" above; describe big
  planes with stepped tonal clusters, not clean lines.
- **2026-06-14 - medieval buildings must be compressed to the world style.**
  Houses and halls use the tree/fountain visual language as the primary style
  reference: broad 4-6 roof bands, chunky block windows, large plaster/stone
  patches, few colors per material, soft stepped shading and minimal outlines.
  **Why:** dense shingles, tiny facade marks and noisy wall dithering make a
  building feel like it came from another asset set. **Consequence:** reduce
  house visual information by roughly half or more before adding detail; keep
  the entrance on the readable side wall for halls.

## Do / Don't checklist

**Do**
- Draw at origin `(0,0)`, build upward in −Y.
- Build volume from `iso_block`/`iso_box`; keep footprints 2:1.
- Cast exactly one shadow, first, via the `PixelDraw` helpers.
- Derive every colour from `pal()` + `shade()`/`lerp()`.
- Drive variety from a deterministic `variant` int.
- Keep a clean silhouette; add detail as a few alpha `px_rect`s.

**Don't**
- Load image/sprite assets or draw flat billboards.
- Use raw `draw_rect`/`draw_circle` instead of the snapped `px_*` primitives.
- Hand-roll a shadow oval or stack translucent blobs.
- Light from the wrong side (sun is upper-right: top brightest, SE lit, SW dark).
- Add a `kind` to `WorldEntity` without also giving it an `icon_height()` case.
