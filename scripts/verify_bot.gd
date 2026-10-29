extends SceneTree
## 无界面：单机人机决策、客机移动确认，以及人机真的会在对局里行动。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _fill_rules():
		return
	if not _bot_rules():
		return
	if not _predict():
		return
	await _solo_scene()


func _bot_rules() -> bool:
	var grid := _empty(9, 9)
	var bot := Vector2i(3, 3)
	var flee := MatchBot.decide({
		"grid": grid, "cols": 9, "rows": 9, "cell": bot,
		"blast_range": 2, "can_place": true,
		"bombs": [{"x": 3, "y": 3, "timer": 0.4, "range": 2, "pierce": false}],
		"others": [], "lethal": [],
	})
	if int(flee.action) != MatchBot.Action.MOVE:
		return _fail("人机站在自己的爆炸上：%s" % str(flee))
	if absi(int(flee.dx)) + absi(int(flee.dy)) != 1:
		return _fail("躲避步：%s" % str(flee))
	print("[verify_bot] 躲避通过")

	grid[3][4] = 2
	var place := MatchBot.decide({
		"grid": grid, "cols": 9, "rows": 9, "cell": bot,
		"blast_range": 2, "can_place": true,
		"bombs": [], "others": [Vector2i(7, 7)], "lethal": [],
	})
	if int(place.action) != MatchBot.Action.BOMB:
		return _fail("人机没有炸相邻软墙：%s" % str(place))
	print("[verify_bot] 放弹通过")

	var hall := _empty(9, 9)
	for x in 9:
		for y in 9:
			hall[y][x] = 1
	hall[2][2] = 0
	hall[2][3] = 0
	hall[2][4] = 2
	var trapped := MatchBot.decide({
		"grid": hall, "cols": 9, "rows": 9, "cell": Vector2i(2, 2),
		"blast_range": 2, "can_place": true,
		"bombs": [], "others": [], "lethal": [],
	})
	if int(trapped.action) == MatchBot.Action.BOMB:
		return _fail("人机在死胡同里放了炸弹")
	print("[verify_bot] 不死胡同放弹通过")

	var safe := _empty(9, 9)
	safe[3][5] = 2
	var around := MatchBot.decide({
		"grid": safe, "cols": 9, "rows": 9, "cell": Vector2i(3, 3),
		"blast_range": 2, "can_place": false,
		"bombs": [{"x": 1, "y": 3, "timer": 0.3, "range": 1, "pierce": false}],
		"others": [], "lethal": [Vector2i(3, 4)],
	})
	# 软墙在右边。下面是致死格。左边落在射程 1 的爆炸里。
	if int(around.action) != MatchBot.Action.MOVE or int(around.dx) != 1 or int(around.dy) != 0:
		return _fail("人机没有走向软墙、也没躲开火：%s" % str(around))
	print("[verify_bot] 避开危险通过")

	var pickup := _empty(9, 9)
	var grabbed := MatchBot.decide({
		"grid": pickup, "cols": 9, "rows": 9, "cell": Vector2i(3, 3),
		"blast_range": 2, "can_place": true,
		"bombs": [], "others": [], "lethal": [],
		"powerups": [Vector2i(3, 4)],
	})
	if int(grabbed.action) != MatchBot.Action.MOVE or int(grabbed.dx) != 0 or int(grabbed.dy) != 1:
		return _fail("人机放过了相邻道具：%s" % str(grabbed))
	print("[verify_bot] 道具通过")

	# 窄廊 + 射程 2：两步启发式逃不出，完整 BFS 沿廊走出火线后应放弹。
	var lane := _empty(9, 9)
	for x in range(1, 8):
		for y in range(1, 8):
			lane[y][x] = 1
	for y in range(1, 8):
		lane[y][4] = 0
	lane[7][4] = 2
	var deep := MatchBot.decide({
		"grid": lane, "cols": 9, "rows": 9, "cell": Vector2i(4, 6),
		"blast_range": 2, "can_place": true, "bomb_stock": 1,
		"bombs": [], "others": [], "lethal": [], "powerups": [],
	})
	if int(deep.action) != MatchBot.Action.BOMB:
		return _fail("完整逃生 BFS 应允许放弹：%s" % str(deep))
	print("[verify_bot] 深廊逃生放弹通过")

	# 远处道具：不只捡四邻，应朝道具迈步。
	var far := _empty(9, 9)
	var hunt := MatchBot.decide({
		"grid": far, "cols": 9, "rows": 9, "cell": Vector2i(2, 2),
		"blast_range": 2, "can_place": false, "bomb_stock": 0,
		"bombs": [], "others": [], "lethal": [],
		"powerups": [Vector2i(6, 2)],
	})
	if int(hunt.action) != MatchBot.Action.MOVE or int(hunt.dx) != 1 or int(hunt.dy) != 0:
		return _fail("人机没有奔向远处道具：%s" % str(hunt))
	print("[verify_bot] 远处道具通过")

	# 有踢弹：唯一出路被弹堵住时，逃命应迈向炸弹格踢开。
	var kick_grid := _empty(9, 9)
	for x in range(1, 8):
		for y in range(1, 8):
			kick_grid[y][x] = 1
	kick_grid[4][2] = 0
	kick_grid[4][3] = 0
	kick_grid[4][4] = 0
	kick_grid[4][5] = 0
	var kick_flee := MatchBot.decide({
		"grid": kick_grid, "cols": 9, "rows": 9, "cell": Vector2i(2, 4),
		"blast_range": 2, "can_place": false, "has_kick": true,
		"bombs": [
			{"x": 2, "y": 4, "timer": 0.5, "range": 2, "pierce": false},
			{"x": 3, "y": 4, "timer": 1.0, "range": 1, "pierce": false},
		],
		"others": [], "lethal": [], "powerups": [],
	})
	# 自己站在弹上（危险），东侧有另一颗挡路；踢开后可往安全走。
	if int(kick_flee.action) != MatchBot.Action.MOVE:
		return _fail("有踢逃命应移动：%s" % str(kick_flee))
	print("[verify_bot] 踢弹逃命通过")

	# 禁回头：刚向右走过来，左右都通时优先不立刻退回。
	var anti := _empty(9, 9)
	anti[3][5] = 2
	var no_back := MatchBot.decide({
		"grid": anti, "cols": 9, "rows": 9, "cell": Vector2i(3, 3),
		"blast_range": 2, "can_place": false, "bomb_stock": 0,
		"bombs": [], "others": [], "lethal": [], "powerups": [],
		"last_dx": -1, "last_dy": 0, "stuck": 0,
		"grind_x": -1, "grind_y": -1,
	})
	# 软墙在 (5,3)，应向右；last 是从右来的（last_dx=-1 表示上步向左），不要立刻再向左。
	if int(no_back.action) != MatchBot.Action.MOVE:
		return _fail("禁回头场景应移动：%s" % str(no_back))
	if int(no_back.dx) == -1 and int(no_back.dy) == 0:
		return _fail("人机立刻回头了：%s" % str(no_back))
	print("[verify_bot] 禁回头通过")
	return true


