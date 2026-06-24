extends Node
## Audio (autoload) — GROUNDWORK for music + sound effects.
##
## No audio FILES ship yet: this wires every action/event to a sound id and provides per-biome/zone
## music with cross-fade, but each mapping in data/audio.json is empty, so the game is SILENT until
## you fill one in (drop a file under res://assets/audio/ and reference it). Then it just plays — no
## further code needed for the already-wired events.
##
## • Music: play_music(tag) cross-fades to the track mapped at `tag`. Driven by biome_changed here;
##   add zone names to the map and call play_music(zone) from zone logic for per-zone tracks.
## • SFX: play(event_id) fires the mapped one-shot. The events below are auto-wired; for a NEW action
##   sound (e.g. a shop "sell"), add the id to audio.json and call Audio.play("sell") where it happens.

const CONFIG := "res://data/audio.json"
const SFX_VOICES := 8          # round-robin pool so overlapping sounds don't cut each other
const MUSIC_FADE := 1.6        # seconds for the music cross-fade

var master_volume := 0.8
var music_volume := 0.7
var sfx_volume := 0.9
var enabled := true

var _music: Dictionary = {}    # tag -> stream path
var _sfx: Dictionary = {}      # event id -> stream path
var _footsteps: Dictionary = {} # surface family (grass/sand/snow/rock/path/water) -> footstep path
var _ambient: Dictionary = {}  # tag -> looping bed path (rain / wind + per-biome ambience tags)
var _cache: Dictionary = {}    # path -> AudioStream
var _warned: Dictionary = {}   # paths already warned missing

# Looping ambience beds, cross-faded: "rain"/"wind" track the live Weather; "biome" swaps on biome
# change. Each entry = {player, tag, cur, target}. Add more channels via set_ambient().
var _ambient_layers: Dictionary = {}
var ambient_volume := 0.8

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_i := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _music_tag := "__init__"   # sentinel so the first play_music always takes


func _ready() -> void:
	_load_config()
	for i: int in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)
	_music_a = _new_music_player()
	_music_b = _new_music_player()
	_music_active = _music_a
	_wire_events()


# ─────────────────────────────── public API ─────────────────────────────────

## Fire the one-shot SFX mapped to `event_id` (data/audio.json "sfx"). No-op if unmapped/silent.
func play(event_id: String, pitch_var := 0.06) -> void:
	if not enabled:
		return
	var stream := _stream(str(_sfx.get(event_id, "")))
	if stream == null:
		return
	var p := _sfx_players[_sfx_i]
	_sfx_i = (_sfx_i + 1) % _sfx_players.size()
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.volume_db = _vol_db(sfx_volume)
	p.play()


## One-shot footstep for the given surface family ("grass"/"sand"/"snow"/"rock"/"path"/"water").
## Driven by the movement code (world_visual_controller) once per stride. Quieter than action SFX and
## falls back to "grass" so an unmapped surface still ticks once a grass step sound is supplied.
func footstep(surface: String, pitch_var := 0.12) -> void:
	if not enabled or _sfx_players.is_empty():
		return
	var stream := _stream(str(_footsteps.get(surface, _footsteps.get("grass", ""))))
	if stream == null:
		return
	var p := _sfx_players[_sfx_i]
	_sfx_i = (_sfx_i + 1) % _sfx_players.size()
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.volume_db = _vol_db(sfx_volume * 0.7)
	p.play()


## Cross-fade music to the track mapped at `tag` (a biome music tag or zone name). No-op if it's
## already the current tag. An empty/unmapped tag fades the music out.
func play_music(tag: String) -> void:
	if tag == _music_tag:
		return
	_music_tag = tag
	var stream := _stream(str(_music.get(tag, "")))
	var nxt: AudioStreamPlayer = _music_b if _music_active == _music_a else _music_a
	var cur := _music_active
	if cur.playing:
		var t := create_tween()
		t.tween_property(cur, "volume_db", -80.0, MUSIC_FADE)
		t.tween_callback(cur.stop)
	if stream != null and enabled:
		nxt.stream = stream
		nxt.volume_db = -80.0
		nxt.play()
		create_tween().tween_property(nxt, "volume_db", _vol_db(music_volume), MUSIC_FADE)
		_music_active = nxt


func stop_music() -> void:
	play_music("")


## Live volume control (0..1). Wire a settings slider to these later.
func set_volumes(master: float, music: float, sfx: float) -> void:
	master_volume = clampf(master, 0.0, 1.0)
	music_volume = clampf(music, 0.0, 1.0)
	sfx_volume = clampf(sfx, 0.0, 1.0)
	if _music_active != null and _music_active.playing:
		_music_active.volume_db = _vol_db(music_volume)


