# Importing `.glb` 3D models into Imota

How to take a model you generated in **Modly** (or any DCC tool) and drop it into Imota so it
renders correctly, sits in the right place, matches the pixel-art look, and — crucially — stays
**isolated** from gameplay so you can swap or delete it later without touching game logic.

> TL;DR: raw `.glb` files live in `models/`. Gameplay code never references a `.glb` path. A thin
> **loader script per model** (the only coupling point) instantiates it, fixes scale/offset, and
> applies a stylised material. Everything else just asks for a `Node3D`. The existing
> [`scripts/render/smithy_prop.gd`](../scripts/render/smithy_prop.gd) is the reference
> implementation — copy it.

---

## 0. How Imota renders 3D (so you know where models fit)

- The world is **3D rendered through a low-res SubViewport** (≈640×360) presented at an integer
  scale, plus toon shading + posterization. That low-res pass IS the "pixel art" — you do **not**
  pre-pixelate models; the viewport does it.
- **1 tile = 1 world unit** (`TILE_S = 1.0`). The ground plane is Y-up. The sun is a fixed
  directional light (see [`world_atmosphere.gd`](../scripts/render/world_atmosphere.gd)).
- Almost all current art is **procedural** (`scripts/render/prop_meshes.gd`,
  `mover_meshes.gd`) — meshes built in code. `.glb` import is the path for hand-made/AI-generated
  models that would be painful to build procedurally (buildings, landmarks, props).
- Static props are parented under `render.props_root` and (where possible) batched into MultiMeshes
  by [`static_prop_batcher.gd`](../scripts/render/static_prop_batcher.gd). Moving things (player,
  enemies) are individual animated rigs under the same root.

**Coordinate / unit cheatsheet for Modly export:**

