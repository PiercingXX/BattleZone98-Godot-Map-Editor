extends RefCounted
class_name DockLayout
## Snapshot / restore which panel lives in which right-column dock.
## Docks are TabContainers sharing a rearrange group; panels are their
## direct children, identified by node name.

const TITLES := {
	"HistoryPanel": "History",
	"FindingsPanel": "Findings",
	"InspectorPanel": "Object",
	"PalettePanel": "Tool",
	"WorldPanel": "World",
	"FeaturesPanel": "Features",
	"ViewPanel": "View",
	"MinimapPanel": "Minimap",
}


## dock name → {"tabs": [panel names in order], "current": int}
static func snapshot(docks: Dictionary) -> Dictionary:
	var out := {}
	for dock_name in docks:
		var dock: TabContainer = docks[dock_name]
		if dock == null:
			continue
		var tabs: Array = []
		for i in dock.get_tab_count():
			tabs.append(str(dock.get_tab_control(i).name))
		out[str(dock_name)] = {"tabs": tabs, "current": dock.current_tab}
	return out


## Move panels into the docks recorded by ``data``. Panels not mentioned
## keep their scene defaults; unknown names are ignored.
static func apply(docks: Dictionary, data: Dictionary) -> void:
	var panels := {}
	for dock_name in docks:
		var dock: TabContainer = docks[dock_name]
		if dock == null:
			continue
		for i in dock.get_tab_count():
			var c := dock.get_tab_control(i)
			panels[str(c.name)] = c
	for dock_name in data:
		if not docks.has(str(dock_name)) or docks[str(dock_name)] == null:
			continue
		var dock: TabContainer = docks[str(dock_name)]
		var rec: Variant = data[dock_name]
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var tabs: Variant = (rec as Dictionary).get("tabs", [])
		if typeof(tabs) != TYPE_ARRAY:
			continue
		var idx := 0
		for panel_name in tabs:
			var panel: Control = panels.get(str(panel_name))
			if panel == null:
				continue
			if panel.get_parent() != dock:
				panel.get_parent().remove_child(panel)
				dock.add_child(panel)
			dock.move_child(panel, idx)
			idx += 1
	for dock_name in data:
		if not docks.has(str(dock_name)) or docks[str(dock_name)] == null:
			continue
		var dock2: TabContainer = docks[str(dock_name)]
		var rec2: Variant = data[dock_name]
		if typeof(rec2) != TYPE_DICTIONARY:
			continue
		var cur := int((rec2 as Dictionary).get("current", 0))
		if dock2.get_tab_count() > 0:
			dock2.current_tab = clampi(cur, 0, dock2.get_tab_count() - 1)


static func retitle(docks: Dictionary) -> void:
	for dock_name in docks:
		var dock: TabContainer = docks[dock_name]
		if dock == null:
			continue
		for i in dock.get_tab_count():
			var n := str(dock.get_tab_control(i).name)
			dock.set_tab_title(i, str(TITLES.get(n, n)))
