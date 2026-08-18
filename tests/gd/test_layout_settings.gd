extends RefCounted
## Layout + view persistence: splits, console, focus, leftover View toggles.


func run(t) -> void:
	var snap := _snapshot()
	_round_trip(t)
	_coerce(t)
	_dict(t)
	_restore(snap)


func _round_trip(t) -> void:
	Settings.layout_split_body = 180
	Settings.layout_split_mid = -320
	Settings.layout_split_right = 390
	Settings.layout_split_upper = 210
	Settings.layout_split_lower = 90
	Settings.console_visible = true
	Settings.focus_mode = true
	Settings.collapse_palette = true
	Settings.collapse_inspector = false
	Settings.collapse_features = true
	Settings.collapse_findings = true
	Settings.collapse_history = false
	Settings.view_grid = true
	Settings.view_slope = true
	Settings.view_ghost_variants = true
	Settings.view_balance = true
	Settings.view_aipaths = true
	Settings.save()

	Settings.layout_split_body = Settings.LAYOUT_SPLIT_BODY_DEFAULT
	Settings.layout_split_mid = Settings.LAYOUT_SPLIT_MID_DEFAULT
	Settings.layout_split_right = Settings.LAYOUT_SPLIT_RIGHT_DEFAULT
	Settings.layout_split_upper = Settings.LAYOUT_SPLIT_UPPER_DEFAULT
	Settings.layout_split_lower = Settings.LAYOUT_SPLIT_LOWER_DEFAULT
	Settings.console_visible = false
	Settings.focus_mode = false
	Settings.collapse_palette = false
	Settings.collapse_features = false
	Settings.collapse_findings = false
	Settings.view_grid = false
	Settings.view_slope = false
	Settings.view_ghost_variants = false
	Settings.view_balance = false
	Settings.view_aipaths = false
	ObjectMarkers.ghost_other_variants = false
	BalanceOverlay.enabled = false
	AiPathOverlay.enabled = false

	Settings._load()
	t.eq(Settings.layout_split_body, 180, "split_body persists")
	t.eq(Settings.layout_split_mid, -320, "split_mid persists (negative ok)")
	t.eq(Settings.layout_split_right, 390)
	t.eq(Settings.layout_split_upper, 210)
	t.eq(Settings.layout_split_lower, 90)
	t.ok(Settings.console_visible, "console visibility persists")
	t.ok(Settings.focus_mode, "focus mode persists")
	t.ok(Settings.collapse_palette)
	t.ok(not Settings.collapse_inspector)
	t.ok(Settings.collapse_features)
	t.ok(Settings.collapse_findings)
	t.ok(not Settings.collapse_history)
	t.ok(Settings.view_grid)
	t.ok(Settings.view_slope)
	t.ok(Settings.view_ghost_variants)
	t.ok(Settings.view_balance)
	t.ok(Settings.view_aipaths)
	t.ok(ObjectMarkers.ghost_other_variants, "load applies ghost static")
	t.ok(BalanceOverlay.enabled, "load applies balance static")
	t.ok(AiPathOverlay.enabled, "load applies aipaths static")
	t.eq(Settings.LAYOUT_SAVE_IDLE_S, 1.0, "split-drag save waits 1s idle")


func _coerce(t) -> void:
	t.eq(Settings.coerce_split(12, 0), 12)
	t.eq(Settings.coerce_split(-280, 0), -280)
	t.eq(Settings.coerce_split(12.9, 0), 12)
	t.eq(Settings.coerce_split("44", 0), 44)
	t.eq(Settings.coerce_split("nope", 7), 7)
	t.eq(Settings.coerce_split(null, 9), 9)
	t.eq(Settings.coerce_split(INF, 3), 3)


func _dict(t) -> void:
	Settings.apply_layout_dict({
		"split_body": 111,
		"split_mid": -50,
		"console_visible": true,
		"focus_mode": false,
		"view_grid": true,
		"view_ghost_variants": false,
	})
	var d := Settings.layout_dict()
	t.eq(int(d.get("split_body")), 111)
	t.eq(int(d.get("split_mid")), -50)
	t.ok(bool(d.get("console_visible")))
	t.ok(not bool(d.get("focus_mode")))
	t.ok(bool(d.get("view_grid")))
	t.ok(not bool(d.get("view_ghost_variants")))
	t.ok(not ObjectMarkers.ghost_other_variants)


func _snapshot() -> Dictionary:
	var cfg: Variant = null
	if FileAccess.file_exists(Settings.PATH):
		cfg = FileAccess.get_file_as_string(Settings.PATH)
	return {
		"cfg": cfg,
		"layout": Settings.layout_dict(),
		"ever_had_recents": Settings.ever_had_recents,
		"ghost": ObjectMarkers.ghost_other_variants,
		"balance": BalanceOverlay.enabled,
		"aipaths": AiPathOverlay.enabled,
	}


func _restore(snap: Dictionary) -> void:
	if snap["cfg"] == null:
		if FileAccess.file_exists(Settings.PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
		Settings._cfg = ConfigFile.new()
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		if f:
			f.store_string(str(snap["cfg"]))
			f.close()
		Settings._load()
	Settings.apply_layout_dict(snap["layout"])
	Settings.ever_had_recents = bool(snap["ever_had_recents"])
	ObjectMarkers.ghost_other_variants = bool(snap["ghost"])
	BalanceOverlay.enabled = bool(snap["balance"])
	AiPathOverlay.enabled = bool(snap["aipaths"])
