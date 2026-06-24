extends RefCounted
class_name JsonIO
## Shared JSON file reader — one existence check, one parse, consistent logging.
##
## Replaces the ~16 inline `JSON.parse_string(FileAccess.get_file_as_string(path))` copies that
## each guarded (or silently didn't guard) differently. Use read_dict/read_array for the typed
## common cases, read_variant when a file may legitimately hold either.
##
## A missing file is SILENT by default (returns the empty fallback); pass `required = true` for
## canonical data that must exist, to get a pushed error. Malformed JSON always warns.

## Parse a JSON file expected to hold an object. Returns {} (or `fallback`) on any failure.
static func read_dict(path: String, required := false, fallback: Dictionary = {}) -> Dictionary:
	var v: Variant = read_variant(path, required)
	return v if v is Dictionary else fallback


## Parse a JSON file expected to hold an array. Returns [] (or `fallback`) on any failure.
static func read_array(path: String, required := false, fallback: Array = []) -> Array:
	var v: Variant = read_variant(path, required)
	return v if v is Array else fallback


## Raw parse — returns the parsed Variant, or null if the file is missing/unreadable/malformed.
static func read_variant(path: String, required := false) -> Variant:
	if not FileAccess.file_exists(path):
		if required:
			push_error("JsonIO: required file missing: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_warning("JsonIO: malformed/empty JSON: %s" % path)
	return parsed
