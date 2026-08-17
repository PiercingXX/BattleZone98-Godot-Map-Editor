extends Window


func _ready() -> void:
	close_requested.connect(hide)
	%Body.text = """[code]RMB look     mouse wheel zoom     MMB orbit
WASD fly     Q/E up down     Shift fast     Ctrl slow
F frame map     Space top-down     H slope tint     V walk-the-surface
1 fly   2 raise   3 lower   4 flatten   5 smooth   6 ramp
7 paint   8 place   9 select   0 noise
[ ] radius     Shift+[ ] strength     Esc fly
Ctrl+Z undo     Ctrl+Shift+Z redo     Ctrl+S save     ` log     F1 this
LMB sculpt / place / select     Shift+click keep placing[/code]"""


func popup_help() -> void:
	popup_centered()
