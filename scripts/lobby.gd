extends Control
## 登录和等待房间。连上之后浏览已有房间；房间状态归 GameState。

const _NICK_PATH := "user://nickname.txt"
const _NICK_LS := "bomberman_nickname"
## 浏览房间列表时自动刷新的间隔（秒）。
const DIRECTORY_REFRESH_SEC := 5.0
## 大厅倾斜木板最多展示的房间行数。
const ROOM_LIST_MAX := 3
## 第一次进来或输入框为空时的默认昵称：形容词 + 名词 + 两位数字（不超过 16 字）。
const _NICK_ADJ: PackedStringArray = [
	"摸鱼", "划水", "咸鱼", "躺平", "摆烂", "潜水", "挂机", "佛系", "偷懒", "摸虾",
]
const _NICK_NOUN: PackedStringArray = [
	"炸弹", "土豆", "青蛙", "企鹅", "仓鼠", "猫咪", "鸭鸭", "熊猫",
	"幽灵", "矿工", "水手", "队长", "骑士", "狐狸", "狗子", "西瓜",
]

@onready var subtitle: Label = %Subtitle
@onready var login_box: VBoxContainer = %LoginBox
@onready var name_edit: LineEdit = %NameEdit
@onready var join_code_edit: LineEdit = %JoinCodeEdit
@onready var join_password_edit: LineEdit = %JoinPasswordEdit
@onready var room_list_label: Label = %RoomListLabel
@onready var room_list_scroll: ScrollContainer = %RoomListScroll
@onready var room_list: VBoxContainer = %RoomList
@onready var room_board: Control = %RoomBoard
@onready var buttons_tilt: Control = %ButtonsTilt
@onready var create_room_btn: Button = %CreateRoomBtn
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
@onready var music_toggle: CheckBox = %MusicToggle
@onready var sfx_toggle: CheckBox = %SfxToggle
@onready var more_btn: Button = %MoreBtn
@onready var secondary_box: VBoxContainer = %SecondaryBox

const _STATUS_OK := Color(0.18, 0.55, 0.22, 1)
const _STATUS_BAD := Color(0.75, 0.18, 0.12, 1)
const _STATUS_IDLE := Color(0.4, 0.32, 0.22, 1)

var _web := false
var _updating_ui := false
var _ui_lock := false
var _pending_register := false
var _shown_close := false
var _register_timer: Timer
var _browsing := false
var _selected_room_code := ""
var _dir_timer: Timer
var _centering := false


func _set_login_status(message: String) -> void:
	login_status.text = message
	var bad := _message_is_error(message)
	var color := _STATUS_IDLE
	if bad:
		color = _STATUS_BAD
	elif message.find("已连接") >= 0 or message.find("已刷新") >= 0:
		color = _STATUS_OK
	login_status.add_theme_color_override("font_color", color)


func _message_is_error(message: String) -> bool:
	for piece in ["失败", "无效", "断开", "无法", "错误", "不正确", "没有", "已满", "请出", "拒绝", "稍后再", "对局中"]:
		if message.find(piece) >= 0:
			return true
	return false


func _center_panel() -> void:
	if _centering:
		return
	var panel := get_node_or_null("Center/Panel") as Control
	if panel == null:
		return
	var host := panel.get_parent() as Control
	if host == null:
		return
	_centering = true
	var min_size := panel.get_combined_minimum_size()
	var w := int(ceil(min_size.x))
	var h := int(ceil(min_size.y))
	if w % 2 == 1:
		w += 1
	if h % 2 == 1:
		h += 1
	# 面板略偏下，给后方立绘留空；水平略左偏抵消木板逆时针倾斜。
	var x := int((int(host.size.x) - w) / 2) - 12
	var y := int((int(host.size.y) - h) * 0.58)
	y = maxi(y, int(host.size.y * 0.34))
	if y + h > int(host.size.y) - 8:
		y = maxi(8, int(host.size.y) - h - 8)
	panel.position = Vector2(x, y)
	panel.size = Vector2(w, h)
	_refresh_tilt_pivots()
	_centering = false


func _play_panel_intro() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var panel := get_node_or_null("Center/Panel") as CanvasItem
	if panel == null:
		return
	panel.modulate.a = 0.0
	_step_panel_alpha(panel, 0)


