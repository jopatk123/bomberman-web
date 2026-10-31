extends SceneTree
## 无界面：等待房间规则、地图同步数据、登录和房间界面文案。
## 运行：godot --headless --path . -s res://scripts/verify_lobby.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gs = root.get_node("GameState")
	if not _check_rules(gs):
		quit(1)
		return
	if not _check_sources():
		quit(1)
		return
	if not await _check_lobby_ui(gs):
		quit(1)
		return
	if not await _check_match_uses_room_map(gs):
		quit(1)
		return
	print("[verify_lobby] 成功")
	quit(0)


func _check_rules(gs) -> bool:
	if not _check_password_full_and_match(gs):
		return false
	if not _check_lobby_directory(gs):
		return false
	if not _check_host_ready_and_map(gs):
		return false
	if not _check_snapshot(gs):
		return false
	if not _check_arena_maps():
		return false
	gs.reset_lobby()
	return true


func _check_password_full_and_match(gs) -> bool:
	gs.reset_lobby()
	if RoomCodes.normalize("ab3k") != "AB3K" or RoomCodes.normalize("ab") != "" or RoomCodes.normalize("OOOO") != "":
		push_error("[verify_lobby] 失败：房间码规范化不对")
		return false
	var created: String = gs.try_register(2, "  ", " fish ")
	if created != "" or str(gs.players[2]["name"]) != "摸鱼人" or gs.room_password != "fish":
		push_error("[verify_lobby] 失败：空昵称或带空格的密码")
		return false
	var code := str(gs.room_code)
	if code.length() != 4 or int(gs.host_peer_id) != 2:
		push_error("[verify_lobby] 失败：第一个玩家应是 %s 的房主" % code)
		return false
	var bad: String = gs.try_register(3, "乙", "nope", code)
	if bad != gs.MSG_BAD_PASSWORD or gs.players.has(3):
		push_error("[verify_lobby] 失败：错误密码被接受了（%s）" % bad)
		return false
	if gs.try_register(3, "乙", "fish", code.to_lower()) != "" or not gs.players.has(3):
		push_error("[verify_lobby] 失败：小写房间码没能加入")
		return false
	gs.rooms[code].in_match = true
	gs.in_match = true
	var during: String = gs.try_register(4, "丙", "fish", code)
	if during != gs.MSG_IN_MATCH:
		push_error("[verify_lobby] 失败：对局中登记 -> %s" % during)
		return false
	var other: String = gs.try_register(4, "丙", "")
	if other != "" or gs.room_code == code or gs.rooms.size() != 2:
		push_error("[verify_lobby] 失败：有一间在对局时开不了第二间（%s）" % other)
		return false
	if gs.try_register(5, "丁", "", "no") != gs.MSG_BAD_CODE:
		push_error("[verify_lobby] 失败：房间码太短")
		return false
	if gs.try_register(5, "丁", "", "ZZZZ") != gs.MSG_NO_ROOM:
		push_error("[verify_lobby] 失败：房间不存在")
		return false
	gs.reset_lobby()
	var first: String = gs.try_register(10, "玩家0", "")
	var full_code := str(gs.room_code)
	if first != "":
		push_error("[verify_lobby] 失败：创建房间 %s" % first)
		return false
	for i in range(1, gs.MAX_PLAYERS):
		var joined: String = gs.try_register(10 + i, "玩家%d" % i, "", full_code)
		if joined != "":
			push_error("[verify_lobby] 失败：座位 %d 过早被拒：%s" % [i, joined])
			return false
	var full: String = gs.try_register(99, "溢出", "", full_code)
	if full != gs.MSG_FULL or gs.players.size() != gs.MAX_PLAYERS:
		push_error("[verify_lobby] 失败：满员 -> %s 人数=%d" % [full, gs.players.size()])
		return false
	var extra: String = gs.try_register(100, "另一间", "")
	if extra != "" or gs.rooms.size() != 2:
		push_error("[verify_lobby] 失败：满员挡住了新开一间（%s）" % extra)
		return false
	gs.reset_lobby()
	for i in RoomCodes.MAX_ROOMS:
		if gs.try_register(1000 + i, "房%d" % i, "") != "":
			push_error("[verify_lobby] 失败：房间数在 %d 就提前到顶" % i)
			return false
	if gs.try_register(2000, "再来", "") != gs.MSG_TOO_MANY:
		push_error("[verify_lobby] 失败：房间数量上限")
		return false
	print("[verify_lobby] 密码 / 对局中 / 满员通过")
	return true