func _predict() -> bool:
	var a := Vector2i(1, 1)
	var b := Vector2i(2, 1)
	var c := Vector2i(3, 1)
	var mid: Dictionary = MovePredict.ack([a, b, c], b)
	if mid.chain.size() != 2 or mid.chain[0] != b or mid.show != c:
		return _fail("确认裁链：%s" % str(mid))
	var rejected: Dictionary = MovePredict.ack([a, b], a)
	if rejected.chain.size() != 1 or rejected.show != a:
		return _fail("确认拒绝：%s" % str(rejected))
	var snapped: Dictionary = MovePredict.ack([a, b], Vector2i(8, 8))
	if snapped.show != Vector2i(8, 8):
		return _fail("确认拉回：%s" % str(snapped))
	var same: Dictionary = MovePredict.ack([b], b)
	if same.show != b or same.chain.size() != 1:
		return _fail("确认原格：%s" % str(same))
	print("[verify_bot] 预演确认通过")
	return true


func _fill_rules() -> bool:
	if MatchFill.bot_peer_id(1) != MatchBot.PEER_ID:
		return _fail("第一个人机编号偏离了 MatchBot.PEER_ID")
	var src := {
		1: {"name": "甲", "color_idx": 0, "ready": true},
	}
	var filled := MatchFill.fill(src)
	if src.size() != 1 or src.has(MatchBot.PEER_ID):
		return _fail("补位改动了大厅名单")
	if not _expect_fill(filled, 1, "1 human"):
		return false
	var again := MatchFill.fill(filled)
	if not _same_fighters(filled, again):
		return _fail("补位不是幂等的：%s 对 %s" % [str(filled), str(again)])
	for n in [2, 3]:
		var humans := {}
		for i in n:
			humans[10 + i] = {"name": "人%d" % i, "color_idx": i, "ready": true}
		if not _expect_fill(MatchFill.fill(humans), n, "%d humans" % n):
			return false
	var four := {}
	for i in 4:
		four[i + 1] = {"name": "满%d" % i, "color_idx": i, "ready": true}
	var full := MatchFill.fill(four)
	if full.size() != 4 or not MatchFill.bot_ids(full).is_empty():
		return _fail("4 个真人被补了人机：%s" % str(full))
	var seats: Array = MatchFill.seat_order(full)
	if seats != [1, 2, 3, 4]:
		return _fail("4 个真人的座位被重排了：%s" % str(seats))
	print("[verify_bot] 补位规则通过")
	return true


