extends RefCounted
## Camera framing and the 2D/3D switch, as palette entries.


func command_list() -> Array:
	return [
		ShellActionCommand.new(
			Keymap.ACTION_FRAME,
			"view.frame_map",
			"Frame map",
			"View",
			"Pull the camera back until the whole map is in shot.",
		),
		ShellActionCommand.new(
			Keymap.ACTION_TOP_DOWN,
			"view.top_down",
			"Top-down view",
			"View",
			"Look straight down at the map, keeping the 3D camera.",
		),
		ShellActionCommand.new(
			Keymap.ACTION_MAP_MODE,
			"view.map_mode",
			"Toggle 2D map mode",
			"View",
			"Swap between the orthographic north-up 2D map and 3D.",
		),
	]
