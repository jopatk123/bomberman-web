extends Control
## Login + waiting room. Room codes live on GameState; this script only wires the UI.

const _NICK_PATH := "user://nickname.txt"
const _NICK_LS := "bomberman_nickname"

@onready var subtitle: Label = %Subtitle
@onready var login_box: VBoxContainer = %LoginBox
@onready var name_edit: LineEdit = %NameEdit
@onready var join_code_edit: LineEdit = %JoinCodeEdit
@onready var join_password_edit: LineEdit = %JoinPasswordEdit
@onready var port_edit: LineEdit = %PortEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var port_row: HBoxContainer = %PortRow
@onready var advanced_box: VBoxContainer = %AdvancedBox
@onready var advanced_btn: Button = %AdvancedBtn
@onready var web_hint: Label = %WebHint
@onready var host_btn: Button = %HostBtn
@onready var enter_btn: Button = %EnterBtn
@onready var solo_btn: Button = %SoloBtn
@onready var login_status: Label = %LoginStatus
@onready var room_box: VBoxContainer = %RoomBox
@onready var room_status: Label = %RoomStatus
@onready var room_code_label: Label = %RoomCodeLabel
@onready var room_index: Label = %RoomIndex
@onready var server_note: Label = %ServerNote
@onready var room_password_edit: LineEdit = %RoomPasswordEdit
@onready var room_access: Label = %RoomAccess
@onready var map_option: OptionButton = %MapOption
@onready var map_desc_label: Label = %MapDescLabel
@onready var seed_edit: LineEdit = %SeedEdit
@onready var player_list: VBoxContainer = %PlayerList
@onready var ready_btn: Button = %ReadyBtn
@onready var start_btn: Button = %StartBtn
@onready var leave_btn: Button = %LeaveBtn

var _web := false
var _updating_ui := false
var _ui_lock := false
var _pending_register := false
var _shown_close := false
var _register_timer: Timer


func _ready() -> void:
	_web = OS.has_feature("web")
	_setup_maps()
	_load_nickname_into_field()
	port_edit.text = str(Net.DEFAULT_PORT)
	address_edit.text = Net.get_default_join_address()
	advanced_box.visible = false
	_apply_platform_chrome()
	_connect_controls()
	_connect_net_signals()
	if not GameState.player_list_changed.is_connected(_on_room_changed):
		GameState.player_list_changed.connect(_on_room_changed)
	if not GameState.register_rejected.is_connected(_on_register_rejected):
		GameState.register_rejected.connect(_on_register_rejected)
	if not GameState.kicked.is_connected(_on_kicked):
		GameState.kicked.connect(_on_kicked)
	if not GameState.match_starting.is_connected(_on_match_starting):
		GameState.match_starting.connect(_on_match_starting)
	_enter_initial_screen()


func _enter_initial_screen() -> void:
	var notice := GameState.consume_notice()
	if Net.is_dedicated():
		if GameState.rooms.is_empty():
			_ui_lock = true
			GameState.reset_lobby()
			_ui_lock = false
		_show_room()
		return
	if Net.is_server:
		_commit_nickname()
		_ui_lock = true
		if GameState.rooms.is_empty():
			GameState.reset_lobby()
			GameState.try_register(maxi(Net.get_peer_id(), 1), GameState.local_player_name, "", "")
		_ui_lock = false
		_show_room()
		return
	_show_login(notice if not notice.is_empty() else _default_login_hint())


func _default_login_hint() -> String:
	if _web:
		return "填写昵称。房间码留空会新开一间"
	return "填写昵称。房间码留空会新开一间，或本机开房"


func _apply_platform_chrome() -> void:
	web_hint.visible = _web
	if _web:
		host_btn.visible = false
		port_row.visible = false
		web_hint.text = "将连接本站游戏服"
	else:
		host_btn.visible = true
		port_row.visible = true


func _setup_maps() -> void:
	map_option.clear()
	for id in range(int(Arena.MapId.CLASSIC), int(Arena.MapId.MAZE) + 1):
		map_option.add_item(Arena.map_name(id), id)