| Imota expectation | Value |
|---|---|
| Up axis | **+Y** |
| Forward (where "front" faces) | **+Z** (the rig faces +Z; orient your model's front toward +Z) |
| Units | **1 tile = 1.0 world unit.** Model a 4-tile building ≈ 4 units wide |
| Origin | Put the origin at the **base center** (X/Z centered, Y at the bottom) if you can — saves offset math |
| Handedness | glTF standard (Godot imports it correctly) |

---

## 1. Where files go (the directory contract)

```
models/                         ← raw .glb source assets live ONLY here
  smithy.glb
  smithy.glb.import             ← Godot auto-generates this; commit it
  <your_model>.glb
  <your_model>.glb.import
scripts/render/
  smithy_prop.gd                ← per-model loader (the isolation layer) — one per model
  <your_model>_prop.gd          ← copy of the pattern for your model
docs/GLB_IMPORT_GUIDE.md        ← this file
tools/glb_inspect.gd            ← prints a .glb's tree + AABB (run headless)
```

Rules:
- **Never** scatter `.glb` files elsewhere or reference `res://models/...` from gameplay/sim/world
  code. The only files allowed to `preload("res://models/…")` are the per-model `*_prop.gd` loaders
  under `scripts/render/`.
- `.glb` is binary; it's already covered by the repo's binary handling. Commit **both** the `.glb`
  and its generated `.glb.import` sidecar (Godot needs the `.import` to map to the baked
  `.godot/imported/*.scn`).
- Keep one model per file. Name files after the *thing*, not the look (`watchtower.glb`, not
  `blue_tower_v3.glb`) so a re-export with a new look drops in over the same name.

---

## 2. Exporting from Modly

Aim for a clean, low-poly, game-ready `.glb`:

1. **Scale to tiles.** 1 tile = 1 unit. If a model should span ~4 tiles, make it ~4 units wide. (You
   can also fix scale at load time — see `scale_for()` — but exporting close to target is tidier.)
2. **Apply transforms** (freeze scale/rotation) before export so the root has an identity transform.
3. **Origin at the base, centered** on X/Z. If you can't, note the bottom Y — `glb_inspect` will tell
   you and you offset at load time.
4. **+Y up, front toward +Z.**
5. **Low poly.** The render target is tiny; keep triangle counts modest. LODs are auto-generated on
   import, but start lean.
6. **Materials — pick one of two paths** (see §6 for detail):
   - **Flat / untextured** (recommended, matches the smithy): export with no textures or a single
     plain material. Imota synthesises the stylised colour at load time.
   - **Textured**: export with an embedded base-color texture (no metalness/roughness maps needed).
     Keep textures small (≤256² is plenty at this resolution).
7. **Embed** textures in the `.glb` (single self-contained file) — easier to manage than loose
   images.
8. **No cameras/lights** in the export. The world owns lighting.
9. **Animations**: only if the model is meant to animate on its own (a windmill, a flag). For
   characters/creatures, prefer the procedural rig system — see §9.

Export → save the `.glb` straight into `models/`.

---

## 3. Importing into Godot

1. Drop `your_model.glb` into `models/`. With the Godot editor open (or on the next
   `godot --headless --path . --import`), Godot generates `your_model.glb.import` and a baked scene
   under `.godot/imported/`.
2. **Inspect it** before writing any code:
   ```
   # edit tools/glb_inspect.gd PATH := "res://models/your_model.glb"  (or generalise it)
   godot --headless --path . res://tools/glb_inspect.tscn
   ```
   It prints the node tree, mesh surfaces, per-surface materials, and the scene **AABB**
   (`pos` = min corner, `size` = extents). Note:
   - `size.x` / `size.z` → how many units wide it is now → your `NATIVE_WIDTH`.
   - `pos.y` → the bottom Y (often negative) → your `SCENE_BOTTOM_Y` for ground offset.
3. **Import settings** (defaults are fine; the smithy uses stock settings). The ones that matter:
   - `nodes/apply_root_scale = true`, `nodes/root_scale = 1.0` — bake export scale.
   - `meshes/generate_lods = true` — free distance LODs.
   - `meshes/create_shadow_meshes = true` — cheaper shadow passes.
   - `materials/extract = 0` — keep materials embedded (we usually override them anyway).
   You normally don't need to touch these. If you do, change them in the editor's Import dock and
   re-import; the choices persist in the `.glb.import` file (commit it).

---

## 4. The isolation layer — a per-model loader (the ONE coupling point)

This is what keeps models swappable. Gameplay/world code asks a small script for a `Node3D`; that
script is the only thing that knows the file path, scale, offset, and look. Copy
[`smithy_prop.gd`](../scripts/render/smithy_prop.gd):

```gdscript
extends RefCounted
class_name WatchtowerProp
## Loads models/watchtower.glb and gives it the world's stylised look. Self-contained: the only
## file that knows this model's path, native size, and ground offset. Swap the .glb (same path) and
## nothing else changes; delete this script + its callers to remove the model entirely.

const GLB := preload("res://models/watchtower.glb")

# From tools/glb_inspect (AABB): bottom Y and native width in world units.
const SCENE_BOTTOM_Y := -0.91
const NATIVE_WIDTH := 2.0

## Scale so the model spans `target_tiles` tiles (1 tile = 1 unit).
static func scale_for(target_tiles: float) -> float:
	return target_tiles / NATIVE_WIDTH

## World-units to add AFTER scaling so the model sits ON the ground.
static func bottom_offset(model_scale: float) -> float:
	return -SCENE_BOTTOM_Y * model_scale

static func build() -> Node3D:
	var inst: Node3D = GLB.instantiate()
	for mi: MeshInstance3D in _all_meshes(inst):
		_styleize(mi)
	return inst

# … _styleize() + _all_meshes() — see §6 + copy from smithy_prop.gd
```

**The contract every loader follows:**
- `build() -> Node3D` returns a ready-to-place node with its look already applied.
- `scale_for(tiles)` and `bottom_offset(scale)` express size/ground placement in **tiles**, not
  raw units, so callers never deal with the model's native scale.
- It `preload`s exactly one `.glb`. No gameplay state, no singletons.

> **Scaling up: a model registry (optional, do this once you have ~5+ models).**
> Instead of one `*_prop.gd` per model, add a data registry `data/models.json`:
> ```json
> { "watchtower": { "path": "res://models/watchtower.glb", "tiles": 3.0, "bottom_y": -0.91, "yaw": 0.0, "style": "flat" },
>   "smithy":     { "path": "res://models/smithy.glb",     "tiles": 4.0, "bottom_y": -0.909, "yaw": 0.47, "style": "flat" } }
> ```
> and a single `ModelLibrary.instance(id) -> Node3D` loader that reads it, instantiates, scales,
> offsets, and applies the style. Then gameplay refers to a **logical id string** (`"watchtower"`)
> and the JSON is the only thing that maps id → file. That's the most decoupled form: re-skinning is
> a JSON edit; adding a model needs no new code. Keep `.glb` loads lazy (`load()` not `preload`) so
> the registry doesn't pull every model into memory at boot.

---

## 5. Placing a model in the world

Models are **pure visuals** parented to the 3D root. The 2D entity/sim layer stays the source of
truth (position, picking, gameplay); the model is just its 3D stand-in. Placement mirrors the
smithy seam in [`world_render_preview_tools.gd`](../scripts/render/world_render_preview_tools.gd):

```gdscript
var s := WatchtowerProp.scale_for(3.0)          # ~3 tiles across
var inst := WatchtowerProp.build()
inst.scale = Vector3(s, s, s)
# iso_to_3d maps a 2D world position to 3D; height_at gives the ground Y at that spot.
inst.position = render.iso_to_3d(pos, render.height_at(pos)) + Vector3(0.0, WatchtowerProp.bottom_offset(s), 0.0)
inst.rotation.y = yaw                            # face it
render.props_root.add_child(inst)
render.invalidate_static_batches()              # if it should batch with other static props
```

Key APIs (all on `WorldRender3D`, reached via `world.render_3d`):
- `iso_to_3d(world_pos: Vector2, y: float) -> Vector3` — 2D→3D position.
- `height_at(world_pos) -> float` — ground height (water surface over water). **Wait until the
  target chunk's data is loaded** before reading height, or the model floats/sinks (the smithy waits
  for `chunk_manager.data_chunks()` to include the spawn chunk).