func _expect_fill(roster: Dictionary, human_count: int, label: String) -> bool:
	if roster.size() != 4:
		return _fail("%s 人数 %d" % [label, roster.size()])
	var bots: Array = MatchFill.bot_ids(roster)
	if bots.size() != 4 - human_count:
		return _fail("%s 人机 %s" % [label, str(bots)])
	var humans := MatchFill.humans(roster)
	if humans.size() != human_count:
		return _fail("%s 剩下真人 %d" % [label, humans.size()])
	for id in bots:
		var entry: Dictionary = roster[id]
		if not bool(entry.get("bot", false)) or not MatchFill.is_bot_id(int(id)):
			return _fail("%s 人机没有标记：%s" % [label, str(entry)])
		var nick := str(entry.get("name", ""))
		if not nick.begins_with("人机"):
			return _fail("%s 名字 %s" % [label, nick])
	if str(roster[bots[0]].name) != "人机1":
		return _fail("%s 第一个名字 %s" % [label, str(roster[bots[0]].name)])
	return true


func _same_fighters(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k):
			return false
		if str(a[k].get("name", "")) != str(b[k].get("name", "")):
			return false
		if int(a[k].get("color_idx", -1)) != int(b[k].get("color_idx", -2)):
			return false
		if bool(a[k].get("bot", false)) != bool(b[k].get("bot", false)):
			return false
	return true


func _solo_scene() -> void:
	var gs = root.get_node("GameState")
	gs.reset_lobby()
	gs.solo_bot = true
	gs.players = {
		1: {"name": "我", "color_idx": 0, "ready": true},
	}
	gs.host_peer_id = 1
	gs.in_match = true
	gs.map_id = 0
	gs.soft_seed = 1
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	# 出生角在 _ready 里分配。要在 _process 让人机走开之前检查。
	if not _expect_scene(game, gs, 1):
		return
	await process_frame
	await process_frame
	if str(game.status_label.text).find("人机") < 0:
		_fail("状态：%s" % game.status_label.text)
		return
	var start: Vector2i = game.player_nodes[MatchBot.PEER_ID].get_meta("cell")
	var human: Vector2i = game.player_nodes[1].get_meta("cell")
	for _i in 6:
		for raw in MatchFill.bot_ids(game.match_roster):
			game.player_stats[int(raw)].move_cd = 0.0
		game._tick_bot(0.0)
	var after: Vector2i = game.player_nodes[MatchBot.PEER_ID].get_meta("cell")
	if after == start and game.bombs.is_empty():
		_fail("人机没有任何行动")
		return
	if game.player_nodes[1].get_meta("cell") != human:
		_fail("人机把真人移动了")
		return
	if not _expect_scene_counts(game, gs, 2):
		return
	if not _expect_scene_counts(game, gs, 3):
		return
	if not _expect_full_humans(game, gs):
		return
	if not _expect_rematch_refill(game, gs):
		return
	# 同一帧两颗影子：第二颗不能被改名，也不能漏掉。
	game._show_bomb_ghost(human)
	game._show_bomb_ghost(human)
	if game._ghost_node == null or str(game._ghost_node.name) != "BombGhost":
		_fail("影子不见了或被改名：%s" % str(game._ghost_node))
		return
	var ghost: Node2D = game._ghost_node
	game._clear_bomb_ghost()
	await process_frame
	if is_instance_valid(ghost):
		_fail("清掉之后影子还在")
		return
	print("[verify_bot] 影子炸弹通过")
	var audio := root.get_node("Audio")
	audio.play_boom()
	if not ResourceLoader.exists(audio.sfx_path("boom")):
		_fail("爆炸采样缺失")
		return
	print("[verify_bot] 单机场景通过")
	print("[verify_bot] 成功")
	quit(0)


