extends Node
## Shared lobby / match state (names, ready, in-match).

signal player_list_changed
signal match_starting

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


func reset_lobby() -> void:
	players.clear()
	in_match = false
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
