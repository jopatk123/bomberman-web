extends SceneTree
## Headless: illegal move steps, mid-match forfeit, rematch permission, lobby notice.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script: GDScript = load("res://scripts/game_root.gd")
	if not script.can_request_rematch(false, 1, 1, 1):
		_fail("offline solo should rematch")
		return
	if not script.can_request_rematch(true, 4, 4, 2):
		_fail("online host should rematch")
		return
	if script.can_request_rematch(true, 8, 4, 2):
		_fail("non-host rematch")
		return
	if script.can_request_rematch(true, 4, 4, 1):
		_fail("online rematch with one player")
		return
	if script.can_request_rematch(true, 0, 4, 3):
		_fail("dedicated process rematch")
		return
	print("[verify_session] rematch permission OK")

	var session = load("res://scripts/match_session.gd").new()
	var skipped_kill := false
	session.forfeit_peer(null, 0, {1: true}, false, func(_id, _reason): skipped_kill = true, func(): pass)
	if skipped_kill or session.leaving:
		_fail("unknown peer was forfeited")
		return
	session.leaving = true
	var gs = root.get_node("GameState")
	session.leave(null, "不会切场景")
	if gs.pending_notice == "不会切场景":
		_fail("second leave still switched scenes")
		return
	session.leaving = false
	gs.players = {7: {"name": "丁", "color_idx": 0, "ready": true}}
	var last_alive := {7: true}
	var killed_last := false
	session.forfeit_peer(null, 7, last_alive, false, func(_id, _reason): killed_last = true, func(): pass)
	if killed_last or gs.players.has(7) or last_alive.has(7) or session.left_for_lobby:
		_fail("last offline peer did not clear the room quietly")
		return
	print("[verify_session] session guards OK")

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
		_fail("teleport step was applied")
		return
	game.player_stats[1].move_cd = 0.0
	game._apply_move(1, 1, 1)
	if game.player_nodes[1].get_meta("cell") != cell:
		_fail("diagonal step was applied")
		return
	var stepped := false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		game.player_stats[1].move_cd = 0.0
		game._apply_move(1, d.x, d.y)
		if game.player_nodes[1].get_meta("cell") != cell:
			stepped = true
			break
	if not stepped:
		_fail("unit step did not move")
		return
	print("[verify_session] move step OK")

	game._forfeit_peer(3)
	if game.match_over:
		_fail("one leave in a 3-player match ended it")
		return
	if game.alive.get(3, false) or gs.players.has(3):
		_fail("leaver still in roster")
		return
	if game.status_label.text.find("丙") < 0 or game.status_label.text.find("已离开") < 0:
		_fail("leave status: %s" % game.status_label.text)
		return
	if not game.alive.get(1, false) or not game.alive.get(2, false):
		_fail("remaining players were killed")
		return
	print("[verify_session] forfeit continues OK")

	game.alive[99] = true
	game._rpc_setup_match(gs.soft_seed, gs.players, gs.map_id)
	if game.alive.has(99) or not game.alive.get(1, false):
		_fail("setup did not reset alive")
		return
	if game.match_over:
		_fail("setup left match_over set")
		return
	print("[verify_session] setup clears stale alive OK")

	game._forfeit_peer(2)
	if not game.match_over:
		_fail("last opponent leaving did not end the match")
		return
	if game.end_title.text.find("甲") < 0 or game.end_title.text.find("获胜") < 0:
		_fail("winner text: %s" % game.end_title.text)
		return
	if gs.players.has(2) or game.alive.get(2, false):
		_fail("forfeited winner-path player remains")
		return
	if gs.players.size() != 1:
		_fail("roster size %d" % gs.players.size())
		return
	print("[verify_session] forfeit win OK")

	game._rpc_setup_match(gs.soft_seed, gs.players, gs.map_id)
	for id in game.alive.keys():
		game.alive[id] = false
	game.match_over = false
	game._check_winner()
	if not game.match_over or game.end_title.text.find("平局") < 0:
		_fail("draw text: %s" % game.end_title.text)
		return
	if game.end_title.text.find("获胜") >= 0:
		_fail("draw announced as a win: %s" % game.end_title.text)
		return
	print("[verify_session] draw OK")

	game.queue_free()
	await process_frame
	gs.pending_notice = "与服务器断开"
	gs.in_match = false
	var lobby = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	if lobby.login_status.text != "与服务器断开":
		_fail("notice: %s" % lobby.login_status.text)
		return
	if gs.pending_notice != "":
		_fail("notice was not consumed")
		return
	print("[verify_session] lobby notice OK")
	print("[verify_session] SUCCESS")
	quit(0)


func _fail(msg: String) -> void:
	push_error("[verify_session] FAIL: %s" % msg)
	quit(1)
