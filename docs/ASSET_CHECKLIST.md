# Asset Checklist

Production checklist of every visual/audio asset Imota needs, what already exists, and where it
lives or should live. **Grounded in the repo** — paths are real.

> **READ THIS FIRST — Imota is a procedural-art game.** Almost all 3D models and item icons are
> **built in code at runtime**, not loaded from files:
> - 3D props/buildings/decor → `scripts/render/prop_meshes.gd` (+ `static_prop_batcher.gd`)
> - Player/enemy bodies, held weapons & tools → `scripts/render/mover_meshes.gd` + `mover_rig.gd`
> - Item/inventory icons → `scripts/ui/item_icon.gd` (vector-drawn per item category)
> - Terrain/water → `scripts/render/terrain/terrain_chunk_mesher.gd` + `terrain_style.gd` + shaders
>
> So a "missing asset" here usually means **a procedural mesh/icon to author in code, a VFX to add,
> or an optional `.glb`/PNG to swap in** — NOT a missing file. The only file-based art assets are the
> 22 skill-icon PNGs, one `.glb` (`models/smithy.glb`), the worldgen mask PNGs, and dev-tool baker
> output. There is **no shipped audio** (the system is wired but every path is empty).
>
> When you mark something `[x]`, it means "exists and renders" — give the generating file (script)
> OR the asset path. See `docs/GLB_IMPORT_GUIDE.md` for swapping a procedural prop to a `.glb`.

## Legend
- `[x]` Verified existing (a file on disk, OR a procedural generator in code that renders today)
- `[ ]` Needed / missing
- `[~]` Exists but placeholder / incomplete / reused / needs improvement
- `[?]` Unsure / needs human confirmation (often: "do we want a file-based asset instead of procedural?")

## Summary
Counts are by *system/kind*, not by enumerating all 976 items (every item already gets a procedural
icon — see §2). Approximate, grounded in this audit:
- **Real asset files on disk:** 22 skill-icon PNGs (`[x]`), 1 GLB `smithy.glb` (`[x]`), ~8 worldgen
  mask/source PNGs (`[x]`), dev baker output `generated/props/*.png` (not runtime — `[~]`).
- **Procedural asset systems (exist & render, `[x]`):** item-icon kinds (~33 shapes), prop/structure
  kinds (~120 in `prop_meshes.decor_parts`), town/furniture props (~70 in `_city_prop_parts`),
  hike-diorama dressing (~30), tree species (canopy_pine/maple/birch/palm/saguaro/deadtree/acacia +
  alpine_pine), held weapon kinds (~14), held tool kinds (axe/pickaxe/fishing_rod), enemy body
  archetypes (~19: humanoid/dragon/serpent/slime/wraith/eye/spider/scarab/crawler/crab/bat/bear/wolf/
  boar/cow/sheep/goat/mole/bird), boss regalia, gather poses (7), combat lunges, walk/idle gait,
  several VFX (leaf puff, rock chip, tree fall/grow, fishing bubbles, blob shadows).
- **Missing (`[ ]`):** ALL audio files (system hooked, ~empty `data/audio.json`); several VFX (water
  splash on cast/catch, level-up flourish, item-pickup pop, ripple, generic resource-depletion);
  optional `.glb` upgrades for hero buildings.
- **Placeholder / needs improvement (`[~]`):** item-icon distinctiveness (976 items share ~33 shape
  templates + material tints; many read alike); a few props reuse meshes; only 1 NPC entry in
  `data/npcs.json` (the `kind:"npc"` model now varies robe/skin/headwear per id via
  `prop_meshes._npc_figure`, so adding NPC defs yields visible variety for free); dialogue portraits (none).
- **Critical missing:** none blocks play (procedural art covers everything). Highest-value gaps are
  **audio**, **item-icon variety**, and a few **feedback VFX**. See "Missing Assets To Make".

## How To Maintain This File
Future agents MUST:
1. **Search the repo first** (`grep`/`find`) before declaring an asset missing — most art is
   procedural in `scripts/render/` or `scripts/ui/item_icon.gd`.
2. Check off `[x]` once it exists and you've verified the **path** (file path OR the generating
   script + function).
3. Add the exact path/owner.
4. Update the "Used by" / references when a scene/script starts using it.
5. Mark placeholders/reused art `[~]` with what needs improving.
6. **Do not create duplicate assets** with different names — extend the existing procedural kind or
   reuse the file. New file art that replaces procedural art must follow `docs/GLB_IMPORT_GUIDE.md`
   (keep roofs/leaves/etc. as separate meshes).

## Asset Folder Map
Current:
- `assets/skill_icons/` — 22 skill PNGs (the only shipped icon files).
- `models/` — `.glb` models (only `smithy.glb`). Per-model loaders in `scripts/render/*_prop.gd`.
- `data/world/masks/`, `data/world/source/`, `data/world/baked/aldreth_map.png` — worldgen authoring
  inputs (biome/elevation/river masks), NOT in-game art.
- `generated/props/*.png`, `generated/sprite_atlas/page_0.png` — OUTPUT of `tools/prop_baker_3d.gd`
  (dev eyeballing); **not loaded at runtime**.
