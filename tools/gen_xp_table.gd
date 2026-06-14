extends SceneTree
## Generates data/xp_table.json from the OSRS experience formula, slowed by a
## single tunable multiplier S (Imota spec §1). Run headless:
##   godot --headless --path C:/Dev/imota-idle --script res://tools/gen_xp_table.gd
##
##   osrsXp(L) = floor( 1/4 * Σ_{i=1..L-1} floor( i + 300 * 2^(i/7) ) )
##   xpRequired[L] = round( osrsXp(L) * S )
##
## S is the one balancing knob. Start 1.25 (spec). Table is 1..MAX_LEVEL, with
## index = level; xpRequired[0] and [1] are 0 (no XP to be level 1).

const MAX_LEVEL := 99
const S := 1.25  # XP slowdown multiplier; the single balance knob.


func _init() -> void:
	var xp_required: Array = []
	xp_required.resize(MAX_LEVEL + 1)
	xp_required[0] = 0
	var acc := 0.0
	for level: int in range(1, MAX_LEVEL + 1):
		# osrsXp(level) uses the running sum of i=1..level-1.
		var osrs := int(floor(0.25 * acc))
		xp_required[level] = int(round(float(osrs) * S))
		acc += floor(float(level) + 300.0 * pow(2.0, float(level) / 7.0))
	var out := {"maxLevel": MAX_LEVEL, "slowdown": S, "xpRequired": xp_required}
	var f := FileAccess.open("res://data/xp_table.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("xp_table.json: maxLevel=%d S=%.2f  L2=%d L50=%d L99=%d" % [
		MAX_LEVEL, S, int(xp_required[2]), int(xp_required[50]), int(xp_required[99])])
	quit(0)
