extends RefCounted
## _parse_json_object on clean JSON, stderr prefix, empty, truncated.


func run(t) -> void:
	var clean: Dictionary = Backend._parse_json_object('{"ok": true, "n": 1}')
	t.eq(clean.get("ok"), true)
	t.eq(clean.get("n"), 1)

	var noisy: Dictionary = Backend._parse_json_object("loading assets\nwarn: skip\n{\"ok\": true, \"verb\": \"probe\"}")
	t.eq(noisy.get("ok"), true)
	t.eq(noisy.get("verb"), "probe")

	var nested: Dictionary = Backend._parse_json_object("loading assets\n{\n  \"ok\": true,\n  \"installs\": [{\"kind\": \"game\"}]\n}")
	t.eq(nested.get("ok"), true, "noise + nested object")
	t.eq((nested.get("installs", []) as Array).size(), 1, "nested array survives")

	var braced: Dictionary = Backend._parse_json_object("progress {5 of 9}\n{\"ok\": true}")
	t.eq(braced.get("ok"), true, "noise containing balanced braces")

	var unbalanced: Dictionary = Backend._parse_json_object("stray { in noise\n{\"ok\": true}")
	t.eq(unbalanced.get("ok"), true, "noise with unbalanced brace")

	t.eq(Backend._parse_json_object(""), {})
	t.eq(Backend._parse_json_object("no json here"), {})
	t.eq(Backend._parse_json_object("{\"ok\": tru"), {}, "truncated")
	t.eq(Backend._parse_json_object("[1, 2, 3]"), {}, "array is not an object")
