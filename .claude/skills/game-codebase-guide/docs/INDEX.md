# Imota codebase wiki — index

This wiki documents the **Imota** Godot 4.6 game so an AI agent can safely extend it. Every page is
grounded in real files. Start at `FEATURE_MAP.md`, then read the system page(s) for your task, then
inspect the actual source.

## Map of pages

| Page | Read it when… |
|---|---|
| `PROJECT_OVERVIEW.md` | You need the big picture, engine version, run/test commands. |
| `ARCHITECTURE.md` | You need the boot→gameplay lifecycle and layer model. |
| **`FEATURE_MAP.md`** | **Always first** — find your feature's files, signals, data, deps. |
| `GODOT_SCENE_MAP.md` | Touching `world.tscn` or scene-built nodes; what not to rename. |
| `AUTOLOADS_AND_GLOBALS.md` | Using/extending an autoload singleton. |
| `DATA_FLOW.md` | Understanding how a click or tick propagates. |
| `SIGNALS_AND_EVENTS.md` | Wiring UI/feedback; finding who emits/listens a signal. |
| `INPUT_ACTIONS.md` | Adding a key/mouse handler. |
| `INVENTORY_ITEMS_AND_RESOURCES.md` | Items, tools, recipes, ids, renames. |
| `PLAYER_ACTIONS_AND_TOOLS.md` | The click→walk→act pipeline; gather/combat/craft. |
| `UI_AND_HUD.md` | HUD, tabs, widgets, popups. |
| `SAVE_LOAD_AND_PERSISTENCE.md` | Adding a saved field; migrations; save-safety. |
| `WORLD_MAP_AND_NODES.md` | World gen, chunks, sites, POIs, baked world, the editor. |
| `ANIMATION_AND_SPRITES.md` | 3D render, rigs, gather/combat poses, decor, shaders. |
| `ADDING_NEW_FEATURES.md` | "Where does my feature go?" decision tree. |
| `SAFE_EDITING_RULES.md` | The rules every edit must follow. |
| `COMMON_TASK_RECIPES.md` | Step-by-step for frequent tasks. |
| `TROUBLESHOOTING.md` | Debugging signals, scene refs, animation/tool issues. |
| `OPEN_QUESTIONS.md` | Unverified/risky areas — read before trusting them. |
| `FILE_OWNERSHIP_MAP.md` | Which file owns which responsibility. |
| `GLOSSARY.md` | Project-specific terms. |

## Quick facts

- Engine: **Godot 4.6** (GDScript only). Main scene: `res://scenes/world.tscn`.
- 15 autoloads (see `AUTOLOADS_AND_GLOBALS.md`).
- Content is data-driven: `data/*.json` loaded by `DataRegistry`.
- Validate: `godot --headless --path . res://tools/validate.tscn` → must print `ALL TESTS PASSED`.
- The repo-root `docs/` folder holds human design docs (background, may lag code). THIS wiki is the
  AI-facing source of truth; keep it updated when you change architecture/behavior.
