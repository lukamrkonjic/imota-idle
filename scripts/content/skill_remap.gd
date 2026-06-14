extends RefCounted
class_name SkillRemap
## The single source of truth for the Bloobs -> Imota skill-key remap (spec §2).
##
## Used by: GameState skill migration (save keys), tools/remap_skills.gd (data
## reqs/bonusXp/recipe skill fields), and tools/import_bloobs_data.gd (so a
## re-import writes the new skill names while ids are still minted from the
## original Bloobs slug, keeping the frozen id registry stable).
##
## Notes:
## - foraging stays foraging (gathering only; potion-making split into Alchemy).
## - beastmastery is no longer a skill; its level-lock folds into Slayer, so its
##   XP migrates into Slayer.
## - imbuing / soulbinding have no successor skill yet; their recipes/XP are
##   re-homed into Crafting (flagged, not dropped — spec §2).

const MAP := {
	"devotion": "prayer",
	"tracking": "hunter",
	"dexterity": "agility",
	"homesteading": "farming",
	"herbology": "alchemy",
	"beastmastery": "slayer",
	"imbuing": "crafting",
	"soulbinding": "crafting",
}


static func to_new(skill: String) -> String:
	return MAP.get(skill, skill)