## Drive a looping ambience bed on `channel` (e.g. "rain"/"wind"/"biome"). `tag` selects the loop from
## audio.json "ambient"; `target` is the 0..1 loudness to ease toward (0 fades the bed out). Swapping
## `tag` on a live channel swaps the stream. `_process` calls this for weather; call it for custom beds.
func set_ambient(channel: String, tag: String, target: float) -> void:
	var layer := _ambient_layer(channel)
	target = clampf(target, 0.0, 1.0)
	if tag != layer.tag:
		layer.tag = tag
		var stream := _stream(str(_ambient.get(tag, "")))
		var p: AudioStreamPlayer = layer.player
		p.stream = stream
		if stream != null and enabled and target > 0.0:
			p.play()
	layer.target = target


# ─────────────────────────────── internals ──────────────────────────────────

## Ease every live ambience bed toward its target loudness, and bind the weather beds to the live
## Weather autoload so rain/wind fade in and out with the storm. No-op (silent) until beds are mapped.
func _process(delta: float) -> void:
	if not enabled:
		return
	set_ambient("rain", "rain", Weather.rain)
	set_ambient("wind", "wind", smoothstep(0.2, 1.0, Weather.wind))
	for ch: String in _ambient_layers:
		var layer: Dictionary = _ambient_layers[ch]
		var p: AudioStreamPlayer = layer.player
		layer.cur = move_toward(layer.cur, layer.target, delta * 0.6)
		if layer.cur <= 0.0005:
			if p.playing:
				p.stop()
		else:
			if not p.playing and p.stream != null:
				p.play()
			p.volume_db = _vol_db(ambient_volume * float(layer.cur))


## Lazily create the AudioStreamPlayer + bookkeeping for an ambience channel.
func _ambient_layer(channel: String) -> Dictionary:
	if not _ambient_layers.has(channel):
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_ambient_layers[channel] = {"player": p, "tag": "", "cur": 0.0, "target": 0.0}
	return _ambient_layers[channel]

func _new_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = -80.0
	add_child(p)
	return p


func _vol_db(channel: float) -> float:
	return linear_to_db(clampf(channel * master_volume, 0.0001, 1.0))


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG):
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if doc is Dictionary:
		_music = (doc as Dictionary).get("music", {})
		_sfx = (doc as Dictionary).get("sfx", {})
		_footsteps = (doc as Dictionary).get("footsteps", {})
		_ambient = (doc as Dictionary).get("ambient", {})


func _stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		if not _warned.has(path):
			_warned[path] = true
			push_warning("Audio: stream missing on disk: %s (mapped in audio.json)" % path)
		return null
	var s: AudioStream = load(path)
	_cache[path] = s
	return s


## Connect the live game events to sound ids. Adding a sound later = just fill the path in audio.json.
func _wire_events() -> void:
	EventBus.level_up.connect(func(_s: String, _l: int) -> void: play("level_up"))
	EventBus.enemy_killed.connect(func(_n: String) -> void: play("enemy_killed"))
	EventBus.player_died.connect(func(_n: String) -> void: play("player_death"))
	EventBus.loot_gained.connect(func(_i: String, _q: int) -> void: play("loot"))
	EventBus.coins_changed.connect(func(_a: int) -> void: play("coins"))   # selling/buying/drops
	EventBus.firemaking_log_burned.connect(func() -> void: play("firemaking"))
	EventBus.wc_log_chopped.connect(func(_p: Vector2, _sp: String) -> void: play("chop_hit"))
	EventBus.prayer_activated.connect(func(_n: String) -> void: play("prayer"))
	EventBus.bank_requested.connect(func() -> void: play("bank"))
	EventBus.teleport_requested.connect(func(_p: Vector2) -> void: play("teleport"))
	# Combat: you hitting an enemy vs. taking a hit (defend), and misses.
	EventBus.combat_hit_splat.connect(func(_amt: int, miss: bool, on_player: bool) -> void:
		if miss:
			play("attack_miss")
		else:
			play("player_hurt" if on_player else "enemy_hit"))
	# Gather + production "hits" via the per-skill XP grant (combat skills use the hit splats above).
	EventBus.xp_gained.connect(_on_xp)
	# Per-biome MUSIC + the per-biome AMBIENCE bed (birds/waves/wind), both keyed by the biome's
	# music_tag (biomes.json). Zones can drive play_music()/set_ambient("biome", …) too.
	EventBus.biome_changed.connect(func(_b: String, music_tag: String) -> void:
		play_music(music_tag)
		set_ambient("biome", music_tag, 1.0))


func _on_xp(skill: String, _amount: float) -> void:
	match skill:
		"mining": play("mine_hit")
		"fishing": play("fish_hit")
		"foraging": play("forage_hit")
		"cooking": play("cook")
		"smithing": play("smith")
		"crafting", "fletching", "alchemy": play("craft")
		# woodcutting -> wc_log_chopped; firemaking -> firemaking_log_burned; combat -> hit splats.
