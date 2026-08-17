extends RefCounted
## _parse_json_object on clean JSON, stderr prefix, empty, truncated.


func run(t) -> void:
	var clean: Dictionary = Backend._parse_json_object('{"ok": true, "n": 1}')
	t.eq(clean.get("ok"), true)
	t.eq(clean.get("n"), 1)

	var noisy: Dictionary = Backend._parse_json_object("loading assets\nwarn: skip\n{\"ok\": true, \"verb\": \"probe\"}")
	t.eq(noisy.get("ok"), true)
	t.eq(noisy.get("verb"), "probe")

	t.eq(Backend._parse_json_object(""), {})
	t.eq(Backend._parse_json_object("no json here"), {})
	t.eq(Backend._parse_json_object("{\"ok\": tru"), {}, "truncated")
	t.eq(Backend._parse_json_object("[1, 2, 3]"), {}, "array is not an object")
