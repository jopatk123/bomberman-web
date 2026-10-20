extends Node
## Shared lobby / match state (names, ready, in-match, map + soft seed).

signal player_list_changed
signal match_starting
signal map_settings_changed

const MAX_PLAYERS := 4
## Colors for up to 4 players (visual only).
const PLAYER_COLORS := [
	Color(0.2, 0.55, 1.0),
	Color(1.0, 0.35, 0.3),
	Color(0.25, 0.85, 0.4),
	Color(1.0, 0.85, 0.2),
]

## peer_id -> { "name": String, "color_idx": int }
var players: Dictionary = {}
var local_player_name: String = "摸鱼人"
var in_match: bool = false

## Lobby / match map selection (Arena.MapId).
var map_id: int = 0
## Resolved soft-wall seed used for the current / next match. -1 = not resolved yet.
var soft_seed: int = -1
## Raw lobby seed field (empty or non-int ⇒ random at resolve).
var seed_input: String = ""


func reset_lobby() -> void:
	players.clear()
	in_match = false
	# Keep map_id / seed_input as lobby preferences across disconnects.
	soft_seed = -1
	player_list_changed.emit()


func register_local_as_host() -> void:
	var id := 1
	players[id] = {
		"name": local_player_name,
		"color_idx": 0,
	}
	player_list_changed.emit()


func get_sorted_peer_ids() -> Array:
	var ids: Array = players.keys()
	ids.sort()
	return ids


func color_for_peer(peer_id: int) -> Color:
	if not players.has(peer_id):
		return Color.WHITE
	var idx: int = int(players[peer_id].get("color_idx", 0)) % PLAYER_COLORS.size()
	return PLAYER_COLORS[idx]


## Authority: turn seed_input / pending soft_seed into a concrete non-negative int.
func resolve_soft_seed() -> int:
	if soft_seed >= 0:
		return soft_seed
	var t := seed_input.strip_edges()
	if t.is_empty() or not t.is_valid_int():
		soft_seed = randi() & 0x7fffffff
	else:
		soft_seed = int(t)
	return soft_seed


func set_map_id(id: int) -> void:
	map_id = Arena.clamp_map_id(id)
	map_settings_changed.emit()


func set_seed_input(text: String) -> void:
	seed_input = text
	soft_seed = -1
	map_settings_changed.emit()