func _step_panel_alpha(panel: CanvasItem, step: int) -> void:
	var alphas: Array[float] = [0.25, 0.5, 0.75, 1.0]
	if step >= alphas.size() or not is_instance_valid(panel):
		return
	get_tree().create_timer(0.04).timeout.connect(func() -> void:
		if not is_instance_valid(panel):
			return
		panel.modulate.a = alphas[step]
		_step_panel_alpha(panel, step + 1)
	)


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
	if not GameState.lobby_directory_changed.is_connected(_on_lobby_directory_changed):
		GameState.lobby_directory_changed.connect(_on_lobby_directory_changed)
	_setup_directory_timer()
	_hide_seed_row()
	_enter_initial_screen()
	if not resized.is_connected(_center_panel):
		resized.connect(_center_panel)
	var panel := get_node_or_null("Center/Panel") as Control
	if panel and not panel.minimum_size_changed.is_connected(_center_panel):
		panel.minimum_size_changed.connect(_center_panel)
	call_deferred("_center_panel")
	_play_panel_intro()
	_bind_audio_toggles()
	_apply_main_button_styles()
	_apply_tilt_layout()
	if secondary_box:
		secondary_box.visible = false
	if not Net.is_dedicated():
		Audio.request_music("lobby")


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
	call_deferred("_auto_connect_if_needed")


func _default_login_hint() -> String:
	if _web:
		return "正在自动连接服务器…"
	return "正在自动连接；也可本机开房"


func _apply_platform_chrome() -> void:
	web_hint.visible = _web
	if _web:
		host_btn.visible = false
		port_row.visible = false
		web_hint.text = "将连接 %s" % Net.get_default_join_address()
	else:
		host_btn.visible = true
		port_row.visible = true


func _hide_seed_row() -> void:
	var row := seed_edit.get_parent() if seed_edit else null
	if row is CanvasItem:
		row.visible = false
	var hint := get_node_or_null("%MapHint")
	if hint is Label:
		hint.text = "只有房主能改地图和密码"


func _setup_directory_timer() -> void:
	_dir_timer = Timer.new()
	_dir_timer.wait_time = DIRECTORY_REFRESH_SEC
	_dir_timer.one_shot = false
	_dir_timer.autostart = false
	add_child(_dir_timer)
	_dir_timer.timeout.connect(_on_directory_refresh_tick)


func _on_directory_refresh_tick() -> void:
	if not _browsing or not Net.is_client or not Net.is_online():
		return
	if not login_box.visible or _pending_register:
		return
	GameState.request_lobby_directory()


func _auto_connect_if_needed() -> void:
	# 无界面校验和专用服路径不要主动向外连。
	if DisplayServer.get_name() == "headless":
		return
	if Net.is_dedicated() or Net.is_server:
		return
	if _browsing or Net.is_online() or room_box.visible:
		return
	_begin_enter(false)


func _setup_maps() -> void:
	map_option.clear()
	map_option.add_item(Arena.map_name(Arena.MAP_RANDOM), Arena.MAP_RANDOM)
	for id in range(int(Arena.MapId.CLASSIC), int(Arena.MapId.MAZE) + 1):
		map_option.add_item(Arena.map_name(id), id)
	var idx := map_option.get_item_index(Arena.MAP_RANDOM)
	if idx >= 0:
		map_option.select(idx)


func _connect_controls() -> void:
	if not enter_btn.pressed.is_connected(_on_enter_pressed):
		enter_btn.pressed.connect(_on_enter_pressed)
	if not create_room_btn.pressed.is_connected(_on_create_room_pressed):
		create_room_btn.pressed.connect(_on_create_room_pressed)
	if not join_password_edit.text_submitted.is_connected(_on_join_password_submitted):
		join_password_edit.text_submitted.connect(_on_join_password_submitted)
	if not host_btn.pressed.is_connected(_on_host_pressed):
		host_btn.pressed.connect(_on_host_pressed)
	if not solo_btn.pressed.is_connected(_on_solo_pressed):
		solo_btn.pressed.connect(_on_solo_pressed)
	if not advanced_btn.pressed.is_connected(_on_advanced_pressed):
		advanced_btn.pressed.connect(_on_advanced_pressed)
	if more_btn and not more_btn.pressed.is_connected(_on_more_pressed):
		more_btn.pressed.connect(_on_more_pressed)
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
	_bind_audio_toggles()


