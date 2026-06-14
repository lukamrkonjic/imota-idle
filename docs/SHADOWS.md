# Directional shadow system

One global, stylized sun drives every shadow in the world. Characters, trees,
tents, props, walls and buildings all cast in the **same direction**, at the
**same projection angle**, in the **same desaturated colour**, with the **same
crisp pixel-snapped edge style**. It replaces the earlier mixture of centered
ovals, swept convex-hull "carpets", and multi-blob streaks.

## How it fits this engine

The world is drawn procedurally in `_draw()` (no sprite nodes), and **every
shadow funnels through four entry points**, so the system is centralized rather
than living on per-object `ShadowCaster2D` nodes:

| File | Role |
|---|---|
| `scripts/world/art/core/world_lighting.gd` | **`WorldLighting`** (the "WorldLightingSettings"): the shared sun — direction, elevation, colour, opacity, length, contact strength, max length, pixel-snap. The documented world→iso conversion lives here. |
| `scripts/world/art/core/shadow_projector.gd` | **`ShadowProjector`**: the one caster. `contact`, `cast_blade`, `cast_tree`, `cast_silhouette`. Every shadow is a *small number of solid, flat-alpha, pixel-snapped polygons* — never stacked translucent blobs or a swept hull. |
| `scripts/world/art/core/pixel_draw.gd` | `draw_foot_shadow` / `draw_tight_character_shadow` / `draw_tree_shadow` — the prop/character/tree entry points, routed to `ShadowProjector`. ~40 callers upgraded with no call-site churn. |
| `scripts/world/art/structures/building_art.gd` | Buildings call `ShadowProjector.cast_silhouette` directly. |

No shaders, no blur textures: edges are crisp and pixel-snapped to match the
art. "Softness" is the low, desaturated alpha itself, not a Gaussian.

## The global sun (`WorldLighting` = WorldLightingSettings)

```gdscript
WorldLighting.sun_azimuth_deg          # sun bearing in WORLD ground space; shadows fall opposite
WorldLighting.sun_elevation_degrees    # sun height; LOWER => LONGER shadows
WorldLighting.shadow_color             # dark, desaturated cool grey — never pure black
WorldLighting.shadow_opacity           # master alpha of a single projected shadow (kept low)
WorldLighting.shadow_length_multiplier # global length scale
WorldLighting.contact_shadow_opacity   # the compact patch right under the foot
WorldLighting.maximum_shadow_length    # hard px clamp so tall things don't blanket the map
WorldLighting.pixel_snap_enabled       # snap shadow geometry to the art pixel grid
```

### World → iso conversion (the important part)
The camera is isometric, so **screen-down is NOT a valid ground direction**. We
take the sun bearing in world-ground space, flip it (shadows oppose the sun),
then map it onto the iso ground:

```
screen.x = (world.x - world.y)
screen.y = (world.x + world.y) * ISO_RATIO   # ISO_RATIO = 0.5
```

`ground_dir()` returns that normalised screen vector; `project(height)` returns
the throw length in px (`height × length_factor`, clamped to
`maximum_shadow_length`). The default `sun_azimuth_deg = 245` puts the sun in
the upper-right (matching the art, which lights NE faces brightest), so shadows
fall toward the lower-left — in front of objects, onto visible ground.

### Day/night
Tween any field above from a controller and every shadow follows on the next
redraw. No per-object work.

## Shadow structure (two parts)

Every caster gets a **compact contact patch** at its ground point plus a
**projected shadow** whose length scales with the caster's height:

```
projected_length = object_height × length_factor   (clamped to maximum_shadow_length)
```

| Caster | Call | Shape |
|---|---|---|
| Prop / structure / wall | `PixelDraw.draw_foot_shadow(c, foot_half, _, alpha, height)` | one tapering **blade** + contact |
| Character / NPC | `PixelDraw.draw_tight_character_shadow(c, body_half)` | short subtle **blade** + contact |
| Tree / bush | `PixelDraw.draw_tree_shadow(c, canopy_r)` | narrow **trunk blade** + **canopy disc** + contact |
| Building / large structure | `ShadowProjector.cast_silhouette(c, footprint, roof_height)` | footprint + smaller offset roof diamond hulled into one **leaning house silhouette** + foundation patch |

`alpha` on the prop/character/tree calls is now only a **relative weight** (vs
each helper's baseline, clamped to a sane range). The master strength is
`shadow_opacity`.

## Terrain receiving (hooks)

`WorldLighting.receives_shadow(surface)` and `surface_opacity_scale(surface)`
classify `"ground" | "road" | "water" | "elevated" | "cliff" | "hidden"`:
hidden/cliff receive nothing; water takes a fainter, cooler shadow. The world is
currently flat (no elevation/cliff geometry), so these are policy hooks ready
for when elevation is added — see *Known limitations*.

## Opacity & overlap
`shadow_opacity` is deliberately low (≈0.22) and each shadow is a **single flat
fill**, so two or three overlapping shadows read as "darker ground", never a
solid black region. `shadow_color` is a desaturated cool grey, not black.

## Draw order
Shadows are drawn **first** in each caster's `_draw`, beneath the body, and (with
the sun in the upper-right) fall toward the viewer onto visible ground, where the
scene's Y-sort orders front objects above them. Shadows never affect collision,
navigation, input or selection.

## Performance
Static shadows (buildings, walls, fixed props, chunks) only redraw when their
object redraws; chunk ground freezes after first draw. Only moving/animated
casters (player, NPCs, wind-swayed trees, animated props) redraw per frame. All
fills are cheap solid polygons — no per-pixel work, no per-object materials.

## Known limitations (honest notes)
* **Cross-object overlap** is controlled by low single-fill alpha, not a shared
  compositing buffer. Three+ heavy overlaps tint but never go black; a dedicated
  `CanvasGroup` shadow layer is the future upgrade if strict capping is wanted.
* **Elevation/cliffs**: the receiving hooks exist but the world has no elevation
  geometry yet, so shadows are not split/clipped at cliff faces.

## What caused the old artifacts (migration note)
* **Diagonal banding / striped building carpets** came from `cast_hull`, which
  swept the *whole footprint* along the light and filled the convex hull — a fat
  parallelogram — plus stacked translucent penumbra layers. Replaced by
  `cast_silhouette` (one solid house-shaped polygon + foundation patch).
* **Segmented "chain of blocks" smears** under props/characters came from
  `cast_streak`, which drew **5 discrete translucent blobs** along a line; the
  gaps and overlaps read as detached segments and banding. Replaced by
  `cast_blade` (one continuous tapering quad).
* **Giant black ovals** were oversized centered contact ellipses; now `contact`
  is a small, pixel-snapped patch.
* **Stretched-down-screen shadows** assumed screen-down ≈ world-south; now the
  direction always comes from the documented iso conversion in `ground_dir()`.

## Validation
`tools/shadow_test.tscn` lays out a player, tree, tent, prop, large building,
wall, and two overlapping casters on a ground band:
```
godot --path . res://tools/shadow_test.tscn -- --out=C:/path/shots/
```
Saves `shadow_test.png`. Use it to confirm shared direction, height-based
length, contact points, no stripes, and that overlaps stay readable.