- `shaders/` — `toon_ground/toon_water/toon_world/palette_snap/outline/dawn_mist`.
- Procedural art lives in **code**: `scripts/render/{prop_meshes,mover_meshes,mover_rig,terrain_style,
  fishing_decor_3d,world_fx_3d}.gd`, `scripts/ui/item_icon.gd`.

Recommended (create only when first used):
- `assets/audio/music/`, `assets/audio/sfx/` — referenced by `data/audio.json` (paths currently empty).
- `models/<name>.glb` + `scripts/render/<name>_prop.gd` — for any hand-made/AI building or prop.
- `assets/item_icons/` — ONLY if you move item icons from procedural to PNG (not currently the design).

---

## 3D / GLB Assets

### Buildings & Structures
All procedural via `prop_meshes.gd` unless noted. Placeable via the world editor STRUCTURES catalog
(`tools/world_editor.gd`) and/or spawned from POI data (`data/world/pois.json`,
`world_entity_spawner.gd`). `kind` strings drive the mesh.
- [x] Smithy — **GLB** — `models/smithy.glb` (loader `scripts/render/smithy_prop.gd`). Reference for
  GLB integration. Priority: Low (done). Roof NOT separated (single mesh) — `[~]` if interiors wanted.
- [x] House / Hall (`building`, `house`, `tent`) — procedural `prop_meshes` + `_city_prop_parts`
  (cabin/lodge variants in `hike_*`). Critical. **Roofs are part of the mesh** → see Risks.
- [x] Cabin / Lodge (`hike_cabin`, `hike_lodge`) — procedural, with separate door/window/roof-rib
  sub-parts (`hike_cabin_door`, `hike_cabin_win_l/r`, `hike_cabin_roof_rib`). Medium.
- [x] Fountain, Well — `prop_meshes` `fountain` / `_city_prop_parts "well"`. Medium.
- [x] Walls & fences (`city_wall`, `fence`, `fence_post`, `paddock_fence`, `hike_fence`,
  `iron_fence`) — procedural. Medium.
- [x] Bridge (`bridge`, `bridge_pole`) — procedural. Medium.
- [x] Tent, Campfire (`tent`, `campfire`, `hike_campfire`) — procedural. High (camp/cooking).
- [x] Market stall / awning (`stall`, `market_awning`) — procedural. Medium.
- [x] Storage chest (`chest`) — procedural. High (bank visual). Color/lid not separated — `[~]`.
- [x] Sign / signpost / hanging sign (`sign`, `signpost`, `hanging_sign`, `crooked_post`,
  `hike_sign`) — procedural. Medium.
- [x] Stations: anvil/forge (`anvil`, `forge`, `grindstone`), altar (`altar`), obelisk (`obelisk`) —
  procedural. High (skill stations).
- [x] Ruins & monuments (`ruin_arch`, `ruin_pillar`, `broken_wall`, `rubble_pile`, `broken_statue`,
  `standing_stone_dark`) — procedural. Low.
- [x] Graveyard set (`gravestone`, `tomb`, `crypt`, `coffin`, `mausoleum/mourning_statue`, `gallows`,
  `gibbet/stocks`) — procedural `_city_prop_parts`. Low.
- [x] Caves / mines: cave entrance + ladders (`ladder_up`/down) — procedural + POI. High (mining/caves).
- [x] Landmarks: `mammoth`, `meteor`, `mountain` — procedural. Low.
- [x] Town props: lamp/lamp_post, barrel, cart, hay/hay_bale, flowerbox, crate, water_trough,
  brazier, torch, banner, training_dummy, archery_target, weapon_rack, stable, hitching_post, etc. —
  procedural `_city_prop_parts`. Low–Medium.
- [x] Interior furniture: table, chair, bench, bed, shelf, bookcase, cauldron, fireplace,
  candelabra, throne, lectern, alchemy_table, barrel_rack, crate_stack — procedural. Low (only seen
  if interiors are used). Interiors themselves: `[?]` (no enterable-interior system confirmed).
- [ ] Fishing hut, barn, dock — no dedicated `kind`; would be a new procedural kind or `.glb`. Low.
- [?] Portals — `obelisk` doubles as fast-travel; a distinct "portal" model is not present. Confirm.

### Terrain & World Props
- [x] Mineable rocks (`rock`, `geode`, `cairn`) — procedural; mining sites use `kind:"rock"`. Critical.
  **Ore veins are SEPARATE meshes** (`prop_meshes._rock_parts(ore)`): a grey boulder base + colour/glow
  shards keyed off the ore's display name (`_ore_vein_style`: copper/tin/coal/iron/silver = matte,
  gold/mithril/adamant/rune/dragon/gems/lava = emissive glow via `_ore_vein_mat`). A depleted (dimmed)
  rock renders base-only. Add a new ore's colour by adding a row to `_ore_vein_style`.
