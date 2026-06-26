# Adding new features — where does it go?

Decision tree. Find your feature, do the smallest change in the named place, reuse existing systems.

## "I want to add content the player gets/uses"
- **A new item** (material/food/equipment) → `data/items.json` only. → `INVENTORY_ITEMS_AND_RESOURCES.md`.
- **A new tool** → `data/tools.json` + an equippable `data/items.json` entry (slot Axe/Pickaxe/Rod/Lens).
- **A new gather node / rock / fish / herb** → `data/gather_nodes.json` (+ item; + optional biome rule
  in `data/world/skill_sites.json`). Re-bake or place in the editor.
- **A new recipe** (cook/smith/craft/…) → `data/recipes.json` (+ output item).
- **A new enemy** → `data/enemies.json` (+ drop items); place via monster/POI data or editor.
- **A new prayer** → `data/prayers.json`. **A new crop** → `data/farming.json`.
> None of these need new code. Add JSON, then `validate.tscn`.

## "I want a new world thing"
- **A new placed object / station / landmark** → a `WorldEntity kind` + its `action`; spawn it from
  POI data (`data/world/pois.json`) handled in `scripts/world/world_entity_spawner.gd`; give it a 3D
  look (procedural `prop_meshes.gd` or a `.glb`). → `WORLD_MAP_AND_NODES.md` + `ANIMATION_AND_SPRITES.md`.
- **A new fishing/gather spot in a specific place** → use the world editor Skills tool, or author it
  in chunk data; re-bake. → `WORLD_MAP_AND_NODES.md`.

## "I want new player behavior / an action"
- New interaction on click → extend `world_activity_controller.begin_action`/`execute_action` (one
  file) and route to an existing sim or a HUD popup. → `PLAYER_ACTIONS_AND_TOOLS.md`.
- New gather/skill animation → `mover_rig.gd` `_pose_gather_work` + `mover_renderer_3d.gd` mapping. →
  `ANIMATION_AND_SPRITES.md`.
- Movement/camera tuning → `player_avatar.gd` (speeds), `world_camera_rig_3d.gd` (zoom/pitch),
  `mover_rig.gd` (gait).

## "I want UI"
- New tab/panel/orb/popup → `scripts/ui/` (tab in `tabs/`, widget in `widgets/`, window in
  `hud_popups.gd`), wired to `EventBus` signals. → `UI_AND_HUD.md`.

## "I want feedback/effects"
- New particle/FX on an event → emit an `EventBus` signal where the event happens, handle it in
  `scripts/render/world_fx_3d.gd` (mirror `_on_wc_log`/`_on_mining_struck`). → `SIGNALS_AND_EVENTS.md`.

## "I want to store something across sessions"
- New saved field → `GameState.to_save_dict` + defaulted `from_save_dict` (+ migration only if needed)
  + a validate round-trip test. → `SAVE_LOAD_AND_PERSISTENCE.md`.

## "I want a new global system"
- **Strongly prefer not to.** First check whether `GameState`, a sim, or a controller already owns
  this responsibility (see `FILE_OWNERSHIP_MAP.md`). Adding an autoload is rare and must go through
  `OPEN_QUESTIONS.md`/the owner. There is exactly one of each core system — do not duplicate.

## Always
1. Read `FEATURE_MAP.md` row + the system doc, then the actual source.
2. Make the minimal change in the owning file.
3. `godot --headless --path . res://tools/validate.tscn` → `ALL TESTS PASSED`.
4. Update the wiki if behavior/ownership/signals/save changed.
