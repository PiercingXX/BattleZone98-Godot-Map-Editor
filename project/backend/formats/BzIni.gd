extends RefCounted
class_name BzIni
## ``.ini`` workshop + multiplayer metadata writer.
##
## Port of ``backend/bzmap/formats/ini.py``. Write-only; values are quoted
## to match the corpus. Defaults: ``gameType = K``, ``maxPlayers = 14``.

const _EOL := "\r\n"


static func write_ini(
	path: String,
	mission_name: String,
	map_type: String = "multiplayer",
	customtags: String = "",
	min_players: int = 1,
	max_players: int = 14,
	game_type: String = "K"
) -> void:
	## Write a ``.ini`` metadata file to ``path``.
	var tags := 'customtags = "%s"' % customtags
	var text := (
		"[DESCRIPTION]" + _EOL
		+ 'missionName = "%s"' % mission_name + _EOL
		+ _EOL
		+ "[WORKSHOP]" + _EOL
		+ ';mapType = "instant_action"' + _EOL
		+ 'mapType = "%s"' % map_type + _EOL
		+ tags + _EOL
		+ _EOL
		+ "[MULTIPLAYER]" + _EOL
		+ 'minPlayers = "%s"' % str(min_players) + _EOL
		+ 'maxPlayers = "%s"' % str(max_players) + _EOL
		+ 'gameType = "%s"' % game_type + _EOL
	)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("write_ini failed: %s" % path)
		return
	f.store_buffer(text.to_utf8_buffer())
