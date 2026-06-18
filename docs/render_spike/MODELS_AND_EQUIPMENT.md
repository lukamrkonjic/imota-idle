# 3D Models & Equipment System

How the in-world 3D characters (player, enemies) are built, animated, and shown
wearing armor / holding weapons. All of this lives in
`scripts/render/prop_meshes.gd` (meshes) + `scripts/render/world_render_3d.gd`
(animation) + `scripts/render/equip_loadout.gd` (data → loadout).

Everything is low-poly primitives (`_box`/`_cyl`/`_cone`/`_sphere`/`_octa`),
palette-driven via `_mat_from` / `equip_material`, and cached by string key.

## Rig templates

A "rig" is a `Node3D` tree. One per moving character, built once and reused. Each
tags itself with two metas the renderer reads:

- `body3d` — animation template: `humanoid`, `quad`, `bird`. (Beastman uses
  `humanoid`.) Drives which `_pose_*` runs.
- `base_scale` — overall size (species size × boss bump). The pose multiplies its
  squash by this each frame, so size survives per-frame scaling.

| Builder | body3d | Used by | Notes |
|---|---|---|---|
| `figure_rig(body, head, cape=clear)` | humanoid | player, goblins, skeletons | Natural human proportions: normal squared head, hair, rolled-sleeve shirt, trousers, boots. |
| `beastman_rig(spec)` | humanoid | gnolls | Hunched hyena-folk; snout head, ears, fur + loincloth, long clawed arms. |
| `quadruped_rig(spec)` | quad | cow/wolf/boar/sheep/goat/pig/mole | Four legs + tail; ears/horns/tusks/wool flags. |
| `bird_rig(spec)` | bird | chickens | Small two-legged fowl; beak/comb/wattle. |

`enemy_rig(e)` picks the template + colours + size from the enemy name
(`enemy_body_type` + `_variant_size`), then applies its archetype loadout.

### Animation pivots (named child `Node3D`s)

The pose functions swing these via `_set_pivot` (rotation.x):

- humanoid / beastman: `leg_l`, `leg_r`, `arm_l`, `arm_r`
- quad: `leg_fl`, `leg_fr`, `leg_bl`, `leg_br`, `tail`
- bird: `leg_l`, `leg_r`

Every template has an **idle** so nothing stands frozen: humanoids breathe + sway
+ drift the arms; quadrupeds breathe + weight-shift + periodically dip to graze;
birds bob + peck + cock the head. Combat adds a tick-synced attack lunge (see
`_on_combat_swing`) and makes the player + target face each other.

Each mover also gets a soft **blob shadow** (`blob_shadow()`), pinned to the ground
and sized per body type; the rig's real cast-shadow is disabled so there's one
clean shadow.

## Equipment (worn armor + held weapons)

### Sockets = capability

A rig exposes named empty `Node3D` **sockets**; equipment is parented to them.
**If a rig lacks a socket, it cannot show that slot.** This is the entire
capability gate — a chicken has no sockets, so it wears nothing.

| Socket | Where | humanoid | beastman | quad | bird |
|---|---|:-:|:-:|:-:|:-:|
| `socket_mainhand` | right hand (child of `arm_r`, so weapons swing) | ✓ | ✓ | | |
| `socket_offhand` | left hand (child of `arm_l`) | ✓ | ✓ | | |
| `socket_head` | head | ✓ | ✓ | | |
| `socket_body` | chest / back | ✓ | ✓ | ✓ (barding) | |
| `socket_legs` | hips | ✓ | ✓ | | |
| `socket_back` | upper back | ✓ | ✓ | | |

`equip_profile(rig)` returns the slots a given rig supports.

### Applying a loadout

`apply_equipment(rig, loadout)` where
`loadout = { slot: {kind, material, tint?} }` and `slot` ∈
`mainhand/offhand/head/body/legs/back`. It clears any prior gear, then for each
slot the rig supports builds the mesh (`equip_parts`) and parents it under the
socket (cast-shadow off). Slots the rig can't support are silently skipped.

- **kinds:** weapons `sword/dagger/axe/mace/spear/bow/staff/wand`, armor
  `helm/hood/chest/robe_top/robe_bottom/cape/shield`.
- **materials** (`equip_material`): `cloth` (tinted) / `leather` / `bronze` /
  `iron` / `steel` / `mithril` / `adamant` / `rune` / `gold` / `wood` / `gem`.
- Weapons are modelled extending **+Y from the grip**, so they read as held and
  swing with the arm pivot.

### Cheap cloth flow

Robe skirts (`socket_legs`) and capes (`socket_back`) are flagged `cloth` and
swayed procedurally in `_flow_cloth` — they pivot at the waist/shoulders, trail
back as the wearer moves, and ripple on a soft wind oscillation. Pure
trig + one rotation per piece, no physics.

### Loadout sources (`equip_loadout.gd`)

- `for_player(GameState.equipment)` — maps worn items (Weapon/Shield/Helm/Body/
  Cape) → kind + material by item name; re-applied on `equipment_changed`.
- `for_enemy(name, level)` — from the combat archetype: magic → hood + robe top +
  robe bottom + staff; ranged → bow; melee → tiered sword (+ shield for fighters).
  Goblin Mage → purple cloth robe set + wooden staff.

## Checklist: adding a new model

1. **Build the rig** with a builder that returns a `Node3D`; reuse a template
   (`quadruped_rig`/`bird_rig`/`figure_rig`/`beastman_rig`) if it fits, else add a
   new one and a `_pose_*` for it.
2. **Name the animation pivots** to match its `body3d` template (or write the pose).
3. **Set metas:** `body3d` and `base_scale`.
4. **Add sockets** for every slot the creature should be able to wear/hold — and
   *only* those (omit them to forbid gear, like the bird).
5. **Give it an idle** in its `_pose_*` so it's never static.
6. **Route it** in `enemy_rig` (name → template + colours + size), and add any new
   size keywords to `_variant_size`.
7. If it can wear cloth, the skirt/cape sway is automatic (flagged in
   `apply_equipment`); just use `robe_bottom` / `cape` kinds.

## Verifying

Screenshot with crisp pixels — launch `Godot --path . -- --crisp` (forces near
native res in `_scale_from_setting`); auto-capture lands at
`user://world3d_shot.png`. Real gameplay keeps the player's Settings pixelation.
