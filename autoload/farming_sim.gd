extends Node
## FarmingSim (spec §16, §21) — the one background system. Plots grow on the
## global tick *while the player does any other activity*, so it's a genuine
## passive layer that still respects the no-offline rule (no growth while the
## game is closed). Data-driven from data/farming.json; all numbers are
## placeholders to tune later.
##
## A plot is either {} (empty) or:
##   { "seed", "crop", "xp": float, "yield": int, "grow": int, "age": int }

const DATA_PATH := "res://data/farming.json"
const GROW_INTERVAL := 1.0   # seconds of game time per growth tick (tunable)
const DEFAULT_PLOTS := 3

var crops: Dictionary = {}    # seed name -> crop def
var plots: Array = []         # fixed-size; index = plot
var plot_count := DEFAULT_PLOTS
var _accum := 0.0
var suppress := false         # headless tests set this so it never auto-ticks


func _ready() -> void:
	_load_crops()
	_resize_plots(plot_count)


func _process(delta: float) -> void:
	if suppress:
		return
	advance(delta)


func _load_crops() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary:
		crops = parsed.get("crops", {})


func _resize_plots(n: int) -> void:
	plot_count = maxi(1, n)
	while plots.size() < plot_count:
		plots.append({})
	if plots.size() > plot_count:
		plots = plots.slice(0, plot_count)


# --------------------------------------------------------------- planting ----

func can_plant(seed_name: String) -> bool:
	if not crops.has(seed_name):
		return false
	return GameState.level("farming") >= int(crops[seed_name].get("levelReq", 1))


## Plant a seed from inventory into the first empty plot. Returns true on success.
func plant(seed_name: String) -> bool:
	if not crops.has(seed_name):
		return false
	var def: Dictionary = crops[seed_name]
	if GameState.level("farming") < int(def.get("levelReq", 1)):
		EventBus.combat_log.emit("Farming level %d required for %s" % [int(def.get("levelReq", 1)), seed_name])
		return false
	var idx := _first_empty_plot()
	if idx < 0:
		EventBus.combat_log.emit("All farming plots are full.")
		return false
	if GameState.count_item(seed_name) <= 0 or not GameState.remove_item(seed_name, 1):
		EventBus.combat_log.emit("You have no %s." % DataRegistry.item_display_name(seed_name))
		return false
	plots[idx] = {
		"seed": seed_name,
		"crop": str(def["crop"]),
		"xp": float(def.get("xp", 0.0)),
		"yield": int(def.get("yield", 1)),
		"grow": int(def.get("growTicks", 20)),
		"age": 0,
	}
	EventBus.combat_log.emit("[farming] Planted %s." % DataRegistry.item_display_name(seed_name))
	EventBus.farming_changed.emit()
	return true


func _first_empty_plot() -> int:
	for i: int in plots.size():
		if (plots[i] as Dictionary).is_empty():
			return i
	return -1


# ---------------------------------------------------------------- growth ----

func advance(delta: float) -> void:
	_accum += delta
	while _accum >= GROW_INTERVAL:
		_accum -= GROW_INTERVAL
		_tick_growth()


func _tick_growth() -> void:
	var any := false
	for i: int in plots.size():
		var p: Dictionary = plots[i]
		if p.is_empty():
			continue
		p["age"] = int(p["age"]) + 1
		any = true
		if int(p["age"]) >= int(p["grow"]):
			_harvest(i)
	if any:
		EventBus.farming_changed.emit()


## Auto-harvest a ready plot: yield to inventory + Farming XP, then clear it.
func _harvest(i: int) -> void:
	var p: Dictionary = plots[i]
	var added := GameState.add_item(str(p["crop"]), int(p["yield"]))
	if added == 0:
		# Inventory full: leave the plot ready (it retries next tick) and grant no XP —
		# previously XP was awarded and the plot cleared even when nothing was stored.
		EventBus.combat_log.emit("[farming] Inventory full — %s left to harvest." % DataRegistry.item_display_name(str(p["crop"])))
		return
	GameState.add_xp("farming", float(p["xp"]))
	EventBus.loot_gained.emit(str(p["crop"]), added)
	EventBus.combat_log.emit("[farming] Harvested %s." % DataRegistry.item_display_name(str(p["crop"])))
	plots[i] = {}


func ready_count() -> int:
	var n := 0
	for p: Dictionary in plots:
		if not p.is_empty():
			n += 1
	return n


# ------------------------------------------------------------ persistence ----

func to_save() -> Dictionary:
	return {"plotCount": plot_count, "plots": plots.duplicate(true)}


func from_save(d: Dictionary) -> void:
	_resize_plots(int(d.get("plotCount", DEFAULT_PLOTS)))
	var saved: Array = d.get("plots", [])
	for i: int in plots.size():
		plots[i] = (saved[i] as Dictionary).duplicate(true) if i < saved.size() and saved[i] is Dictionary else {}
	EventBus.farming_changed.emit()


func reset() -> void:
	plot_count = DEFAULT_PLOTS
	plots = []
	_resize_plots(plot_count)
	_accum = 0.0
