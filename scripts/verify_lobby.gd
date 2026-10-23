extends SceneTree
## Headless: waiting-room rules, map sync data, and login/room UI copy.
## Run: godot --headless --path . -s res://scripts/verify_lobby.gd

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
	print("[verify_lobby] SUCCESS")
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
		push_error("[verify_lobby] FAIL: room code normalize")
		return false
	var created: String = gs.try_register(2, "  ", " fish ")
	if created != "" or str(gs.players[2]["name"]) != "摸鱼人" or gs.room_password != "fish":
		push_error("[verify_lobby] FAIL: empty nick / padded password")
		return false
	var code := str(gs.room_code)
	if code.length() != 4 or int(gs.host_peer_id) != 2:
		push_error("[verify_lobby] FAIL: first player should be host of %s" % code)
		return false
	var bad: String = gs.try_register(3, "乙", "nope", code)
	if bad != gs.MSG_BAD_PASSWORD or gs.players.has(3):
		push_error("[verify_lobby] FAIL: bad password was accepted (%s)" % bad)
		return false
	if gs.try_register(3, "乙", "fish", code.to_lower()) != "" or not gs.players.has(3):
		push_error("[verify_lobby] FAIL: lowercase code did not join")
		return false
	gs.rooms[code].in_match = true
	gs.in_match = true
	var during: String = gs.try_register(4, "丙", "fish", code)
	if during != gs.MSG_IN_MATCH:
		push_error("[verify_lobby] FAIL: in-match register -> %s" % during)
		return false
	var other: String = gs.try_register(4, "丙", "")
	if other != "" or gs.room_code == code or gs.rooms.size() != 2:
		push_error("[verify_lobby] FAIL: second room while one is in match (%s)" % other)
		return false
	if gs.try_register(5, "丁", "", "no") != gs.MSG_BAD_CODE:
		push_error("[verify_lobby] FAIL: short code")
		return false
	if gs.try_register(5, "丁", "", "ZZZZ") != gs.MSG_NO_ROOM:
		push_error("[verify_lobby] FAIL: missing room")
		return false
	gs.reset_lobby()
	var first: String = gs.try_register(10, "玩家0", "")
	var full_code := str(gs.room_code)
	if first != "":
		push_error("[verify_lobby] FAIL: create room %s" % first)
		return false
	for i in range(1, gs.MAX_PLAYERS):
		var joined: String = gs.try_register(10 + i, "玩家%d" % i, "", full_code)
		if joined != "":
			push_error("[verify_lobby] FAIL: slot %d rejected early: %s" % [i, joined])
			return false
	var full: String = gs.try_register(99, "溢出", "", full_code)
	if full != gs.MSG_FULL or gs.players.size() != gs.MAX_PLAYERS:
		push_error("[verify_lobby] FAIL: full room -> %s size=%d" % [full, gs.players.size()])
		return false
	var extra: String = gs.try_register(100, "另一间", "")
	if extra != "" or gs.rooms.size() != 2:
		push_error("[verify_lobby] FAIL: full room blocked a new room (%s)" % extra)
		return false
	gs.reset_lobby()
	for i in RoomCodes.MAX_ROOMS:
		if gs.try_register(1000 + i, "房%d" % i, "") != "":
			push_error("[verify_lobby] FAIL: room cap hit early at %d" % i)
			return false
	if gs.try_register(2000, "再来", "") != gs.MSG_TOO_MANY:
		push_error("[verify_lobby] FAIL: room cap")
		return false
	print("[verify_lobby] password / in-match / full OK")
	return true