func _connect_controls() -> void:
	if not enter_btn.pressed.is_connected(_on_enter_pressed):
		enter_btn.pressed.connect(_on_enter_pressed)
	if not host_btn.pressed.is_connected(_on_host_pressed):
		host_btn.pressed.connect(_on_host_pressed)
	if not solo_btn.pressed.is_connected(_on_solo_pressed):
		solo_btn.pressed.connect(_on_solo_pressed)
	if not advanced_btn.pressed.is_connected(_on_advanced_pressed):
		advanced_btn.pressed.connect(_on_advanced_pressed)
	if not name_edit.text_submitted.is_connected(_on_name_submitted):
		name_edit.text_submitted.connect(_on_name_submitted)
	if not ready_btn.pressed.is_connected(_on_ready_pressed):
		ready_btn.pressed.connect(_on_ready_pressed)
	if not start_btn.pressed.is_connected(_on_start_pressed):
		start_btn.pressed.connect(_on_start_pressed)
	if not leave_btn.pressed.is_connected(_on_leave_pressed):
		leave_btn.pressed.connect(_on_leave_pressed)
	if not map_option.item_selected.is_connected(_on_map_selected):
		map_option.item_selected.connect(_on_map_selected)
	if not seed_edit.text_submitted.is_connected(_on_seed_committed):
		seed_edit.text_submitted.connect(_on_seed_committed)
	if not seed_edit.focus_exited.is_connected(_on_seed_focus_exited):
		seed_edit.focus_exited.connect(_on_seed_focus_exited)
	if not seed_edit.text_changed.is_connected(_on_seed_committed):
		seed_edit.text_changed.connect(_on_seed_committed)
	if not room_password_edit.text_submitted.is_connected(_on_room_password_committed):
		room_password_edit.text_submitted.connect(_on_room_password_committed)
	if not room_password_edit.focus_exited.is_connected(_on_room_password_focus_exited):
		room_password_edit.focus_exited.connect(_on_room_password_focus_exited)


func _connect_net_signals() -> void:
	if not Net.connected_to_server.is_connected(_on_connected):
		Net.connected_to_server.connect(_on_connected)
	if not Net.connection_failed.is_connected(_on_fail):
		Net.connection_failed.connect(_on_fail)
	if not Net.peer_disconnected.is_connected(_on_peer_out):
		Net.peer_disconnected.connect(_on_peer_out)
	if not Net.disconnected.is_connected(_on_disc):
		Net.disconnected.connect(_on_disc)


func _on_advanced_pressed() -> void:
	advanced_box.visible = not advanced_box.visible
	advanced_btn.text = "收起高级" if advanced_box.visible else "高级"


func _on_name_submitted(_text: String) -> void:
	_on_enter_pressed()


func _on_enter_pressed() -> void:
	_shown_close = false
	_commit_nickname()
	_set_login_busy(true)
	login_status.text = "正在连接…"
	var err := Net.join(address_edit.text.strip_edges())
	if err != OK:
		_set_login_busy(false)
		login_status.text = "进入失败：%s" % error_string(err)


func _on_host_pressed() -> void:
	_shown_close = false
	_commit_nickname()
	var port := int(port_edit.text)
	if port <= 0 or port > 65535:
		login_status.text = "端口无效"
		return
	var err := Net.host(port)
	if err != OK:
		login_status.text = "本机开房失败：%s" % error_string(err)
		return
	_ui_lock = true
	GameState.reset_lobby()
	GameState.try_register(maxi(Net.get_peer_id(), 1), GameState.local_player_name, join_password_edit.text, "")
	_ui_lock = false
	_show_room()


func _on_solo_pressed() -> void:
	_commit_nickname()
	Net.close()
	_ui_lock = true
	GameState.reset_lobby()
	GameState.players[1] = {
		"name": GameState.local_player_name,
		"color_idx": 0,
		"ready": true,
	}
	GameState.players[MatchBot.PEER_ID] = {
		"name": MatchBot.NAME,
		"color_idx": 1,
		"ready": true,
	}
	GameState.solo_bot = true
	GameState.host_peer_id = 1
	GameState.in_match = true
	GameState.resolve_soft_seed()
	_ui_lock = false
	_go_to_game()


func _on_connected() -> void:
	_pending_register = true
	login_status.text = "已连接，登记中…"
	_arm_register_timeout()
	GameState._rpc_register_player.rpc_id(
		1, GameState.local_player_name, join_password_edit.text.strip_edges(), join_code_edit.text
	)


func _on_fail() -> void:
	_pending_register = false
	_stop_register_timer()
	_set_login_busy(false)
	_show_login("连接失败，请检查地址或稍后再试")


func _on_disc() -> void:
	if _shown_close or _ui_lock:
		return
	if Net.is_server:
		return
	_show_closed("与服务器断开")


func _on_register_rejected(message: String) -> void:
	_show_closed(message if not message.is_empty() else "无法进入房间")


func _on_kicked(message: String) -> void:
	_show_closed(message if not message.is_empty() else "你已被请出房间")


func _show_closed(message: String) -> void:
	_pending_register = false
	_stop_register_timer()
	_shown_close = true
	_ui_lock = true
	if not Net.is_server:
		Net.close()
	GameState.reset_lobby()
	_ui_lock = false
	_set_login_busy(false)
	_show_login(message)