func _check_lobby_directory(gs) -> bool:
	gs.reset_lobby()
	if gs.try_register(2, "甲", "secret") != "":
		push_error("[verify_lobby] 失败：为目录创建房间失败")
		return false
	var code_a := str(gs.room_code)
	if gs.try_register(4, "乙", "") != "":
		push_error("[verify_lobby] 失败：目录的第二间房失败")
		return false
	var code_b := str(gs.room_code)
	var dir: Array = gs.make_lobby_directory()
	if dir.size() != 2:
		push_error("[verify_lobby] 失败：目录条数 %d" % dir.size())
		return false
	var by_code := {}
	for e in dir:
		by_code[str(e.code)] = e
	if not by_code.has(code_a) or not bool(by_code[code_a].locked) or int(by_code[code_a].count) != 1:
		push_error("[verify_lobby] 失败：上锁房间摘要不对")
		return false
	if not by_code.has(code_b) or bool(by_code[code_b].locked):
		push_error("[verify_lobby] 失败：开放房间摘要不对")
		return false
	for e in dir:
		if e.has("room_password") or str(e).find("secret") >= 0:
			push_error("[verify_lobby] 失败：目录里泄露了密码")
			return false
	gs.apply_lobby_directory(dir)
	if gs.lobby_directory.size() != 2:
		push_error("[verify_lobby] 失败：套用目录失败")
		return false
	print("[verify_lobby] 大厅目录通过")
	gs.reset_lobby()
	return true


func _check_host_ready_and_map(gs) -> bool:
	gs.reset_lobby()
	if gs.try_register(8, "晚到", "") != "":
		return false
	var code := str(gs.room_code)
	if gs.try_register(4, "房主", "", code) != "":
		return false
	if gs.try_register(6, "中间", "", code) != "":
		return false
	if int(gs.host_peer_id) != 4:
		push_error("[verify_lobby] 失败：房主应是最小 peer，实际 %s" % gs.host_peer_id)
		return false
	if gs.start_block_reason() != gs.MSG_NEED_READY:
		push_error("[verify_lobby] 失败：没人准备的房间也能开始")
		return false
	gs.set_player_ready(4, true)
	gs.set_player_ready(6, true)
	if gs.start_block_reason() != gs.MSG_NEED_READY:
		push_error("[verify_lobby] 失败：peer 8 没有准备标记")
		return false
	gs.set_player_ready(8, true)
	if gs.start_block_reason() != "":
		push_error("[verify_lobby] 失败：全员准备仍被拦住：%s" % gs.start_block_reason())
		return false
	if gs.apply_map_settings(8, 2, "99"):
		push_error("[verify_lobby] 失败：非房主改了地图")
		return false
	if not gs.apply_map_settings(4, 2, "99") or int(gs.map_id) != int(Arena.MapId.CROSS) or gs.seed_input != "99" or int(gs.soft_seed) != -1:
		push_error("[verify_lobby] 失败：房主的地图设置没有生效")
		return false
	if gs.resolve_soft_seed() != 99:
		push_error("[verify_lobby] 失败：固定种子没有落定")
		return false
	if not gs.apply_password(4, "  secret ") or gs.room_password != "secret":
		push_error("[verify_lobby] 失败：房主改密码")
		return false
	if gs.apply_password(6, "nope"):
		push_error("[verify_lobby] 失败：非房主改了密码")
		return false
	if gs.try_kick(6, 8) or not gs.players.has(8):
		push_error("[verify_lobby] 失败：非房主踢人")
		return false
	if not gs.try_kick(4, 8) or gs.players.has(8) or int(gs.host_peer_id) != 4:
		push_error("[verify_lobby] 失败：房主踢人")
		return false
	gs.players.erase(4)
	gs.recompute_host()
	if int(gs.host_peer_id) != 6:
		push_error("[verify_lobby] 失败：房主没有交给下一个最小 peer")
		return false
	gs.players.clear()
	gs.recompute_host()
	if gs.start_block_reason() != gs.MSG_NEED_PLAYERS:
		push_error("[verify_lobby] 失败：空房开始的原因不对")
		return false
	gs.launch_match()
	if gs.in_match:
		push_error("[verify_lobby] 失败：空房也被开成了对局")
		return false
	print("[verify_lobby] 房主 / 准备 / 地图 / 踢人通过")
	return true


