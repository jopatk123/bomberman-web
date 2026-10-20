extends Node
## Shared room snapshot: players, host, password, map, ready, in-match.
## Room RPCs live here so they still resolve after the server enters the match scene.
## Match simulation does not belong in this autoload.

signal player_list_changed
signal match_starting
signal map_settings_changed
signal register_rejected(message: String)
signal kicked(message: String)

const MAX_PLAYERS := 4
const MSG_FULL := "房间已满（最多 4 人）"
const MSG_IN_MATCH := "对局中，请稍后再来"
const MSG_BAD_PASSWORD := "房间密码不正确"
const MSG_NEED_PLAYERS := "至少 2 人才能开始"
const MSG_NEED_READY := "全员准备后才能开始"
## Colors for up to 4 players (visual only).
const PLAYER_COLORS := [
	Color(0.2, 0.55, 1.0),
	Color(1.0, 0.35, 0.3),
	Color(0.25, 0.85, 0.4),
	Color(1.0, 0.85, 0.2),
]

## peer_id -> { "name": String, "color_idx": int, "ready": bool }
var players: Dictionary = {}
var local_player_name: String = "摸鱼人"
var in_match: bool = false
## Smallest peer id currently in `players`. Dedicated server (peer 1) is not a player.
var host_peer_id: int = 0
var room_password: String = ""
## Lobby / match map selection (Arena.MapId).
var map_id: int = 0
## Resolved soft-wall seed used for the current / next match. -1 = not resolved yet.
var soft_seed: int = -1
## Raw lobby seed field (empty or non-int ⇒ random at resolve).
var seed_input: String = ""


func reset_lobby() -> void:
	players.clear()
	in_match = false
	host_peer_id = 0
	room_password = ""
	# Keep map_id / seed_input as lobby preferences across disconnects.
	soft_seed = -1
	player_list_changed.emit()


func register_local_as_host() -> void:
	var id := local_peer_id()
	if id <= 0:
		id = 1
	var nick := local_player_name.strip_edges()
	if nick.is_empty():
		nick = "摸鱼人"
	players[id] = {
		"name": nick,
		"color_idx": 0,
		"ready": false,
	}
	recompute_host()
	player_list_changed.emit()


func local_peer_id() -> int:
	if not Net.is_online():
		return 0
	return Net.get_peer_id()


func recompute_host() -> void:
	var ids := get_sorted_peer_ids()
	host_peer_id = int(ids[0]) if not ids.is_empty() else 0


func get_sorted_peer_ids() -> Array:
	var ids: Array = []
	for k in players.keys():
		ids.append(int(k))
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


func is_local_host() -> bool:
	if Net.is_dedicated():
		return false
	var id := local_peer_id()
	return id > 0 and id == host_peer_id


func start_block_reason() -> String:
	if players.size() < 2:
		return MSG_NEED_PLAYERS
	for id in get_sorted_peer_ids():
		if not bool(players[id].get("ready", false)):
			return MSG_NEED_READY
	return ""


## Empty string means the player was accepted (or was already in the room).
func try_register(sender: int, player_name: String, password: String) -> String:
	if sender <= 0:
		return MSG_BAD_PASSWORD
	if players.has(sender):
		return ""
	if in_match:
		return MSG_IN_MATCH
	var given := password.strip_edges()
	if room_password != "" and given != room_password:
		return MSG_BAD_PASSWORD
	if players.size() >= MAX_PLAYERS:
		return MSG_FULL
	var nick := player_name.strip_edges()
	if nick.is_empty():
		nick = "摸鱼人"
	if nick.length() > 16:
		nick = nick.substr(0, 16)
	var used: Array = []
	for p in players.values():
		used.append(int(p.get("color_idx", 0)))
	var color_idx := 0
	while color_idx in used and color_idx < MAX_PLAYERS:
		color_idx += 1
	players[sender] = {
		"name": nick,
		"color_idx": color_idx % MAX_PLAYERS,
		"ready": false,
	}
	recompute_host()
	return ""


func set_player_ready(peer_id: int, is_ready: bool) -> bool:
	if not players.has(peer_id):
		return false
	players[peer_id]["ready"] = is_ready
	return true


func apply_password(sender: int, password: String) -> bool:
	if sender != host_peer_id:
		return false
	room_password = password.strip_edges()
	return true


func apply_map_settings(sender: int, next_map: int, next_seed_input: String) -> bool:
	if sender != host_peer_id:
		return false
	set_map_id(next_map)
	set_seed_input(next_seed_input)
	return true


func try_kick(requester: int, target_id: int) -> bool:
	if requester != host_peer_id:
		return false
	if target_id == requester or not players.has(target_id):
		return false
	players.erase(target_id)
	recompute_host()
	return true


func make_snapshot() -> Dictionary:
	return {
		"players": players.duplicate(true),
		"host_peer_id": host_peer_id,
		"room_password": room_password,
		"map_id": map_id,
		"seed_input": seed_input,
		"soft_seed": soft_seed,
		"in_match": in_match,
	}


