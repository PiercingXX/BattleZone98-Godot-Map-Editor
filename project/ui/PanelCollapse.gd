extends RefCounted
class_name PanelCollapse
## Shared header-toggle copy for collapsible editor panels.


static func header_text(title: String, expanded: bool) -> String:
	return "%s ▾" % title if expanded else "%s ▸" % title


static func apply_toggle(btn: Button, title: String, expanded: bool) -> void:
	if btn == null:
		return
	btn.toggle_mode = true
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.set_pressed_no_signal(expanded)
	btn.text = header_text(title, expanded)
	btn.tooltip_text = "Collapse panel" if expanded else "Expand panel"


static func make_toggle(title: String, expanded: bool = true) -> Button:
	var b := Button.new()
	b.name = "Collapse"
	apply_toggle(b, title, expanded)
	return b
