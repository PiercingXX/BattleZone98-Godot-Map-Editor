extends Window


func _ready() -> void:
	close_requested.connect(hide)
	if size.y < 480:
		size.y = 480
	refresh()


func refresh() -> void:
	var text := Keymap.help_text()
	var extra := "Select  drag empty ground to box-select (marquee); Shift adds to the selection. Hold M and drag LMB to measure a 3D distance (status bar + line; release logs metres).\nQuery  %s Select replaces the selection; Add unions. Batch: Set team → [spin]; Replace class… (one undo; placement_mode other than bzn asks to confirm). Copy to variant… clones the selection into another BZN variant (new ids; one undo; the player object is never copied).\nTerrain selection  Photoshop/GIMP mask at heightfield resolution (not saved). Empty mask = no selection = every cell editable. QSel (quick select) paints with the brush (LMB add, Alt+LMB subtract). RSel drag a ground rectangle (Shift add, Alt subtract, plain replace). Wand click floods contiguous cells within the height tolerance (Shift add, Alt subtract; tolerance slider is metres). Select by material selects every cell whose tile base is the active swatch. Ctrl+A select all, Ctrl+D deselect, Ctrl+Shift+I invert. Feather… box-blurs the mask by metres; Grow/Shrink expand or contract by N cells. While a selection exists, raise/lower/flatten/smooth/noise/ramp and material paint multiply their per-cell effect by mask/255. Marching-ants overlay pulses on the edge.\nClone  Ctrl+click sets the source point (GIMP). Painting copies height deltas from the source-relative region through the brush with falloff (one undo). Clone materials also copies tile words.\nSymmetry  Brush section (sculpt / paint / place): Off, Mirror X (east-west), Mirror Z (north-south), Rotate 180, Quad (4-fold; square maps only). Each stamp, ramp, or placement applies at every image point as one undo.\nPaint region  select a water/plant feature then Paint region; LMB paints the mask, Alt+LMB erases\nTeam  Shift+0…7 assign the selection (inspector Team row for 0–4; SpinBox for higher)\nCamera  Alt+1…5 recall a stored view; Ctrl+Alt+1…5 store (per session)\nHistory  right-column list under Findings; click a named undo step to jump there\nScreenshot  More → Screenshot viewport writes the 3D view to user://screenshots/\nBinary BZN  the game must re-save as ASCII (`/asciisave`); the editor copies the Steam launch command\nView  top-bar checkboxes hide categories / water / plants / sky (view only; hidden objects still save). Ghost other variants draws the inactive BZN variants as tinted, unpickable ghosts. AI Paths draws [AiPath] polylines (x,z on the heightfield) with point markers and labels; unlabeled paths are shown dim and are not editable. Select-tool: click a marker to select, drag to move (one undo). Add path / Add point / Delete on the path strip (disabled with a why-tooltip). Save rewrites [AiPaths] only when a path was edited.\nTest  persist + install to addon/, launch via Steam; polls BZLogger.txt (8 Sim Startup lines = loaded). Press again to cancel the poll (does not close the game).\n" % EditActions.OBJECT_QUERY_HELP
	if text.ends_with("[/code]"):
		text = text.substr(0, text.length() - 7) + extra + "[/code]"
	else:
		text += extra
	%Body.text = text
	title = "Hotkeys  (%s)" % Keymap.scheme_label()


func popup_help() -> void:
	refresh()
	popup_centered()
