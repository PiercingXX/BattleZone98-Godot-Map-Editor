extends Window


func _ready() -> void:
	close_requested.connect(hide)
	if size.y < 400:
		size.y = 400
	%Body.text = """[code]RMB look     mouse wheel zoom     MMB orbit
WASD fly     Q/E up down     Shift fast     Ctrl slow
F frame map     Space top-down     H slope tint     V walk-the-surface
G grid     Delete remove selected
1 fly   2 raise   3 lower   4 flatten   5 smooth   6 ramp
7 paint   8 place   9 select   0 noise
Select: arrows nudge 1 m (Shift 5 m)     R rotate +15° (Shift+R +90°)
[ ] radius     Shift+[ ] strength     Esc fly
Ctrl+Z undo     Ctrl+Shift+Z redo     Ctrl+S save     ` log     F1 this
LMB sculpt / place / select     Shift+click keep placing
Alt+LMB eyedropper (paint)
Autosave     every 30s while unsaved (a crash does not lose the session; Ctrl+S writes the map files)[/code]"""


func popup_help() -> void:
	popup_centered()