func _on_peer_out(id: int) -> void:
	# Match scene owns the forfeit once it is current. Lobby only drops the roster
	# while it is still the current scene (including the frame before the swap).
	if GameState.peer_in_match(id):
		return
	if Net.is_authority():
		GameState.drop_waiting_peer(id)
		return
	if room_box.visible:
		_refresh_room()


func _on_room_changed() -> void:
	if _ui_lock:
		return
	if Net.is_dedicated():
		_show_room()
		return
	if GameState.in_match and _local_in_room():
		return
	if _local_in_room():
		_pending_register = false
		_stop_register_timer()
		_show_room()
		return
	if _pending_register:
		return
	if room_box.visible:
		_show_login("已离开房间")


func _on_ready_pressed() -> void:
	var me := GameState.local_peer_id()
	if not GameState.players.has(me):
		return
	var next := not bool(GameState.players[me].get("ready", false))
	GameState.submit_ready(next)


func _on_start_pressed() -> void:
	if not GameState.is_local_host():
		return
	_push_map_settings()
	var reason := GameState.start_block_reason()
	if reason != "":
		room_status.text = "等待中 %d/%d · %s" % [GameState.players.size(), GameState.MAX_PLAYERS, reason]
		return
	GameState.request_start()


func _on_leave_pressed() -> void:
	_pending_register = false
	_stop_register_timer()
	_shown_close = true
	_ui_lock = true
	Net.close()
	GameState.reset_lobby()
	_ui_lock = false
	_set_login_busy(false)
	_show_login("已离开房间")


func _on_map_selected(_index: int) -> void:
	_push_map_settings()


func _on_seed_committed(_text: String) -> void:
	_push_map_settings()


func _on_seed_focus_exited() -> void:
	_push_map_settings()


func _on_room_password_committed(_text: String) -> void:
	_push_password()


func _on_room_password_focus_exited() -> void:
	_push_password()


func _push_map_settings() -> void:
	if _updating_ui or not GameState.is_local_host():
		return
	var idx := map_option.selected
	var next_map := map_option.get_item_id(idx) if idx >= 0 else 0
	var seed_text := seed_edit.text
	if next_map == GameState.map_id and seed_text == GameState.seed_input:
		return
	GameState.request_map_settings(next_map, seed_text)


func _push_password() -> void:
	if _updating_ui or not GameState.is_local_host():
		return
	var pw := room_password_edit.text.strip_edges()
	if pw == GameState.room_password:
		return
	GameState.request_password(pw)


func _on_match_starting() -> void:
	if Net.is_dedicated():
		_show_room()
		return
	if Net.is_online() and not GameState.players.has(Net.get_peer_id()):
		return
	if Net.is_online():
		MatchHost.open_room(GameState.room_code)
		visible = false
		return
	_go_to_game()


func _go_to_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _show_login(message: String) -> void:
	login_box.visible = true
	room_box.visible = false
	subtitle.visible = true
	subtitle.text = "房间码留空会新开一间"
	_set_login_busy(false)
	if not message.is_empty():
		login_status.text = message


func _show_room() -> void:
	login_box.visible = false
	room_box.visible = true
	subtitle.visible = false
	_refresh_room()


func _set_login_busy(busy: bool) -> void:
	enter_btn.disabled = busy
	host_btn.disabled = busy
	solo_btn.disabled = busy


