extends SceneTree
## Headless: solo bot decisions, client move-ack, and the bot actually acting in a match.

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
		return _fail("bot stood on its blast: %s" % str(flee))
	if absi(int(flee.dx)) + absi(int(flee.dy)) != 1:
		return _fail("flee step: %s" % str(flee))
	print("[verify_bot] flee OK")

	grid[3][4] = 2
	var place := MatchBot.decide({
		"grid": grid, "cols": 9, "rows": 9, "cell": bot,
		"blast_range": 2, "can_place": true,
		"bombs": [], "others": [Vector2i(7, 7)], "lethal": [],
	})
	if int(place.action) != MatchBot.Action.BOMB:
		return _fail("bot did not bomb adjacent soft: %s" % str(place))
	print("[verify_bot] place OK")

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
		return _fail("bot bombed a dead-end corridor")
	print("[verify_bot] no dead-end bomb OK")

	var safe := _empty(9, 9)
	safe[3][5] = 2
	var around := MatchBot.decide({
		"grid": safe, "cols": 9, "rows": 9, "cell": Vector2i(3, 3),
		"blast_range": 2, "can_place": false,
		"bombs": [{"x": 1, "y": 3, "timer": 0.3, "range": 1, "pierce": false}],
		"others": [], "lethal": [Vector2i(3, 4)],
	})
	# Soft is to the right. Down is lethal. Left is inside the range-1 blast.
	if int(around.action) != MatchBot.Action.MOVE or int(around.dx) != 1 or int(around.dy) != 0:
		return _fail("bot did not walk toward soft, clear of fire: %s" % str(around))
	print("[verify_bot] avoid danger OK")

	var pickup := _empty(9, 9)
	var grabbed := MatchBot.decide({
		"grid": pickup, "cols": 9, "rows": 9, "cell": Vector2i(3, 3),
		"blast_range": 2, "can_place": true,
		"bombs": [], "others": [], "lethal": [],
		"powerups": [Vector2i(3, 4)],
	})
	if int(grabbed.action) != MatchBot.Action.MOVE or int(grabbed.dx) != 0 or int(grabbed.dy) != 1:
		return _fail("bot skipped an adjacent powerup: %s" % str(grabbed))
	print("[verify_bot] powerup OK")
	return true


func _predict() -> bool:
	var a := Vector2i(1, 1)
	var b := Vector2i(2, 1)
	var c := Vector2i(3, 1)
	var mid: Dictionary = MovePredict.ack([a, b, c], b)
	if mid.chain.size() != 2 or mid.chain[0] != b or mid.show != c:
		return _fail("ack trim: %s" % str(mid))
	var rejected: Dictionary = MovePredict.ack([a, b], a)
	if rejected.chain.size() != 1 or rejected.show != a:
		return _fail("ack reject: %s" % str(rejected))
	var snapped: Dictionary = MovePredict.ack([a, b], Vector2i(8, 8))
	if snapped.show != Vector2i(8, 8):
		return _fail("ack snap: %s" % str(snapped))
	var same: Dictionary = MovePredict.ack([b], b)
	if same.show != b or same.chain.size() != 1:
		return _fail("ack same: %s" % str(same))
	print("[verify_bot] predict ack OK")
	return true


func _fill_rules() -> bool:
	if MatchFill.bot_peer_id(1) != MatchBot.PEER_ID:
		return _fail("first bot id drifted from MatchBot.PEER_ID")
	var src := {
		1: {"name": "甲", "color_idx": 0, "ready": true},
	}
	var filled := MatchFill.fill(src)
	if src.size() != 1 or src.has(MatchBot.PEER_ID):
		return _fail("fill mutated the lobby roster")
	if not _expect_fill(filled, 1, "1 human"):
		return false
	var again := MatchFill.fill(filled)
	if not _same_fighters(filled, again):
		return _fail("fill was not idempotent: %s vs %s" % [str(filled), str(again)])
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
		return _fail("4 humans were padded: %s" % str(full))
	var seats: Array = MatchFill.seat_order(full)
	if seats != [1, 2, 3, 4]:
		return _fail("4 human seats reshuffled: %s" % str(seats))
	print("[verify_bot] fill rules OK")
	return true


