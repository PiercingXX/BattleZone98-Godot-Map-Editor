extends RefCounted
## Chrome SVG icons exist, parse, and load as textures.


func run(t) -> void:
	t.ok(EditorIcons.NAMES.size() >= 30, "full chrome icon set")
	for name in EditorIcons.NAMES:
		var path := EditorIcons.path_for(name)
		t.ok(FileAccess.file_exists(path), "%s.svg exists" % name)
		var raw := FileAccess.get_file_as_string(path)
		t.ok(raw.contains("<svg"), "%s is SVG" % name)
		t.ok(
			raw.contains('viewBox="0 0 24 24"') or raw.contains('viewBox="0 0 16'),
			"%s draws on a 24 or 16 grid" % name
		)
		t.ok(
			raw.contains('width="24"') and raw.contains('height="24"'),
			"%s renders at 24 px" % name
		)
		t.ok("#ffffff" in raw.to_lower(), "%s uses #ffffff fill" % name)
		t.ok(not raw.contains("<image"), "%s has no embedded raster" % name)
		t.ok(not raw.contains("xlink:href"), "%s has no external href" % name)
		var tex := EditorIcons.texture(name)
		t.ok(tex is Texture2D, "%s loads as Texture2D" % name)

	var fly := EditorIcons.texture("fly")
	var raise := EditorIcons.texture("raise")
	t.ok(fly != null and raise != null)
	t.ok(fly != raise, "tool icons are distinct textures")

	var btn := Button.new()
	EditorIcons.apply_button(btn, "raise", false)
	t.ok(btn.icon != null, "apply_button sets icon")
	t.eq(btn.text, "", "tool apply is icon-only")
	btn.queue_free()

	var labeled := Button.new()
	labeled.text = "Open"
	EditorIcons.apply_button(labeled, "open", true)
	t.ok(labeled.icon != null)
	t.eq(labeled.text, "Open", "file actions keep their label")
	labeled.queue_free()