func _refresh_room() -> void:
	_updating_ui = true
	var count := GameState.players.size()
	var host := GameState.is_local_host()
	var in_room := _local_in_room()
	var dedicated := Net.is_dedicated()
	var base := "等待中 %d/%d" % [count, GameState.MAX_PLAYERS]
	if GameState.room_code != "":
		room_code_label.text = "房间码 %s" % GameState.room_code
		room_code_label.visible = not dedicated
	else:
		room_code_label.text = "房间码"
		room_code_label.visible = false
	room_index.visible = dedicated
	if dedicated:
		room_index.text = GameState.room_index_text()
		count = 0
		for room in GameState.rooms.values():
			count += room.players.size()
		base = "房间 %d 间 · %d 人" % [GameState.rooms.size(), count]
	if dedicated and not in_room:
		room_status.text = "%s · 专用服务器" % base
	elif host:
		var reason := GameState.start_block_reason()
		room_status.text = base if reason.is_empty() else "%s · %s" % [base, reason]
	else:
		room_status.text = "%s · 等待房主开始" % base
	server_note.visible = dedicated
	room_access.text = "公开房" if GameState.room_password.is_empty() else "需要密码"
	var mid := Arena.clamp_map_id(GameState.map_id)
	var map_idx := map_option.get_item_index(mid)
	map_option.set_block_signals(true)
	seed_edit.set_block_signals(true)
	if map_idx >= 0 and map_option.selected != map_idx:
		map_option.select(map_idx)
	map_desc_label.text = Arena.map_desc(mid)
	map_option.disabled = not host
	seed_edit.editable = host
	if not seed_edit.has_focus() and seed_edit.text != GameState.seed_input:
		seed_edit.text = GameState.seed_input
	if host:
		room_password_edit.editable = true
		room_password_edit.placeholder_text = "空为公开房"
		if not room_password_edit.has_focus() and room_password_edit.text != GameState.room_password:
			room_password_edit.text = GameState.room_password
	else:
		room_password_edit.editable = false
		room_password_edit.text = ""
		room_password_edit.placeholder_text = "房主已设置密码" if not GameState.room_password.is_empty() else "空为公开房"
	seed_edit.set_block_signals(false)
	map_option.set_block_signals(false)
	_rebuild_players()
	ready_btn.visible = in_room
	if in_room:
		var me: Dictionary = GameState.players[GameState.local_peer_id()]
		ready_btn.text = "取消准备" if bool(me.get("ready", false)) else "准备"
	start_btn.visible = host
	start_btn.disabled = GameState.start_block_reason() != ""
	leave_btn.visible = not dedicated
	_updating_ui = false


func _rebuild_players() -> void:
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.free()
	var ids := GameState.get_sorted_peer_ids()
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "（还没有人）"
		player_list.add_child(empty)
		return
	var me := GameState.local_peer_id()
	var host := GameState.is_local_host()
	for id in ids:
		var info: Dictionary = GameState.players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = str(info.get("name", "玩家"))
		row.add_child(name_label)
		if int(id) == GameState.host_peer_id:
			var host_label := Label.new()
			host_label.text = "房主"
			host_label.modulate = Color(1, 0.85, 0.4)
			row.add_child(host_label)
		var ready_label := Label.new()
		var is_ready := bool(info.get("ready", false))
		ready_label.text = "已准备" if is_ready else "未准备"
		ready_label.modulate = Color(0.45, 0.9, 0.55) if is_ready else Color(0.7, 0.72, 0.78)
		row.add_child(ready_label)
		if host and int(id) != me:
			var kick := Button.new()
			kick.text = "请出"
			kick.pressed.connect(_on_kick_pressed.bind(int(id)))
			row.add_child(kick)
		player_list.add_child(row)


func _on_kick_pressed(peer_id: int) -> void:
	GameState.request_kick(peer_id)


func _local_in_room() -> bool:
	var id := GameState.local_peer_id()
	return id > 0 and GameState.players.has(id)


func _commit_nickname() -> void:
	var nick := name_edit.text.strip_edges()
	if nick.is_empty():
		nick = "摸鱼人"
	if nick.length() > 16:
		nick = nick.substr(0, 16)
	GameState.local_player_name = nick
	_save_nickname(nick)


func _load_nickname_into_field() -> void:
	var saved := _load_saved_nickname()
	name_edit.text = saved
	if not saved.is_empty():
		GameState.local_player_name = saved


func _load_saved_nickname() -> String:
	if _web:
		var raw = JavaScriptBridge.eval("localStorage.getItem('%s')" % _NICK_LS, true)
		if raw != null:
			var from_js := str(raw).strip_edges()
			if from_js != "" and from_js != "null" and from_js != "undefined":
				return from_js.substr(0, 16)
	if FileAccess.file_exists(_NICK_PATH):
		var file := FileAccess.open(_NICK_PATH, FileAccess.READ)
		if file:
			var text := file.get_as_text().strip_edges()
			file.close()
			return text.substr(0, 16)
	return ""


func _save_nickname(nick: String) -> void:
	if _web:
		JavaScriptBridge.eval("localStorage.setItem('%s', %s);" % [_NICK_LS, JSON.stringify(nick)], true)
	var file := FileAccess.open(_NICK_PATH, FileAccess.WRITE)
	if file:
		file.store_string(nick)
		file.close()


func _arm_register_timeout() -> void:
	if _register_timer == null:
		_register_timer = Timer.new()
		_register_timer.one_shot = true
		_register_timer.timeout.connect(_on_register_timeout)
		add_child(_register_timer)
	_register_timer.start(8.0)


func _stop_register_timer() -> void:
	if _register_timer != null:
		_register_timer.stop()


func _on_register_timeout() -> void:
	if not _pending_register:
		return
	_show_closed("服务器没有回应登记，请稍后再试")