func _connect_net_signals() -> void:
	if not Net.connected_to_server.is_connected(_on_connected):
		Net.connected_to_server.connect(_on_connected)
	if not Net.connection_failed.is_connected(_on_fail):
		Net.connection_failed.connect(_on_fail)
	if not Net.peer_disconnected.is_connected(_on_peer_out):
		Net.peer_disconnected.connect(_on_peer_out)
	if not Net.disconnected.is_connected(_on_disc):
		Net.disconnected.connect(_on_disc)


func _bind_audio_toggles() -> void:
	if music_toggle == null or sfx_toggle == null:
		return
	music_toggle.set_pressed_no_signal(not Audio.music_muted)
	sfx_toggle.set_pressed_no_signal(not Audio.sfx_muted)
	if not music_toggle.toggled.is_connected(_on_music_toggled):
		music_toggle.toggled.connect(_on_music_toggled)
	if not sfx_toggle.toggled.is_connected(_on_sfx_toggled):
		sfx_toggle.toggled.connect(_on_sfx_toggled)


func _on_music_toggled(on: bool) -> void:
	Audio.set_music_muted(not on)
	if on:
		Audio.unlock_from_gesture()
	_ui_click()


func _on_sfx_toggled(on: bool) -> void:
	if on:
		Audio.set_sfx_muted(false)
		_ui_click()
	else:
		_ui_click()
		Audio.set_sfx_muted(true)


func _ui_click() -> void:
	if Net.is_dedicated():
		return
	Audio.unlock_from_gesture()
	Audio.play_sfx("ui_click")


func _on_more_pressed() -> void:
	_ui_click()
	if secondary_box == null:
		return
	secondary_box.visible = not secondary_box.visible
	if more_btn:
		more_btn.text = "收起选项 ▴" if secondary_box.visible else "更多选项 ▾"
	call_deferred("_center_panel")


func _on_advanced_pressed() -> void:
	_ui_click()
	advanced_box.visible = not advanced_box.visible
	advanced_btn.text = "收起高级" if advanced_box.visible else "高级"
	call_deferred("_center_panel")



## 容器布局会冲掉 rotation；就绪后多帧再倾斜木板与主按钮。
func _apply_tilt_layout() -> void:
	call_deferred("_refresh_tilt_pivots")
	get_tree().create_timer(0.0).timeout.connect(_refresh_tilt_pivots)


func _refresh_tilt_pivots() -> void:
	if room_board:
		room_board.pivot_offset = room_board.size * 0.5
		room_board.rotation = -0.12
	if buttons_tilt:
		buttons_tilt.pivot_offset = buttons_tilt.size * 0.5
		buttons_tilt.rotation = 0.09
	if solo_btn and solo_btn.size.x > 1.0:
		solo_btn.pivot_offset = solo_btn.size * 0.5
		solo_btn.rotation = -0.06
	if create_room_btn and create_room_btn.size.x > 1.0:
		create_room_btn.pivot_offset = create_room_btn.size * 0.5
		create_room_btn.rotation = 0.07
	if enter_btn and enter_btn.size.x > 1.0:
		enter_btn.pivot_offset = enter_btn.size * 0.5
		enter_btn.rotation = 0.05


## 给开始/创建/加入套上彩色黏土九宫（无烘焙字）。
func _apply_main_button_styles() -> void:
	_style_button(solo_btn, "btn_start")
	_style_button(create_room_btn, "btn_create")
	_style_button(enter_btn, "btn_join")
	_style_button(start_btn, "btn_start")


func _style_button(btn: Button, stem: String) -> void:
	if btn == null:
		return
	var base := "res://assets/art/watercolor/lobby/%s.png" % stem
	var hover := "res://assets/art/watercolor/lobby/%s_hover.png" % stem
	var pressed := "res://assets/art/watercolor/lobby/%s_pressed.png" % stem
	btn.add_theme_stylebox_override("normal", _clay_style(base))
	btn.add_theme_stylebox_override("hover", _clay_style(hover))
	btn.add_theme_stylebox_override("pressed", _clay_style(pressed))
	btn.add_theme_stylebox_override("hover_pressed", _clay_style(pressed))
	btn.add_theme_stylebox_override("disabled", _clay_style(base, Color(0.75, 0.75, 0.75, 0.85)))
	btn.add_theme_color_override("font_color", Color(0.16, 0.1, 0.05, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.12, 0.07, 0.03, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.1, 0.06, 0.02, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.32, 0.28, 1))
	btn.add_theme_font_size_override("font_size", 18)