func apply_snapshot(snapshot: Dictionary) -> void:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return
	if snapshot.has("players"):
		players = _normalize_players(snapshot["players"])
		host_peer_id = int(snapshot.get("host_peer_id", 0))
		room_password = str(snapshot.get("room_password", ""))
		map_id = Arena.clamp_map_id(int(snapshot.get("map_id", map_id)))
		if snapshot.has("seed_input"):
			seed_input = str(snapshot["seed_input"])
		if snapshot.has("soft_seed"):
			soft_seed = int(snapshot["soft_seed"])
		if snapshot.has("in_match"):
			in_match = bool(snapshot["in_match"])
	else:
		# Older snapshots were the players dict itself.
		players = _normalize_players(snapshot)
	if not players.has(host_peer_id):
		recompute_host()
	player_list_changed.emit()


func broadcast_room() -> void:
	var snap := make_snapshot()
	if Net.is_online():
		if Net.is_authority():
			_rpc_sync_players.rpc(snap)
		return
	apply_snapshot(snap)


func submit_ready(is_ready: bool) -> void:
	if Net.is_online() and Net.is_client:
		_rpc_set_ready.rpc_id(1, is_ready)
		return
	if set_player_ready(local_peer_id(), is_ready):
		broadcast_room()


func request_password(password: String) -> void:
	if Net.is_online() and Net.is_client:
		_rpc_set_password.rpc_id(1, password)
		return
	if apply_password(local_peer_id(), password):
		broadcast_room()


func request_map_settings(next_map: int, next_seed_input: String) -> void:
	if Net.is_online() and Net.is_client:
		_rpc_sync_map_settings.rpc_id(1, next_map, next_seed_input)
		return
	if apply_map_settings(local_peer_id(), next_map, next_seed_input):
		broadcast_room()


func request_kick(target_id: int) -> void:
	if Net.is_online() and Net.is_client:
		_rpc_kick.rpc_id(1, target_id)
		return
	_kick_as(local_peer_id(), target_id)


func request_start() -> void:
	if Net.is_online() and Net.is_client:
		_rpc_request_start.rpc_id(1)
		return
	_start_as(local_peer_id())


func launch_match() -> void:
	if not Net.is_authority():
		return
	if start_block_reason() != "":
		return
	map_id = Arena.clamp_map_id(map_id)
	resolve_soft_seed()
	in_match = true
	var snap := make_snapshot()
	if Net.is_online():
		_rpc_start_match.rpc(snap)
	else:
		_rpc_start_match(snap)


@rpc("any_peer", "reliable")
func _rpc_register_player(player_name: String, password: String) -> void:
	if not Net.is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	var err := try_register(sender, player_name, password)
	if err != "":
		_reject_and_drop(sender, err)
		return
	broadcast_room()


@rpc("authority", "reliable")
func _rpc_register_rejected(message: String) -> void:
	register_rejected.emit(message)


@rpc("any_peer", "reliable")
func _rpc_set_ready(is_ready: bool) -> void:
	if not Net.is_authority():
		return
	if set_player_ready(multiplayer.get_remote_sender_id(), is_ready):
		broadcast_room()


@rpc("any_peer", "reliable")
func _rpc_set_password(password: String) -> void:
	if not Net.is_authority():
		return
	if apply_password(multiplayer.get_remote_sender_id(), password):
		broadcast_room()


@rpc("any_peer", "reliable")
func _rpc_sync_map_settings(next_map: int, next_seed_input: String) -> void:
	if not Net.is_authority():
		return
	if apply_map_settings(multiplayer.get_remote_sender_id(), next_map, next_seed_input):
		broadcast_room()


@rpc("any_peer", "reliable")
func _rpc_kick(target_id: int) -> void:
	if not Net.is_authority():
		return
	_kick_as(multiplayer.get_remote_sender_id(), int(target_id))


@rpc("authority", "reliable")
func _rpc_kicked(message: String) -> void:
	kicked.emit(message)


@rpc("any_peer", "reliable")
func _rpc_request_start() -> void:
	if not Net.is_authority():
		return
	_start_as(multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _rpc_sync_players(snapshot: Dictionary) -> void:
	apply_snapshot(snapshot)


@rpc("authority", "call_local", "reliable")
func _rpc_start_match(snapshot: Dictionary) -> void:
	apply_snapshot(snapshot)
	in_match = true
	match_starting.emit()


func _start_as(sender: int) -> void:
	if not Net.is_authority():
		return
	if sender != host_peer_id:
		return
	launch_match()


func _kick_as(requester: int, target_id: int) -> void:
	if not try_kick(requester, target_id):
		return
	if Net.is_online() and Net.is_authority():
		_rpc_kicked.rpc_id(target_id, "你已被请出房间")
		broadcast_room()
		_drop_peer_soon(target_id)
	else:
		player_list_changed.emit()


func _reject_and_drop(peer_id: int, message: String) -> void:
	if Net.is_online() and Net.is_authority():
		_rpc_register_rejected.rpc_id(peer_id, message)
		_drop_peer_soon(peer_id)


func _drop_peer_soon(peer_id: int) -> void:
	var tree := get_tree()
	if tree == null:
		Net.disconnect_peer(peer_id)
		return
	var timer := tree.create_timer(0.4)
	timer.timeout.connect(func() -> void:
		Net.disconnect_peer(peer_id)
	)


func _normalize_players(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in raw.keys():
		var entry = raw[k]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id := int(k)
		if id <= 0:
			continue
		var nick := str(entry.get("name", "玩家%d" % id)).strip_edges()
		if nick.is_empty():
			nick = "摸鱼人"
		out[id] = {
			"name": nick,
			"color_idx": int(entry.get("color_idx", 0)) % MAX_PLAYERS,
			"ready": bool(entry.get("ready", false)),
		}
	return out
