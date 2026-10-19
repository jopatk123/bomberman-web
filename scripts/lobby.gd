extends Control
## Lobby: create/join WebSocket room, start match.

@onready var name_edit: LineEdit = %NameEdit
@onready var port_edit: LineEdit = %PortEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var status_label: Label = %StatusLabel
@onready var players_label: Label = %PlayersLabel
@onready var host_btn: Button = %HostBtn
@onready var join_btn: Button = %JoinBtn
@onready var start_btn: Button = %StartBtn
@onready var solo_btn: Button = %SoloBtn

var _dedicated: bool = false


func _ready() -> void:
	name_edit.text = GameState.local_player_name
	port_edit.text = str(Net.DEFAULT_PORT)
	address_edit.text = Net.get_default_join_address()
	start_btn.disabled = true
	_connect_net_signals()
	GameState.player_list_changed.connect(_refresh_players)
	_dedicated = Net.is_server and _was_cmdline_server()
	# Browser cannot host a dedicated listen-server usefully; Hangzhou runs the server.
	if OS.has_feature("web"):
		host_btn.visible = false
		port_edit.editable = false
		status_label.text = "网页版：填写昵称后加入（默认 wss://当前域名/ws）"
	if Net.is_server:
		status_label.text = "服务器已在端口 %d 监听。等待客户端…" % Net.listen_port
		host_btn.disabled = true
		join_btn.disabled = true
		solo_btn.disabled = true
		if _dedicated:
			# Dedicated: peer 1 is not a playable slot
			GameState.reset_lobby()
			start_btn.disabled = true
			status_label.text = "专用服务器模式：≥2 名客户端加入后自动开局（也可由客户端请求开始）"
		else:
			GameState.reset_lobby()
			GameState.register_local_as_host()
			start_btn.disabled = false
		_refresh_players()


func _was_cmdline_server() -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--server" or a == "--dedicated":
			return true
	return false


func _connect_net_signals() -> void:
	if not Net.connected_to_server.is_connected(_on_connected):
		Net.connected_to_server.connect(_on_connected)
	if not Net.connection_failed.is_connected(_on_fail):
		Net.connection_failed.connect(_on_fail)
	if not Net.peer_connected.is_connected(_on_peer_in):
		Net.peer_connected.connect(_on_peer_in)
	if not Net.peer_disconnected.is_connected(_on_peer_out):
		Net.peer_disconnected.connect(_on_peer_out)
	if not Net.disconnected.is_connected(_on_disc):
		Net.disconnected.connect(_on_disc)
	if not Net.server_started.is_connected(_on_server_started):
		Net.server_started.connect(_on_server_started)


func _on_host_pressed() -> void:
	GameState.local_player_name = name_edit.text.strip_edges()
	if GameState.local_player_name.is_empty():
		GameState.local_player_name = "摸鱼人"
	var port := int(port_edit.text)
	var err := Net.host(port)
	if err != OK:
		status_label.text = "创建房间失败: %s" % error_string(err)
		return
	_dedicated = false
	GameState.reset_lobby()
	GameState.register_local_as_host()
	status_label.text = "房间已创建（主机也是玩家）。等待同事加入…"
	host_btn.disabled = true
	join_btn.disabled = true
	start_btn.disabled = false
	_refresh_players()


func _on_join_pressed() -> void:
	GameState.local_player_name = name_edit.text.strip_edges()
	if GameState.local_player_name.is_empty():
		GameState.local_player_name = "摸鱼人"
	var err := Net.join(address_edit.text.strip_edges())
	if err != OK:
		status_label.text = "加入失败: %s" % error_string(err)
		return
	status_label.text = "正在连接…"
	host_btn.disabled = true
	join_btn.disabled = true


func _on_solo_pressed() -> void:
	GameState.local_player_name = name_edit.text.strip_edges()
	if GameState.local_player_name.is_empty():
		GameState.local_player_name = "摸鱼人"
	Net.close()
	GameState.reset_lobby()
	GameState.players[1] = {"name": GameState.local_player_name, "color_idx": 0}
	status_label.text = "单机测试：仅 1 名玩家，无 AI。进入对局…"
	_go_to_game()


