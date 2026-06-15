extends RefCounted
class_name PrayerLore
## Prayer training data (spec §16): burying bones grants Prayer XP. PLACEHOLDER
## per-bone XP — tune later. Any item whose name contains "Bones" is buriable.

const BONE_XP := {
	"Bones": 5.0,
	"Fish Bones": 4.0,
	"Pile Of Bones": 5.0,
	"Rotten Bones": 4.0,
	"Frozen Bones": 8.0,
	"Necrotic Bones": 12.0,
	"Desiccated Bones": 12.0,
	"Scorched Pile Of Bones": 14.0,
	"Golden Desiccated Bones": 25.0,
	"Golden Scorched Pile Of Bones": 30.0,
}
const DEFAULT_BONE_XP := 5.0


static func is_bone(item_name: String) -> bool:
	return item_name.contains("Bones")


static func bone_xp(item_name: String) -> float:
	return float(BONE_XP.get(item_name, DEFAULT_BONE_XP))
