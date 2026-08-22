extends RefCounted
class_name BzAct
## `.act` palette writer (F6 §3): 256 RGB triplets, 768 bytes, no header.
##
## Redux takes the map's fog colour from the palette the `.trn`'s
## `[Color] Palette` names — there is no `FogColor` key anywhere in the `.trn`.
## Changing fog colour therefore means shipping the map its own `.act`.
##
## The palette is not ours to invent: every indexed `.map` texture on the map
## resolves through it (F6 §4), so a generated ramp would recolour the world.
## `with_fog` copies a real palette and overwrites one entry.

const SIZE := 768
const ENTRIES := 256

## Which entry the engine reads as fog. Recorded here rather than inlined so
## the day it turns out to be a different index it is a one-line change.
const FOG_INDEX := 0


static func read(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return BzErrors.err(
			"io", "%s: cannot read" % path, error_string(FileAccess.get_open_error()), path
		)
	if bytes.size() != SIZE:
		return BzErrors.err(
			"bad_act",
			"%s: .act must be %d bytes, got %d" % [path, SIZE, bytes.size()],
			"An .act palette is 256 RGB triplets and nothing else.",
			path
		)
	return {"ok": true, "palette": bytes}


static func write(path: String, palette: PackedByteArray) -> Dictionary:
	if palette.size() != SIZE:
		return BzErrors.err(
			"bad_act", "refusing to write a %d-byte .act" % palette.size(), "", path
		)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return BzErrors.err(
			"write_failed", "%s: cannot write" % path,
			error_string(FileAccess.get_open_error()), path
		)
	f.store_buffer(palette)
	f.close()
	return {"ok": true}


static func with_fog(base: PackedByteArray, color: Color) -> PackedByteArray:
	## `base` with FOG_INDEX replaced. A base of the wrong size is refused by
	## returning it untouched — the caller checks the size and warns.
	if base.size() != SIZE:
		return base
	var out := base.duplicate()
	var at: int = FOG_INDEX * 3
	out[at] = clampi(int(round(color.r * 255.0)), 0, 255)
	out[at + 1] = clampi(int(round(color.g * 255.0)), 0, 255)
	out[at + 2] = clampi(int(round(color.b * 255.0)), 0, 255)
	return out


static func fog_color(palette: PackedByteArray) -> Color:
	if palette.size() != SIZE:
		return Color(0.54, 0.59, 0.66)
	var at: int = FOG_INDEX * 3
	return Color8(palette[at], palette[at + 1], palette[at + 2])
