extends Node
## Shared room snapshot: players, host, password, map, ready, in-match.
## `rooms` is every room on this process. The flat fields mirror the local player's room.
## Room RPCs live here so they still resolve after a match node exists.
## Match simulation does not belong in this autoload.

signal player_list_changed
signal match_starting
signal map_settings_changed
signal register_rejected(message: String)
signal kicked(message: String)
signal lobby_directory_changed

const MAX_PLAYERS := 4
const MSG_FULL := "房间已满（最多 4 人）"
const MSG_IN_MATCH := "对局中，请稍后再来"
const MSG_BAD_PASSWORD := "房间密码不正确"
const MSG_NEED_PLAYERS := "至少 2 人才能开始"
const MSG_NEED_READY := "全员准备后才能开始"
const MSG_NO_ROOM := "没有这个房间"
const MSG_BAD_CODE := "房间码是 4 位"
const MSG_TOO_MANY := "服务器房间已满，稍后再开"
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
var map_id: int = Arena.MAP_RANDOM
## Resolved soft-wall seed used for the current / next match. -1 = not resolved yet.
var soft_seed: int = -1
## Raw lobby seed field (empty or non-int ⇒ random at resolve).
var seed_input: String = ""
## Shown once on the next lobby screen (disconnect, kick, leave). Survives reset_lobby().
var pending_notice: String = ""
## Offline "单机试试". Bots themselves are created at match start by MatchFill, online or not.
var solo_bot: bool = false
## code -> room dictionary. Authority keeps every room; a client only mirrors `room_code`.
var rooms: Dictionary = {}
## peer_id -> room code. Authority only.
var peer_room: Dictionary = {}
## Room this peer is sitting in. Empty on a dedicated server and before register.
var room_code: String = ""
## Public lobby catalog for the login browser (no passwords). Clients mirror from authority.
var lobby_directory: Array = []


func _ready() -> void:
	if not Net.peer_connected.is_connected(_on_net_peer_connected):
		Net.peer_connected.connect(_on_net_peer_connected)


func _on_net_peer_connected(peer_id: int) -> void:
	if Net.is_authority():
		push_lobby_directory_to(peer_id)


func reset_lobby() -> void:
	players.clear()
	rooms.clear()
	peer_room.clear()
	room_code = ""
	in_match = false
	host_peer_id = 0
	room_password = ""
	solo_bot = false
	lobby_directory.clear()
	# Keep map_id / seed_input as lobby preferences across disconnects.
	soft_seed = -1
	player_list_changed.emit()
	lobby_directory_changed.emit()


func consume_notice() -> String:
	var message := pending_notice
	pending_notice = ""
	return message


func register_local_as_host() -> void:
	var id := local_peer_id()
	if id <= 0:
		id = 1
	if peer_room.has(id):
		_mirror(str(peer_room[id]))
		return
	try_register(id, local_player_name, room_password, "")


func local_peer_id() -> int:
	if not Net.is_online():
		return 0
	return Net.get_peer_id()


func recompute_host() -> void:
	var ids := get_sorted_peer_ids()
	host_peer_id = int(ids[0]) if not ids.is_empty() else 0
	if room_code != "" and rooms.has(room_code):
		rooms[room_code].host_peer_id = host_peer_id


func get_sorted_peer_ids() -> Array:
	return _sorted_ids(players)


func color_for_peer(peer_id: int) -> Color:
	if not players.has(peer_id):
		return Color.WHITE
	var idx: int = int(players[peer_id].get("color_idx", 0)) % PLAYER_COLORS.size()
	return PLAYER_COLORS[idx]


## Authority: turn seed_input / pending soft_seed into a concrete non-negative int.
func resolve_soft_seed() -> int:
	if room_code != "" and rooms.has(room_code):
		return resolve_room_seed(room_code)
	if soft_seed >= 0:
		return soft_seed
	var t := seed_input.strip_edges()
	if t.is_empty() or not t.is_valid_int():
		soft_seed = randi() & 0x7fffffff
	else:
		soft_seed = int(t)
	return soft_seed


func resolve_room_seed(code: String) -> int:
	if not rooms.has(code):
		return soft_seed if soft_seed >= 0 else 0
	var room: Dictionary = rooms[code]
	var current := int(room.get("soft_seed", -1))
	if current >= 0:
		if code == room_code:
			soft_seed = current
		return current
	var t := str(room.get("seed_input", "")).strip_edges()
	var resolved: int
	if t.is_empty() or not t.is_valid_int():
		resolved = randi() & 0x7fffffff
	else:
		resolved = int(t)
	room.soft_seed = resolved
	if code == room_code:
		soft_seed = resolved
	return resolved