- [x] Trees (canopy_pine/maple/birch/palm/saguaro/deadtree/acacia, `alpine_pine`, `hike_conifer`,
  `hike_deciduous`, `mossy_log`, `hike_log`, `hike_stump`) — procedural; species from
  `data/world/tree_species.json`. Critical. **Leaves vs trunk:** separate parts within the procedural
  mesh (e.g. `hike_pine_trunk` vs `hike_pine_*` foliage) → good for future leaf recolor.
- [x] Bushes/flowers/mushrooms (`berry_bush`, `bush`, `thistle`, `dandelion`, `toadstool`, `mushroom`,
  `daisy`, `bell`, `white/purple/pink` flowers, `frozen_shrub`, `hike_flower`) — procedural
  (foraging nodes). High.
- [x] Grass/reeds/ferns/cactus (`grass`, `reed`, `fern`, `cactus`, `tumbleweed`, `hike_grass`) —
  procedural decor. Medium.
- [x] Shore/water props (`starfish`, `coral`, `hike_pool`) — procedural. Low.
- [x] Fishing spot indicator — **bubbles** via `scripts/render/fishing_decor_3d.gd` (translucent cyan
  spheres on the water). High. (`[~]` historical note: old static `fish_school` pebble mesh is
  intentionally skipped — don't re-enable.)
- [x] Resource node sites in general — `kind:"fish"/"burrow"/"stall"` for fishing/hunter/thieving;
  `prop_meshes` cases exist. High.
- [x] Cliffs/boulders/pebbles (`hike_cliff`, `hike_boulder`, `hike_pebble`) — procedural. Low.
- [x] Paths/leaf-litter (`hike_path`, `hike_leaf_litter`) — procedural + terrain tint. Low.
- [x] Lamps/torches/benches/barrels/sacks/buckets — procedural (also under town props). Low.

### Tools (held)
Held tool meshes in `mover_meshes.gd` (`weapon_profile` + `equip_parts`); chosen by
`equip_loadout.gd`; swapped in-hand while gathering by `mover_renderer_3d._refresh_gather_tool`.
Inventory icons are procedural (`item_icon.gd` kinds `axe`/`pickaxe`). 60 tool *items* in `data/tools.json`
across 4 slots (Axe/Pickaxe/Rod/Lens) with material tiers (progress-tiered).
- [x] Axe (woodcutting) — held mesh `kind:"axe"` + icon kind `axe`. Critical.
- [x] Pickaxe (mining) — held mesh `kind:"pickaxe"` (added this session) + icon kind `pickaxe`. Critical.
- [x] Fishing rod (fishing) — held mesh `kind:"fishing_rod"` + cast line/float (`mover_renderer_3d`).
  Critical.
- [~] Foraging "Lens" tool — has a slot + tier items, but **no distinct held mesh** (bare-handed
  forage pose). Medium — add a `lens`/`sickle` held mesh if desired.
- [ ] Hunter / Thieving tools — toolless by design (`SkillRegistry.base_progress`); no held mesh.
  Low (intentional). Confirm if a trap/lockpick prop is wanted.
- [~] Tool material tiers (bronze→…→dragon) — meshes are **one shape, material-tinted** via
  `equip_loadout.material_for` + icon `material_color`. Distinct per-tier shapes: `[~]` (not modelled).
- [ ] Nets, harpoons, hammers, knives, sickles, hoes, watering cans, shovels, cooking/crafting tools
  as *held world models* — not modelled (the game uses rod/cage fishing + station crafting). Low /
  `[?]` whether needed.

### Weapons (held)
Held meshes in `mover_meshes.gd` `weapon_profile`/`equip_parts`; families mapped by
`equip_loadout.weapon_kind`/`weapon_kind_for_def`. Icons via `item_icon.gd`.
- [x] Sword / scimitar, Dagger, Mace, Axe (1h) — held mesh + icon. High.
- [x] Greatsword / two-handed, Battleaxe, Warhammer/hammer — held "heavy" meshes (added this
  session). High.
- [x] Spear / halberd (polearm) — held mesh. Medium.
- [x] Bow (ranged) — held mesh + ranged shot VFX (`combat_ranged_shot`). High.
- [x] Staff / wand (magic) — held mesh + cast pose. High.
- [~] Per-material weapon variants (bronze..dragon) — material-tinted, not per-tier shapes. `[~]`.
- [ ] Arrows / ammunition as visible models — `Ammunition` slot exists; no distinct arrow mesh. Low.
- [~] Enemy weapons — enemies are body archetypes; some carry implied weapons but no separate
  enemy-weapon meshes. Low.

### Armor & Equipment (worn)
Worn gear built procedurally in `mover_meshes.gd` (`equip_parts` for helm/body/legs/boots/gloves/
shield/cape) + `equip_loadout.gd` (cloth/leather/metal materials, cape/robe tints). Slots in
`GameState.equipment`. Icons via `item_icon.gd` (helm/body/legs/boots/gloves/cape/shield/ring).
- [x] Helmet, Chest (body), Legs, Boots, Gloves, Shield, Cape — procedural worn meshes + icons. High.
- [x] Robes/wizard hat/hood (cloth set), cape/robe color tints — procedural, color-swappable via
  loadout tints. Medium.
- [x] **Cape silhouettes** — `build_cape(m, profile, style)` supports `full` / `short` (shoulder
  cloak) / `trim` (gold-edged) / `hooded` / `tattered` (frayed twin-tail hem). An item pins it via a
  `style` field; otherwise `_cape_style_for(material)` picks one per tier (cloth = the plain hero
  drape, unchanged). All ripple via the same segment chain.
- [x] **Body silhouettes** — `chest` (ornate full plate w/ pauldrons), `jerkin` (leather vest),
  `scale`/`chain`/`hauberk` (NEW mid-tier scale mail), `robe_top` (mage). Distinct shapes, not just tints.
- [~] Distinct armor *sets* per material tier — bodies/capes now vary by shape; per-slot matched
  "sets" (themed helm+body+legs+cape) are still tint-driven. `[~]`.
- [ ] Backpack — not modelled. Low.
- [?] Rings/amulets visible on the body — equippable + iconned, but not shown on the 3D rig. Confirm
  if visible jewellery is wanted.
- [?] Male/female / body-type variants — single body archetype (sim players vary look via tints).
  Confirm if body variants are wanted.

### Enemies & Creatures
Enemy rigs are procedural archetypes in `mover_meshes.gd` (`enemy_rig`), animated by `mover_rig.gd`.
**~19 body archetypes** chosen from the enemy name by keyword (`enemy_body_type`): `humanoid`
(default, + goblin/gnoll gaits), `dragon`, `serpent`, `slime`, `wraith`, `eye`, `spider`, `scarab`,
`crawler`, `crab`, `bat`, `bear`, `wolf`, `boar`, `cow`, `sheep`, `goat`, `mole`, `bird`. The renderer
dispatches each to a pose: `_pose_humanoid/goblin/gnoll/bird/dragon/serpent/slime/float/scuttle/crab/
bat/quadruped` (`mover_renderer_3d.gd` match). 120 enemies in `data/enemies.json` map onto these.
- [x] Humanoid enemies (goblins/skeletons/bandits/…) — `humanoid` rig (+ goblin/gnoll gaits). Critical.
- [x] Dragons/drakes/wyverns; serpents/nagas; slimes/oozes; wraiths/ghosts (float); floating eyes;
  spiders/scarabs (scuttle); crawlers/worms; crabs; bats; bears/wolves/boars/cows/sheep/goats/moles
  (quadruped variants via `quadruped_rig` spec); birds. All have dedicated rigs. High→Low.
- [x] Animations: idle, walk (gait per archetype), combat attack lunge, hit flash + shake, **death
  topple** — `mover_rig.gd` + `mover_renderer_3d.gd`. High.
- [x] Distinct quadruped gaits — `_pose_quadruped` reads a `gait_style` meta: bear=`lumber` (slow,
  heavy roll), cow/sheep/goat=`graze` (placid, head dips), boar=`trot_quick`, mole=`scurry`; wolves
  keep the default even trot. Set per species in `enemy_rig`.
- [x] New archetypes **golem / treant / imp** — `golem_rig` (stone biped w/ glowing core),
  `treant_rig` (tree-man w/ leafy wind-swayed canopy), `imp_rig` (small winged flyer). Golem/treant
  ride the humanoid pose via the biped skeleton; imp uses the bat pose. Keywords in `enemy_body_type`.
- [ ] Further archetypes (centaur/hydra/kraken) — add a rig builder + keyword + pose the same way. Low.
- [x] Loot/drop icons — drops are items → procedural `item_icon.gd`. Covered.
- [ ] Enemy-specific VFX/sounds (roar, cast) — none beyond generic hitsplats. Low.
- [x] **Bosses read as bosses** — `is_boss` enemies get `_add_boss_regalia` (a glowing ground aura
  ring tinted by element + a bony horn crown on humanoids) + a bigger base scale (×1.3) + a slow
  breathing idle (`mover_renderer_3d` boss-swell). Universal across every archetype, no bespoke model.
- [~] **Bespoke flagship-boss models** — `_bespoke_boss_rig(name)` returns a unique rig for named
  bosses (built so far: **Pumpkin Jack** — glowing carved jack-o'-lantern head + witch hat). Add a
  branch there to give any of the other ~34 bosses (Aurelion, Vaerthrax, etc.) its own model.

### NPCs & Characters
- [x] Sim players (ambient NPC crowd) — use the PLAYER rig with deterministic looks/loadouts
  (`scripts/world/sim/*`, `data/sim_players/{names,looks,dialogue}.json`). High.
- [x] Generic NPC marker (`kind:"npc"`, `prop_meshes "npc"` + `mover` humanoid). Medium.
- [~] Dedicated NPC roles (banker/shopkeeper/trainer/guard/merchant/skill master) — only **1 entry**
  in `data/npcs.json`; roles are mostly stations, not characters. `[~]`/`[ ]` — add NPC defs +
  outfits if the design wants named NPCs.
- [ ] Dialogue portraits — none (dialog opens via `hud.open_npc_dialog`, no portrait art). Medium if
  dialogue UI wants faces.
- [x] NPC idle/walk — sim players walk/idle via the shared rig. Low.

### Resource nodes & Decorations
Covered above (rocks/trees/bushes/fish/burrow/stall + decor). All procedural. `[x]`.

---

## 2D Art and Icons

### Inventory / item / shop icons
- [x] **All 976 items get a procedural icon** — `scripts/ui/item_icon.gd` `classify()` maps each item
  to one of ~33 drawn shapes (sword/axe/pickaxe/bow/staff/shield/helm/body/legs/food/fish/log/ore/
  bar/potion/gem/coin/bone/ring/lock/boots/gloves/cape/arrow/heart/fist/skull/fire/leaf/seed/prayer/
  misc) + a material tint (`material_color`: bronze/iron/steel/black/mithril/adamant/rune/dragon/
  gold/silver). No item lacks an icon. Critical system — `[x]`.
- [~] **Icon distinctiveness** — many items share a shape+tint and read alike (e.g. all logs, all
  bars, all "misc" materials). Improvement: more shape kinds / per-item detail. Medium.
- [?] Items that fall through `classify()` to `"misc"` — verify which item families look generic and
  deserve a dedicated kind (e.g. seeds, herbs, gems, keys). Medium.
- [x] Currency/coin icon — `item_icon` kind `coin`. Done.
- [x] Stackable items — handled by the inventory tab (qty label); icon is per-item. Done.
- [ ] Shop "goods" hero art — shop lists reuse item icons; no separate shop art. Low.

### Skill icons
- [x] All 22 skills — PNGs in `assets/skill_icons/` (attack, strength, defence, hitpoints, ranged,
  magic, prayer, slayer, farming, agility, woodcutting, mining, fishing, foraging, thieving, hunter,
  cooking, smithing, firemaking, fletching, crafting, alchemy). Used by `SkillRegistry`/HUD skills
  tab. `[x]` Critical — complete.

### UI / HUD icons & art
Mostly procedurally drawn in `scripts/ui/widgets/*` + `osrs_hud.gd`.
- [x] Status orbs (HP, Prayer, Run) — `scripts/ui/widgets/status_orb.gd` (drawn). High.
- [x] Tab icons (combat/skills/inventory/equipment/prayer/magic) — `scripts/ui/widgets/tab_icon.gd`
  (drawn). High.
- [x] Action buttons (Bank/Slayer/Map) — `scripts/ui/widgets/icon_button.gd` (drawn). High.
- [x] Minimap + player/route/entity dots — `scripts/ui/widgets/minimap.gd` (drawn). High.
- [x] Inventory/equipment slots, panels, chatbox, zone banners — drawn in `osrs_hud.gd` + tabs. High.
- [x] Click marker / action indicator — `scripts/ui/click_marker_art.gd` + `world.show_click_fx`. Med.
- [x] Hitsplats / floating XP / damage numbers — `scripts/world/hit_splat.gd`,
  `world_visual_controller` (drawn). High.
- [ ] Buff/debuff status icons — prayers toggle but no on-HUD buff-icon row. Low/Medium.
- [ ] Cursor icons (custom) — uses default + pointing-hand. Low.
- [ ] Tooltip art / interaction-prompt art — tooltips are text panels; no art. Low.
- [?] Level-up art / banner — level-up emits chat + (see VFX). Confirm if a banner graphic is wanted.

### Map / minimap icons
- [x] Minimap markers (player, route, entities) — drawn (`minimap.gd`). High.
- [x] World map (M) — uses worldgen data + `data/world/baked/aldreth_map.png`. Medium.
- [ ] Distinct POI/marker icon set (bank/shop/quest/obelisk pins) — minimal; add if wanted. Low.

### Dialogue / portraits
- [ ] NPC/quest portraits — none. Medium (only if dialogue UI grows faces).

### VFX sprites
See "Animation and VFX Assets".

---

## Animation and VFX Assets
Animations are **code-driven poses** (`scripts/render/mover_rig.gd`), not sprite sheets/AnimationPlayers.
VFX are procedural meshes/particles (`scripts/render/world_fx_3d.gd`, `fishing_decor_3d.gd`).

### Player gather/skill animations (`mover_rig.gd` `_pose_gather_work`)
- [x] Woodcutting chop — `chop` pose. Critical.
- [x] Mining swing — `mine` pose (overhead pickaxe, this session). Critical.
- [x] Fishing rod cast — `fish_rod` (rod + line + float). Critical.
- [x] Fishing lobster kneel (cage) — `fish_kneel`. High.
- [x] Foraging pick — `forage` (bend + hands). High.
- [x] Hunter trap-set — `trap`. Medium.
- [x] Thieving reach — `steal`. Medium.
- [x] Walk/idle gait (speed-scaled), turn spring, squash — `_pose_humanoid`. Critical.
- [x] "Face the node, then animate" gate — `mover_renderer_3d`. Done.

### Combat animations
- [x] Melee attack lunge, heavy/onehand/staff/bow attack styles — `mover_rig` + `weapon_profile`
  `attack` types. High.
- [x] Take-a-hit flash + shake, death topple — `mover_renderer_3d`. High.
- [x] Ranged shot projectile (arrow) — `scripts/world/arrow_proj.gd` + `combat_ranged_shot`. High.

### VFX (exist)
- [x] Woodcutting leaf puff — `world_fx_3d._on_wc_log` (`wc_log_chopped`). High.
- [x] Tree fall + regrow — `world_fx_3d._on_wc_felled/_on_wc_grew`. Medium.
- [x] Mining rock-chip / dust puff — `world_fx_3d._on_mining_struck` (`mining_struck`, this session).
  High.
- [x] Fishing-spot bubbles — `fishing_decor_3d.gd`. High.
- [x] Blob shadows under movers — `prop_meshes.blob_shadow`. Medium.
- [x] Dawn mist, weather (rain/snow) — `shaders/dawn_mist.gdshader`, `world_weather_fx.gd`. Medium.

### VFX (missing — good next adds)
- [ ] Water splash on fishing cast + catch — Loop/one-shot — used by fishing — none. Medium.
- [ ] Generic resource-depletion poof (rock/bush) — only woodcutting has fall/puff. Medium.
- [ ] Level-up flourish — emits chat only; no particle. Medium.
- [ ] Item-pickup pop / loot sparkle — `loot_gained` has no world VFX. Low/Medium.
- [ ] Surface ripple ring around fishing spot — bubbles only. Low.
- [ ] UI notification effect (toast/flash) — none. Low.

---

## Materials and Textures
Materials are mostly **palette colors in code** (`scripts/world/art/core/pixel_palette.gd`,
`equip_loadout.material_color`, `terrain_style.gd`), not texture files. The toon shaders read
vertex/material color. Water/sand use small generated noise textures (`make_water_noise`).
- [x] Metal tiers (bronze/iron/steel/black/mithril/adamant/rune/dragon/gold/silver) — color map in
  `item_icon.material_color` + `equip_loadout`. `[x]` (color-swap, not textures).
- [x] Tree leaf vs trunk colors — separate palette colors per species; leaves & trunk are separate
  mesh parts (good for recolor). `[x]`.
- [x] Rock / ore colors — palette + `terrain_style`; ore vein color via material. `[x]`.
- [x] Roof / wall / path / grass / water colors — `terrain_style.gd` + palette + toon shaders. `[x]`.
- [x] Snow (white, not purple) — fixed this session in `terrain_style`/`toon_ground` cold tints. `[x]`.
- [x] Sand noise / water foam noise — generated (`TerrainChunkMesher.make_water_noise`). `[x]`.
- [~] Bark / rock surface **textures** (vs flat color) — none; the look is flat-shaded by design.
  `[~]` only if a more textured look is desired.
- [?] Seasonal / biome material variants — biome tints exist (`terrain_style.biome_tinted`); explicit
  seasons not implemented. Confirm.

### GLB part-separation requirements (if/when swapping procedural → file art)
Per `docs/GLB_IMPORT_GUIDE.md`, keep these as SEPARATE meshes/materials:
- [ ] **House/building roof separate from walls** — REQUIRED if interiors are enterable (roof must
  hide). `smithy.glb` does NOT separate its roof → fix before using as an interior building. **Risk.**
- [x] Tree leaves separate from trunk — already separate in procedural trees; preserve in any GLB.
- [ ] Door separate from house — procedural cabins have `*_door` parts; preserve in GLB.
- [ ] Ore vein separate from rock — currently one `rock` mesh; separate if veins should deplete
  visually. Medium.
- [x] Tool head separate from handle — pickaxe is built head+haft; keep separable in any GLB.

---

## Existing Assets Verified
| Status | Asset | Type | Path | Used By | Notes |
|---|---|---|---|---|---|
| [x] | 22 skill icons | PNG | `assets/skill_icons/*.png` | SkillRegistry / HUD skills tab | One per skill; complete |
| [x] | Smithy | GLB | `models/smithy.glb` (+`.import`) | `scripts/render/smithy_prop.gd` | Reference GLB; roof not separated |
| [x] | Item icons (all) | Procedural 2D | `scripts/ui/item_icon.gd` | Inventory/bank/shop/equipment | ~33 shape kinds + material tints |
| [x] | Props/buildings/decor | Procedural 3D | `scripts/render/prop_meshes.gd` | StaticPropBatcher, world | ~120 decor + ~70 town/furniture kinds |
| [x] | Player/enemy bodies + worn gear + held weapons/tools | Procedural 3D | `scripts/render/mover_meshes.gd`, `equip_loadout.gd` | MoverRenderer3D | 5 enemy archetypes; tier = color tint |
| [x] | Gather/combat/walk animations | Code poses | `scripts/render/mover_rig.gd`, `mover_renderer_3d.gd` | All skilling + combat | chop/mine/cast/kneel/forage/trap/steal + lunges |
| [x] | Fishing-spot bubbles | Procedural VFX | `scripts/render/fishing_decor_3d.gd` | Fishing spots | translucent cyan spheres |
| [x] | Wc/mining/tree VFX | Procedural VFX | `scripts/render/world_fx_3d.gd` | Woodcutting, mining | leaf puff, rock chip, fall/grow |
| [x] | HUD widgets (orbs/tabs/buttons/minimap/hitsplats) | Procedural 2D | `scripts/ui/widgets/*`, `osrs_hud.gd`, `hit_splat.gd` | HUD | all drawn |
| [x] | Terrain/water + shaders | Procedural + shaders | `terrain_chunk_mesher.gd`, `terrain_style.gd`, `shaders/*` | World render | flat-lit toon |
| [x] | Worldgen masks / world map | PNG | `data/world/masks/*`, `data/world/baked/aldreth_map.png` | WorldGen / world map | authoring inputs, not props |
| [~] | Baked prop sprites | PNG | `generated/props/*.png` | `tools/prop_baker_3d.gd` only | dev output, NOT runtime |

## Missing Assets To Make
| Priority | Status | Asset | Type | Intended Path | Needed For | Notes |
|---|---|---|---|---|---|---|
| High | [ ] | SFX: chop, mine, fish splash, UI click, combat hit, pickup, footsteps | Audio | `assets/audio/sfx/*.ogg` → paths in `data/audio.json` | All actions | System fully wired; just add files + paths |
| High | [ ] | Music: per-biome + combat + town | Audio | `assets/audio/music/*.ogg` → `data/audio.json` | Ambience | Cross-fades on biome change |
| High | [~] | Item-icon variety | Procedural 2D | `scripts/ui/item_icon.gd` | Inventory readability | 976 items share ~33 shapes; add kinds/detail |
| Medium | [ ] | Water splash VFX (cast + catch) | Procedural VFX | `scripts/render/world_fx_3d.gd` | Fishing feel | mirror `_on_mining_struck` |
| Medium | [ ] | Resource-depletion poof (rock/bush) | Procedural VFX | `world_fx_3d.gd` | Mining/foraging feedback | only wc has it |
| Medium | [ ] | Level-up flourish | Procedural VFX | `world_fx_3d.gd` / HUD | Progression feedback | chat-only today |
| Medium | [~] | NPC roles + outfits (banker/shopkeeper/trainer/…) | Data + procedural | `data/npcs.json` + sim loadouts | Town life / dialogue | only 1 npc def |
| Medium | [ ] | Dialogue portraits | 2D art | `assets/portraits/` | NPC dialogue UI | none today |
| Low | [~] | Enemy archetype variety | Procedural 3D | `mover_meshes.gd` enemy_rig | 120 enemies, ~22 rigs (incl. golem/treant/imp) + per-species gaits | bosses get regalia; 1 bespoke (Pumpkin Jack) |
| Medium | [ ] | Foraging held tool (lens/sickle) mesh | Procedural 3D | `mover_meshes.gd` | Foraging readability | currently bare-handed |
| Low | [ ] | Item-pickup / loot sparkle VFX | Procedural VFX | `world_fx_3d.gd` | Loot feedback | on `loot_gained` |
| Low | [ ] | Buff/debuff HUD icons | Procedural 2D | `scripts/ui/` | Prayer/boosts | none today |
| Low | [ ] | POI map-pin icon set | Procedural 2D | `minimap.gd` / world map | Navigation | generic dots today |
| Low | [ ] | Fishing hut / barn / dock models | Procedural 3D or GLB | `prop_meshes.gd` or `models/` | World flavor | no kind yet |
| Low | [?] | Per-tier weapon/armor/tool silhouettes | Procedural 3D | `mover_meshes.gd` | Gear progression visual | currently color-tinted only |
| Low | [?] | Visible rings/amulets / backpack on rig | Procedural 3D | `mover_meshes.gd` | Cosmetic | iconned but not worn-visible |

## Placeholder / Needs Improvement
| Status | Asset | Current Path | Problem | Needed Fix |
|---|---|---|---|---|
| [~] | Item icons | `scripts/ui/item_icon.gd` | 976 items share ~33 shape templates + tints; many read alike | Add icon kinds / per-family detail; verify `misc` fallbacks |
| [~] | Enemy variety | `mover_meshes.gd` (enemy_rig) | 120 enemies → 5 body archetypes | Add archetypes; unique boss looks |
| [~] | Gear tiers | `equip_loadout.gd` / `mover_meshes.gd` | bronze→dragon are color tints, not shapes | Optional per-tier meshes |
| [~] | `smithy.glb` roof | `models/smithy.glb` | roof merged into the model | Separate roof mesh if it becomes an enterable interior |
| [~] | NPCs | `data/npcs.json` | only 1 entry; roles are stations | Add NPC defs + outfits + (optional) portraits |
| [~] | `generated/props/*.png` | `generated/props/` | dev baker output, not runtime; could confuse | Keep; document as dev-only (done here) |
| [~] | Foraging tool | (none) | no held mesh; bare-handed | Add lens/sickle held mesh |

---

## Per-Feature Asset Requirements
- **Mining:** [x] rock mesh, [x] pickaxe held+icon, [x] mine swing, [x] rock-chip VFX. [ ] ore-vein
  separation, [ ] depletion poof, [ ] mining SFX.
- **Fishing:** [x] fishing-spot bubbles, [x] rod held+cast anim + line/float, [x] lobster kneel,
  [x] fish item icons. [ ] splash VFX, [ ] fishing SFX.
- **Woodcutting:** [x] tree species meshes (leaves≠trunk), [x] axe held+icon, [x] chop anim,
  [x] leaf puff + fall/grow. [ ] chop SFX.
- **Foraging/Hunter/Thieving:** [x] bush/burrow/stall meshes, [x] forage/trap/steal poses,
  [x] item icons. [~] foraging held tool, [ ] action SFX.
- **Inventory:** [x] procedural item icons (all 976), [x] slot/grid UI. [~] icon distinctiveness.
- **Shops:** [x] reuse item icons + shop popup UI. [ ] shop hero art (optional).
- **Bank:** [x] chest mesh + bank popup UI + bank button. (chest lid not separated — `[~]`).
- **Combat:** [x] enemy archetypes + worn gear + weapons, [x] attack/hit/death anims, [x] hitsplats +
  arrow proj. [~] enemy variety, [ ] enemy SFX/VFX.
- **Skills:** [x] 22 skill icon PNGs, [x] skills tab UI, [x] XP float. [?] level-up banner art.
- **Player equipment:** [x] worn meshes (helm/body/legs/boots/gloves/shield/cape) + icons +
  color tints. [~] per-tier silhouettes; [?] visible jewellery/backpack.
- **Enemies:** see Combat.
- **Buildings/interiors:** [x] exterior procedural buildings + cabins (door/window/roof-rib parts).
  [ ] enterable interiors (roof-hide system) — `smithy.glb` roof would need separating; [?] confirm
  if interiors are planned.
- **Map/minimap:** [x] minimap + world map + dots + `aldreth_map.png`. [ ] POI pin icon set.
- **UI/HUD:** [x] orbs/tabs/buttons/panels/chat/banners/hitsplats (all drawn). [ ] buff icons,
  custom cursors, toasts.
- **Save/load:** no icons/visual-state assets (text + state only). N/A.

## Naming Conventions
Follow the EXISTING conventions (don't invent new ones):
- **Skill icon files:** `assets/skill_icons/<skill_id>.png` where `<skill_id>` is the lowercase skill
  key from `data/skills.json` (e.g. `woodcutting.png`). Add a new skill icon at exactly this path.
- **GLB models:** `models/<thing>.glb` named after the THING, not its look (`watchtower.glb`, not
  `blue_tower_v3.glb`) + a loader `scripts/render/<thing>_prop.gd` (mirror `smithy_prop.gd`).
- **Procedural kinds:** lowercase snake_case `kind` strings matched in `prop_meshes.gd` /
  `mover_meshes.gd` (e.g. `"berry_bush"`, `"canopy_pine"`, `"fishing_rod"`). Reuse an existing kind or
  add a new `match` case — don't fork a parallel function.
- **Item/enemy/recipe content:** stable `id` (`item.*`/`enemy.*`/`node.*`/`recipe.*`) + frozen `name`;
  rename only `displayName` (see `docs/SAVE_FORMAT.md` / the codebase-guide skill).
- **Audio:** `assets/audio/music/<tag>.ogg`, `assets/audio/sfx/<event>.ogg`; wire the path into
  `data/audio.json` (tags/events already listed there).

## Asset Creation Rules For Future AI Agents
1. **Search first.** Most art is procedural — `grep` `prop_meshes.gd`/`mover_meshes.gd`/`item_icon.gd`
   and `find` the `assets/`/`models/` folders before declaring anything missing.
2. If it exists, mark `[x]` here with the path (file OR generating script+function).
3. If it's a placeholder/reused, mark `[~]` and say what to improve.
4. **GLB buildings with enterable interiors → keep the roof a SEPARATE mesh/node** (so it can hide on
   entry). `smithy.glb` does not — fix before using it as an interior.
5. **Color-changing GLB parts → separate materials/meshes** (roof/walls, leaves/trunk, door, ore
   vein, tool head/handle). See `docs/GLB_IMPORT_GUIDE.md`.
6. **Item icons → match the procedural style/size** in `scripts/ui/item_icon.gd` (add a `kind` +
   `classify()` mapping rather than a one-off). Don't introduce PNG item icons without a design call.
7. **Equipped tools/weapons → verify they work with the rig** (`weapon_profile` grip rotation +
   `equip_parts` mesh + `_refresh_gather_tool`/`equip_loadout` mapping); test with
   `tools/weapon_pose_preview.tscn` / `tools/fish_shot.tscn`.
8. **No duplicate icons/models** for the same item unless an intentional variant.
9. **Update this file** whenever an asset is added, moved, renamed, replaced, or wired to a feature.
   Also tick it in the codebase-guide wiki reference.
10. **Audio:** drop the file under `assets/audio/...`, set its path in `data/audio.json` — it then
    plays via the existing `Audio` hooks; no code needed.