func _expect_fill(roster: Dictionary, human_count: int, label: String) -> bool:
	if roster.size() != 4:
		return _fail("%s size %d" % [label, roster.size()])
	var bots: Array = MatchFill.bot_ids(roster)
	if bots.size() != 4 - human_count:
		return _fail("%s bots %s" % [label, str(bots)])
	var humans := MatchFill.humans(roster)
	if humans.size() != human_count:
		return _fail("%s humans left %d" % [label, humans.size()])
	for id in bots:
		var entry: Dictionary = roster[id]
		if not bool(entry.get("bot", false)) or not MatchFill.is_bot_id(int(id)):
			return _fail("%s bot not marked: %s" % [label, str(entry)])
		var nick := str(entry.get("name", ""))
		if not nick.begins_with("人机"):
			return _fail("%s name %s" % [label, nick])
	if str(roster[bots[0]].name) != "人机1":
		return _fail("%s first label %s" % [label, str(roster[bots[0]].name)])
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
	# Spawn corners are assigned in _ready. Check them before _process lets bots walk.
	if not _expect_scene(game, gs, 1):
		return
	await process_frame
	await process_frame
	if str(game.status_label.text).find("人机") < 0:
		_fail("status: %s" % game.status_label.text)
		return
	var start: Vector2i = game.player_nodes[MatchBot.PEER_ID].get_meta("cell")
	var human: Vector2i = game.player_nodes[1].get_meta("cell")
	for _i in 6:
		for raw in MatchFill.bot_ids(game.match_roster):
			game.player_stats[int(raw)].move_cd = 0.0
		game._tick_bot(0.0)
	var after: Vector2i = game.player_nodes[MatchBot.PEER_ID].get_meta("cell")
	if after == start and game.bombs.is_empty():
		_fail("bot took no action")
		return
	if game.player_nodes[1].get_meta("cell") != human:
		_fail("bot moved the human")
		return
	if not _expect_scene_counts(game, gs, 2):
		return
	if not _expect_scene_counts(game, gs, 3):
		return
	if not _expect_full_humans(game, gs):
		return
	if not _expect_rematch_refill(game, gs):
		return
	# Two ghosts in one frame: the second must not be renamed or leak.
	game._show_bomb_ghost(human)
	game._show_bomb_ghost(human)
	if game._ghost_node == null or str(game._ghost_node.name) != "BombGhost":
		_fail("ghost missing or renamed: %s" % str(game._ghost_node))
		return
	var ghost: Node2D = game._ghost_node
	game._clear_bomb_ghost()
	await process_frame
	if is_instance_valid(ghost):
		_fail("ghost survived clear")
		return
	print("[verify_bot] bomb ghost OK")
	var wav: PackedFloat32Array = game._sfx._boom_samples()
	if wav.is_empty():
		_fail("boom sample empty")
		return
	print("[verify_bot] solo scene OK")
	print("[verify_bot] SUCCESS")
	quit(0)


func _expect_scene(game, gs, human_count: int) -> bool:
	if game.player_nodes.size() != 4 or game.match_roster.size() != 4:
		return _fail("scene fighters nodes=%d roster=%d" % [game.player_nodes.size(), game.match_roster.size()])
	if gs.players.size() != human_count:
		return _fail("lobby roster grew to %d" % gs.players.size())
	var spawns := Arena.spawn_cells()
	var seats: Array = MatchFill.seat_order(game.match_roster)
	if seats.size() != 4:
		return _fail("seats %s" % str(seats))
	for i in seats.size():
		var id := int(seats[i])
		if not game.player_nodes.has(id):
			return _fail("missing fighter %d" % id)
		var node: Node2D = game.player_nodes[id]
		if node.get_meta("cell") != spawns[i]:
			return _fail("spawn %d id %d cell %s" % [i, id, str(node.get_meta("cell"))])
		var is_bot := MatchFill.is_bot_id(id)
		if bool(node.get_meta("bot")) != is_bot:
			return _fail("bot meta id %d" % id)
		if is_bot and gs.players.has(id):
			return _fail("bot seated in lobby %d" % id)
		var shown := _pawn_label(node)
		if shown != str(game.match_roster[id].get("name", "")):
			return _fail("label %s != %s" % [shown, str(game.match_roster[id].name)])
		if is_bot and not shown.begins_with("人机"):
			return _fail("bot label %s" % shown)
	print("[verify_bot] scene humans=%d OK" % human_count)
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
		return _fail("4 humans gained bots")
	if gs.players.size() != 4:
		return _fail("4 human lobby %d" % gs.players.size())
	var spawns := Arena.spawn_cells()
	var seats: Array = MatchFill.seat_order(game.match_roster)
	for i in seats.size():
		if game.player_nodes[int(seats[i])].get_meta("cell") != spawns[i]:
			return _fail("full human spawn shifted")
		if bool(game.player_nodes[int(seats[i])].get_meta("bot")):
			return _fail("human marked bot")
	print("[verify_bot] 4 humans unchanged OK")
	return true


func _expect_rematch_refill(game, gs) -> bool:
	gs.players = {
		41: {"name": "甲", "color_idx": 0, "ready": true},
		44: {"name": "乙", "color_idx": 2, "ready": true},
	}
	game._restart_match()
	if not _expect_scene(game, gs, 2):
		return false
	# A human leaves before the next round. Fill follows whoever is still seated.
	gs.players.erase(44)
	game._restart_match()
	if not _expect_scene(game, gs, 1):
		return false
	if str(game.status_label.text).find("人机1") < 0:
		return _fail("rematch status: %s" % game.status_label.text)
	print("[verify_bot] rematch refill OK")
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
	push_error("[verify_bot] FAIL: %s" % msg)
	quit(1)
	return false