func _clay_style(path: String, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(path)
	box.texture_margin_left = 20
	box.texture_margin_top = 16
	box.texture_margin_right = 20
	box.texture_margin_bottom = 16
	box.content_margin_left = 12
	box.content_margin_top = 8
	box.content_margin_right = 12
	box.content_margin_bottom = 8
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.modulate_color = modulate
	return box


func _style_room_row(btn: Button, in_match: bool) -> void:
	var box := StyleBoxTexture.new()
	box.texture = load("res://assets/art/watercolor/lobby/room_row.png")
	box.texture_margin_left = 18
	box.texture_margin_top = 12
	box.texture_margin_right = 18
	box.texture_margin_bottom = 12
	box.content_margin_left = 12
	box.content_margin_top = 6
	box.content_margin_right = 12
	box.content_margin_bottom = 6
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	btn.add_theme_stylebox_override("normal", box)
	btn.add_theme_stylebox_override("hover", box)
	btn.add_theme_stylebox_override("pressed", box)
	btn.add_theme_stylebox_override("disabled", box)
	btn.add_theme_font_size_override("font_size", 15)
	if in_match:
		btn.add_theme_color_override("font_color", Color(0.62, 0.18, 0.12, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.62, 0.18, 0.12, 1))
		btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.28, 0.22, 1))
	else:
		btn.add_theme_color_override("font_color", Color(0.2, 0.38, 0.18, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.14, 0.32, 0.12, 1))
		btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.36, 1))


func _on_name_submitted(_text: String) -> void:
	_on_enter_pressed()


func _on_enter_pressed() -> void:
	# 已连上时「加入」= 进所选房；未选房则提示（列表仍自动刷新）。
	if _browsing and Net.is_client and Net.is_online():
		_ui_click()
		if _selected_room_code.is_empty():
			_set_login_status("先点选一个房间再加入")
			return
		_join_selected_room()
		return
	_begin_enter(true)


func _begin_enter(from_user: bool) -> void:
	if from_user:
		_ui_click()
	_shown_close = false
	_commit_nickname()
	if _browsing and Net.is_client and Net.is_online():
		GameState.request_lobby_directory()
		_set_login_status("已刷新房间列表")
		return
	_set_login_busy(true)
	_set_login_status("正在连接…")
	var err := Net.join(address_edit.text.strip_edges())
	if err != OK:
		_set_login_busy(false)
		_set_login_status("连接失败：%s" % error_string(err))


func _on_host_pressed() -> void:
	_ui_click()
	_shown_close = false
	_commit_nickname()
	var port := int(port_edit.text)
	if port <= 0 or port > 65535:
		_set_login_status("端口无效")
		return
	var err := Net.host(port)
	if err != OK:
		_set_login_status("本机开房失败：%s" % error_string(err))
		return
	_ui_lock = true
	GameState.reset_lobby()
	GameState.try_register(maxi(Net.get_peer_id(), 1), GameState.local_player_name, join_password_edit.text, "")
	_ui_lock = false
	_show_room()


func _on_solo_pressed() -> void:
	_ui_click()
	Audio.request_music("match")
	_commit_nickname()
	Net.close()
	_ui_lock = true
	GameState.reset_lobby()
	GameState.players[1] = {
		"name": GameState.local_player_name,
		"color_idx": 0,
		"ready": true,
	}
	# 人机不占大厅座位。开局时由 game_root 把另外三个角补上。
	GameState.solo_bot = true
	GameState.host_peer_id = 1
	GameState.in_match = true
	GameState.resolve_soft_seed()
	_ui_lock = false
	_go_to_game()


func _on_connected() -> void:
	_browsing = true
	_pending_register = false
	_stop_register_timer()
	_set_login_busy(false)
	_set_login_status("已连接，选择房间或新建")
	_set_browse_chrome(true)
	GameState.request_lobby_directory()


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
	# 还连在大厅浏览里：名单留着，只说明为什么没进成。
	if _browsing and Net.is_client and Net.is_online() and not _local_in_room():
		_pending_register = false
		_stop_register_timer()
		_set_login_busy(false)
		_set_login_status(message if not message.is_empty() else "无法进入房间")
		return
	_show_closed(message if not message.is_empty() else "无法进入房间")


