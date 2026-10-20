extends SceneTree
## Headless: Arena multi-map layouts, seed reproducibility, spawn escapes.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_clamp():
		quit(1)
		return
	if not _test_names():
		quit(1)
		return
	if not _test_layouts_differ():
		quit(1)
		return
	if not _test_border_and_spawns():
		quit(1)
		return
	if not _test_seed_repro():
		quit(1)
		return
	if not _test_spawn_escapes():
		quit(1)
		return
	if not _test_cross_maze_not_blocking():
		quit(1)
		return
	if not _test_empty_grid_alias():
		quit(1)
		return
	if not _test_game_state_resolve():
		quit(1)
		return
	print("[verify_maps] SUCCESS")
	quit(0)


func _fail(msg: String) -> bool:
	push_error("[verify_maps] FAIL: %s" % msg)
	return false


func _test_clamp() -> bool:
	if Arena.clamp_map_id(-3) != 0:
		return _fail("clamp negative")
	if Arena.clamp_map_id(99) != int(Arena.MapId.MAZE):
		return _fail("clamp high")
	if Arena.clamp_map_id(2) != 2:
		return _fail("clamp mid")
	print("[verify_maps] clamp OK")
	return true


func _test_names() -> bool:
	var expected := {
		0: "经典",
		1: "开阔",
		2: "十字",
		3: "迷宫",
	}
	for id in expected.keys():
		if Arena.map_name(id) != expected[id]:
			return _fail("map_name %s" % id)
		if Arena.map_desc(id).is_empty():
			return _fail("empty desc %s" % id)
	print("[verify_maps] names OK")
	return true


func _count_hard(grid: Array) -> int:
	return Arena.count_hard(grid)


func _hard_fingerprint(grid: Array) -> String:
	var parts: PackedStringArray = []
	for y in Arena.ROWS:
		for x in Arena.COLS:
			if int(grid[y][x]) == Arena.CELL_HARD:
				parts.append("%d,%d" % [x, y])
	return "|".join(parts)


func _test_layouts_differ() -> bool:
	var grids: Dictionary = {}
	var counts: Dictionary = {}
	for id in range(4):
		grids[id] = Arena.build_base_grid(id)
		counts[id] = _count_hard(grids[id])
	# OPEN should be fewest hard (border only = 13*2 + 11*2 - 4 corners = 44)
	if counts[1] >= counts[0]:
		return _fail("OPEN should have fewer hard than CLASSIC (%d vs %d)" % [counts[1], counts[0]])
	if counts[2] <= counts[0]:
		return _fail("CROSS should have more hard than CLASSIC (%d vs %d)" % [counts[2], counts[0]])
	if counts[3] <= counts[0]:
		return _fail("MAZE should have more hard than CLASSIC (%d vs %d)" % [counts[3], counts[0]])
	var fps: Dictionary = {}
	for id in range(4):
		fps[id] = _hard_fingerprint(grids[id])
	for a in range(4):
		for b in range(a + 1, 4):
			if fps[a] == fps[b]:
				return _fail("layouts %d and %d identical hard pattern" % [a, b])
	print("[verify_maps] layouts differ OK hard=", counts)
	return true


func _test_border_and_spawns() -> bool:
	for id in range(4):
		var grid: Array = Arena.build_base_grid(id)
		for x in Arena.COLS:
			if int(grid[0][x]) != Arena.CELL_HARD or int(grid[Arena.ROWS - 1][x]) != Arena.CELL_HARD:
				return _fail("border row hard map %d" % id)
		for y in Arena.ROWS:
			if int(grid[y][0]) != Arena.CELL_HARD or int(grid[y][Arena.COLS - 1]) != Arena.CELL_HARD:
				return _fail("border col hard map %d" % id)
		for s in Arena.spawn_cells():
			if int(grid[s.y][s.x]) != Arena.CELL_EMPTY:
				return _fail("spawn not empty map %d at %s" % [id, s])
	print("[verify_maps] border+spawns OK")
	return true