func _check_lobby_directory(gs) -> bool:
	gs.reset_lobby()
	if gs.try_register(2, "甲", "secret") != "":
		push_error("[verify_lobby] FAIL: create for directory")
		return false
	var code_a := str(gs.room_code)
	if gs.try_register(4, "乙", "") != "":
		push_error("[verify_lobby] FAIL: second room for directory")
		return false
	var code_b := str(gs.room_code)
	var dir: Array = gs.make_lobby_directory()
	if dir.size() != 2:
		push_error("[verify_lobby] FAIL: directory size %d" % dir.size())
		return false
	var by_code := {}
	for e in dir:
		by_code[str(e.code)] = e
	if not by_code.has(code_a) or not bool(by_code[code_a].locked) or int(by_code[code_a].count) != 1:
		push_error("[verify_lobby] FAIL: locked room summary")
		return false
	if not by_code.has(code_b) or bool(by_code[code_b].locked):
		push_error("[verify_lobby] FAIL: open room summary")
		return false
	for e in dir:
		if e.has("room_password") or str(e).find("secret") >= 0:
			push_error("[verify_lobby] FAIL: password leaked in directory")
			return false
	gs.apply_lobby_directory(dir)
	if gs.lobby_directory.size() != 2:
		push_error("[verify_lobby] FAIL: apply directory")
		return false
	print("[verify_lobby] lobby directory OK")
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
		push_error("[verify_lobby] FAIL: host should be smallest peer, got %s" % gs.host_peer_id)
		return false
	if gs.start_block_reason() != gs.MSG_NEED_READY:
		push_error("[verify_lobby] FAIL: unready room could start")
		return false
	gs.set_player_ready(4, true)
	gs.set_player_ready(6, true)
	if gs.start_block_reason() != gs.MSG_NEED_READY:
		push_error("[verify_lobby] FAIL: missing ready on peer 8")
		return false
	gs.set_player_ready(8, true)
	if gs.start_block_reason() != "":
		push_error("[verify_lobby] FAIL: all ready but blocked: %s" % gs.start_block_reason())
		return false
	if gs.apply_map_settings(8, 2, "99"):
		push_error("[verify_lobby] FAIL: non-host changed the map")
		return false
	if not gs.apply_map_settings(4, 2, "99") or int(gs.map_id) != int(Arena.MapId.CROSS) or gs.seed_input != "99" or int(gs.soft_seed) != -1:
		push_error("[verify_lobby] FAIL: host map settings did not apply")
		return false
	if gs.resolve_soft_seed() != 99:
		push_error("[verify_lobby] FAIL: fixed seed did not resolve")
		return false
	if not gs.apply_password(4, "  secret ") or gs.room_password != "secret":
		push_error("[verify_lobby] FAIL: host password")
		return false
	if gs.apply_password(6, "nope"):
		push_error("[verify_lobby] FAIL: non-host set password")
		return false
	if gs.try_kick(6, 8) or not gs.players.has(8):
		push_error("[verify_lobby] FAIL: non-host kick")
		return false
	if not gs.try_kick(4, 8) or gs.players.has(8) or int(gs.host_peer_id) != 4:
		push_error("[verify_lobby] FAIL: host kick")
		return false
	gs.players.erase(4)
	gs.recompute_host()
	if int(gs.host_peer_id) != 6:
		push_error("[verify_lobby] FAIL: host did not move to next smallest peer")
		return false
	gs.players.clear()
	gs.recompute_host()
	if gs.start_block_reason() != gs.MSG_NEED_PLAYERS:
		push_error("[verify_lobby] FAIL: empty room start reason")
		return false
	gs.launch_match()
	if gs.in_match:
		push_error("[verify_lobby] FAIL: launch_match started an empty room")
		return false
	print("[verify_lobby] host / ready / map / kick OK")
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
		push_error("[verify_lobby] FAIL: snapshot dropped room code")
		return false
	gs.reset_lobby()
	gs.apply_snapshot(snap)
	if str(gs.room_code) != sync_code or int(gs.host_peer_id) != 3 or gs.room_password != "pw" or int(gs.map_id) != 1 or gs.seed_input != "77" or int(gs.soft_seed) != 77:
		push_error("[verify_lobby] FAIL: snapshot room fields")
		return false
	if not gs.players.has(3) or not bool(gs.players[3]["ready"]):
		push_error("[verify_lobby] FAIL: snapshot dropped ready")
		return false
	gs.apply_snapshot({5: {"name": "旧快照", "color_idx": 1}})
	if not gs.players.has(5) or bool(gs.players[5].get("ready", true)):
		push_error("[verify_lobby] FAIL: legacy players snapshot")
		return false
	if int(gs.host_peer_id) != 5:
		push_error("[verify_lobby] FAIL: legacy snapshot did not recompute host")
		return false
	print("[verify_lobby] snapshot OK")
	return true


