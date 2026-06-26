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
- **Movement:** WASD/right-drag move + wheel zoom are documented in the top-of-screen hint; movement
  is primarily click-to-walk via the path controller. (Confirm WASD handling in
  `world_input_controller.gd` / camera rig before relying on it — see `OPEN_QUESTIONS.md`.)
- **Configurable keys** are stored in `GameSettings` (NOT InputMap): `GameSettings.keybind(action_id)`
  / `set_keybind`. The settings popup is generated from a keybind list. Example: "hide HUD".

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
