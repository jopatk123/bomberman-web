extends Control
## Lobby: create/join WebSocket room, pick map/seed, start match.

@onready var name_edit: LineEdit = %NameEdit
@onready var port_edit: LineEdit = %PortEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var status_label: Label = %StatusLabel
@onready var players_label: Label = %PlayersLabel
@onready var host_btn: Button = %HostBtn
@onready var join_btn: Button = %JoinBtn
@onready var start_btn: Button = %StartBtn
@onready var solo_btn: Button = %SoloBtn
@onready var map_option: OptionButton = %MapOption
@onready var map_desc_label: Label = %MapDescLabel
@onready var seed_edit: LineEdit = %SeedEdit

var _dedicated: bool = false
var _suppress_map_signals: bool = false


func _ready() -> void:
	name_edit.text = GameState.local_player_name
	port_edit.text = str(Net.DEFAULT_PORT)
	address_edit.text = Net.get_default_join_address()
	start_btn.disabled = true
	_fill_map_options()
	_apply_map_ui_from_state()
	_connect_map_signals()
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
			_set_map_controls_editable(false)
		else:
			GameState.reset_lobby()
			GameState.register_local_as_host()
			start_btn.disabled = false
			_set_map_controls_editable(true)
		_refresh_players()
	else:
		_set_map_controls_editable(true)


func _fill_map_options() -> void:
	map_option.clear()
	for id in range(int(Arena.MapId.CLASSIC), int(Arena.MapId.MAZE) + 1):
		map_option.add_item(Arena.map_name(id), id)


func _connect_map_signals() -> void:
	if not map_option.item_selected.is_connected(_on_map_selected):
		map_option.item_selected.connect(_on_map_selected)
	if not seed_edit.text_changed.is_connected(_on_seed_changed):
		seed_edit.text_changed.connect(_on_seed_changed)


func _apply_map_ui_from_state() -> void:
	_suppress_map_signals = true
	var mid := Arena.clamp_map_id(GameState.map_id)
	var idx := map_option.get_item_index(mid)
	if idx >= 0:
		map_option.select(idx)
	else:
		map_option.select(0)
	seed_edit.text = GameState.seed_input
	map_desc_label.text = Arena.map_desc(mid)
	_suppress_map_signals = false


func _set_map_controls_editable(editable: bool) -> void:
	map_option.disabled = not editable
	seed_edit.editable = editable


func _on_map_selected(index: int) -> void:
	if _suppress_map_signals:
		return
	if not _can_edit_map():
		_apply_map_ui_from_state()
		return
	var mid := map_option.get_item_id(index)
	GameState.set_map_id(mid)
	map_desc_label.text = Arena.map_desc(mid)
	_broadcast_map_settings()


func _on_seed_changed(new_text: String) -> void:
	if _suppress_map_signals:
		return
	if not _can_edit_map():
		return
	GameState.set_seed_input(new_text)
	_broadcast_map_settings()


func _can_edit_map() -> bool:
	if _dedicated:
		return false
	if Net.is_online() and Net.is_client:
		return false
	return true


func _broadcast_map_settings() -> void:
	if not Net.is_authority():
		return
	if not Net.is_online():
		return
	_rpc_sync_map_settings.rpc(GameState.map_id, GameState.seed_input)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_map_settings(p_map_id: int, p_seed_input: String) -> void:
	GameState.map_id = Arena.clamp_map_id(p_map_id)
	GameState.seed_input = p_seed_input
	GameState.soft_seed = -1
	_apply_map_ui_from_state()
	if Net.is_client:
		_set_map_controls_editable(false)


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
	_read_map_from_ui()
	status_label.text = "房间已创建（主机也是玩家）。等待同事加入…"
	host_btn.disabled = true
	join_btn.disabled = true
	start_btn.disabled = false
	_set_map_controls_editable(true)
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
	_set_map_controls_editable(false)


func _on_solo_pressed() -> void:
	GameState.local_player_name = name_edit.text.strip_edges()
	if GameState.local_player_name.is_empty():
		GameState.local_player_name = "摸鱼人"
	Net.close()
	GameState.reset_lobby()
	GameState.players[1] = {"name": GameState.local_player_name, "color_idx": 0}
	_read_map_from_ui()
	GameState.resolve_soft_seed()
	status_label.text = "单机测试：仅 1 名玩家，无 AI。进入对局…"
	_go_to_game()


func _read_map_from_ui() -> void:
	var idx := map_option.selected
	if idx < 0:
		idx = 0
	GameState.map_id = Arena.clamp_map_id(map_option.get_item_id(idx))
	GameState.seed_input = seed_edit.text
	GameState.soft_seed = -1


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
	_read_map_from_ui()
	var mid := Arena.clamp_map_id(GameState.map_id)
	var seed := GameState.resolve_soft_seed()
	GameState.map_id = mid
	GameState.soft_seed = seed
	_rpc_start_match.rpc(GameState.players, mid, seed)


@rpc("any_peer", "reliable")
func _rpc_request_start() -> void:
	if not Net.is_authority():
		return
	if GameState.players.size() < 1:
		return
	_try_start_match()


@rpc("authority", "call_local", "reliable")
func _rpc_start_match(snapshot: Dictionary, p_map_id: int = 0, p_soft_seed: int = -1) -> void:
	GameState.players = snapshot.duplicate(true)
	GameState.map_id = Arena.clamp_map_id(p_map_id)
	if p_soft_seed >= 0:
		GameState.soft_seed = p_soft_seed
	else:
		GameState.resolve_soft_seed()
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
	_set_map_controls_editable(false)


func _on_fail() -> void:
	status_label.text = "连接失败，请检查地址/端口"
	host_btn.disabled = false
	join_btn.disabled = false
	_set_map_controls_editable(true)


func _on_disc() -> void:
	status_label.text = "与服务器断开"
	host_btn.disabled = false
	join_btn.disabled = false
	start_btn.disabled = true
	start_btn.text = "开始对局"
	GameState.reset_lobby()
	_set_map_controls_editable(true)
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
	_rpc_sync_map_settings.rpc(GameState.map_id, GameState.seed_input)
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