func _expect_scene(game, gs, human_count: int) -> bool:
	if game.player_nodes.size() != 4 or game.match_roster.size() != 4:
		return _fail("场景角色 节点=%d 名单=%d" % [game.player_nodes.size(), game.match_roster.size()])
	if gs.players.size() != human_count:
		return _fail("大厅名单涨到了 %d" % gs.players.size())
	var spawns := Arena.spawn_cells()
	var seats: Array = MatchFill.seat_order(game.match_roster)
	if seats.size() != 4:
		return _fail("座位 %s" % str(seats))
	for i in seats.size():
		var id := int(seats[i])
		if not game.player_nodes.has(id):
			return _fail("缺少角色 %d" % id)
		var node: Node2D = game.player_nodes[id]
		if node.get_meta("cell") != spawns[i]:
			return _fail("出生 %d 编号 %d 格子 %s" % [i, id, str(node.get_meta("cell"))])
		var is_bot := MatchFill.is_bot_id(id)
		if bool(node.get_meta("bot")) != is_bot:
			return _fail("人机 meta 编号 %d" % id)
		if is_bot and gs.players.has(id):
			return _fail("人机占了大厅座位 %d" % id)
		var shown := _pawn_label(node)
		if shown != str(game.match_roster[id].get("name", "")):
			return _fail("标签 %s != %s" % [shown, str(game.match_roster[id].name)])
		if is_bot and not shown.begins_with("人机"):
			return _fail("人机标签 %s" % shown)
	print("[verify_bot] 场景真人=%d 通过" % human_count)
	return true


func _expect_scene_counts(game, gs, human_count: int) -> bool:
	var humans := {}
	for i in human_count:
		humans[20 + i] = {"name": "测%d" % i, "color_idx": i, "ready": true}
	gs.players = humans
	game._restart_match()
	return _expect_scene(game, gs, human_count)


func _expect_full_humans(game, gs) -> bool:
	var humans := {}
	for i in 4:
		humans[30 + i] = {"name": "满%d" % i, "color_idx": i, "ready": true}
	gs.players = humans
	game._restart_match()
	if not MatchFill.bot_ids(game.match_roster).is_empty() or game.player_nodes.size() != 4:
		return _fail("4 个真人被加了人机")
	if gs.players.size() != 4:
		return _fail("4 人大厅人数 %d" % gs.players.size())
	var spawns := Arena.spawn_cells()
	var seats: Array = MatchFill.seat_order(game.match_roster)
	for i in seats.size():
		if game.player_nodes[int(seats[i])].get_meta("cell") != spawns[i]:
			return _fail("满员真人的出生点挪了")
		if bool(game.player_nodes[int(seats[i])].get_meta("bot")):
			return _fail("真人被标成人机")
	print("[verify_bot] 4 个真人未改通过")
	return true


func _expect_rematch_refill(game, gs) -> bool:
	gs.players = {
		41: {"name": "甲", "color_idx": 0, "ready": true},
		44: {"name": "乙", "color_idx": 2, "ready": true},
	}
	game._restart_match()
	if not _expect_scene(game, gs, 2):
		return false
	# 下一局开始前有真人离开。补位跟着还坐着的人走。
	gs.players.erase(44)
	game._restart_match()
	if not _expect_scene(game, gs, 1):
		return false
	if str(game.status_label.text).find("人机1") < 0:
		return _fail("再来一局状态：%s" % game.status_label.text)
	print("[verify_bot] 再来一局补位通过")
	return true


func _pawn_label(node: Node2D) -> String:
	for child in node.get_children():
		if child is Label:
			return str(child.text)
	return ""


func _empty(cols: int, rows: int) -> Array:
	var grid: Array = []
	for y in rows:
		var row: Array = []
		for x in cols:
			var hard := x == 0 or y == 0 or x == cols - 1 or y == rows - 1
			row.append(1 if hard else 0)
		grid.append(row)
	return grid


func _fail(msg: String) -> bool:
	push_error("[verify_bot] 失败：%s" % msg)
	quit(1)
	return false
