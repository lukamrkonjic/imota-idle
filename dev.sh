#!/usr/bin/env bash
# Cross-platform dev launcher for Imota (Godot 4.6) — works on macOS, Linux, and
# Git Bash on Windows. It locates the Godot 4.6 binary so you don't have to type
# the full path on every machine.
#
#   ./dev.sh run         # play the game (main scene)
#   ./dev.sh editor      # open the Godot editor on this project
#   ./dev.sh validate    # headless test suite (tools/validate.tscn)
#   ./dev.sh bake        # re-bake the finite overworld (headless, CPU-only)
#   ./dev.sh atlas       # re-bake the sprite atlas (needs a display — runs windowed)
#   ./dev.sh preview     # biome worldgen preview window
#   ./dev.sh <name> ...  # run any tools/<name>.tscn, forwarding extra args
#
# Engine lookup order: $GODOT env var -> PATH (godot4/godot) -> common install
# locations. Override anytime:  GODOT=/path/to/Godot ./dev.sh run

set -euo pipefail
cd "$(dirname "$0")"

find_godot() {
  if [[ -n "${GODOT:-}" ]]; then printf '%s\n' "$GODOT"; return; fi
  local c
  for c in godot4 godot Godot; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return; fi
  done
  local p
  for p in \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
    "/Applications/Godot_mono.app/Contents/MacOS/Godot" \
    "/c/Dev/Godot/Godot_v4.6.3-stable_win64.exe" \
    "/c/Program Files/Godot/Godot.exe"; do
    if [[ -x "$p" ]]; then printf '%s\n' "$p"; return; fi
  done
  printf '\n'
}

GODOT_BIN="$(find_godot)"
if [[ -z "$GODOT_BIN" ]]; then
  echo "ERROR: Godot 4.6 not found." >&2
  echo "  Install it, put it on your PATH, or set GODOT=/path/to/Godot" >&2
  echo "  macOS (Apple Silicon): https://godotengine.org/download/macos/ (Godot 4.6, standard build)" >&2
  exit 1
fi

cmd="${1:-run}"; shift || true
case "$cmd" in
  run)          exec "$GODOT_BIN" --path . "$@" ;;
  editor|edit)  exec "$GODOT_BIN" -e --path . "$@" ;;
  validate)     exec "$GODOT_BIN" --headless --path . res://tools/validate.tscn "$@" ;;
  bake)         exec "$GODOT_BIN" --headless --path . res://tools/world_bake.tscn "$@" ;;
  atlas)        exec "$GODOT_BIN" --path . res://tools/bake_sprites.tscn "$@" ;;
  preview)      exec "$GODOT_BIN" --path . res://tools/biome_preview.tscn "$@" ;;
  *)
    name="${cmd%.tscn}"
    if [[ -f "tools/$name.tscn" ]]; then
      exec "$GODOT_BIN" --path . "res://tools/$name.tscn" "$@"
    fi
    echo "Unknown command: $cmd" >&2
    echo "Try: run | editor | validate | bake | atlas | preview | <tools-scene-name>" >&2
    exit 1
    ;;
esac