func set_map_id(id: int) -> void:
	map_id = Arena.lobby_map_id(id)
	if room_code != "" and rooms.has(room_code):
		rooms[room_code].map_id = map_id
	map_settings_changed.emit()


func set_seed_input(text: String) -> void:
	seed_input = text
	soft_seed = -1
	if room_code != "" and rooms.has(room_code):
		rooms[room_code].seed_input = text
		rooms[room_code].soft_seed = -1
	map_settings_changed.emit()


func is_local_host() -> bool:
	if Net.is_dedicated():
		return false
	var id := local_peer_id()
	return id > 0 and id == host_peer_id


func start_block_reason() -> String:
	if room_code != "" and rooms.has(room_code):
		return _block_reason(rooms[room_code].players)
	return _block_reason(players)


func peer_in_match(id: int) -> bool:
	var code := str(peer_room.get(int(id), ""))
	if code == "" or not rooms.has(code):
		return false
	return bool(rooms[code].in_match)


func room_index_text() -> String:
	if rooms.is_empty():
		return "还没有房间。留空房间码就会新开一间。"
	var codes: Array = rooms.keys()
	codes.sort()
	var lines: PackedStringArray = []
	for code in codes:
		var room: Dictionary = rooms[code]
		var names: PackedStringArray = []
		for id in _sorted_ids(room.players):
			names.append(str(room.players[id].get("name", id)))
		var state := "对局中" if bool(room.in_match) else "等待中"
		var who := "、".join(names)
		lines.append("%s · %s %d/%d · %s" % [code, state, room.players.size(), MAX_PLAYERS, who])
	return "\n".join(lines)


## Empty string means the player was accepted (or was already in a room).
## An empty code opens a new room. A code joins that room.
func make_lobby_directory() -> Array:
	var out: Array = []
	var codes: Array = rooms.keys()
	codes.sort()
	for code in codes:
		var room: Dictionary = rooms[code]
		var names: Array = []
		for id in _sorted_ids(room.players):
			names.append(str(room.players[id].get("name", id)))
		out.append({
			"code": str(code),
			"count": int(room.players.size()),
			"max": MAX_PLAYERS,
			"in_match": bool(room.in_match),
			"locked": not str(room.get("room_password", "")).is_empty(),
			"who": ", ".join(names),
		})
	return out


func apply_lobby_directory(entries: Array) -> void:
	lobby_directory = entries.duplicate(true)
	lobby_directory_changed.emit()


func broadcast_lobby_directory() -> void:
	if not Net.is_authority():
		return
	var payload := make_lobby_directory()
	if not Net.is_online():
		apply_lobby_directory(payload)
		return
	for pid in multiplayer.get_peers():
		_rpc_sync_lobby_directory.rpc_id(int(pid), payload)
	apply_lobby_directory(payload)


func push_lobby_directory_to(peer_id: int) -> void:
	if not Net.is_authority() or peer_id <= 0:
		return
	if not Net.is_online():
		apply_lobby_directory(make_lobby_directory())
		return
	_rpc_sync_lobby_directory.rpc_id(peer_id, make_lobby_directory())


func request_lobby_directory() -> void:
	if Net.is_online() and Net.is_client:
		_rpc_request_lobby_directory.rpc_id(1)
		return
	if Net.is_authority():
		apply_lobby_directory(make_lobby_directory())



func try_register(sender: int, player_name: String, password: String, code: String = "") -> String:
	if sender <= 0:
		return MSG_BAD_PASSWORD
	if peer_room.has(sender):
		return ""
	var raw := code.strip_edges()
	var norm := RoomCodes.normalize(raw)
	if raw != "" and norm == "":
		return MSG_BAD_CODE
	var created := false
	if norm == "":
		if rooms.size() >= RoomCodes.MAX_ROOMS:
			return MSG_TOO_MANY
		norm = RoomCodes.allocate(rooms)
		if norm == "":
			return MSG_TOO_MANY
		rooms[norm] = RoomCodes.fresh(norm, password)
		created = true
	elif not rooms.has(norm):
		return MSG_NO_ROOM
	if not created:
		var reject := _reject_join(rooms[norm], password)
		if reject != "":
			return reject
	_seat(norm, sender, player_name)
	_mirror(norm)
	return ""


func set_player_ready(peer_id: int, is_ready: bool) -> bool:
	var roster := _roster_for_peer(peer_id)
	if not roster.has(peer_id):
		return false
	roster[peer_id]["ready"] = is_ready
	return true