func _check_arena_maps() -> bool:
	if Arena.map_name(Arena.MapId.CLASSIC) != "经典" or Arena.map_name(Arena.MapId.CROSS) != "十字":
		push_error("[verify_lobby] FAIL: map names")
		return false
	if Arena.map_name(Arena.MapId.MAZE) != "迷宫" or Arena.map_desc(Arena.MapId.OPEN).is_empty():
		push_error("[verify_lobby] FAIL: maze name or open desc")
		return false
	if Arena.count_hard(Arena.build_base_grid(Arena.MapId.OPEN)) >= Arena.count_hard(Arena.build_base_grid(Arena.MapId.CLASSIC)):
		push_error("[verify_lobby] FAIL: open layout is not more open")
		return false
	var cross_a := Arena.build_match_grid(Arena.MapId.CROSS, 424242)
	var cross_b := Arena.build_match_grid(Arena.MapId.CROSS, 424242)
	if not _same_grid(cross_a, cross_b):
		push_error("[verify_lobby] FAIL: same map+seed was not reproducible")
		return false
	print("[verify_lobby] arena maps OK")
	return true


func _check_sources() -> bool:
	var lobby_src := FileAccess.get_file_as_string("res://scripts/lobby.gd")
	var scene_src := FileAccess.get_file_as_string("res://scenes/lobby.tscn")
	var state_src := FileAccess.get_file_as_string("res://autoload/GameState.gd")
	if lobby_src.find("_maybe_autostart") >= 0 or lobby_src.find("自动开局") >= 0:
		push_error("[verify_lobby] FAIL: auto-start still mentioned in lobby")
		return false
	if scene_src.find("连接服务器") < 0 or scene_src.find("新建房间") < 0 or scene_src.find("单机试试") < 0 or scene_src.find("本机开房") < 0:
		push_error("[verify_lobby] FAIL: login copy missing from lobby.tscn")
		return false
	if scene_src.find("RoomListScroll") < 0 or state_src.find("_rpc_sync_lobby_directory") < 0:
		push_error("[verify_lobby] FAIL: room list UI or directory RPC missing")
		return false
	if lobby_src.find("将连接本站游戏服") < 0 or lobby_src.find("OS.has_feature(\"web\")") < 0:
		push_error("[verify_lobby] FAIL: web host/address folding missing")
		return false
	if state_src.find("_rpc_sync_map_settings") < 0 or state_src.find("对局中，请稍后再来") < 0 or state_src.find("没有这个房间") < 0:
		push_error("[verify_lobby] FAIL: GameState room RPC or reject copy missing")
		return false
	if FileAccess.get_file_as_string("res://scripts/room_codes.gd").find("@rpc") >= 0:
		push_error("[verify_lobby] FAIL: rpc leaked into room codes")
		return false
	if state_src.find("@rpc") >= 0 and FileAccess.get_file_as_string("res://scripts/match/arena.gd").find("@rpc") >= 0:
		push_error("[verify_lobby] FAIL: rpc leaked into match/")
		return false
	print("[verify_lobby] sources OK")
	return true