func _on_start_pressed() -> void:
	if Net.is_client:
		_rpc_request_start.rpc_id(1)
		status_label.text = "已请求主机开始…"
		return
	if not Net.is_authority():
		status_label.text = "只有主机可以开始对局"
		return
	_try_start_match()


func _try_start_match() -> void:
	if not Net.is_authority():
		return
	var count := GameState.players.size()
	if count < 1:
		status_label.text = "至少需要 1 名玩家"
		return
	if count == 1:
		status_label.text = "仅 1 人开局（空场测试，无 AI）"
	_rpc_start_match.rpc(GameState.players)


@rpc("any_peer", "reliable")
func _rpc_request_start() -> void:
	if not Net.is_authority():
		return
	if GameState.players.size() < 1:
		return
	_try_start_match()


@rpc("authority", "call_local", "reliable")
func _rpc_start_match(snapshot: Dictionary) -> void:
	GameState.players = snapshot.duplicate(true)
	GameState.in_match = true
	GameState.match_starting.emit()
	_go_to_game()


func _go_to_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_server_started(port: int) -> void:
	status_label.text = "监听端口 %d" % port


func _on_connected() -> void:
	status_label.text = "已连接，登记中…"
	_rpc_register_player.rpc_id(1, GameState.local_player_name)
	# Client can request start when enough players
	start_btn.disabled = false
	start_btn.text = "请求开始对局"


func _on_fail() -> void:
	status_label.text = "连接失败，请检查地址/端口"
	host_btn.disabled = false
	join_btn.disabled = false


func _on_disc() -> void:
	status_label.text = "与服务器断开"
	host_btn.disabled = false
	join_btn.disabled = false
	start_btn.disabled = true
	start_btn.text = "开始对局"
	GameState.reset_lobby()
	_refresh_players()


func _on_peer_in(_id: int) -> void:
	_refresh_players()
	_update_start_enabled()
	_maybe_autostart_dedicated()


func _on_peer_out(id: int) -> void:
	if Net.is_authority() and GameState.players.has(id):
		GameState.players.erase(id)
		_rpc_sync_players.rpc(GameState.players)
	_refresh_players()
	_update_start_enabled()


@rpc("any_peer", "reliable")
func _rpc_register_player(player_name: String) -> void:
	if not Net.is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	if GameState.players.size() >= GameState.MAX_PLAYERS and not GameState.players.has(sender):
		return
	var used: Array = []
	for p in GameState.players.values():
		used.append(int(p.get("color_idx", 0)))
	var color_idx := 0
	while color_idx in used and color_idx < GameState.MAX_PLAYERS:
		color_idx += 1
	GameState.players[sender] = {
		"name": player_name if not player_name.is_empty() else ("玩家%d" % sender),
		"color_idx": color_idx % GameState.MAX_PLAYERS,
	}
	_rpc_sync_players.rpc(GameState.players)
	_update_start_enabled()
	_maybe_autostart_dedicated()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_players(snapshot: Dictionary) -> void:
	GameState.players = snapshot.duplicate(true)
	_refresh_players()
	_update_start_enabled()


func _maybe_autostart_dedicated() -> void:
	if not _dedicated or not Net.is_authority():
		return
	if GameState.in_match:
		return
	if GameState.players.size() >= 2:
		print("[Lobby] Dedicated auto-start with %d players" % GameState.players.size())
		_try_start_match()


func _update_start_enabled() -> void:
	if _dedicated:
		start_btn.disabled = true
		if GameState.players.size() >= 2:
			status_label.text = "专用服：已有 %d 人，即将自动开局…" % GameState.players.size()
		return
	if Net.is_server:
		start_btn.disabled = GameState.players.size() < 1
		if GameState.players.size() >= 2:
			status_label.text = "已有 %d 人，可以开始对局" % GameState.players.size()
	elif Net.is_client:
		start_btn.disabled = false


func _refresh_players() -> void:
	var lines: PackedStringArray = []
	for id in GameState.get_sorted_peer_ids():
		var info: Dictionary = GameState.players[id]
		lines.append("• [%d] %s" % [id, info.get("name", "?")])
	if lines.is_empty():
		players_label.text = "（暂无玩家）"
	else:
		players_label.text = "\n".join(lines)