func _check_snapshot(gs) -> bool:
	gs.reset_lobby()
	gs.try_register(3, "同步", "")
	gs.set_player_ready(3, true)
	var sync_code := str(gs.room_code)
	gs.apply_password(3, "pw")
	gs.apply_map_settings(3, 1, "77")
	gs.rooms[sync_code].soft_seed = 77
	gs.soft_seed = 77
	var snap: Dictionary = gs.make_snapshot()
	if str(snap.get("room_code", "")) != sync_code:
		push_error("[verify_lobby] 失败：快照丢了房间码")
		return false
	gs.reset_lobby()
	gs.apply_snapshot(snap)
	if str(gs.room_code) != sync_code or int(gs.host_peer_id) != 3 or gs.room_password != "pw" or int(gs.map_id) != 1 or gs.seed_input != "77" or int(gs.soft_seed) != 77:
		push_error("[verify_lobby] 失败：快照房间字段不对")
		return false
	if not gs.players.has(3) or not bool(gs.players[3]["ready"]):
		push_error("[verify_lobby] 失败：快照丢了准备状态")
		return false
	gs.apply_snapshot({5: {"name": "旧快照", "color_idx": 1}})
	if not gs.players.has(5) or bool(gs.players[5].get("ready", true)):
		push_error("[verify_lobby] 失败：旧版玩家快照不对")
		return false
	if int(gs.host_peer_id) != 5:
		push_error("[verify_lobby] 失败：旧快照没有重算房主")
		return false
	print("[verify_lobby] 快照通过")
	return true


func _check_arena_maps() -> bool:
	if Arena.map_name(Arena.MapId.CLASSIC) != "经典" or Arena.map_name(Arena.MapId.CROSS) != "十字":
		push_error("[verify_lobby] 失败：地图名称不对")
		return false
	if Arena.map_name(Arena.MapId.MAZE) != "迷宫" or Arena.map_desc(Arena.MapId.OPEN).is_empty():
		push_error("[verify_lobby] 失败：迷宫名或开阔说明不对")
		return false
	if Arena.count_hard(Arena.build_base_grid(Arena.MapId.OPEN)) >= Arena.count_hard(Arena.build_base_grid(Arena.MapId.CLASSIC)):
		push_error("[verify_lobby] 失败：开阔图并没有更开阔")
		return false
	var cross_a := Arena.build_match_grid(Arena.MapId.CROSS, 424242)
	var cross_b := Arena.build_match_grid(Arena.MapId.CROSS, 424242)
	if not _same_grid(cross_a, cross_b):
		push_error("[verify_lobby] 失败：同一张图加同一颗种子不能复现")
		return false
	if Arena.map_name(Arena.MAP_RANDOM) != "随机":
		push_error("[verify_lobby] 失败：随机地图名称不对")
		return false
	var rolled := Arena.resolve_map_id(Arena.MAP_RANDOM)
	if rolled < int(Arena.MapId.CLASSIC) or rolled > int(Arena.MapId.MAZE):
		push_error("[verify_lobby] 失败：解析随机地图 %d" % rolled)
		return false
	if Arena.lobby_map_id(Arena.MAP_RANDOM) != Arena.MAP_RANDOM:
		push_error("[verify_lobby] 失败：大厅随机地图编号不对")
		return false
	print("[verify_lobby] 场地地图通过")
	return true