- `props_root: Node3D` — parent for static props.
- `invalidate_static_batches()` — rebuild MultiMesh batches after adding/removing a static prop.

If you're wiring a model to a **placeable entity kind** (so the editor/spawner can drop it), the
clean hook is in [`prop_meshes.gd`](../scripts/render/prop_meshes.gd): map a `kind`/`prop_kind`
to either procedural `*_parts()` **or** a model loader, and have the renderer instantiate
accordingly. Keep the mapping in one place so a model is opt-in per kind and the procedural version
remains the fallback.

---

## 6. Matching the pixel-art look (materials)

Modly models usually arrive either flat-white (no UVs) or PBR-textured. Neither matches the world
out of the box. Two supported styles:

**(a) Flat / synthesised colour (recommended — what the smithy does).**
The mesh ships untextured; synthesise per-vertex colours (e.g. by height band) + a little hash
dither so facets read as worked material, then a cheap material that uses vertex colour as albedo:

```gdscript
static func _styleize(mi: MeshInstance3D) -> void:
	# … rebuild the mesh writing ARRAY_COLOR per vertex (see smithy_prop._recolor) …
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mat.metallic = 0.0          # NEVER leave metalness on — it reads wrong under the fixed sun
	mi.material_override = mat
```
This is the most "Imota" result and needs no texture work in Modly. Copy
`smithy_prop._recolor()` and change the colour bands.

