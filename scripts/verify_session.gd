extends SceneTree
## 无界面：非法移动、中途退出、再来一局资格、大厅提示。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script: GDScript = load("res://scripts/game_root.gd")
	if not script.can_request_rematch(false, 1, 1, 1):
		_fail("离线单机应能再来一局")
		return
	if not script.can_request_rematch(true, 4, 4, 2):
		_fail("联机房主应能再来一局")
		return
	if script.can_request_rematch(true, 8, 4, 2):
		_fail("非房主不该能再来一局")
		return
	if script.can_request_rematch(true, 4, 4, 1):
		_fail("联机只剩一人不该能再来一局")
		return
	if script.can_request_rematch(true, 0, 4, 3):
		_fail("专用服进程自己不该能再来一局")
		return
	print("[verify_session] 再来一局资格通过")

	var session = load("res://scripts/match_session.gd").new()
	var skipped_kill := false
	session.forfeit_peer(null, 0, {1: true}, false, func(_id, _reason): skipped_kill = true, func(): pass)
	if skipped_kill or session.leaving:
		_fail("未知 peer 被当成弃权处理了")
		return
	session.leaving = true
	var gs = root.get_node("GameState")
	session.leave(null, "不会切场景")
	if gs.pending_notice == "不会切场景":
		_fail("第二次离开仍然切了场景")
		return
	session.leaving = false
	gs.players = {7: {"name": "丁", "color_idx": 0, "ready": true}}
	var last_alive := {7: true}
	var killed_last := false
	session.forfeit_peer(null, 7, last_alive, false, func(_id, _reason): killed_last = true, func(): pass)
	if killed_last or gs.players.has(7) or last_alive.has(7) or session.left_for_lobby:
		_fail("最后一个离线玩家没有安静地清空房间")
		return
	print("[verify_session] 会话防护通过")

	gs.players = {
		1: {"name": "甲", "color_idx": 0, "ready": true},
		2: {"name": "乙", "color_idx": 1, "ready": true},
		3: {"name": "丙", "color_idx": 2, "ready": true},
	}
	gs.host_peer_id = 1
	gs.in_match = true
	gs.map_id = 0
	gs.soft_seed = 1

	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var cell: Vector2i = game.player_nodes[1].get_meta("cell")
	game.player_stats[1].move_cd = 0.0
	game._apply_move(1, 3, 0)
	if game.player_nodes[1].get_meta("cell") != cell:
		_fail("瞬移步被接受了")
		return
	game.player_stats[1].move_cd = 0.0
	game._apply_move(1, 1, 1)
	if game.player_nodes[1].get_meta("cell") != cell:
		_fail("斜向步被接受了")
		return
	var stepped := false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		game.player_stats[1].move_cd = 0.0
		game._apply_move(1, d.x, d.y)
		if game.player_nodes[1].get_meta("cell") != cell:
			stepped = true
			break
	if not stepped:
		_fail("正常一步没有移动")
		return
	print("[verify_session] 移动步长通过")

	game._forfeit_peer(3)
	if game.match_over:
		_fail("三人局走一个人就把对局结束了")
		return
	if game.alive.get(3, false) or gs.players.has(3):
		_fail("离开的人还在名单里")
		return
	if game.status_label.text.find("丙") < 0 or game.status_label.text.find("已离开") < 0:
		_fail("离开状态：%s" % game.status_label.text)
		return
	if not game.alive.get(1, false) or not game.alive.get(2, false):
		_fail("剩下的人被一起判死了")
		return
	print("[verify_session] 中途退出后对局继续通过")

	game.alive[99] = true
	game._rpc_setup_match(gs.soft_seed, gs.players, gs.map_id)
	if game.alive.has(99) or not game.alive.get(1, false):
		_fail("开局没有重置存活")
		return
	if game.match_over:
		_fail("开局后终局标记还在")
		return
	print("[verify_session] 开局清掉过期存活标记通过")

	game._forfeit_peer(2)
	if game.match_over:
		_fail("另一个真人离开后，人机应让对局继续")
		return
	if gs.players.has(2) or game.alive.get(2, false):
		_fail("走出胜负线的人还留着")
		return
	if gs.players.size() != 1:
		_fail("名单人数 %d" % gs.players.size())
		return
	for raw in MatchFill.bot_ids(game.match_roster):
		game._kill_player(int(raw))
	if not game.match_over:
		_fail("最后一人站着却没有结束对局")
		return
	if game.end_title.text.find("甲") < 0 or game.end_title.text.find("获胜") < 0:
		_fail("胜者文字：%s" % game.end_title.text)
		return
	print("[verify_session] 退出判胜通过")

	game._rpc_setup_match(gs.soft_seed, gs.players, gs.map_id)
	for id in game.alive.keys():
		game.alive[id] = false
	game.match_over = false
	game._check_winner()
	if not game.match_over or game.end_title.text.find("平局") < 0:
		_fail("平局文字：%s" % game.end_title.text)
		return
	if game.end_title.text.find("获胜") >= 0:
		_fail("平局被报成获胜：%s" % game.end_title.text)
		return
	print("[verify_session] 平局通过")

	game.queue_free()
	await process_frame
	gs.pending_notice = "与服务器断开"
	gs.in_match = false
	var lobby = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	if lobby.login_status.text != "与服务器断开":
		_fail("提示：%s" % lobby.login_status.text)
		return
	if gs.pending_notice != "":
		_fail("提示没有被取走")
		return
	print("[verify_session] 大厅提示通过")
	print("[verify_session] 成功")
	quit(0)


func _fail(msg: String) -> void:
	push_error("[verify_session] 失败：%s" % msg)
	quit(1)
