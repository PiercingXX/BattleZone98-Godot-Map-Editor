extends RefCounted
## One toggle per viewport filter, mirroring the View panel's checkboxes.
## Filters are view-only — hidden objects still save — so nothing here
## touches the undo stack.

## key → caption, matching ViewPanel's display order.
const FILTERS: Array = [
	["geysers", "Geysers"],
	["scrap", "Scrap"],
	["spawns", "Spawns"],
	["buildings", "Buildings"],
	["units", "Units"],
	["props", "Props"],
	["water", "Water"],
	["plants", "Plants"],
	["sky", "Sky"],
	["labels", "Labels"],
	["ghosts", "Ghost variants"],
	["balance", "Balance overlay"],
	["aipaths", "AI paths"],
]


func command_list() -> Array:
	var out: Array = []
	for pair in FILTERS:
		out.append(_Filter.new(str(pair[0]), str(pair[1])))
	return out


class _Filter:
	extends EditorCommand

	## Overlays have nothing to draw without a map; plain category filters
	## are just Settings flags and stay usable either way.
	const NEEDS_SESSION: PackedStringArray = ["balance", "aipaths"]

	var key: String = ""

	func _init(filter_key: String = "", caption: String = "") -> void:
		key = filter_key
		id = "view.filter.%s" % filter_key
		title = "Toggle %s" % caption.to_lower()
		category = "View filters"
		description = "Show or hide %s in the viewport. View only — " \
			% caption.to_lower() + "hidden objects still save."

	func is_enabled() -> bool:
		if key in NEEDS_SESSION:
			return MapState.has_session
		return true

	func state() -> bool:
		match key:
			"labels":
				return Settings.view_labels
			"ghosts":
				return ObjectMarkers.ghost_other_variants
			"balance":
				return BalanceOverlay.enabled
			"aipaths":
				return AiPathOverlay.enabled
			_:
				return Settings.view_flag(key)

	func run(ctx) -> void:
		var on := not state()
		match key:
			"labels":
				Settings.view_labels = on
			"ghosts":
				ObjectMarkers.ghost_other_variants = on
				Settings.view_ghost_variants = on
			"balance":
				BalanceOverlay.enabled = on
				Settings.view_balance = on
			"aipaths":
				AiPathOverlay.enabled = on
				Settings.view_aipaths = on
			_:
				Settings.set_view_group(key, on)
		Settings.save()
		ctx.log_line("view %s %s" % [key, "on" if on else "off"])
		ctx.call_hook(CommandContext.HOOK_REFRESH_VIEW)
