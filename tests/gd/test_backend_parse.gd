extends RefCounted
## Backend._parse_args: the CLI-style flag arrays the wrapper methods build
## must round-trip into the flags/positional form the dispatcher consumes.


func run(t) -> void:
	var open := Backend._parse_args(PackedStringArray(
		["/maps/canyon.trn", "--session", "/tmp/s1"]
	))
	t.eq((open["positional"] as Array).size(), 1, "one positional")
	t.eq(open["positional"][0], "/maps/canyon.trn")
	t.eq(open["flags"].get("session"), "/tmp/s1")

	var new_args := Backend._parse_args(PackedStringArray([
		"--stem", "mymap", "--world", "green", "--width", "2560",
		"--depth", "1280", "--session", "/tmp/s2", "--game-root", "",
		"--pack-kind", "bzp",
	]))
	var nf: Dictionary = new_args["flags"]
	t.eq(nf.get("stem"), "mymap")
	t.eq(nf.get("width"), "2560")
	t.eq(nf.get("depth"), "1280")
	t.eq(nf.get("game-root"), "", "empty value flag survives")
	t.eq(nf.get("pack-kind"), "bzp")

	var assets := Backend._parse_args(PackedStringArray(
		["--game-root", "/g", "--cache", "/c", "--refresh", "--no-convert"]
	))
	var af: Dictionary = assets["flags"]
	t.eq(af.get("refresh"), true, "boolean flag")
	t.eq(af.get("no-convert"), true, "boolean flag with no value")
	t.eq(af.get("cache"), "/c", "value flag after boolean parsing")

	var eq_form := Backend._parse_args(PackedStringArray(["--session=/tmp/s3"]))
	t.eq(eq_form["flags"].get("session"), "/tmp/s3", "--flag=value form")

	t.eq(Backend._parse_args(PackedStringArray()), {"flags": {}, "positional": []})