func apply_password(sender: int, password: String) -> bool:
	var code := str(peer_room.get(sender, ""))
	var host := host_peer_id
	if code != "" and rooms.has(code):
		host = int(rooms[code].host_peer_id)
	if sender != host:
		return false
	var pw := password.strip_edges()
	if code != "" and rooms.has(code):
		rooms[code].room_password = pw
	if code == "" or code == room_code:
		room_password = pw
	return true


func apply_map_settings(sender: int, next_map: int, next_seed_input: String) -> bool:
	var code := str(peer_room.get(sender, ""))
	if code != "" and rooms.has(code):
		if sender != int(rooms[code].host_peer_id):
			return false
		rooms[code].map_id = Arena.lobby_map_id(next_map)
		rooms[code].seed_input = next_seed_input
		rooms[code].soft_seed = -1
		_mirror(code)
		return true
	if sender != host_peer_id:
		return false
	set_map_id(next_map)
	set_seed_input(next_seed_input)
	return true


func try_kick(requester: int, target_id: int) -> bool:
	var code := str(peer_room.get(requester, ""))
	var roster: Dictionary = players
	var host := host_peer_id
	if code != "" and rooms.has(code):
		host = int(rooms[code].host_peer_id)
		roster = rooms[code].players
	if requester != host:
		return false
	if target_id == requester or not roster.has(target_id):
		return false
	roster.erase(target_id)
	peer_room.erase(target_id)
	var new_host := _smallest(roster)
	if code != "" and rooms.has(code):
		rooms[code].host_peer_id = new_host
	if code == "" or code == room_code:
		host_peer_id = new_host
	return true


func make_snapshot() -> Dictionary:
	return snapshot_for(room_code)


