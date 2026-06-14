extends RefCounted
class_name BuildingStyles
## Registry of settlement building styles.
## Each style maps to a draw implementation in this folder.
##
## Current styles:
##   "medieval"  — BuildingArt (scripts/world/art/structures/building_art.gd)
##                 Stone + timber-frame, hip/gabled tiled roof, city colour palette.
##
## Adding a new style:
##   1. Create  <style>_building_art.gd  here with the same static interface:
##        draw_body(canvas, foot, variant, accent)
##        draw_roof(canvas, foot, variant, roof_color, alpha)
##        wall_height(foot, variant) -> float
##        roof_height(foot, variant) -> float
##        total_height(foot, variant) -> float
##   2. Preload it in building_art.gd and add a  match _style:  arm.
##   3. Set  WorldEntity.building_style  to the style string in world_entity_spawner
##      when constructing entities for that settlement type.
##   4. Add a palette entry in PixelPalette if new colours are needed.
##
## Planned future styles:
##   "desert"  — mudbrick walls, flat roof with parapet, sand/ochre palette
##   "ruin"    — collapsed walls, rubble fill, overgrown, no roof
##   "village" — smaller, rougher timber frames, thatched roof variant

const STYLES: Array[String] = ["medieval"]
