# Player actions & tools

The "action pipeline" turns a click into a walk and then a gameplay activity. It is the single path
for gathering, combat, crafting, banking, NPC dialog, and world traversal. **Reuse it** — do not add
a parallel interaction path.

## Entities carry their action
A `WorldEntity` (`scripts/world/world_entity.gd`) has `kind` (tree/rock/fish/bush/enemy/station/sim/
npc/cave/…) and an `action: Dictionary`. Action shapes:
- Gather: `{type:"gather", skill, node, chunk_key, site_index}`
- Enemy: `{type:"enemy", name, level, wander?, leash?}`
- Station: `{type:"station", station, skill?, recipe?}` (station ∈ bank/shop/anvil/altar/campfire/…)
- NPC: `{type:"npc", npc}`; plus `descend`/`ascend`/`obelisk`/`landmark`/`hook`.
`WorldEntity.is_interactable()` decides if it's clickable; `display_label()` / `tooltip_content()`
feed the HUD.

## The pipeline (files)
1. `scripts/world/world_input_controller.gd` — `handle_input` left-click → `entity_at` → 
   `world.begin_action(entity)`.
2. `scripts/world/world.gd` — `begin_action` delegates to `_activity_ctrl.begin_action`.
3. `scripts/world/world_activity_controller.gd` — `begin_action`:
   - stops running sims + clears combat target,
   - sets `world.pending_action` (with `entity_path` and `exact_stand=true` for gather/fishing),
   - chooses a stand position by action type:
     - **enemy ranged** → nearest in-range tile (or stand if already in range),
     - **enemy melee** → `_attack_gap(entity)` short of the mob,
     - **fishing** → `FishingHelper.best_stand` (the walkable tile at the water's edge),
     - **other gather** → `_adjacent_stand(entity.position, player)` (the tile right beside the node),
   - `world.walk_to_pos(target)`.
4. `scripts/world/world_path_controller.gd` — A* `walk_to_pos`; `exact_stand` skips the
   stop-one-tile-short trim so the player ends on the chosen tile. On arrival fires `player.arrived`.
5. `world_activity_controller.execute_action(action)` — starts the activity:
   - gather → `_start_gather` → `TickSim.start_gather(skill, node)` (fishing: `can_cast_from` +
     `player.set_fish_cast(water_pos)`), sets `world.gather_ref`.
   - enemy → `CombatSim.start_combat(name, hud.train_style())`, sets `world.combat_target_entity`.
   - station → open bank/shop UI, or `RecipeSim.start_craft`, or open the recipe popup.
   - npc → `hud.open_npc_dialog`.

## Tools in hand & gather requirements
- A gather needs the right tool equipped: `GameState.tool_progress(skill) > 0` (slot from
  `SkillRegistry.tool_slot`). See `INVENTORY_ITEMS_AND_RESOURCES.md`.
- The 3D rig swaps the matching tool: `MoverRenderer3D._refresh_gather_tool` → axe (woodcutting),
  pickaxe (mining), fishing rod (rod-fishing); foraging/hunter/thieving are bare-handed. Tool meshes
  + grip in `scripts/render/mover_meshes.gd` (`weapon_profile` + `equip_parts`).

## Player movement
- `scripts/world/player_avatar.gd` (`PlayerAvatar`): `WALK_SPEED`/`RUN_SPEED`, `walk_to(target)`,
  emits `arrived` at each waypoint, `is_running()` (gated by `GameState` run energy), and fishing
  state (`fishing`, `fish_cast_pos`, `set_fish_cast/clear_fish_cast`).
- `scripts/world/world_path_controller.gd`: path build, follow-entity ("Follow"), `stop_walking`.

## Animation of the action
The gather/combat motion is the 3D rig's job (cosmetic). The renderer reads `TickSim`/`CombatSim`
state + `world.gather_ref` to: face the node/water, then play the per-skill pose (chop/mine/cast/
kneel/forage/trap/steal) — gated on having turned to face it. See `ANIMATION_AND_SPRITES.md`.

## To add a new action type / interactable
1. Give the entity an `action` dict with a new `type` (or reuse an existing one).
2. Handle the walk target in `world_activity_controller.begin_action` (if it needs special stand
   logic) and the start in `execute_action`. Keep both edits minimal and in that one file.
3. If it starts a long activity, route it through an existing sim (don't invent a new sim) or open a
   HUD popup via `hud.open_*`. Recipe: `COMMON_TASK_RECIPES.md` → "Add a new NPC/interactable".