func _on_kicked(message: String) -> void:
	_show_closed(message if not message.is_empty() else "你已被请出房间")


func _show_closed(message: String) -> void:
	_pending_register = false
	_browsing = false
	_selected_room_code = ""
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
	# 对局场景成为当前场景后，弃权由它负责。大厅只在自己还是当前场景时
	# 从名单里拿掉这个人（包括切场景前的那一帧）。
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
		_browsing = false
		_selected_room_code = ""
		_stop_register_timer()
		_show_room()
		return
	if _pending_register:
		return
	if room_box.visible:
		_show_login("已离开房间")


func _on_ready_pressed() -> void:
	if not Net.is_dedicated():
		Audio.unlock_from_gesture()
		Audio.play_sfx("ready")
	var me := GameState.local_peer_id()
	if not GameState.players.has(me):
		return
	var next := not bool(GameState.players[me].get("ready", false))
	GameState.submit_ready(next)


func _on_start_pressed() -> void:
	_ui_click()
	if not GameState.is_local_host():
		return
	_push_map_settings()
	var reason := GameState.start_block_reason()
	if reason != "":
		room_status.text = "等待中 %d/%d · %s" % [GameState.players.size(), GameState.MAX_PLAYERS, reason]
		return
	GameState.request_start()


func _on_leave_pressed() -> void:
	_ui_click()
	_pending_register = false
	_browsing = false
	_selected_room_code = ""
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
	var next_map := map_option.get_item_id(idx) if idx >= 0 else Arena.MAP_RANDOM
	var seed_text := ""
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
	Audio.request_music("match")
	if Net.is_online() and not GameState.players.has(Net.get_peer_id()):
		return
	if Net.is_online():
		MatchHost.open_room(GameState.room_code)
		visible = false
		return
	_go_to_game()


func _go_to_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")



func _on_lobby_directory_changed() -> void:
	if login_box.visible:
		_refresh_room_list()


func _set_browse_chrome(on: bool) -> void:
	room_list_label.visible = true
	room_list_scroll.visible = true
	create_room_btn.visible = true
	create_room_btn.disabled = not on
	enter_btn.text = "加入"
	solo_btn.text = "开始"
	create_room_btn.text = "创建房间"
	if on:
		_set_login_status("已连接，选择房间或新建" if login_status.text.begins_with("正在") or login_status.text.is_empty() else login_status.text)
		if _dir_timer and _dir_timer.is_stopped():
			_dir_timer.start()
	elif _dir_timer:
		_dir_timer.stop()


func _refresh_room_list() -> void:
	if room_list == null:
		return
	for child in room_list.get_children():
		room_list.remove_child(child)
		child.free()
	var entries: Array = GameState.lobby_directory
	# 无房：槽位留白，不放占位文案。
	if entries.is_empty():
		_selected_room_code = ""
		return
	var shown := 0
	for raw in entries:
		if shown >= ROOM_LIST_MAX:
			break
		var entry: Dictionary = raw
		var code := str(entry.get("code", ""))
		var count := int(entry.get("count", 0))
		var cap := int(entry.get("max", GameState.MAX_PLAYERS))
		var in_match := bool(entry.get("in_match", false))
		var locked := bool(entry.get("locked", false))
		var who := str(entry.get("who", ""))
		var state := "● 进行中" if in_match else "● 等待中"
		var lock_mark := "锁 " if locked else ""
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 38)
		btn.text = "%s%s  %d/%d  %s" % [lock_mark, code, count, cap, state]
		if who != "":
			btn.text += "  %s" % who
		_style_room_row(btn, in_match)
		btn.disabled = in_match or count >= cap or not _browsing
		if code == _selected_room_code:
			btn.modulate = Color(1.12, 1.14, 0.9, 1.0)
		var captured := code
		btn.pressed.connect(func() -> void: _on_room_row_pressed(captured))
		room_list.add_child(btn)
		shown += 1


func _on_room_row_pressed(code: String) -> void:
	_ui_click()
	if not _browsing or code.is_empty():
		return
	_selected_room_code = code
	_refresh_room_list()
	var locked := false
	for raw in GameState.lobby_directory:
		if str(raw.get("code", "")) == code:
			locked = bool(raw.get("locked", false))
			break
	if locked and join_password_edit.text.strip_edges().is_empty():
		_set_login_status("房间 %s 需要密码，填好后回车或再点一次" % code)
		join_password_edit.grab_focus()
		return
	_join_selected_room()



