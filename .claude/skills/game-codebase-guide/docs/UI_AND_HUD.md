# UI & HUD

## Entry point
`scripts/ui/osrs_hud.gd` is the `$HUD` CanvasLayer (layer 10), built entirely in code. `world.gd`
calls `hud.bind_world(self)`. The HUD reflects gameplay via `EventBus` signals (it does not poll,
except live-redraw widgets). It exposes methods the world/popups call: `set_hover_text`,
`update_world_tooltip`, `train_style`, `open_bank/open_shop/open_slayer/open_npc_dialog/open_obelisks/
open_recipes/open_skill_guide/open_farming`, `show_ui_click_marker`.

## Layout (5 corner regions, scaled by `GameSettings.ui_scale`)
- Top-left: hover/action text, FPS + tile debug.
- Top-right: HP/Prayer/Run status orbs, circular minimap, Bank/Slayer/Map buttons, coins label.
- Top-center: zone banner + cave/layer banner.
- Bottom-left: chatbox (RichTextLabel, ≤100 lines).
- Bottom-right: side panel = `TabContainer` (6 tabs) + drawn tab icon row.

## Tabs (`scripts/ui/tabs/`)
RefCounted classes built into the TabContainer; each has `build() -> Control` and `refresh()`:
`combat_tab.gd` (`HudCombatTab` — training style + stats), `skills_tab.gd` (`HudSkillsTab` — skill
grid + XP hover, `update_cell(skill)`), `inventory_tab.gd` (`HudInventoryTab` — 28-slot grid +
left/right menus), `equipment_tab.gd` (`HudEquipmentTab` — worn slots + tools), `prayer_tab.gd`
(`HudPrayerTab` — toggles + bury bones), `magic_tab.gd` (`HudMagicTab` — placeholder).

## Widgets (`scripts/ui/widgets/`)
`status_orb.gd` (`StatusOrb` — HP/Prayer/Run; Run orb left-click toggles run, right-click rests),
`minimap.gd` (`MinimapPanel` — zoomable, click-to-walk via `navigate_requested`), `icon_button.gd`
(`IconButton` — Bank/Slayer/Map), `tab_icon.gd` (`TabIcon` — side-panel tab selector).
`scripts/ui/item_icon.gd` (`ItemIcon`) draws procedural item icons.

## Popups (`scripts/ui/hud_popups.gd`, `HudPopups`)
PopupPanel windows opened via `hud.open_*`: Bank, Shop, Slayer, NPC dialog, Farming, Obelisks,
Recipes (per skill), Skill guide (lists nodes + an "Auto" row that fires `gather_requested`).

## HUD refresh = EventBus signal handlers (see `SIGNALS_AND_EVENTS.md`)
Examples: `xp_gained → skills tab cell`; `level_up → chat + skills refresh`;
`inventory_changed → inventory tab`; `equipment_changed → equipment + combat tabs`;
`coins_changed → coins label`; `hp_changed/run_energy_changed → orbs redraw`;
`combat_log/loot_gained → chatbox`; `zone_changed/world_layer_changed → banners`;
`prayer_changed → prayer tab`; `game_loaded → _refresh_all()`.
Choose granularity: `update_cell(skill)` for frequent single-skill XP; `refresh()` for structural
changes; `_process` `queue_redraw` only for continuously animated widgets (orbs).

## Adding a HUD panel/tab — pattern
1. Create `scripts/ui/tabs/<name>_tab.gd` (RefCounted, `class_name Hud<Name>Tab`) with `build()` +
   `refresh()`.
2. In `osrs_hud._build_side_panel()`: preload it, `tabs.add_child(_<name>_tab.build())`, add an icon
   to the tab-icon `defs` list.
3. In `osrs_hud._ready()`: connect the EventBus signals it needs to `_<name>_tab.refresh()` /
   `update_cell`.
For a new orb/button, mirror `status_orb.gd`/`icon_button.gd` and add it in
`_build_minimap_cluster()`. For a new window, add an `open_<x>()` to `HudPopups` and a forwarder on
`osrs_hud`. Full example in `COMMON_TASK_RECIPES.md`.

## Don't
- Don't poll `GameState` every frame for static data — connect a signal.
- Don't rename HUD-exposed methods (`open_bank`, `train_style`, …) without updating callers in
  `world_activity_controller.gd` / `world.gd`.
- Don't add a second HUD or a parallel popup manager.
