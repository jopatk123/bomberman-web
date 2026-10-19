extends SceneTree
## Headless smoke: owner bomb-pass, kick slide blocked by hard, sudden death, rematch clears fire.

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

	var pid: int = 1
	if not game.player_nodes.has(pid):
		push_error("[verify_feel] FAIL: no player")
		quit(1)
		return

	# --- 1) Owner bomb-pass: place bomb, walk off same cell ---
	var start: Vector2i = game.player_nodes[pid].get_meta("cell")
	# Clear move cd
	game.player_stats[pid].move_cd = 0.0
	game._try_place_bomb(pid)
	if game.bombs.is_empty():
		push_error("[verify_feel] FAIL: bomb not placed")
		quit(1)
		return
	var bid: int = int(game.bombs.keys()[0])
	if bool(game.bombs[bid].get("solid", true)):
		push_error("[verify_feel] FAIL: new bomb should be non-solid for owner")
		quit(1)
		return
	# Find open adjacent empty cell
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var moved := false
	for d in dirs:
		var nxt: Vector2i = start + d
		if game._walkable(nxt) and game._bomb_id_at(nxt) < 0:
			game.player_stats[pid].move_cd = 0.0
			game._apply_move(pid, d.x, d.y)
			moved = true
			break
	if not moved:
		push_error("[verify_feel] FAIL: could not walk off bomb (no free adj)")
		quit(1)
		return
	var after: Vector2i = game.player_nodes[pid].get_meta("cell")
	if after == start:
		push_error("[verify_feel] FAIL: owner could not leave bomb cell")
		quit(1)
		return
	if not bool(game.bombs[bid].get("solid", false)):
		push_error("[verify_feel] FAIL: bomb should solidify after owner leaves")
		quit(1)
		return
	print("[verify_feel] owner bomb-pass OK")

	# --- 2) Kick slide blocked by hard ---
	# Grant kick, place bomb on a cell next to a hard wall and kick into wall
	game.player_stats[pid].kick = 1
	game.player_stats[pid].move_cd = 0.0
	# Clear old bombs
	game.bombs.clear()
	game._clear_bomb_visuals()
	# Put player at (1,1) — right of left border hard; try kick left into hard
	game.player_nodes[pid].set_meta("cell", Vector2i(1, 1))
	game.player_nodes[pid].position = game._cell_to_pos(Vector2i(1, 1))
	# Place bomb at (2,1), player at (1,1), kick right... need bomb between player and wall
	# Setup: bomb at (1,1), player at (2,1), kick left toward (0,1) HARD
	game.bombs[99] = {
		"x": 1, "y": 1, "owner": pid, "timer": 99.0, "range": 2,
		"solid": true, "slide_dx": 0, "slide_dy": 0, "slide_cd": 0.0,
	}
	game._spawn_bomb_visual(99, Vector2i(1, 1))
	game.player_nodes[pid].set_meta("cell", Vector2i(2, 1))
	game.player_stats[pid].move_cd = 0.0
	var kicked: bool = game._try_kick_bomb(99, -1, 0) # toward hard border
	if kicked:
		push_error("[verify_feel] FAIL: kick into hard should fail")
		quit(1)
		return
	if int(game.bombs[99].x) != 1 or int(game.bombs[99].y) != 1:
		push_error("[verify_feel] FAIL: bomb moved when kick into hard")
		quit(1)
		return
	# Kick into open space should succeed — (3,1) if empty
	# Player at (2,1), bomb at (3,1), kick +x
	game.bombs.erase(99)
	game._clear_bomb_visuals()
	# Find an empty corridor for kick
	var kick_ok := false
	for y in range(1, game.ROWS - 1):
		for x in range(1, game.COLS - 3):
			if game.grid[y][x] != game.Cell.EMPTY:
				continue
			if game.grid[y][x + 1] != game.Cell.EMPTY:
				continue
			# Place bomb at (x,y), kick +x
			game.bombs[77] = {
				"x": x, "y": y, "owner": pid, "timer": 99.0, "range": 2,
				"solid": true, "slide_dx": 0, "slide_dy": 0, "slide_cd": 0.0,
			}
			if game._try_kick_bomb(77, 1, 0):
				if int(game.bombs[77].x) == x + 1:
					kick_ok = true
					# Next slide into hard pillar if any
					break
			game.bombs.erase(77)
		if kick_ok:
			break
	if not kick_ok:
		push_error("[verify_feel] FAIL: kick into empty failed")
		quit(1)
		return
	print("[verify_feel] kick slide / hard block OK")

	# --- 3) BlastRules: hard stops, soft clears+stops ---
	var g: Array = []
	for y in 5:
		var row: Array = []
		for x in 5:
			row.append(0)
		g.append(row)
	g[2][0] = 1 # HARD left of center
	g[2][4] = 2 # SOFT right
	var r = BlastRules.compute_rays(g, Vector2i(2, 2), 3, 5, 5)
	var hits: Array = r.hit
	var softs: Array = r.cleared_soft
	# Should NOT include (0,2) hard; SHOULD include (4,2) soft and stop
	for h in hits:
		if h == Vector2i(0, 2):
			push_error("[verify_feel] FAIL: blast pierced hard")
			quit(1)
			return
	if Vector2i(4, 2) not in hits:
		push_error("[verify_feel] FAIL: soft not hit")
		quit(1)
		return
	if Vector2i(4, 2) not in softs:
		push_error("[verify_feel] FAIL: soft not cleared list")
		quit(1)
		return
	print("[verify_feel] blast rules OK")

	# --- 4) Sudden death activates ---
	game.sudden.reset()
	game.sudden.elapsed = SuddenDeath.START_AT - 0.01
	game.sudden._pulse_left = 0.0
	var before_lethal: int = game.sudden.lethal.size()
	# Force tick past threshold with interval ready
	var tr: Dictionary = game.sudden.tick(0.05, game.COLS, game.ROWS, game.grid, game.Cell.HARD)
	if not tr.just_activated and not game.sudden.active:
		# need another tick to expand if just activated with pulse
		tr = game.sudden.tick(0.0, game.COLS, game.ROWS, game.grid, game.Cell.HARD)
	# Activate then force pulse
	game.sudden.active = true
	game.sudden._pulse_left = 0.0
	tr = game.sudden.tick(0.01, game.COLS, game.ROWS, game.grid, game.Cell.HARD)
	if game.sudden.lethal.is_empty() and tr.new_cells.is_empty():
		# Apply via game path
		game.sudden.reset()
		game.sudden.elapsed = SuddenDeath.START_AT
		game.sudden.active = false
		game.sudden._pulse_left = 0.0
		game._tick_sudden_death(0.01)
	if not game.sudden.active:
		push_error("[verify_feel] FAIL: sudden death not active")
		quit(1)
		return
	# Force ring expansion
	game.sudden._pulse_left = 0.0
	game._tick_sudden_death(0.01)
	if game.sudden.lethal.is_empty():
		push_error("[verify_feel] FAIL: no lethal cells after SD tick")
		quit(1)
		return
	print("[verify_feel] sudden death OK lethal=", game.sudden.lethal.size(), " (was ", before_lethal, ")")

	# --- 5) Rematch clears fire ---
	game._restart_match()
	await process_frame
	if game.sudden.active or not game.sudden.lethal.is_empty():
		push_error("[verify_feel] FAIL: rematch did not clear SD")
		quit(1)
		return
	if not game._sd_visuals.is_empty():
		push_error("[verify_feel] FAIL: SD visuals remain after rematch")
		quit(1)
		return
	print("[verify_feel] rematch clears fire OK")

	# Kick powerup apply
	game._apply_powerup(pid, game.PKind.KICK)
	if int(game.player_stats[pid].kick) != 1:
		push_error("[verify_feel] FAIL: kick powerup")
		quit(1)
		return
	print("[verify_feel] kick powerup OK")

	# --- 6) KickRules: owner pass, blocked, kick ---
	var sample := {
		1: {"x": 2, "y": 2, "owner": 1, "solid": false},
	}
	var open_slide := func(_dest: Vector2i) -> bool:
		return true
	var shut_slide := func(_dest: Vector2i) -> bool:
		return false
	var enter: int = KickRules.classify_enter(1, sample, 1, false, 1, 0, shut_slide)
	if enter != KickRules.Enter.WALK:
		push_error("[verify_feel] FAIL: owner should walk through own fresh bomb")
		quit(1)
		return
	enter = KickRules.classify_enter(1, sample, 2, false, 1, 0, open_slide)
	if enter != KickRules.Enter.BLOCKED:
		push_error("[verify_feel] FAIL: non-owner without kick must not enter a fresh bomb")
		quit(1)
		return
	enter = KickRules.classify_enter(1, sample, 2, true, 1, 0, open_slide)
	if enter != KickRules.Enter.KICK:
		push_error("[verify_feel] FAIL: kick should move a fresh bomb when dest is open")
		quit(1)
		return
	sample[1]["solid"] = true
	enter = KickRules.classify_enter(1, sample, 2, true, 1, 0, shut_slide)
	if enter != KickRules.Enter.BLOCKED:
		push_error("[verify_feel] FAIL: kick into a blocked cell should stop")
		quit(1)
		return
	enter = KickRules.classify_enter(1, sample, 2, true, 1, 0, open_slide)
	if enter != KickRules.Enter.KICK:
		push_error("[verify_feel] FAIL: kick should be allowed when dest is open")
		quit(1)
		return
	print("[verify_feel] kick classify OK")

	# --- 7) Clock advance does not create lethal cells; sync snaps elapsed ---
	var clock := SuddenDeath.new()
	clock.advance_elapsed(SuddenDeath.START_AT + 5.0)
	if clock.active or not clock.lethal.is_empty():
		push_error("[verify_feel] FAIL: advance_elapsed changed the zone")
		quit(1)
		return
	game._rpc_sync_match_clock(42.0, false)
	if absf(float(game.sudden.elapsed) - 42.0) > 0.001:
		push_error("[verify_feel] FAIL: clock sync did not apply")
		quit(1)
		return
	print("[verify_feel] clock sync OK")

	# --- 8) Shrink ring swallows bomb + powerup without a blast ---
	game.bombs[56] = {
		"x": 4, "y": 1, "owner": pid, "timer": 9.0, "range": 2,
		"solid": true, "slide_dx": 0, "slide_dy": 0, "slide_cd": 0.0,
	}
	game._spawn_bomb_visual(56, Vector2i(4, 1))
	game.powerups[9] = {"x": 4, "y": 1, "kind": 0}
	game._apply_sudden_ring([Vector2i(4, 1)], PackedInt32Array([56]), PackedInt32Array([9]))
	if game.bombs.has(56) or game.powerups.has(9) or not game.sudden.is_lethal(Vector2i(4, 1)):
		push_error("[verify_feel] FAIL: sudden ring did not swallow bomb/powerup")
		quit(1)
		return
	var swallowed: Node = game.entities.get_node_or_null("Bomb_56")
	if swallowed != null and not swallowed.is_queued_for_deletion():
		push_error("[verify_feel] FAIL: swallowed bomb visual remains")
		quit(1)
		return
	print("[verify_feel] sudden ring swallow OK")

	# --- 9) Kick into existing fire detonates ---
	game.player_nodes[pid].set_meta("cell", Vector2i(1, 1))
	game.grid[1][2] = game.Cell.EMPTY
	game.grid[1][3] = game.Cell.EMPTY
	game._repaint_cells([Vector2i(2, 1), Vector2i(3, 1)])
	var tiles_before: int = game.map_layer.get_child_count()
	game.sudden.lethal[Vector2i(3, 1)] = true
	game.bombs[55] = {
		"x": 2, "y": 1, "owner": pid, "timer": 9.0, "range": 1,
		"solid": true, "slide_dx": 0, "slide_dy": 0, "slide_cd": 0.0,
	}
	if not game._try_kick_bomb(55, 1, 0) or game.bombs.has(55):
		push_error("[verify_feel] FAIL: bomb kicked into fire should detonate")
		quit(1)
		return
	if game.map_layer.get_child_count() != tiles_before:
		push_error("[verify_feel] FAIL: repaint rebuilt the map")
		quit(1)
		return
	print("[verify_feel] kick into fire + repaint OK")

	# --- 10) Walking into the blast of a kick-detonation kills ---
	game.alive[pid] = true
	game.player_stats[pid].kick = 1
	game.player_stats[pid].move_cd = 0.0
	game.player_nodes[pid].set_meta("cell", Vector2i(1, 1))
	game.grid[1][2] = game.Cell.EMPTY
	game.grid[1][3] = game.Cell.EMPTY
	game.sudden.lethal[Vector2i(3, 1)] = true
	game.bombs[58] = {
		"x": 2, "y": 1, "owner": pid, "timer": 9.0, "range": 1,
		"solid": true, "slide_dx": 0, "slide_dy": 0, "slide_cd": 0.0,
	}
	game._apply_move(pid, 1, 0)
	if game.alive.get(pid, false):
		push_error("[verify_feel] FAIL: player should die walking into kick-detonation blast")
		quit(1)
		return
	print("[verify_feel] kick blast step-in OK")

	print("[verify_feel] SUCCESS")
	quit(0)
