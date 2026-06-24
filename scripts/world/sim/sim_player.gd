extends RefCounted
class_name SimPlayer
## A single sim-player's lightweight identity + runtime brain state (the Erenshor "theater"
## model — NOT a second copy of the real player economy). Identity is DETERMINISTIC from the
## world seed + home chunk + slot, so the same world always regenerates the same cast of
## characters with zero save footprint (see docs/SIM_PLAYERS_PLAN.md §5). Runtime state (where
## it's walking, what it's pretending to skill) lives here too and is rebuilt each session.

# Brain states (SimBrain drives the transitions; SimDirector steps the movement).
const IDLE := "idle"
const WALK := "walk"
const GATHER := "gather"
const FOLLOW := "follow"

# --- identity (deterministic, never saved) ---
var pname := "Adventurer"
var skin := Color(0.93, 0.78, 0.62)
var loadout: Dictionary = {}          # {slot: {kind, material, tint?}} for MoverMeshes.apply_equipment
var levels: Dictionary = {}           # skill -> level (flavour; surfaced if inspected)
var combat_level := 3
var personality := 0.5                # 0 = homebody/skiller, 1 = wanderer/social
var walk_speed := 32.0                # px/s, varied per sim so they don't march in lockstep
var home := Vector2.ZERO              # anchor the day-in-the-life loop orbits
var slot_key := ""                    # "cx:cy:slot" — stable id for spawn/cull bookkeeping
var seed := 0                         # per-sim deterministic RNG seed for behaviour rolls

# --- runtime (rebuilt each session) ---
var entity: Node2D = null             # the WorldEntity logic node (rig built by MoverRenderer3D)
var state := IDLE
var state_t := 0.0                    # seconds remaining in the current state
var path := PackedVector2Array()
var path_i := 0
var gather_skill := ""                # which skill it's pretending to train while GATHER
var target: Node2D = null             # gather node / follow buddy
var fake_xp := 0.0                    # theatrical XP toward the current gather skill's next "level"
var commanded := false                # player right-clicked Follow — track the player (RS-style) until told to stop
var follow_repath_t := 0.0            # cooldown between repaths toward the moving player while following

# Dialogue pacing (so chatter is contextual, not constant).
var chat_cd := 0.0                    # seconds until this sim may speak again
var greeted_player_at := -999.0       # last time (s) it greeted the player, to avoid spam
var bubble: Node2D = null             # active speech bubble, if any

var _roll := 0                        # advancing counter so repeated rolls differ deterministically


## A deterministic float in [0,1) that advances each call — used for behaviour rolls that
## must stay reproducible for a given world seed yet vary from one decision to the next.
func roll() -> float:
	_roll += 1
	return WG_r01(seed, _roll)


## Local copy of WG.r01 (avoids importing WG into this tiny struct).
static func WG_r01(s: int, a: int) -> float:
	var h: int = s + a * 0x9E3779B9
	h = (h ^ (h >> 30)) * 0x45D9F3B
	h = (h ^ (h >> 27)) * 0x119DE1F3
	h = h ^ (h >> 31)
	return float((h & 0x7FFFFFFFFFFFFFFF) % 1000003) / 1000003.0


func main_skill() -> String:
	var best := "woodcutting"
	var best_lvl := -1
	for s: String in levels:
		if int(levels[s]) > best_lvl:
			best_lvl = int(levels[s])
			best = s
	return best