**(b) Keep the model's texture, just de-PBR it.**
If the model is textured and you want to keep it, override to an unshaded-ish, matte material so it
sits in the toon world (no specular hotspots, no metalness):

```gdscript
var mat := StandardMaterial3D.new()
mat.albedo_texture = <the imported base-color texture>
mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # crisp at low res
mat.roughness = 1.0
mat.metallic = 0.0
mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
mi.material_override = mat
```

Either way: **always set `metallic = 0` and kill specular.** The world has one fixed directional
light and a posterize pass; shiny PBR looks out of place. You do not need to write a custom toon
shader for props — flat albedo + the global light + the viewport posterization already reads as
pixel art.

---

## 7. Ground placement, scale & facing (recap)

- **Scale** in tiles via `scale_for(tiles)`; 1 tile = 1 unit.
- **Sit on the ground**: add `bottom_offset(scale)` to the Y after positioning, so the model's
  lowest point rests on the terrain instead of being half-buried or floating. Derive
  `SCENE_BOTTOM_Y` from `glb_inspect`'s AABB `pos.y`.
- **Face** with `rotation.y`. The world faces +Z; rotate to taste.
- Read ground height with `height_at(pos)` **after** the chunk is loaded.

---

## 8. Shadows

- Static props should **cast** shadows: leave `cast_shadow = SHADOW_CASTING_SETTING_ON` (default) on
  their `MeshInstance3D`s so they drop a real shadow on the toon ground (the ground receives but
  doesn't cast). See [`docs/SHADOWS.md`](SHADOWS.md).
- Movers (player/enemies) use **blob shadows**, not real cast shadows — if you ever swap a creature
  to a `.glb`, disable its real cast shadow and add a blob (see `mover_renderer_3d.gd`).
- `meshes/create_shadow_meshes = true` in the import keeps shadow passes cheap.

---

## 9. Static props vs animated / character models

- **Static props (buildings, rocks, landmarks, scenery):** the easy, supported path. Follow §4–§7.
  Batched and cheap.
- **Self-animating props (windmill, flag, waterwheel):** a `.glb` can ship an `AnimationPlayer`.
  Instantiate it, grab the `AnimationPlayer`, and `play("loop")` in your loader. Keep it a static
  placement (it animates in place).
- **Characters / creatures:** the player and enemies use the **procedural rig + pose system**
  (`mover_meshes.gd` + `mover_rig.gd`) which drives walk/gather/combat poses in code. A rigged
  `.glb` character would need its own skeleton-driven animation path and would NOT get the existing
  pose logic for free. For now, keep characters procedural unless you're prepared to build that
  bridge. Document it as a separate effort if you go there.

---

## 10. Performance

- Keep polys low; rely on auto **LODs** (`generate_lods`).
- Many copies of the same static model → let `static_prop_batcher` MultiMesh them (call
  `invalidate_static_batches()` after placement). Don't add hundreds of individual `Node3D`s.
- Embed/keep textures small (≤256²). The render target is tiny.
- `.glb` files are binary and bloat the repo; prefer a few reusable models over many one-offs.

---

## 11. Headless / CI & determinism

- `res://tools/validate.tscn` runs **headless** and is the gate. `.glb` files *load* fine headless
  (resources instantiate), but nothing renders — so don't put visual assertions there.
- Model placement is **visual only**; never run it inside the deterministic sim (`TickSim`,
  `CombatSim`, worldgen). The smithy preview is gated behind a `--smithy-preview` cmdline flag
  precisely so it never affects normal play or tests.
- After adding a `.glb`, run `godot --headless --path . --import` once so the baked scene + `.import`
  exist, then `validate.tscn` to confirm nothing broke.

---

## 12. Save-safety & replaceability (the whole point)

- Models are **cosmetic**. **Never** store a model node, path, or instance in a save file. Saves
  reference gameplay state (entity kinds, positions, inventory) — the renderer maps that to a model
  at runtime. See the save-safety contract in [`docs/SAVE_FORMAT.md`](SAVE_FORMAT.md).
- **Swapping a model** = drop a new `.glb` over the same filename (and re-check AABB constants if the
  size changed). No gameplay change, no save migration.
- **Removing a model** = delete the `.glb` + its `*_prop.gd` loader + its caller. Because gameplay
  referenced a logical kind/id (not the file), the worst case is the renderer **falls back to the
  procedural mesh** for that kind. Make your kind→model mapping degrade gracefully: if the model is
  missing, build the procedural part instead of crashing.
- Keep `SCENE_BOTTOM_Y` / `NATIVE_WIDTH` (or the registry's `tiles`/`bottom_y`) as the *only* magic
  numbers, all in the loader/registry — so a re-export only touches those.

---

## 13. Step-by-step checklist

1. **Modly**: model low-poly, +Y up, front +Z, origin at base-center, scale ~tiles, flat or single
   small embedded texture, no lights/cameras → export `.glb`.
2. Save it into `models/your_model.glb`.
3. `godot --headless --path . --import` (or open the editor) → generates `your_model.glb.import`.
4. Point `tools/glb_inspect.gd` at it, run headless, note **AABB** (`size.x`=width, `pos.y`=bottom).
5. Copy `scripts/render/smithy_prop.gd` → `your_model_prop.gd`; set `GLB`, `NATIVE_WIDTH`,
   `SCENE_BOTTOM_Y`; tune `_styleize`/`_recolor` colours.
6. Place it: `build()` → set `scale = scale_for(tiles)`, `position = iso_to_3d(pos, height_at(pos)) +
   bottom_offset`, `rotation.y`, add to `render.props_root`, `invalidate_static_batches()`.
7. (Optional) Register it in `data/models.json` + `ModelLibrary` and map an entity `kind`/`prop_kind`
   to it for editor/spawner placement, with the procedural mesh as fallback.
8. Commit **`.glb` + `.glb.import` + the loader**. Run `validate.tscn`.

---

## 14. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Model is **flat white** | No vertex colours/material — apply `_styleize` (vertex colour or texture override). |
| **Too shiny / plasticky** | `metallic = 0`, `roughness = 1`, disable specular. |
| **Half-buried or floating** | Wrong `SCENE_BOTTOM_Y`; re-read AABB `pos.y` and add `bottom_offset()`. Also ensure you read `height_at()` *after* the chunk loaded. |
| **Wrong size** | `NATIVE_WIDTH` doesn't match the AABB `size.x`; or you forgot `scale_for()`. |
| **Faces inside-out / dark** | Backface culling on inverted normals — fix normals in Modly and re-export. |
| **Blurry texture** | Set `texture_filter = TEXTURE_FILTER_NEAREST` on the material. |
| **Doesn't appear in headless tests** | Expected — nothing renders headless; verify in the windowed app or a preview tool. |
| **Editor didn't generate `.import`** | Run `godot --headless --path . --import`; commit the `.import`. |
| **Repo bloating** | `.glb` is binary; reuse models, keep them small, avoid one-offs. |

---

## 15. Reference files

- Working example loader: [`scripts/render/smithy_prop.gd`](../scripts/render/smithy_prop.gd)
- Placement seam: [`scripts/render/world_render_preview_tools.gd`](../scripts/render/world_render_preview_tools.gd)
- Inspector: `tools/glb_inspect.tscn` / `tools/glb_inspect.gd`
- Look preview: `tools/smithy_preview.tscn` (renders a model from a few angles to eyeball colours)
- Procedural prop system (the fallback / sibling): [`scripts/render/prop_meshes.gd`](../scripts/render/prop_meshes.gd)
- Render coordinator + APIs: [`scripts/render/world_render_3d.gd`](../scripts/render/world_render_3d.gd)
- Shadows: [`docs/SHADOWS.md`](SHADOWS.md) · Art conventions: [`docs/ART_GUIDE.md`](ART_GUIDE.md)
