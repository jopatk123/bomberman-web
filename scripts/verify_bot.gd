extends SceneTree
## Headless: solo bot decisions, client move-ack, and the bot actually acting in a match.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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


func _solo_scene() -> void:
	var gs = root.get_node("GameState")
	gs.reset_lobby()
	gs.solo_bot = true
	gs.players = {
		1: {"name": "我", "color_idx": 0, "ready": true},
		MatchBot.PEER_ID: {"name": MatchBot.NAME, "color_idx": 1, "ready": true},
	}
	gs.host_peer_id = 1
	gs.in_match = true
	gs.map_id = 0
	gs.soft_seed = 1
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	if not game.player_nodes.has(MatchBot.PEER_ID):
		_fail("bot was not spawned")
		return
	if str(game.status_label.text).find("电脑") < 0:
		_fail("status: %s" % game.status_label.text)
		return
	var start: Vector2i = game.player_nodes[MatchBot.PEER_ID].get_meta("cell")
	var human: Vector2i = game.player_nodes[1].get_meta("cell")
	for _i in 6:
		game.player_stats[MatchBot.PEER_ID].move_cd = 0.0
		game._tick_bot(0.0)
	var after: Vector2i = game.player_nodes[MatchBot.PEER_ID].get_meta("cell")
	if after == start and game.bombs.is_empty():
		_fail("bot took no action")
		return
	if game.player_nodes[1].get_meta("cell") != human:
		_fail("bot moved the human")
		return
	var wav: PackedFloat32Array = game._sfx._boom_samples()
	if wav.is_empty():
		_fail("boom sample empty")
		return
	print("[verify_bot] solo scene OK")
	print("[verify_bot] SUCCESS")
	quit(0)


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
