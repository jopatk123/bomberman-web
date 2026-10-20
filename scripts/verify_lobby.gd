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
	gs.room_password = "fish"
	var bad: String = gs.try_register(2, "甲", "nope")
	if bad != gs.MSG_BAD_PASSWORD or not gs.players.is_empty():
		push_error("[verify_lobby] FAIL: bad password was accepted (%s)" % bad)
		return false
	var ok: String = gs.try_register(2, "  ", " fish ")
	if ok != "" or str(gs.players[2]["name"]) != "摸鱼人":
		push_error("[verify_lobby] FAIL: empty nick / padded password")
		return false
	if int(gs.host_peer_id) != 2:
		push_error("[verify_lobby] FAIL: first player should be host")
		return false
	gs.in_match = true
	var during: String = gs.try_register(3, "乙", "fish")
	if during != gs.MSG_IN_MATCH:
		push_error("[verify_lobby] FAIL: in-match register -> %s" % during)
		return false
	gs.in_match = false
	gs.room_password = ""
	gs.players.clear()
	gs.recompute_host()
	for i in gs.MAX_PLAYERS:
		var joined: String = gs.try_register(10 + i, "玩家%d" % i, "")
		if joined != "":
			push_error("[verify_lobby] FAIL: slot %d rejected early: %s" % [i, joined])
			return false
	var full: String = gs.try_register(99, "溢出", "")
	if full != gs.MSG_FULL or gs.players.size() != gs.MAX_PLAYERS:
		push_error("[verify_lobby] FAIL: full room -> %s size=%d" % [full, gs.players.size()])
		return false
	print("[verify_lobby] password / in-match / full OK")
	return true


func _check_host_ready_and_map(gs) -> bool:
	gs.reset_lobby()
	if gs.try_register(8, "晚到", "") != "":
		return false
	if gs.try_register(4, "房主", "") != "":
		return false
	if gs.try_register(6, "中间", "") != "":
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
	gs.host_peer_id = 3
	gs.room_password = "pw"
	gs.map_id = 1
	gs.seed_input = "77"
	gs.soft_seed = 77
	gs.in_match = false
	var snap: Dictionary = gs.make_snapshot()
	gs.reset_lobby()
	gs.apply_snapshot(snap)
	if int(gs.host_peer_id) != 3 or gs.room_password != "pw" or int(gs.map_id) != 1 or gs.seed_input != "77" or int(gs.soft_seed) != 77:
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
	if scene_src.find("进入房间") < 0 or scene_src.find("单机试试") < 0 or scene_src.find("本机开房") < 0:
		push_error("[verify_lobby] FAIL: login copy missing from lobby.tscn")
		return false
	if lobby_src.find("将连接本站游戏服") < 0 or lobby_src.find("OS.has_feature(\"web\")") < 0:
		push_error("[verify_lobby] FAIL: web host/address folding missing")
		return false
	if state_src.find("_rpc_sync_map_settings") < 0 or state_src.find("对局中，请稍后再来") < 0:
		push_error("[verify_lobby] FAIL: GameState room RPC or reject copy missing")
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
	if lobby.enter_btn.text != "进入房间" or lobby.solo_btn.text != "单机试试" or lobby.host_btn.text != "本机开房":
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
	lobby.name_edit.text = ""
	lobby._commit_nickname()
	if gs.local_player_name != "摸鱼人":
		push_error("[verify_lobby] FAIL: empty nickname default")
		return false
	gs.reset_lobby()
	gs.try_register(4, "小明", "")
	gs.try_register(6, "小红", "")
	lobby._show_room()
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
