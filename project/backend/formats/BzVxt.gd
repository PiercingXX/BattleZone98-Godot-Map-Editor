extends RefCounted
class_name BzVxt
## `.vxt` observer vehicle list writer (docs/01 §8). Port of `bzmap.formats.vxt`.
##
## Tab-separated text, one entry per line, blank-line separated. Written
## byte-for-byte as given so a stock block round-trips.

const STANDARD_OBSERVERS: PackedStringArray = [
	"avobserv avobserv.des\tx\tNSDF",
	"svobserv svobserv.des\tx\tCCA",
	"bvobserv bvobserv.des\tx\tBDOG",
	"cvobserv cvobserv.des\tx\tCRA",
	"observer observer.des\tx\tObserver",
]

## Entries separated by blank lines. Python `"\n\n".join(...)` — no trailing
## newline after the last line.
const STANDARD_VXT_TEXT := "avobserv avobserv.des\tx\tNSDF\n\nsvobserv svobserv.des\tx\tCCA\n\nbvobserv bvobserv.des\tx\tBDOG\n\ncvobserv cvobserv.des\tx\tCRA\n\nobserver observer.des\tx\tObserver"


static func write_vxt(path: String, text: String) -> void:
	## Write the `.vxt` observer list `text` to `path` verbatim.
	## No added or stripped line endings (Python `newline=""`).
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("%s: cannot open for write (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(text)


static func write_standard_vxt(path: String) -> String:
	## Write the full five-observer standard list to `path`.
	write_vxt(path, STANDARD_VXT_TEXT)
	return path
