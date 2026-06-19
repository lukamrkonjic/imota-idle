# World design & decisions

Why Imota's world looks and is built the way it is. This is the **vision +
decision record** for geography; the mechanics of how chunks are generated live
in [WORLDGEN_GUIDE.md](WORLDGEN_GUIDE.md), and how things are drawn in
[ART_GUIDE.md](ART_GUIDE.md). Read this before changing the shape of the world,
the progression layout, or how content is added.

## The vision

A **living, RuneScape-like continent you explore on foot** — not a procedural
blob and not a menu of activities. The world should feel *authored and
geographically specific*: a big irregular landmass with peninsulas, gulfs, bays,
mountain country and offshore islands, where places are describable ("the desert
is east, the snow is north, the volcano is the north-east corner") and where new
regions, biomes and even whole new worlds can be **bolted on over time** the way
RuneScape grew — without regenerating or breaking what already exists.

## The decisions

Each entry is a load-bearing choice: **decision → why → consequence**.

### D1 — The world is built from tiles, grouped into chunks

- **Decision:** the unit of the world is a 32px isometric **tile**; tiles are
  grouped into **16×16 chunks** (`WG.CHUNK_TILES`). Everything — terrain,
  collision, biomes, elevation, structures, sites, monsters — is stored per tile
  in a chunk.
- **Why:** chunks stream in/out around the player, serialize compactly, can be
  hand-painted in the editor, and bake to a shipped file. A tile grid keeps
  pathfinding, placement and collision simple and deterministic.
- **Consequence:** new world features must be expressible as tile/chunk data.
  Coordinates come in two spaces — **chunk space** (regions, anchors, bounds) and
  **tile space** (settlements, roads, features); 1 chunk = 16 tiles, chunk `c` →
  centre tile `c*16 + 8`.

### D2 — A finite, authored continent with open ocean beyond

- **Decision:** the primary world (**Aldreth**) is a *finite* continent with
  declared `bounds` in chunk space and open ocean past them, baked to
  `data/world/baked/aldreth.world`. Regions flagged `fixed:false` (e.g. the
  Tanglewild) stay procedural at runtime.
- **Why:** a fixed, handcraftable, shippable world reads as a real place and lets
  us place deliberate cities/landmarks/quests — the OSRS model — while still
  keeping pockets of endless procedural wilderness.
- **Consequence:** the world has a real edge. The infinite generator still exists
  and is reused per chunk, but the finite layer (coastline, authored regions,
  baking) sits on top — see `FiniteWorldGenerator`.

### D3 — The coastline is an irregular landmass, never a radial disc

- **Decision:** continent shape comes from a **signed landmass field**
  (`BiomeClassifier._landmass`): heavily domain-warped low-frequency continent
  noise (peninsulas/gulfs) + ridged detail (capes/coves) + an offshore
  archipelago layer (islands) + a gentle radial falloff. It is **not** distance
  from centre.
- **Why:** the old world was "a huge circle." A living OSRS-like map needs big
  asymmetric landmasses, deep bays, large peninsulas and scattered islands.
- **Consequence:** authored content can't be allowed to drown. Every authored
  region gets a **land-guarantee disc** plus a **corridor** back to the core, so
  the mainland stays one walkable body and the coast still wiggles organically
  just outside those zones. Tuning constants (`_SHORE_R`, `_FALL_SLOPE`,
  `_SEA_LEVEL`, island/guarantee params) live at the top of that block; iterate
  with `tools/coast_preview.tscn` (~3s) before a full bake.

### D4 — Progression is radial and decoupled from the coastline

- **Decision:** difficulty/level radiates **outward from the centre**
  (`norm_dist`/`danger01`), and authored regions carry an explicit `req`/`danger`.
  This is independent of the irregular coast shape.
- **Why:** the shape should be organic, but the *difficulty curve* must stay
  legible — safe green core, rough dangerous rim, like concentric OSRS bands —
  so a player always knows roughly how dangerous "further out" is.
- **Consequence:** a long thin peninsula or a far island is high-level because
  it's far from the hub, which is the intended RuneScape feel (remote = riskier).
  Don't re-couple danger to the coastline.

### D5 — Biomes have fixed home directions

- **Decision:** each biome family has a **compass home** on the continent —
  forest west, desert east, snow/tundra & rocky hills north, swamp/jungle south,
  the volcano in the NE corner — with warped, organic band borders
  (`biome_map_generator._pick_parent_id`).
- **Why:** a describable, memorable geography ("head north-east for the volcano")
  instead of a random biome blob.
- **Consequence:** place new biomes by extending the directional model, not by
  scattering them. A safe plains/farmland hub always sits at the centre.

### D6 — Handcrafted core + procedural wilderness

- **Decision:** in-bounds chunks are **baked** (fixed) unless their region is
  `fixed:false`, which keeps **generating procedurally at runtime**.
- **Why:** hand-author the places that matter (capital, mining town, ruins) and
  let lawless/edge zones (e.g. the Tanglewild jungle) stay ever-shifting and
  cheap to expand.
- **Consequence:** `WorldGen` returns cached → snapshot → freshly generated, in
  that order. Explored land is frozen via snapshots until you deliberately
  invalidate; unvisited land always picks up the latest generator (see
  [WORLDGEN_GUIDE.md](WORLDGEN_GUIDE.md), and bump `generatorVersion` when
  generation rules change).

### D7 — Mountains are localized masses, not elevation-band scenery

- **Decision:** mountain geography gates compact local mass fields with one
  dominant dome/summit. The main slope stays continuous; two spatially masked
  shelf cuts create partial ledges without closing into contour rings. Visual
  material follows slope and curvature before elevation, and elevated decor is
  clustered by landform. The renderer lightly low-passes geometry without
  changing the gameplay height grid.
- **Why:** a broad geographic belt split into many height bands exposes the
  generator as parallel contour stripes and creates sawtooth silhouettes.
- **Consequence:** do not use a compass belt as mountain height by itself, add
  thin shelf bands, or assign alpine material from elevation alone. Preserve
  exact `chunk.elev` values for gameplay and smooth only the rendered surface.
  Procedural lakes must pass a broad-basin test, mountains displace stray water
  above their feet, and the visible alpine trail must also carve a climbable
  ramp through shelf cliffs. Only the final summit crown is non-navigable.
  In finite worlds, the signed landmass field is the sole source of ocean/beach
  parent biomes; low inland macro-height is a valley, never an inland sea.

## Seamless expansion — how content grows

This is the point of the whole design: add content **without** reshuffling the
existing world.

- **Add a region** to `data/world/worldspec/aldreth.json`: a disc in chunk space
  with a biome, level `req`, danger and motif. It automatically gets a
  land-guarantee + corridor (D3), so its peninsula/island is reachable. Bump
  `generatorVersion`, then rebake (`tools/world_bake.tscn`) or "Generate" in the
  editor.
- **Add a biome** in the biome data (palette tiles + ground-decor kinds), then
  give it a home direction in `_pick_parent_id`. New micro-biomes stamp on top
  via sub-biome rules.
- **Add a structure / prop / creature:** follow the registration chain in
  [ART_GUIDE.md](ART_GUIDE.md); it becomes paintable in the editor and shows in
  the preview automatically.
- **Add a whole new world (region/continent like a new RuneScape landmass):**
  drop a new `worldspec/<id>.json`, register it, and point
  `worldspec/index.json` `active` at it (or wire travel between worlds).
  `WorldRegistry` loads exactly one active spec; setting `enabled:false` falls
  back to the pure procedural world.
- **Future-facing:** offshore islands are intentional content hooks (reachable by
  boat/teleport later), mirroring Karamja/the Fremennik isles. Keep the mainland
  connected by land; gate islands behind travel, not behind broken pathing.

## Authoring & iteration tools

| Tool | Use |
|---|---|
| `tools/world_editor.tscn` | paint biomes/terrain/structures, set spawn, generate, save, with a live placeable preview |
| `tools/coast_preview.tscn` | ~3s half-res landmass render — tune coastline shape before baking |
| `tools/world_bake.tscn` | full offline bake of the finite world (+ overview map PNG) |
| `tools/world_shoot.tscn` | windowed in-game screenshots of named places |
| `tools/validate.tscn` | headless checks incl. "spawn is dry land", coastline, reachability |

After any change to world shape or generation: rebake, then run
`tools/validate.tscn` and confirm spawn/coastline/reachability checks pass.