func snapshot_for(code: String) -> Dictionary:
	if code != "" and rooms.has(code):
		var room: Dictionary = rooms[code]
		return {
			"room_code": code,
			"players": room.players.duplicate(true),
			"host_peer_id": int(room.host_peer_id),
			"room_password": str(room.room_password),
			"map_id": int(room.map_id),
			"seed_input": str(room.seed_input),
			"soft_seed": int(room.soft_seed),
			"in_match": bool(room.in_match),
		}
	return {
		"room_code": room_code,
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
		var code := str(snapshot.get("room_code", ""))
		var normalized := _normalize_players(snapshot["players"])
		if code != "" and rooms.has(code):
			var dest: Dictionary = rooms[code].players
			dest.clear()
			for k in normalized.keys():
				dest[k] = normalized[k]
			rooms[code].host_peer_id = int(snapshot.get("host_peer_id", rooms[code].host_peer_id))
			rooms[code].room_password = str(snapshot.get("room_password", rooms[code].room_password))
			rooms[code].map_id = Arena.lobby_map_id(int(snapshot.get("map_id", rooms[code].map_id)))
			if snapshot.has("seed_input"):
				rooms[code].seed_input = str(snapshot["seed_input"])
			if snapshot.has("soft_seed"):
				rooms[code].soft_seed = int(snapshot["soft_seed"])
			if snapshot.has("in_match"):
				rooms[code].in_match = bool(snapshot["in_match"])
			if not Net.is_dedicated():
				room_code = code
				players = dest
				host_peer_id = int(rooms[code].host_peer_id)
				room_password = str(rooms[code].room_password)
				map_id = int(rooms[code].map_id)
				seed_input = str(rooms[code].seed_input)
				soft_seed = int(rooms[code].soft_seed)
				in_match = bool(rooms[code].in_match)
		else:
			if code != "":
				room_code = code
			players = normalized
			host_peer_id = int(snapshot.get("host_peer_id", 0))
			room_password = str(snapshot.get("room_password", ""))
			map_id = Arena.lobby_map_id(int(snapshot.get("map_id", map_id)))
			if snapshot.has("seed_input"):
				seed_input = str(snapshot["seed_input"])
			if snapshot.has("soft_seed"):
				soft_seed = int(snapshot["soft_seed"])
			if snapshot.has("in_match"):
				in_match = bool(snapshot["in_match"])
			if not players.has(host_peer_id):
				recompute_host()
	else:
		# Older snapshots were the players dict itself.
		players = _normalize_players(snapshot)
		if not players.has(host_peer_id):
			recompute_host()
	if not Net.is_dedicated() and room_code != "" and rooms.has(room_code) and not players.has(host_peer_id):
		recompute_host()
	player_list_changed.emit()


func broadcast_room(code: String = "") -> void:
	if code == "":
		code = room_code
	var snap := snapshot_for(code)
	if not Net.is_online():
		apply_snapshot(snap)
		return
	if not Net.is_authority():
		return
	var me := Net.get_peer_id()
	for raw in _peer_ids_of(code):
		var pid := int(raw)
		if pid <= 0 or pid == me:
			continue
		_rpc_sync_players.rpc_id(pid, snap)
	if Net.is_dedicated():
		player_list_changed.emit()
	broadcast_lobby_directory()


func install_roster(code: String, snap: Dictionary) -> Dictionary:
	var normalized := _normalize_players(snap)
	if code != "" and rooms.has(code):
		var dest: Dictionary = rooms[code].players
		dest.clear()
		for k in normalized.keys():
			dest[k] = normalized[k]
		if not Net.is_dedicated() and (room_code == "" or room_code == code):
			players = dest
			room_code = code
		return dest
	players = normalized
	return players


func finish_forfeit(roster: Dictionary, code: String, do_broadcast: bool) -> void:
	if code != "" and rooms.has(code):
		var gone: Array = []
		for raw in peer_room.keys():
			if str(peer_room[raw]) == code and not roster.has(int(raw)):
				gone.append(int(raw))
		for pid in gone:
			peer_room.erase(pid)
		rooms[code].host_peer_id = _smallest(roster)
	if code == "" or (code == room_code and not Net.is_dedicated()):
		recompute_host()
	if do_broadcast:
		broadcast_room(code)
	elif code == "" or code == room_code or Net.is_dedicated():
		player_list_changed.emit()


func drop_waiting_peer(id: int) -> void:
	var code := str(peer_room.get(id, ""))
	if code == "" or not rooms.has(code):
		if players.has(id):
			players.erase(id)
			recompute_host()
			broadcast_room()
		return
	if bool(rooms[code].in_match):
		return
	rooms[code].players.erase(id)
	peer_room.erase(id)
	if rooms[code].players.is_empty():
		rooms.erase(code)
		if room_code == code:
			room_code = ""
			players = {}
			host_peer_id = 0
			in_match = false
			room_password = ""
		player_list_changed.emit()
		broadcast_lobby_directory()
		return
	rooms[code].host_peer_id = _smallest(rooms[code].players)
	_mirror(code)
	broadcast_room(code)


func dissolve_room(code: String) -> void:
	if code == "":
		return
	var gone: Array = []
	for raw in peer_room.keys():
		if str(peer_room[raw]) == code:
			gone.append(int(raw))
	for pid in gone:
		peer_room.erase(pid)
	rooms.erase(code)
	MatchHost.close_room(code)
	if room_code == code:
		room_code = ""
		players = {}
		host_peer_id = 0
		in_match = false
		room_password = ""
	player_list_changed.emit()
	broadcast_lobby_directory()


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
	if room_code != "" and rooms.has(room_code):
		launch_room(room_code)
		return
	if not Net.is_authority():
		return
	if start_block_reason() != "":
		return
	map_id = Arena.lobby_map_id(map_id)
	resolve_soft_seed()
	in_match = true
	_send_start(make_snapshot())


func launch_room(code: String) -> void:
	if Net.is_online() and not Net.is_authority():
		return
	if not rooms.has(code):
		return
	var room: Dictionary = rooms[code]
	if _block_reason(room.players) != "":
		return
	room.map_id = Arena.lobby_map_id(int(room.map_id))
	resolve_room_seed(code)
	room.in_match = true
	_mirror(code)
	_send_start(snapshot_for(code))


@rpc("any_peer", "reliable")
func _rpc_register_player(player_name: String, password: String, code: String = "") -> void:
	if not Net.is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	var err := try_register(sender, player_name, password, code)
	if err != "":
		# Keep the TCP session so the login browser can pick another room.
		_rpc_register_rejected.rpc_id(sender, err)
		return
	broadcast_room(str(peer_room.get(sender, "")))


@rpc("authority", "reliable")
func _rpc_register_rejected(message: String) -> void:
	register_rejected.emit(message)


@rpc("authority", "reliable")
func _rpc_sync_lobby_directory(entries: Array) -> void:
	apply_lobby_directory(entries)


@rpc("any_peer", "reliable")
func _rpc_request_lobby_directory() -> void:
	if not Net.is_authority():
		return
	push_lobby_directory_to(multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func _rpc_set_ready(is_ready: bool) -> void:
	if not Net.is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if set_player_ready(sender, is_ready):
		broadcast_room(str(peer_room.get(sender, "")))


@rpc("any_peer", "reliable")
func _rpc_set_password(password: String) -> void:
	if not Net.is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if apply_password(sender, password):
		broadcast_room(str(peer_room.get(sender, "")))


@rpc("any_peer", "reliable")
func _rpc_sync_map_settings(next_map: int, next_seed_input: String) -> void:
	if not Net.is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if apply_map_settings(sender, next_map, next_seed_input):
		broadcast_room(str(peer_room.get(sender, "")))


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


@rpc("authority", "reliable")
func _rpc_sync_players(snapshot: Dictionary) -> void:
	if Net.is_dedicated():
		return
	apply_snapshot(snapshot)


@rpc("authority", "reliable")
func _rpc_start_match(snapshot: Dictionary) -> void:
	var code := str(snapshot.get("room_code", ""))
	if Net.is_dedicated():
		if code != "" and rooms.has(code):
			rooms[code].in_match = true
		MatchHost.open_room(code)
		player_list_changed.emit()
		return
	apply_snapshot(snapshot)
	in_match = true
	if code != "":
		MatchHost.open_room(code)
	match_starting.emit()


func _start_as(sender: int) -> void:
	if Net.is_online() and not Net.is_authority():
		return
	var code := str(peer_room.get(sender, ""))
	if code != "" and rooms.has(code):
		if sender != int(rooms[code].host_peer_id):
			return
		launch_room(code)
		return
	if sender != host_peer_id:
		return
	launch_match()


func _kick_as(requester: int, target_id: int) -> void:
	var code := str(peer_room.get(requester, ""))
	if not try_kick(requester, target_id):
		return
	if Net.is_online() and Net.is_authority():
		_rpc_kicked.rpc_id(target_id, "你已被请出房间")
		if code != "" and rooms.has(code):
			broadcast_room(code)
		else:
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


func _send_start(snap: Dictionary) -> void:
	var code := str(snap.get("room_code", ""))
	if Net.is_online():
		var me := Net.get_peer_id()
		for raw in _peer_ids_of(code):
			var pid := int(raw)
			if pid <= 0 or pid == me:
				continue
			_rpc_start_match.rpc_id(pid, snap)
	_rpc_start_match(snap)


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


func _sorted_ids(roster: Dictionary) -> Array:
	var ids: Array = []
	for k in roster.keys():
		ids.append(int(k))
	ids.sort()
	return ids


func _smallest(roster: Dictionary) -> int:
	var ids := _sorted_ids(roster)
	return int(ids[0]) if not ids.is_empty() else 0


func _peer_ids_of(code: String) -> Array:
	if code != "" and rooms.has(code):
		return _sorted_ids(rooms[code].players)
	return get_sorted_peer_ids()


func _roster_for_peer(peer_id: int) -> Dictionary:
	var code := str(peer_room.get(peer_id, ""))
	if code != "" and rooms.has(code):
		return rooms[code].players
	return players


func _block_reason(roster: Dictionary) -> String:
	if roster.size() < 2:
		return MSG_NEED_PLAYERS
	for id in _sorted_ids(roster):
		if not bool(roster[id].get("ready", false)):
			return MSG_NEED_READY
	return ""


func _reject_join(room: Dictionary, password: String) -> String:
	if bool(room.get("in_match", false)):
		return MSG_IN_MATCH
	var expected := str(room.get("room_password", ""))
	var given := password.strip_edges()
	if expected != "" and given != expected:
		return MSG_BAD_PASSWORD
	if room.players.size() >= MAX_PLAYERS:
		return MSG_FULL
	return ""


func _seat(code: String, sender: int, player_name: String) -> void:
	var room: Dictionary = rooms[code]
	var roster: Dictionary = room.players
	var nick := player_name.strip_edges()
	if nick.is_empty():
		nick = "摸鱼人"
	if nick.length() > 16:
		nick = nick.substr(0, 16)
	var used: Array = []
	for p in roster.values():
		used.append(int(p.get("color_idx", 0)))
	var color_idx := 0
	while color_idx in used and color_idx < MAX_PLAYERS:
		color_idx += 1
	roster[sender] = {
		"name": nick,
		"color_idx": color_idx % MAX_PLAYERS,
		"ready": false,
	}
	peer_room[sender] = code
	room.host_peer_id = _smallest(roster)


func _mirror(code: String) -> void:
	if code == "" or not rooms.has(code):
		player_list_changed.emit()
		return
	if Net.is_dedicated():
		player_list_changed.emit()
		return
	if Net.is_online() and room_code != "" and code != room_code:
		return
	var room: Dictionary = rooms[code]
	room_code = code
	players = room.players
	host_peer_id = int(room.host_peer_id)
	room_password = str(room.room_password)
	map_id = int(room.map_id)
	seed_input = str(room.seed_input)
	soft_seed = int(room.soft_seed)
	in_match = bool(room.in_match)
	player_list_changed.emit()
