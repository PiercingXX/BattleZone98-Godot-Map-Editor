extends RefCounted
## The starter command set: what ships, what gates it, what it calls.

const ViewFiltersScript = preload(
	"res://project/commands_registry/builtin/ViewFilterCommands.gd"
)


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_geysers := Settings.view_geysers
	var saved_balance := BalanceOverlay.enabled
	var saved_ghosts := ObjectMarkers.ghost_other_variants

	var reg := CommandRegistry.new()
	reg.scan(PackedStringArray([CommandRegistry.BUILTIN_DIR]))
	t.eq(reg.errors.size(), 0, "built-ins scan clean: %s" % str(reg.errors))

	var ids := reg.ids()
	for want in [
		"help.hotkeys", "map.validate",
		"select.all_terrain", "select.invert_terrain", "select.none_terrain",
		"view.frame_map", "view.map_mode", "view.top_down",
	]:
		t.ok(ids.has(want), "ships %s" % want)
	for pair in ViewFiltersScript.FILTERS:
		t.ok(ids.has("view.filter.%s" % str(pair[0])),
			"ships a toggle for the %s filter" % str(pair[0]))
	t.eq(ids.size(), 21, "21 starter commands")

	for cmd in reg.commands:
		t.ok(not str(cmd.get("title")).is_empty(), "every command is named")
		t.ok(not str(cmd.get("description")).is_empty(),
			"%s has prose" % str(cmd.get("id")))
		t.ok(not str(cmd.get("category")).is_empty(),
			"%s has a category" % str(cmd.get("id")))
		# C16: none of the starter set edits map data, so none of them may
		# claim to. A future one that does must push onto UndoStack.
		t.ok(not bool(cmd.get("mutates_map")),
			"%s does not edit the map" % str(cmd.get("id")))

	var actions: Array[String] = []
	var hits: Array[String] = []
	var lines: Array[String] = []
	var ctx := CommandContext.new()
	ctx.bind(CommandContext.HOOK_LOG, func(m: String) -> void: lines.append(m))
	ctx.bind(CommandContext.HOOK_ACTION, func(a: String) -> void:
		actions.append(a)
	)
	ctx.bind(CommandContext.HOOK_VALIDATE, func() -> void:
		hits.append("validate")
	)
	ctx.bind(CommandContext.HOOK_REFRESH_VIEW, func() -> void:
		hits.append("refresh")
	)
	for name in CommandContext.KNOWN_HOOKS:
		t.ok(ctx.has_hook(name), "coordinator can bind %s" % name)

	MapState.has_session = false
	t.ok(not CommandRegistry.is_enabled(reg.get_command("view.frame_map")),
		"frame needs a map")
	t.ok(not reg.run_command("view.frame_map", ctx), "gated off with no map")
	t.eq(actions, [] as Array[String], "nothing dispatched while gated")
	t.ok(CommandRegistry.is_enabled(reg.get_command("help.hotkeys")),
		"the hotkey list works with no map — it is how you learn the tool")
	t.ok(reg.run_command("help.hotkeys", ctx))
	t.eq(actions, [Keymap.ACTION_HELP] as Array[String])

	MapState.has_session = true
	actions.clear()
	t.ok(reg.run_command("view.frame_map", ctx))
	t.ok(reg.run_command("view.top_down", ctx))
	t.ok(reg.run_command("view.map_mode", ctx))
	t.eq(
		actions,
		[Keymap.ACTION_FRAME, Keymap.ACTION_TOP_DOWN, Keymap.ACTION_MAP_MODE]
			as Array[String],
		"view commands go through the shell action hook",
	)
	t.eq(
		CommandRegistry.shortcut_for(reg.get_command("view.frame_map")),
		Keymap.format_action(Keymap.ACTION_FRAME),
		"the palette shows the live chord, not a baked string",
	)

	t.ok(reg.run_command("map.validate", ctx))
	t.ok(hits.has("validate"), "validation runs through its own hook")

	var before_geysers := Settings.view_geysers
	t.ok(reg.run_command("view.filter.geysers", ctx))
	t.eq(Settings.view_geysers, not before_geysers, "the filter flipped")
	t.ok(hits.has("refresh"), "the shell is asked to re-apply the view")
	t.ok(reg.run_command("view.filter.geysers", ctx))
	t.eq(Settings.view_geysers, before_geysers, "and flips back")
	t.ok(reg.run_command("view.filter.ghosts", ctx))
	t.eq(ObjectMarkers.ghost_other_variants, not saved_ghosts,
		"overlay flags live outside Settings and still flip")

	MapState.has_session = false
	t.ok(not CommandRegistry.is_enabled(reg.get_command("view.filter.balance")),
		"overlays that need a map are gated")
	t.ok(CommandRegistry.is_enabled(reg.get_command("view.filter.units")),
		"plain category filters are not")
	t.ok(not CommandRegistry.is_enabled(reg.get_command("select.all_terrain")),
		"selecting terrain needs a heightfield")
	t.ok(not CommandRegistry.is_enabled(reg.get_command("select.none_terrain")),
		"deselect gates on an empty mask, not on the session")
	t.ok(MapState.selection_empty())
	lines.clear()
	t.ok(not reg.run_command("select.invert_terrain", ctx))
	t.ok(str(lines[-1]).contains("unavailable"), "and says why")

	# An unbound hook must report, not crash or half-run (C15).
	var bare := CommandContext.new()
	MapState.has_session = true
	t.ok(not bare.has_hook(CommandContext.HOOK_ACTION))
	t.ok(reg.run_command("view.frame_map", bare),
		"an unbound hook degrades to a logged line, not a crash")

	MapState.has_session = saved_session
	Settings.view_geysers = saved_geysers
	BalanceOverlay.enabled = saved_balance
	ObjectMarkers.ghost_other_variants = saved_ghosts