func _check_lobby_ui(gs) -> bool:
	gs.reset_lobby()
	var packed: PackedScene = load("res://scenes/lobby.tscn")
	var lobby = packed.instantiate()
	root.add_child(lobby)
	await process_frame
	if lobby.enter_btn.text != "连接服务器" or lobby.create_room_btn.text != "新建房间" or lobby.solo_btn.text != "单机试试" or lobby.host_btn.text != "本机开房":
		push_error("[verify_lobby] FAIL: button copy")
		return false
	if not lobby.host_btn.visible or not lobby.port_row.visible:
		push_error("[verify_lobby] FAIL: desktop host/port hidden")
		return false
	if lobby.advanced_box.visible or lobby.room_box.visible or lobby.web_hint.visible:
		push_error("[verify_lobby] FAIL: advanced/room/web hint should start folded")
		return false
	if lobby.login_box.visible == false:
		push_error("[verify_lobby] FAIL: login hidden")
		return false
	lobby._on_advanced_pressed()
	if not lobby.advanced_box.visible or lobby.advanced_btn.text != "收起高级":
		push_error("[verify_lobby] FAIL: advanced toggle")
		return false
	if not str(lobby.address_edit.text).contains("9080"):
		push_error("[verify_lobby] FAIL: default join address %s" % lobby.address_edit.text)
		return false
	if lobby.map_option.item_count != 4 or lobby.map_option.get_item_text(0) != "经典" or lobby.map_option.get_item_text(3) != "迷宫":
		push_error("[verify_lobby] FAIL: map option items")
		return false
	if lobby.room_list_scroll == null or lobby.room_list == null:
		push_error("[verify_lobby] FAIL: room list nodes missing")
		return false
	if int(lobby.room_list_scroll.custom_minimum_size.y) < 120:
		push_error("[verify_lobby] FAIL: room list should show ~3 rows")
		return false
	gs.apply_lobby_directory([
		{"code": "ABCD", "count": 1, "max": 4, "in_match": false, "locked": false, "who": "甲"},
		{"code": "EFGH", "count": 2, "max": 4, "in_match": true, "locked": true, "who": "乙, 丙"},
		{"code": "IJKL", "count": 3, "max": 4, "in_match": false, "locked": true, "who": "丁"},
		{"code": "MNOP", "count": 4, "max": 4, "in_match": false, "locked": false, "who": "满"},
	])
	lobby._browsing = true
	lobby._refresh_room_list()
	if lobby.room_list.get_child_count() != 4:
		push_error("[verify_lobby] FAIL: room list rows %d" % lobby.room_list.get_child_count())
		return false
	lobby.name_edit.text = ""
	lobby._commit_nickname()
	if gs.local_player_name != "摸鱼人":
		push_error("[verify_lobby] FAIL: empty nickname default")
		return false
	gs.reset_lobby()
	gs.try_register(4, "小明", "")
	var shown := str(gs.room_code)
	gs.try_register(6, "小红", "", shown)
	lobby._show_room()
	if lobby.room_code_label.text != "房间码 %s" % shown:
		push_error("[verify_lobby] FAIL: room code label %s" % lobby.room_code_label.text)
		return false
	var texts: PackedStringArray = []
	for row in lobby.player_list.get_children():
		for node in row.get_children():
			if node is Label:
				texts.append(node.text)
	if texts.find("小明") < 0 or texts.find("小红") < 0 or texts.find("房主") < 0 or texts.find("未准备") < 0:
		push_error("[verify_lobby] FAIL: player rows %s" % [", ".join(texts)])
		return false
	if lobby.start_btn.visible:
		push_error("[verify_lobby] FAIL: start shown for a non-host viewer")
		return false
	if lobby.ready_btn.text != "准备" or lobby.leave_btn.text != "离开房间":
		push_error("[verify_lobby] FAIL: room buttons")
		return false
	if not str(lobby.room_status.text).begins_with("等待中 2/4"):
		push_error("[verify_lobby] FAIL: room status %s" % lobby.room_status.text)
		return false
	lobby.queue_free()
	await process_frame
	print("[verify_lobby] lobby UI OK")
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
		push_error("[verify_lobby] FAIL: match ignored room seed (%s)" % game.soft_seed)
		return false
	var expected := Arena.build_match_grid(Arena.MapId.CROSS, 424242)
	if not _same_grid(game.grid, expected):
		push_error("[verify_lobby] FAIL: match grid != host map/seed")
		return false
	game.queue_free()
	await process_frame
	gs.reset_lobby()
	print("[verify_lobby] match seed OK")
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
