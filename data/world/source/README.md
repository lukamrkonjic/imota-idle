# World source art (importer input only)

Drop the **refined Aldreth outline map** here as:

```
data/world/source/aldreth_atlas.png
```

This is the *illustration* — it is read **only** by the offline importer
(`tools/world_trace.gd`), never by the runtime game or the world baker.

The importer converts it into clean, editable masks in `data/world/masks/`:

| Output | Meaning |
|---|---|
| `aldreth_land.png` | binary land/water mask — the editable source of the coastline |
| `aldreth_rivers.png` | inland-water (river/lake) layer |
| `aldreth_trace_preview.png` | review overlay — **approve this before baking** |
| `aldreth_mask.json` | mask ↔ world-chunk mapping + recommended bounds |

Run it:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/world_trace.tscn
```

After hand-editing `aldreth_land.png`, refresh the preview/meta without re-tracing:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/world_trace.tscn -- --from-mask
```
