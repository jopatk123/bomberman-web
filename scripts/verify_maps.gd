extends SceneTree
## 无界面：Arena 多地图布局、种子可复现、出生点能走出来。

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
	print("[verify_maps] 成功")
	quit(0)


func _fail(msg: String) -> bool:
	push_error("[verify_maps] 失败：%s" % msg)
	return false


func _test_clamp() -> bool:
	if Arena.clamp_map_id(-3) != 0:
		return _fail("负数地图编号没有钳住")
	if Arena.clamp_map_id(99) != int(Arena.MapId.MAZE):
		return _fail("过大地图编号没有钳住")
	if Arena.clamp_map_id(2) != 2:
		return _fail("中间地图编号被钳错了")
	print("[verify_maps] 钳制通过")
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
			return _fail("地图名 %s" % id)
		if Arena.map_desc(id).is_empty():
			return _fail("空说明 %s" % id)
	print("[verify_maps] 名称通过")
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
	# 开阔图硬墙应最少（只有围边：13*2 + 11*2 - 4 个角 = 44）。
	if counts[1] >= counts[0]:
		return _fail("开阔图硬墙应少于经典（%d 对 %d）" % [counts[1], counts[0]])
	if counts[2] <= counts[0]:
		return _fail("十字图硬墙应多于经典（%d 对 %d）" % [counts[2], counts[0]])
	if counts[3] <= counts[0]:
		return _fail("迷宫硬墙应多于经典（%d 对 %d）" % [counts[3], counts[0]])
	var fps: Dictionary = {}
	for id in range(4):
		fps[id] = _hard_fingerprint(grids[id])
	for a in range(4):
		for b in range(a + 1, 4):
			if fps[a] == fps[b]:
				return _fail("布局 %d 和 %d 的硬墙图案相同" % [a, b])
	print("[verify_maps] 布局互不相同通过 硬墙=", counts)
	return true


func _test_border_and_spawns() -> bool:
	for id in range(4):
		var grid: Array = Arena.build_base_grid(id)
		for x in Arena.COLS:
			if int(grid[0][x]) != Arena.CELL_HARD or int(grid[Arena.ROWS - 1][x]) != Arena.CELL_HARD:
				return _fail("围边行硬墙 地图 %d" % id)
		for y in Arena.ROWS:
			if int(grid[y][0]) != Arena.CELL_HARD or int(grid[y][Arena.COLS - 1]) != Arena.CELL_HARD:
				return _fail("围边列硬墙 地图 %d" % id)
		for s in Arena.spawn_cells():
			if int(grid[s.y][s.x]) != Arena.CELL_EMPTY:
				return _fail("出生点不是空地 地图 %d 位于 %s" % [id, s])
	print("[verify_maps] 围边和出生点通过")
	return true


func _test_seed_repro() -> bool:
	for id in range(4):
		var a: Array = Arena.build_match_grid(id, 424242)
		var b: Array = Arena.build_match_grid(id, 424242)
		var c: Array = Arena.build_match_grid(id, 424243)
		for y in Arena.ROWS:
			for x in Arena.COLS:
				if int(a[y][x]) != int(b[y][x]):
					return _fail("同一颗种子不能复现 地图 %d" % id)
		var differ := false
		for y in Arena.ROWS:
			for x in Arena.COLS:
				if int(a[y][x]) != int(c[y][x]):
					differ = true
					break
			if differ:
				break
		if not differ and id != 1:
			# 开阔图空格多，软墙几乎总会不一样；还是要查。
			pass
		if not differ:
			# 空格很少时软墙概率可能碰巧一样；先要求软墙数大于 0，再要求不一样。
			var soft_n := 0
			for y in Arena.ROWS:
				for x in Arena.COLS:
					if int(a[y][x]) == Arena.CELL_SOFT:
						soft_n += 1
			if soft_n > 0:
				return _fail("不同种子生成了同一张格子 地图 %d" % id)
		# 出生清场格上不能有软墙。
		var clear := Arena.spawn_clear_cells()
		for cell in clear.keys():
			var c2: Vector2i = cell
			if int(a[c2.y][c2.x]) == Arena.CELL_SOFT:
				return _fail("出生清场格上有软墙 地图 %d 格子 %s" % [id, c2])
	print("[verify_maps] 种子复现通过")
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
				return _fail("出生点走不出 地图 %d 位于 %s 开口=%d" % [id, s, open_n])
	print("[verify_maps] 出生点能离开通过")
	return true


func _reachable_from_spawns(grid: Array) -> bool:
	## 从每个出生点做广度优先搜索；其他出生点必须能沿空地走到。
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
	# 只有硬墙、没有软墙时，四个角也必须互相走得到。
	for id in [int(Arena.MapId.CROSS), int(Arena.MapId.MAZE), int(Arena.MapId.CLASSIC), int(Arena.MapId.OPEN)]:
		var grid: Array = Arena.build_base_grid(id)
		if not _reachable_from_spawns(grid):
			return _fail("硬墙布局把四角隔开了 地图 %d" % id)
	print("[verify_maps] 十字/迷宫可通行通过")
	return true


func _test_empty_grid_alias() -> bool:
	var a: Array = Arena.empty_grid()
	var b: Array = Arena.build_base_grid(Arena.MapId.CLASSIC)
	if _hard_fingerprint(a) != _hard_fingerprint(b):
		return _fail("empty_grid 不等于经典布局")
	print("[verify_maps] empty_grid 别名通过")
	return true


func _test_game_state_resolve() -> bool:
	var gs = root.get_node("GameState")
	gs.seed_input = ""
	gs.soft_seed = -1
	var s1: int = gs.resolve_soft_seed()
	if s1 < 0:
		return _fail("空种子落定成了负数")
	if gs.soft_seed != s1:
		return _fail("软墙种子没有存下来")
	# 再调一次，结果应保持不变。
	if gs.resolve_soft_seed() != s1:
		return _fail("落定结果没有保持")
	gs.soft_seed = -1
	gs.seed_input = "12345"
	var s2: int = gs.resolve_soft_seed()
	if s2 != 12345:
		return _fail("固定种子解析得到 %d" % s2)
	gs.soft_seed = -1
	gs.seed_input = "abc"
	var s3: int = gs.resolve_soft_seed()
	if s3 < 0:
		return _fail("非整数应改成随机")
	gs.set_map_id(99)
	if gs.map_id != int(Arena.MapId.MAZE):
		return _fail("set_map_id 钳制失败")
	print("[verify_maps] GameState 落定通过")
	return true