func _check_sources() -> bool:
	var lobby_src := FileAccess.get_file_as_string("res://scripts/lobby.gd")
	var scene_src := FileAccess.get_file_as_string("res://scenes/lobby.tscn")
	var state_src := FileAccess.get_file_as_string("res://autoload/GameState.gd")
	if lobby_src.find("_maybe_autostart") >= 0 or lobby_src.find("自动开局") >= 0:
		push_error("[verify_lobby] 失败：大厅里还提到自动开始")
		return false
	if scene_src.find("加入") < 0 or scene_src.find("创建房间") < 0 or scene_src.find("开始") < 0 or scene_src.find("本机开房") < 0:
		push_error("[verify_lobby] 失败：lobby.tscn 缺少登录文案")
		return false
	if scene_src.find("RoomListScroll") < 0 or state_src.find("_rpc_sync_lobby_directory") < 0:
		push_error("[verify_lobby] 失败：房间列表界面或目录 RPC 缺失")
		return false
	if scene_src.find("RoomBoard") < 0 or scene_src.find("board_tilt.png") < 0 or scene_src.find("ButtonsTilt") < 0:
		push_error("[verify_lobby] 失败：倾斜木板或倾斜主按钮节点缺失")
		return false
	if lobby_src.find("ROOM_LIST_MAX") < 0 or lobby_src.find("还没有房间…") >= 0:
		push_error("[verify_lobby] 失败：房间列表未限 3 条，或仍有空列表占位文案")
		return false
	if scene_src.find("NinePatchRect") < 0 or scene_src.find("PanelRoot") < 0:
		push_error("[verify_lobby] 失败：石质面板 NinePatch 缺失")
		return false
	if scene_src.find("TitlePlaque") < 0 or scene_src.find("CharStands") < 0:
		push_error("[verify_lobby] 失败：标题牌或立绘站台缺失")
		return false
	if scene_src.find("axis_stretch_horizontal = 1") >= 0:
		push_error("[verify_lobby] 失败：大厅九宫仍在 TILE 平铺")
		return false
	if scene_src.find("corner_radius") >= 0:
		push_error("[verify_lobby] 失败：大厅里还有圆角样式")
		return false
	if lobby_src.find("将连接 %s") < 0 or lobby_src.find("get_default_join_address") < 0 or lobby_src.find("OS.has_feature(\"web\")") < 0:
		push_error("[verify_lobby] 失败：网页端开房或地址提示缺失")
		return false
	if state_src.find("_rpc_sync_map_settings") < 0 or state_src.find("对局中，请稍后再来") < 0 or state_src.find("没有这个房间") < 0:
		push_error("[verify_lobby] 失败：GameState 房间 RPC 或拒绝文案缺失")
		return false
	if FileAccess.get_file_as_string("res://scripts/room_codes.gd").find("@rpc") >= 0:
		push_error("[verify_lobby] 失败：房间码模块里出现了 rpc")
		return false
	if state_src.find("@rpc") >= 0 and FileAccess.get_file_as_string("res://scripts/match/arena.gd").find("@rpc") >= 0:
		push_error("[verify_lobby] 失败：match/ 里出现了 rpc")
		return false
	print("[verify_lobby] 源码约定通过")
	return true


