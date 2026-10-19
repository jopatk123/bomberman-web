extends SceneTree
## Headless: powerup apply/caps + rematch reset.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.players = {1: {"name": "测试", "color_idx": 0}}
	gs.in_match = true

	var ps: PackedScene = load("res://scenes/game.tscn")
	var game = ps.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	if game.player_stats.is_empty():
		push_error("[verify_pu] FAIL: no player_stats after ready")
		quit(1)
		return
	var pid: int = int(game.player_stats.keys()[0])
	var st0: Dictionary = game.player_stats[pid].duplicate()
	print("[verify_pu] base stats bombs=", st0.bombs, " range=", st0.range, " speed=", st0.speed)

	game._apply_powerup(pid, 0)
	game._apply_powerup(pid, 1)
	game._apply_powerup(pid, 2)
	var st1: Dictionary = game.player_stats[pid]
	if int(st1.bombs) != int(st0.bombs) + 1:
		push_error("[verify_pu] FAIL: bomb+")
		quit(1)
		return
	if int(st1.range) != int(st0.range) + 1:
		push_error("[verify_pu] FAIL: range+")
		quit(1)
		return
	if int(st1.speed) != int(st0.speed) + 1:
		push_error("[verify_pu] FAIL: speed+")
		quit(1)
		return
	print("[verify_pu] powerup apply OK ->", st1)

	for i in 10:
		game._apply_powerup(pid, 0)
		game._apply_powerup(pid, 1)
		game._apply_powerup(pid, 2)
	st1 = game.player_stats[pid]
	if int(st1.bombs) != game.MAX_BOMBS or int(st1.range) != game.MAX_RANGE or int(st1.speed) != game.MAX_SPEED_LVL:
		push_error("[verify_pu] FAIL: caps bombs=%s range=%s speed=%s" % [st1.bombs, st1.range, st1.speed])
		quit(1)
		return
	print("[verify_pu] caps OK")

	var soft := Vector2i(-1, -1)
	for y in game.ROWS:
		for x in game.COLS:
			if game.grid[y][x] == game.Cell.SOFT:
				soft = Vector2i(x, y)
				break
		if soft.x >= 0:
			break
	if soft.x < 0:
		push_error("[verify_pu] FAIL: no soft walls")
		quit(1)
		return

	game.grid[soft.y][soft.x] = game.Cell.EMPTY
	var npid: int = int(game.next_powerup_id)
	game.next_powerup_id = npid + 1
	game.powerups[npid] = {"x": soft.x, "y": soft.y, "kind": 0}
	game._spawn_powerup_visual(npid, soft, 0)
	await process_frame
	if game.powerups_layer.get_child_count() < 1:
		push_error("[verify_pu] FAIL: powerup visual missing")
		quit(1)
		return
	print("[verify_pu] powerup visual OK count=", game.powerups_layer.get_child_count())

	# Walk-over pickup
	game.player_nodes[pid].set_meta("cell", soft)
	game._try_pickup_at(pid, soft)
	if game.powerups.has(npid):
		push_error("[verify_pu] FAIL: powerup not consumed")
		quit(1)
		return
	print("[verify_pu] pickup OK stats=", game.player_stats[pid])

	game._restart_match()
	await process_frame
	if game.match_over:
		push_error("[verify_pu] FAIL: still match_over after rematch")
		quit(1)
		return
	if not game.powerups.is_empty():
		push_error("[verify_pu] FAIL: powerups not cleared on rematch")
		quit(1)
		return
	var st2: Dictionary = game.player_stats[pid]
	if int(st2.bombs) != game.BASE_BOMBS or int(st2.range) != game.BASE_BLAST:
		push_error("[verify_pu] FAIL: stats not reset on rematch %s" % st2)
		quit(1)
		return
	print("[verify_pu] rematch reset OK")
	print("[verify_pu] SUCCESS")
	quit(0)
