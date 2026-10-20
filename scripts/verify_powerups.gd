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
	if int(st0.get("pierce", -1)) != 0:
		push_error("[verify_pu] FAIL: base pierce should be 0")
		quit(1)
		return
	if not str(game.help_label.text).contains("黄P穿透"):
		push_error("[verify_pu] FAIL: help text missing 黄P穿透")
		quit(1)
		return

	game._apply_powerup(pid, 0)
	game._apply_powerup(pid, 1)
	game._apply_powerup(pid, 2)
	game._apply_powerup(pid, game.PKind.PIERCE)
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
	if int(st1.pierce) != 1:
		push_error("[verify_pu] FAIL: pierce+")
		quit(1)
		return
	game._apply_powerup(pid, game.PKind.PIERCE)
	if int(game.player_stats[pid].pierce) != 1:
		push_error("[verify_pu] FAIL: pierce should stay 1")
		quit(1)
		return
	game._refresh_stats_hud()
	if not str(game.stats_label.text).contains("穿透 开"):
		push_error("[verify_pu] FAIL: stats HUD missing 穿透 开")
		quit(1)
		return
	var pack: PackedInt32Array = game._stats_pack(pid)
	if pack.size() != 5 or int(pack[4]) != 1:
		push_error("[verify_pu] FAIL: stats pack pierce %s" % pack)
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

	game._spawn_powerup_visual(4242, soft, game.PKind.PIERCE)
	var pierce_vis: Node = game.powerups_layer.get_node_or_null("Powerup_4242")
	if pierce_vis == null:
		push_error("[verify_pu] FAIL: pierce visual missing")
		quit(1)
		return
	var pierce_label := ""
	var pierce_color := Color.BLACK
	for child in pierce_vis.get_children():
		if child is Label:
			pierce_label = str(child.text)
		if child is Polygon2D and pierce_color == Color.BLACK:
			pierce_color = (child as Polygon2D).color
	if pierce_label != "P":
		push_error("[verify_pu] FAIL: pierce label got %s" % pierce_label)
		quit(1)
		return
	if pierce_color.r < 0.8 or pierce_color.g < 0.6 or pierce_color.b > 0.4:
		push_error("[verify_pu] FAIL: pierce color not gold %s" % pierce_color)
		quit(1)
		return
	pierce_vis.queue_free()
	print("[verify_pu] pierce visual OK")

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
	if int(st2.get("pierce", -1)) != 0:
		push_error("[verify_pu] FAIL: pierce not reset on rematch %s" % st2)
		quit(1)
		return
	if not str(game.stats_label.text).contains("穿透 关"):
		push_error("[verify_pu] FAIL: rematch HUD still shows pierce on")
		quit(1)
		return
	var synced := PackedInt32Array([3, 4, 1, 1, 1])
	game._rpc_pickup(pid, 99999, game.PKind.PIERCE, synced)
	var st3: Dictionary = game.player_stats[pid]
	if int(st3.bombs) != 3 or int(st3.range) != 4 or int(st3.speed) != 1 or int(st3.kick) != 1 or int(st3.pierce) != 1:
		push_error("[verify_pu] FAIL: pierce stats pack not applied %s" % st3)
		quit(1)
		return
	game._rpc_pickup(pid, 99998, 0, PackedInt32Array([2, 3, 0, 0]))
	if int(game.player_stats[pid].get("pierce", 0)) != 1:
		push_error("[verify_pu] FAIL: short stats pack cleared pierce")
		quit(1)
		return
	game._rpc_pickup(pid, 99997, game.PKind.PIERCE, PackedInt32Array([2, 3, 0, 0, 0]))
	if int(game.player_stats[pid].get("pierce", 1)) != 0:
		push_error("[verify_pu] FAIL: stats pack did not clear pierce")
		quit(1)
		return
	print("[verify_pu] rematch reset OK")
	print("[verify_pu] SUCCESS")
	quit(0)