func _check_lobby_ui(gs) -> bool:
	gs.reset_lobby()
	var packed: PackedScene = load("res://scenes/lobby.tscn")
	var lobby = packed.instantiate()
	root.add_child(lobby)
	await process_frame
	await process_frame
	if lobby.has_method("_refresh_tilt_pivots"):
		lobby._refresh_tilt_pivots()
	await process_frame
	if lobby.enter_btn.text != "加入" or lobby.create_room_btn.text != "创建房间" or lobby.solo_btn.text != "开始" or lobby.host_btn.text != "本机开房":
		push_error("[verify_lobby] 失败：按钮文案不对")
		return false
	if not lobby.host_btn.visible or not lobby.port_row.visible:
		push_error("[verify_lobby] 失败：桌面端开房或端口被藏起来了")
		return false
	if lobby.advanced_box.visible or lobby.room_box.visible or lobby.web_hint.visible:
		push_error("[verify_lobby] 失败：高级、房间或网页提示一开始应是折叠的")
		return false
	if lobby.secondary_box != null and lobby.secondary_box.visible:
		push_error("[verify_lobby] 失败：更多选项一开始应是折叠的")
		return false
	if lobby.login_box.visible == false:
		push_error("[verify_lobby] 失败：登录区被藏起来了")
		return false
	lobby._on_advanced_pressed()
	if not lobby.advanced_box.visible or lobby.advanced_btn.text != "收起高级":
		push_error("[verify_lobby] 失败：高级开关不对")
		return false
	if not str(lobby.address_edit.text).contains("9080"):
		push_error("[verify_lobby] 失败：默认加入地址 %s" % lobby.address_edit.text)
		return false
	if lobby.map_option.item_count != 5 or lobby.map_option.get_item_text(0) != "随机" or lobby.map_option.get_item_text(4) != "迷宫":
		push_error("[verify_lobby] 失败：地图选项不对")
		return false
	if lobby.seed_edit.get_parent().visible:
		push_error("[verify_lobby] 失败：软墙种子应隐藏")
		return false
	if int(lobby.DIRECTORY_REFRESH_SEC) < 1:
		push_error("[verify_lobby] 失败：目录刷新间隔不对")
		return false
	if int(lobby.map_option.get_item_id(lobby.map_option.selected)) != int(Arena.MAP_RANDOM):
		push_error("[verify_lobby] 失败：地图下拉默认应是随机")
		return false
	var fresh: Dictionary = RoomCodes.fresh("TEST", "")
	if int(fresh.get("map_id", 0)) != int(Arena.MAP_RANDOM):
		push_error("[verify_lobby] 失败：新房间默认地图应是随机")
		return false
	if lobby.room_list_scroll == null or lobby.room_list == null:
		push_error("[verify_lobby] 失败：房间列表节点缺失")
		return false
	if lobby.room_board == null or lobby.buttons_tilt == null:
		push_error("[verify_lobby] 失败：倾斜木板或倾斜按钮容器缺失")
		return false
	if abs(float(lobby.room_board.rotation)) < 0.02 or abs(float(lobby.buttons_tilt.rotation)) < 0.02:
		push_error("[verify_lobby] 失败：木板或主按钮未倾斜")
		return false
	if int(lobby.room_list_scroll.custom_minimum_size.y) < 120:
		push_error("[verify_lobby] 失败：房间列表应大约露出 3 行")
		return false
	if int(lobby.ROOM_LIST_MAX) != 3:
		push_error("[verify_lobby] 失败：ROOM_LIST_MAX 应为 3")
		return false
	gs.apply_lobby_directory([])
	lobby._browsing = true
	lobby._refresh_room_list()
	if lobby.room_list.get_child_count() != 0:
		push_error("[verify_lobby] 失败：空目录仍渲染了占位内容 %d" % lobby.room_list.get_child_count())
		return false
	gs.apply_lobby_directory([
		{"code": "ABCD", "count": 1, "max": 4, "in_match": false, "locked": false, "who": "甲"},
		{"code": "EFGH", "count": 2, "max": 4, "in_match": true, "locked": true, "who": "乙, 丙"},
		{"code": "IJKL", "count": 3, "max": 4, "in_match": false, "locked": true, "who": "丁"},
		{"code": "MNOP", "count": 4, "max": 4, "in_match": false, "locked": false, "who": "满"},
	])
	lobby._browsing = true
	lobby._refresh_room_list()
	if lobby.room_list.get_child_count() != 3:
		push_error("[verify_lobby] 失败：房间列表应最多 3 行，实际 %d" % lobby.room_list.get_child_count())
		return false
	lobby.name_edit.text = ""
	lobby._commit_nickname()
	var auto_nick: String = gs.local_player_name
	if auto_nick.is_empty() or auto_nick.length() > 16 or lobby.name_edit.text != auto_nick:
		push_error("[verify_lobby] 失败：空昵称应自动填一个随机名")
		return false
	if auto_nick == "摸鱼人":
		push_error("[verify_lobby] 失败：默认昵称仍是固定的「摸鱼人」")
		return false
	lobby.name_edit.text = ""
	lobby._commit_nickname()
	if gs.local_player_name == auto_nick:
		# 形容词+名词+两位数字撞车的概率极低；就算撞了也不能是空的。
		if gs.local_player_name.is_empty():
			push_error("[verify_lobby] 失败：第二个随机昵称为空")
			return false
	# 没有存档路径的新加载：输入框应得到一个随机建议。
	var suggested: String = lobby._random_nickname()
	if suggested.is_empty() or suggested.length() > 16:
		push_error("[verify_lobby] 失败：随机昵称不合法 %s" % suggested)
		return false
	gs.reset_lobby()
	gs.try_register(4, "小明", "")
	var shown := str(gs.room_code)
	gs.try_register(6, "小红", "", shown)
	lobby._show_room()
	if lobby.room_code_label.text != "房间码 %s" % shown:
		push_error("[verify_lobby] 失败：房间码标签 %s" % lobby.room_code_label.text)
		return false
	var texts: PackedStringArray = []
	for row in lobby.player_list.get_children():
		for node in row.get_children():
			if node is Label:
				texts.append(node.text)
	if texts.find("小明") < 0 or texts.find("小红") < 0 or texts.find("房主") < 0 or texts.find("未准备") < 0:
		push_error("[verify_lobby] 失败：玩家行 %s" % [", ".join(texts)])
		return false
	if lobby.start_btn.visible:
		push_error("[verify_lobby] 失败：非房主也看到了开始按钮")
		return false
	if lobby.ready_btn.text != "准备" or lobby.leave_btn.text != "离开房间":
		push_error("[verify_lobby] 失败：房间按钮不对")
		return false
	if not str(lobby.room_status.text).begins_with("等待中 2/4"):
		push_error("[verify_lobby] 失败：房间状态 %s" % lobby.room_status.text)
		return false
	lobby.queue_free()
	await process_frame
	print("[verify_lobby] 大厅界面通过")
	return true


func _check_match_uses_room_map(gs) -> bool:
	gs.reset_lobby()
	gs.map_id = int(Arena.MapId.CROSS)
	gs.seed_input = "424242"
	gs.soft_seed = -1
	gs.resolve_soft_seed()
	gs.in_match = true
	gs.players = {1: {"name": "单测", "color_idx": 0, "ready": true}}
	var packed: PackedScene = load("res://scenes/game.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	if int(game.soft_seed) != 424242:
		push_error("[verify_lobby] 失败：对局没用房间种子（%s）" % game.soft_seed)
		return false
	var expected := Arena.build_match_grid(Arena.MapId.CROSS, 424242)
	if not _same_grid(game.grid, expected):
		push_error("[verify_lobby] 失败：对局格子和房主的地图或种子不一致")
		return false
	game.queue_free()
	await process_frame
	gs.reset_lobby()
	print("[verify_lobby] 对局种子通过")
	return true


func _same_grid(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for y in a.size():
		if a[y].size() != b[y].size():
			return false
		for x in a[y].size():
			if int(a[y][x]) != int(b[y][x]):
				return false
	return true
