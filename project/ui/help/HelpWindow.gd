extends Window


func _ready() -> void:
	close_requested.connect(hide)
	if size.y < 420:
		size.y = 420
	refresh()


func refresh() -> void:
	var text := Keymap.help_text()
	var extra := "Select  drag empty ground to box-select (marquee); Shift adds to the selection\nPaint region  select a water/plant feature then Paint region; LMB paints the mask, Alt+LMB erases\nTeam  Shift+0…7 assign the selection (inspector Team row for 0–4; SpinBox for higher)\nView  top-bar checkboxes hide categories / water / plants / sky (view only; hidden objects still save)\n"
	if text.ends_with("[/code]"):
		text = text.substr(0, text.length() - 7) + extra + "[/code]"
	else:
		text += extra
	%Body.text = text
	title = "Hotkeys  (%s)" % Keymap.scheme_label()


func popup_help() -> void:
	refresh()
	popup_centered()
