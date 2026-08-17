extends RefCounted
class_name BzDes
## ``.des`` map description writer — free text from real counts.
##
## Port of ``backend/bzmap/formats/des.py``. GEYSERS / SCRAP must be the
## actual object counts; this module never fabricates them.

const _EOL := "\r\n"

## SIZE bands by map width (metres). Corpus majority per width (des.py).
## Python-vs-spec: F8 lists 5120 m as the maximum observed map; there is no
## "Huge" band here — 5120 is "Large" (ceiling after 3840 is +inf).
const SIZE_BANDS := [
	[2560.0, "Small"],
	[3840.0, "Medium"],
	[INF, "Large"],
]


static func write_des(
	path: String,
	mission_name: String,
	world: String,
	size: String,
	geysers: int,
	scrap: int,
	players: int,
	author: Variant = null
) -> void:
	## Write a ``.des`` description to ``path``.
	##
	## Python-vs-spec: ``mission_name`` is accepted (des.py signature) but
	## never written into the file.
	var text := write_des_text(
		mission_name, world, size, geysers, scrap, players, author
	)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("write_des failed: %s" % path)
		return
	f.store_buffer(text.to_utf8_buffer())


static func write_des_text(
	mission_name: String,
	world: String,
	size: String,
	geysers: int,
	scrap: int,
	players: int,
	author: Variant = null
) -> String:
	## Return the ``.des`` text (CRLF) that write_des would write.
	var who := "Skippy" if author == null else str(author)
	# mission_name is unused — matches des.py.
	var _unused := mission_name
	var lines := PackedStringArray([
		"WORLD: %s\tSIZE: %s" % [world, size],
		"GEYSERS: %d\tSCRAP: %d" % [geysers, scrap],
		"PLAYERS: %d" % players,
		"Made by %s" % who,
	])
	return _EOL.join(lines) + _EOL


static func size_band(width_m: float) -> String:
	## Derive the ``.des`` SIZE label from map width (metres).
	for band in SIZE_BANDS:
		if width_m <= float(band[0]):
			return str(band[1])
	return "Large"
