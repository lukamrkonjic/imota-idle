extends RefCounted
class_name ClickMarkerAnim
## OSRS click-X timing: grow from centre, brief hold, hollow outward, vanish.

const STEP := 0.046
const MAX_ARM := 2

## arm = diagonal reach; gap < 0 = full arm, gap >= 0 = hollow centre outward.
const FRAMES: Array[Dictionary] = [
	{"arm": 0, "gap": -1},
	{"arm": 1, "gap": -1},
	{"arm": 2, "gap": -1},
	{"arm": 2, "gap": -1},
	{"arm": 2, "gap": 1},
]


static func frame_count() -> int:
	return FRAMES.size()


static func step(frame: int) -> Dictionary:
	return FRAMES[clampi(frame, 0, FRAMES.size() - 1)]