func _on_join_password_submitted(_text: String) -> void:
	if not _browsing:
		return
	if _selected_room_code.is_empty():
		_set_login_status("先点选一个房间")
		return
	_on_room_row_pressed(_selected_room_code)


func _on_create_room_pressed() -> void:
	_ui_click()
	_commit_nickname()
	if not _browsing or not Net.is_client or not Net.is_online():
		_set_login_status("请先连接服务器")
		return
	_selected_room_code = ""
	_start_register("", join_password_edit.text.strip_edges())


func _join_selected_room() -> void:
	if _selected_room_code.is_empty():
		return
	var locked := false
	var in_match := false
	var count := 0
	var cap := GameState.MAX_PLAYERS
	for raw in GameState.lobby_directory:
		if str(raw.get("code", "")) == _selected_room_code:
			locked = bool(raw.get("locked", false))
			in_match = bool(raw.get("in_match", false))
			count = int(raw.get("count", 0))
			cap = int(raw.get("max", GameState.MAX_PLAYERS))
			break
	if in_match:
		_set_login_status(GameState.MSG_IN_MATCH)
		return
	if count >= cap:
		_set_login_status(GameState.MSG_FULL)
		return
	var pw := join_password_edit.text.strip_edges()
	if locked and pw.is_empty():
		_set_login_status("请先填写房间密码")
		return
	_start_register(_selected_room_code, pw)


func _start_register(code: String, password: String) -> void:
	_pending_register = true
	_set_login_busy(true)
	_set_login_status("正在进入房间…")
	_arm_register_timeout()
	GameState._rpc_register_player.rpc_id(1, GameState.local_player_name, password, code)


func _show_login(message: String) -> void:
	login_box.visible = true
	room_box.visible = false
	subtitle.visible = true
	subtitle.text = "选房间开战，或自己开一间"
	_browsing = Net.is_client and Net.is_online()
	_set_browse_chrome(_browsing)
	_set_login_busy(false)
	_refresh_room_list()
	if not message.is_empty():
		_set_login_status(message)
	call_deferred("_center_panel")


func _show_room() -> void:
	var entered := not room_box.visible and _local_in_room() and not Net.is_dedicated()
	login_box.visible = false
	room_box.visible = true
	subtitle.visible = false
	_refresh_room()
	call_deferred("_center_panel")
	if entered:
		Audio.play_sfx("enter_room")


func _set_login_busy(busy: bool) -> void:
	enter_btn.disabled = busy
	host_btn.disabled = busy
	solo_btn.disabled = busy
	create_room_btn.disabled = busy or not _browsing


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
	var mid := Arena.lobby_map_id(GameState.map_id)
	var map_idx := map_option.get_item_index(mid)
	map_option.set_block_signals(true)
	seed_edit.set_block_signals(true)
	if map_idx >= 0 and map_option.selected != map_idx:
		map_option.select(map_idx)
	elif map_idx < 0:
		var ridx := map_option.get_item_index(Arena.MAP_RANDOM)
		if ridx >= 0:
			map_option.select(ridx)
			mid = Arena.MAP_RANDOM
	map_desc_label.text = Arena.map_desc(mid)
	map_option.disabled = not host
	seed_edit.editable = false
	seed_edit.text = ""
	var seed_row := seed_edit.get_parent()
	if seed_row is CanvasItem:
		seed_row.visible = false
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
	_ui_click()
	GameState.request_kick(peer_id)


func _local_in_room() -> bool:
	var id := GameState.local_peer_id()
	return id > 0 and GameState.players.has(id)


func _commit_nickname() -> void:
	var nick := name_edit.text.strip_edges()
	if nick.is_empty():
		nick = _random_nickname()
		name_edit.text = nick
	if nick.length() > 16:
		nick = nick.substr(0, 16)
	GameState.local_player_name = nick
	_save_nickname(nick)


func _random_nickname() -> String:
	var adj := _NICK_ADJ[randi() % _NICK_ADJ.size()]
	var noun := _NICK_NOUN[randi() % _NICK_NOUN.size()]
	return "%s%s%02d" % [adj, noun, randi() % 100]


func _load_nickname_into_field() -> void:
	var saved := _load_saved_nickname()
	if saved.is_empty():
		saved = _random_nickname()
	name_edit.text = saved
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
