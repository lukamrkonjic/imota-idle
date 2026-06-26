# Input actions

**There is no Godot `[input]` InputMap** in `project.godot`. All input is handled in code. Do NOT add
`Input.is_action_*` / named actions; follow the existing code-driven pattern.

## Where input is handled
- **World mouse/zoom/hover:** `scripts/world/world_input_controller.gd` (`WorldInputController`),
  invoked from `World._unhandled_input(event)` → `_input_ctrl.handle_input(event)`.
- **HUD keyboard:** `scripts/ui/osrs_hud.gd` `_input` (M = map, runs early) and `_unhandled_key_input`
  (Esc = close map → close popups → toggle game menu; configurable "hide HUD" key).
- **Editor input:** `tools/world_editor.gd` handles its own keys (number keys / letters select tools,
  e.g. `KEY_G` → Skills). Editor-only.

## Mouse (world)
| Input | Handler | Effect |
|---|---|---|
| Left-click on entity | `handle_input` → `entity_at` → `world.begin_action` | walk to + perform the entity's action |
| Left-click on ground | `handle_input` | stop activity, walk there |
| Right-click on sim/NPC | `_show_sim_menu` | context menu: Follow / Stop / Ask to follow / Ask to stop / Examine (ids 1–5 in `_on_ctx_id`) |
| Wheel up/down | `_set_zoom(camera.zoom ± ZOOM_STEP)` | zoom (clamp `ZOOM_MIN 0.55`..`ZOOM_MAX 4.5`, step 0.15) |
| Trackpad pinch | `InputEventMagnifyGesture` | zoom |
| Middle-drag | sets `_orbiting` | 3D camera orbit (`render_3d.orbit_drag`) |
| Hover (per frame) | `update_hover()` (called from `World._process`) | sets `world.hovered_entity`, updates HUD tooltip/action text |

`_over_ui()` guards every world click so HUD clicks don't leak into the world.

## Keyboard
- **M** — toggle world map (`osrs_hud._input`, guarded against text fields).
- **Esc** — hierarchical: close map → close open popup → toggle game menu (`_unhandled_key_input`).
- **F6** — toggle biome debug overlay (`world_input_controller`).
- **Arrow keys (in-game CAMERA)** — `scripts/render/world_camera_rig_3d.gd:update_input` (polled each
  frame): Left/Right rotate the camera yaw; Up = ease to the wide top-down overview; Down = ease to
  the close cinematic angle. These move the CAMERA, not the player.
- **Configurable keys** are stored in `GameSettings` (NOT InputMap): `GameSettings.keybind(action_id)`
  / `set_keybind`. The settings popup is generated from a keybind list. Example: "hide HUD".

### Player MOVEMENT is click-to-walk only (no WASD in-game)
The player moves by **left-clicking the ground/an entity** → A* walk via `world_path_controller`.
There is **no `KEY_W/A/S/D` player-movement handler in the game** (verified: the only `KEY_W` in the
repo is `tools/world_editor.gd:3225`). The "WASD / R-drag move · wheel / pinch zoom · L-click place"
hint you may see comes from the **world editor** (`tools/world_editor.gd:2321`), where **WASD flies
the editor's aerial 3D camera** over the map (editor-only). Do not add in-game WASD movement without
an explicit request — it would be a new system; the click-to-walk path is the established one.

## How a click reaches gameplay
See `DATA_FLOW.md` §1–2: `handle_input` → `entity_at` → `world.begin_action` →
`world_activity_controller.begin_action` (stand tile) → `walk_to_pos` → on arrival `execute_action`.

## Adding an input handler — pattern
**Remappable key:** add an entry to the `GameSettings` keybind list, then handle it in
`osrs_hud._unhandled_key_input` (or `world_input_controller.handle_input`):
```gdscript
if event is InputEventKey and event.pressed and event.keycode == GameSettings.keybind("my_action"):
    _do_my_action()
    get_viewport().set_input_as_handled()
```
**Fixed key (not remappable):** same, but compare to a literal `KEY_*`. Always call
`set_input_as_handled()` so it doesn't double-fire. For mouse, add a branch in
`world_input_controller.handle_input` and respect `_over_ui()`.