func _test_seed_repro() -> bool:
	for id in range(4):
		var a: Array = Arena.build_match_grid(id, 424242)
		var b: Array = Arena.build_match_grid(id, 424242)
		var c: Array = Arena.build_match_grid(id, 424243)
		for y in Arena.ROWS:
			for x in Arena.COLS:
				if int(a[y][x]) != int(b[y][x]):
					return _fail("same seed not reproducible map %d" % id)
		var differ := false
		for y in Arena.ROWS:
			for x in Arena.COLS:
				if int(a[y][x]) != int(c[y][x]):
					differ = true
					break
			if differ:
				break
		if not differ and id != 1:
			# OPEN has many empty cells so soft walls almost always differ; still check
			pass
		if not differ:
			# Soft chance may coincidentally match on tiny empty sets; require soft count > 0 then differ
			var soft_n := 0
			for y in Arena.ROWS:
				for x in Arena.COLS:
					if int(a[y][x]) == Arena.CELL_SOFT:
						soft_n += 1
			if soft_n > 0:
				return _fail("different seeds produced identical grids map %d" % id)
		# Soft never on spawn clear
		var clear := Arena.spawn_clear_cells()
		for cell in clear.keys():
			var c2: Vector2i = cell
			if int(a[c2.y][c2.x]) == Arena.CELL_SOFT:
				return _fail("soft on spawn-clear map %d cell %s" % [id, c2])
	print("[verify_maps] seed repro OK")
	return true


func _test_spawn_escapes() -> bool:
	for id in range(4):
		var grid: Array = Arena.build_match_grid(id, 7)
		for s in Arena.spawn_cells():
			var open_n := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = s + d
				if n.x < 0 or n.y < 0 or n.x >= Arena.COLS or n.y >= Arena.ROWS:
					continue
				if int(grid[n.y][n.x]) == Arena.CELL_EMPTY:
					open_n += 1
			if open_n < 2:
				return _fail("spawn escape blocked map %d at %s open=%d" % [id, s, open_n])
	print("[verify_maps] spawn escapes OK")
	return true


func _reachable_from_spawns(grid: Array) -> bool:
	## BFS from each spawn; every other spawn must be reachable through EMPTY cells.
	var spawns := Arena.spawn_cells()
	for start in spawns:
		var seen: Dictionary = {}
		var q: Array[Vector2i] = [start]
		seen[start] = true
		while not q.is_empty():
			var cur: Vector2i = q.pop_front()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = cur + d
				if n.x < 0 or n.y < 0 or n.x >= Arena.COLS or n.y >= Arena.ROWS:
					continue
				if seen.has(n):
					continue
				if int(grid[n.y][n.x]) != Arena.CELL_EMPTY:
					continue
				seen[n] = true
				q.append(n)
		for other in spawns:
			if not seen.has(other):
				return false
	return true


func _test_cross_maze_not_blocking() -> bool:
	# Hard layout only (no soft) must keep all four corners mutually reachable.
	for id in [int(Arena.MapId.CROSS), int(Arena.MapId.MAZE), int(Arena.MapId.CLASSIC), int(Arena.MapId.OPEN)]:
		var grid: Array = Arena.build_base_grid(id)
		if not _reachable_from_spawns(grid):
			return _fail("hard layout isolates corners map %d" % id)
	print("[verify_maps] CROSS/MAZE traversable OK")
	return true


func _test_empty_grid_alias() -> bool:
	var a: Array = Arena.empty_grid()
	var b: Array = Arena.build_base_grid(Arena.MapId.CLASSIC)
	if _hard_fingerprint(a) != _hard_fingerprint(b):
		return _fail("empty_grid != CLASSIC")
	print("[verify_maps] empty_grid alias OK")
	return true


func _test_game_state_resolve() -> bool:
	var gs = root.get_node("GameState")
	gs.seed_input = ""
	gs.soft_seed = -1
	var s1: int = gs.resolve_soft_seed()
	if s1 < 0:
		return _fail("resolve empty seed negative")
	if gs.soft_seed != s1:
		return _fail("soft_seed not stored")
	# Second call keeps same
	if gs.resolve_soft_seed() != s1:
		return _fail("resolve not sticky")
	gs.soft_seed = -1
	gs.seed_input = "12345"
	var s2: int = gs.resolve_soft_seed()
	if s2 != 12345:
		return _fail("fixed seed parse got %d" % s2)
	gs.soft_seed = -1
	gs.seed_input = "abc"
	var s3: int = gs.resolve_soft_seed()
	if s3 < 0:
		return _fail("non-int should randomize")
	gs.set_map_id(99)
	if gs.map_id != int(Arena.MapId.MAZE):
		return _fail("set_map_id clamp")
	print("[verify_maps] GameState resolve OK")
	return true
