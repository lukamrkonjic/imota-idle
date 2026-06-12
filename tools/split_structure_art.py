import os
import re

# Recover source from back-compat stub's parent if needed; prefer archived copy.
SRC_CANDIDATES = [
	r"C:\Dev\bloobs-godot\tools\_iso_sprites_source.gd",
	r"C:\Dev\bloobs-godot\scripts\world\iso_sprites.gd",
]
OUT = r"C:\Dev\bloobs-godot\scripts\world\art\structures"

FUNCS = [
	("tent_art", "draw_tent", "TentArt"),
	("campfire_art", "draw_campfire", "CampfireArt"),
	("lantern_art", "draw_lantern", "LanternArt"),
	("sign_art", "draw_sign", "SignArt"),
	("chest_art", "draw_chest", "ChestArt"),
	("anvil_art", "draw_anvil", "AnvilArt"),
	("altar_art", "draw_altar", "AltarArt"),
	("obelisk_art", "draw_obelisk", "ObeliskArt"),
	("cave_mouth_art", "draw_cave_mouth", "CaveMouthArt"),
	("ladder_art", "draw_ladder", "LadderArt"),
	("stall_art", "draw_stall", "StallArt"),
	("meteor_art", "draw_meteor", "MeteorArt"),
	("mammoth_art", "draw_mammoth", "MammothArt"),
]

HEADER = """extends RefCounted
class_name {cls}

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


"""


def load_src() -> str:
	for path in SRC_CANDIDATES:
		if os.path.isfile(path):
			text = open(path, encoding="utf-8").read()
			if "static func draw_tent" in text and "var w := PixelPalette.snap(size)" in text:
				return text
	raise SystemExit("missing iso_sprites source with structure implementations")


def extract_func(lines: list[str], name: str) -> list[str]:
	start = None
	for i, line in enumerate(lines):
		if line.startswith(f"static func {name}("):
			start = i
			break
	if start is None:
		raise SystemExit(f"missing {name}")
	out = [lines[start]]
	for i in range(start + 1, len(lines)):
		line = lines[i]
		if line.startswith("static func ") and not line.startswith(" "):
			break
		if line.startswith("# ") and "----" in line:
			break
		out.append(line)
	return out


def main() -> None:
	src = load_src()
	lines = src.splitlines()
	os.makedirs(OUT, exist_ok=True)
	for fname, fn, cls in FUNCS:
		body_lines = extract_func(lines, fn)
		body_lines[0] = body_lines[0].replace(f"static func {fn}", "static func draw", 1)
		path = os.path.join(OUT, fname + ".gd")
		open(path, "w", encoding="utf-8").write(HEADER.format(cls=cls) + "\n".join(body_lines) + "\n")
		print("wrote", fname, "lines", len(body_lines))


if __name__ == "__main__":
	main()
