# Decor examples (reference only — not compiled)

These are donated **procedural nature-decor** scripts (rocks, plants, mushrooms,
grasses, etc.) kept purely as **inspiration** for hand-authoring decor later.

They are **not part of the build**: this folder contains a `.gdignore`, so Godot
skips it entirely — nothing here is compiled, no `class_name` is registered, and
none of it runs in the game or editor.

The live decoration system the game actually uses is
`scripts/world/art/ground_decor/` (`GroundDecorArt`), driven by the world editor's
clutter/forest brushes and the biome canopy/ground-decor config.

To revive any of these: copy the script back under `scripts/` (out of this
gdignored folder) and wire it into the decor catalog. Moved here from
`scripts/world/art/decor/nature/`.
