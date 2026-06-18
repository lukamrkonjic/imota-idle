extends Node2D
## Damage hitsplat in our pixel-art style: an irregular red splatter with the white
## damage number on a hit, or a blue splatter with "0" on a miss/block. Drawn cell
## by cell on the world's PX grid (no sprite assets). Pops in, holds, fades, frees.

const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")

const LIFETIME := 0.85
const POP := 0.10
const FADE := 0.22
const BODY_SCALE := 0.46  # the splatter blob is small; the number sits big on top

const RED := Color(0.82, 0.09, 0.07)
const RED_DARK := Color(0.50, 0.04, 0.04)
const RED_EDGE := Color(0.24, 0.02, 0.02)
const RED_HI := Color(0.95, 0.33, 0.25)
const BLUE := Color(0.15, 0.43, 0.92)
const BLUE_DARK := Color(0.07, 0.25, 0.62)
const BLUE_EDGE := Color(0.02, 0.10, 0.34)
const BLUE_HI := Color(0.58, 0.82, 1.0)

# '#' = body cell, anything else empty. Irregular splatter: spiky top, drippy base.
const SPLAT := [
	"  # # #  ",
	" ####### ",
	"#########",
	" ########",
	"#########",
	"######## ",
	" ####### ",
	"  ## # # ",
]
# Detached droplets (grid col,row; may sit beyond the silhouette rows).
const DROPLETS := [Vector2i(9, 2), Vector2i(-1, 5), Vector2i(2, 8)]

var amount: int = 0
var miss: bool = false
var anchor: Node2D = null        # the target this splat is pinned to (player/enemy)
var follow_offset := Vector2.ZERO  # local offset above the anchor's feet
var projector: Node = null       # 3D renderer; when set, project anchor -> screen px
var lift := 1.5                  # world-Y above the anchor's feet to anchor the splat (3D)
var scale_mul := 1.0             # overall draw size multiplier (bigger on the 3D overlay)

var _t := 0.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	z_index = 700
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		queue_free()
		return
	# Stay pinned to the target so the splat rides along as it moves/chases. With the
	# 3D renderer active the splat is on a screen-space overlay, so project the
	# target's body through the 3D camera; otherwise track its 2D world position.
	if is_instance_valid(anchor):
		if projector != null and projector.is_active():
			position = projector.iso_to_screen(anchor.position, lift) + follow_offset
		else:
			position = anchor.position + follow_offset
	queue_redraw()


func _draw() -> void:
	var s := 1.0
	if _t < POP:
		s = ease(_t / POP, 0.35) * 1.06
	elif _t < POP * 1.7:
		s = lerpf(1.06, 1.0, (_t - POP) / (POP * 0.7))
	var a := 1.0
	if _t > LIFETIME - FADE:
		a = clampf((LIFETIME - _t) / FADE, 0.0, 1.0)
	# Small splatter body... (scaled up by scale_mul for the big 3D overlay splats)
	var sm := s * scale_mul
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(sm * BODY_SCALE, sm * BODY_SCALE))
	_draw_splat(a)
	# ...with the damage number drawn big and bold on top, near full size.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(sm, sm))
	_draw_number(a, BLUE_EDGE if miss else RED_EDGE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_splat(a: float) -> void:
	var body := _body_cells()
	var w := 0
	for row: String in SPLAT:
		w = maxi(w, row.length())
	var h := SPLAT.size()
	var px := float(PixelPalette.PX)
	# Whole-cell offsets so every cell lands on the PX grid — a fractional centre
	# made px_rect's snap shift adjacent rows and leave a seam line.
	var ox := -float(w / 2)
	var oy := -float(h / 2)
	var base: Color = BLUE if miss else RED
	var dark: Color = BLUE_DARK if miss else RED_DARK
	var edge: Color = BLUE_EDGE if miss else RED_EDGE
	var hi: Color = BLUE_HI if miss else RED_HI

	# 1px dark outline: empty cells touching the body (8-neighbourhood).
	var outline: Dictionary = {}
	const NB := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	for cell: Vector2i in body:
		for d: Vector2i in NB:
			var n: Vector2i = cell + d
			if not body.has(n):
				outline[n] = true
	for cell: Vector2i in outline:
		_cell(cell, ox, oy, px, edge, a)

	# Body with mottled darker patches and a top-left highlight.
	for cell: Vector2i in body:
		var seed: int = absi(cell.x * 73 + cell.y * 131 + 17)
		var col := base
		if seed % 5 == 0:
			col = dark
		elif cell.x < int(float(w) * 0.45) and cell.y < int(float(h) * 0.45) and seed % 3 == 0:
			col = hi
		_cell(cell, ox, oy, px, col, a)


func _body_cells() -> Dictionary:
	var d: Dictionary = {}
	for row: int in SPLAT.size():
		var line: String = SPLAT[row]
		for col: int in line.length():
			if line[col] == "#":
				d[Vector2i(col, row)] = true
	for dr: Vector2i in DROPLETS:
		d[dr] = true
	return d


func _cell(cell: Vector2i, ox: float, oy: float, px: float, col: Color, a: float) -> void:
	PixelDraw.px_rect(self, (float(cell.x) + ox) * px, (float(cell.y) + oy) * px, px, px, col, a)


func _draw_number(a: float, outline: Color) -> void:
	var text := "0" if miss else str(amount)
	var fsize := 15
	var tw: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pos := Vector2(-tw * 0.5, fsize * 0.36)
	# Dark outline (1px, all directions) so the number reads on any backdrop.
	for o: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
			Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		draw_string(_font, pos + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(outline.r, outline.g, outline.b, a))
	# Light faux-bold: one extra offset pass so the stroke is slightly thicker.
	for o: Vector2 in [Vector2.ZERO, Vector2(0.7, 0)]:
		draw_string(_font, pos + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 1, a))
