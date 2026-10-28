extends SceneTree
## 无界面：定时空投的时刻、合法格、没空格跳过、再来一局重置，以及场景上的预告节点。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _logic():
		quit(1)
		return
	if not await _scene():
		quit(1)
		return
	print("[verify_airdrop] 成功")
	quit(0)


func _fail(msg: String) -> bool:
	push_error("[verify_airdrop] 失败：%s" % msg)
	return false


func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func _world(grid: Array, bombs: Dictionary, powerups: Dictionary, lethal: Dictionary, next_id: int) -> Dictionary:
	return {
		"grid": grid,
		"cols": Arena.COLS,
		"rows": Arena.ROWS,
		"bombs": bombs,
		"powerups": powerups,
		"lethal": lethal,
		"next_id": next_id,
	}


func _open_grid() -> Array:
	return Arena.build_base_grid(Arena.MapId.OPEN)


func _hard_grid() -> Array:
	var grid: Array = _open_grid()
	for y in Arena.ROWS:
		for x in Arena.COLS:
			grid[y][x] = Arena.CELL_HARD
	return grid


func _logic() -> bool:
	if absf(Airdrop.FIRST_AT - 15.0) > 0.001 or absf(Airdrop.INTERVAL - 10.0) > 0.001:
		return _fail("首投应为 15 秒、间隔应为 10 秒")
	if absf(Airdrop.WARN_SEC - 1.5) > 0.001:
		return _fail("预告应为 1.5 秒")
	if absf(PowerupDrop.CHANCE - 0.38) > 0.001:
		return _fail("软墙掉落概率被改动")
	if not _timing() or not _cells() or not _skip_and_reset() or not _kinds():
		return false
	print("[verify_airdrop] 规则通过")
	return true


func _timing() -> bool:
	var powerups := {}
	var drop := Airdrop.new()
	var world := _world(_open_grid(), {}, powerups, {}, 5)
	var early := drop.tick(13.4, world, _rng(1))
	if not early.warn.is_empty() or not early.land.is_empty() or not drop.pending.is_empty():
		return _fail("13.4 秒不该预告")
	var warned := drop.tick(0.1, world, _rng(2))
	if warned.warn.is_empty() or not warned.land.is_empty():
		return _fail("13.5 秒应只预告、不落地")
	if absf(drop.elapsed - 13.5) > 0.001:
		return _fail("预告时刻 elapsed=%s" % drop.elapsed)
	if int(warned.warn.kind) < 0 or int(warned.warn.kind) > PlayerStats.Kind.PIERCE:
		return _fail("预告种类越界")
	if not powerups.is_empty():
		return _fail("预告阶段不应写入道具")
	var still := drop.tick(1.4, world, _rng(3))
	if not still.land.is_empty() or drop.pending.is_empty():
		return _fail("14.9 秒还应停在预告")
	var landed := drop.tick(0.1, world, _rng(4))
	if landed.land.is_empty() or not drop.pending.is_empty():
		return _fail("15 秒应落地并清掉预告")
	if absf(drop.elapsed - 15.0) > 0.001 or absf(drop.next_land_at - 25.0) > 0.001:
		return _fail("首投后下一轮应是 25 秒")
	if int(landed.land.id) != 5 or int(landed.next_id) != 6:
		return _fail("落地 id 应沿用 next_id")
	if int(landed.land.kind) != int(warned.warn.kind):
		return _fail("落地种类应与预告时抽到的一致")
	if int(powerups[5].kind) != int(landed.land.kind):
		return _fail("PowerupDrop.consider 没有写入种类")
	var cell := Vector2i(int(landed.land.x), int(landed.land.y))
	if Airdrop.near_spawn(cell) or not Airdrop.is_legal_cell(cell, world.grid, Arena.COLS, Arena.ROWS, {}, {}, {}):
		return _fail("开阔图首投落在了出生点附近或非法格")

	world = _world(_open_grid(), {}, {}, {}, 1)
	var late := drop.tick(8.4, world, _rng(5))
	if not late.warn.is_empty():
		return _fail("23.4 秒还不到第二轮预告")
	var second_warn := drop.tick(0.1, world, _rng(6))
	if second_warn.warn.is_empty() or not second_warn.land.is_empty():
		return _fail("23.5 秒应预告第二轮")
	var second := drop.tick(1.5, world, _rng(7))
	if second.land.is_empty() or absf(drop.elapsed - 25.0) > 0.001:
		return _fail("第二轮应在 25 秒落地")
	if absf(drop.next_land_at - 35.0) > 0.001:
		return _fail("25 秒之后下一轮应是 35 秒")

	var burst := Airdrop.new()
	var burst_powers := {}
	var burst_ev := burst.tick(100.0, _world(_open_grid(), {}, burst_powers, {}, 1), _rng(8))
	if burst_ev.land.is_empty() or burst_powers.size() != 1:
		return _fail("大跳帧只应补一件，实际 %d" % burst_powers.size())
	if burst.next_land_at <= burst.elapsed:
		return _fail("大跳帧后时钟应拨到未来")
	print("[verify_airdrop] 时刻通过")
	return true


func _cells() -> bool:
	if not Airdrop.near_spawn(Vector2i(1, 1)) or not Airdrop.near_spawn(Vector2i(3, 3)):
		return _fail("出生点周围 2 格应避开")
	if Airdrop.near_spawn(Vector2i(1, 4)) or Airdrop.near_spawn(Vector2i(6, 5)):
		return _fail("更远的格子不应算出生点附近")

	var grid: Array = _hard_grid()
	grid[2][2] = Arena.CELL_EMPTY
	grid[5][6] = Arena.CELL_EMPTY
	for seed in 12:
		var picked := Airdrop.pick_cell(grid, Arena.COLS, Arena.ROWS, {}, {}, {}, _rng(seed))
		if picked != Vector2i(6, 5):
			return _fail("有远处空地时不应投在出生点附近 %s" % picked)

	var bombs := {1: {"x": 6, "y": 5}}
	var away_blocked := Airdrop.pick_cell(grid, Arena.COLS, Arena.ROWS, bombs, {}, {}, _rng(1))
	if away_blocked != Vector2i(2, 2):
		return _fail("远处被炸弹占住时应退回出生点附近")
	var occupied := {9: {"x": 6, "y": 5, "kind": 0}}
	if Airdrop.pick_cell(grid, Arena.COLS, Arena.ROWS, {}, occupied, {}, _rng(1)) != Vector2i(2, 2):
		return _fail("已有道具的格子不应再投")
	var lethal := {Vector2i(6, 5): true}
	if Airdrop.pick_cell(grid, Arena.COLS, Arena.ROWS, {}, {}, lethal, _rng(1)) != Vector2i(2, 2):
		return _fail("致死格不应入选")
	grid[5][6] = Arena.CELL_SOFT
	if Airdrop.pick_cell(grid, Arena.COLS, Arena.ROWS, {}, {}, {}, _rng(1)) != Vector2i(2, 2):
		return _fail("软墙不应入选")
	grid[5][6] = Arena.CELL_HARD
	grid[2][2] = Arena.CELL_HARD
	if Airdrop.pick_cell(grid, Arena.COLS, Arena.ROWS, {}, {}, {}, _rng(1)).x >= 0:
		return _fail("没有空地时应返回无效格")

	var open := _open_grid()
	var sd: Dictionary = {}
	for y in Arena.ROWS:
		for x in Arena.COLS:
			var c := Vector2i(x, y)
			if int(open[y][x]) == Arena.CELL_EMPTY and not Airdrop.near_spawn(c):
				sd[c] = true
	var during := Airdrop.new()
	var powers := {}
	var ev := during.tick(15.0, _world(open, {}, powers, sd, 1), _rng(4))
	if ev.land.is_empty():
		return _fail("缩圈后出生点附近仍有空地就应继续投")
	var landed := Vector2i(int(ev.land.x), int(ev.land.y))
	if sd.has(landed) or not Airdrop.near_spawn(landed):
		return _fail("缩圈后的落点必须是非致死的退路格")
	print("[verify_airdrop] 合法格通过")
	return true


func _skip_and_reset() -> bool:
	var drop := Airdrop.new()
	var powerups := {}
	var skipped := drop.tick(14.5, _world(_hard_grid(), {}, powerups, {}, 1), _rng(1))
	if not skipped.warn.is_empty() or not skipped.land.is_empty() or skipped.cancel:
		return _fail("没有空地时应静默跳过，而不是预告")
	if not powerups.is_empty() or not drop.pending.is_empty():
		return _fail("跳过的轮次不应留下道具或预告")
	if absf(drop.next_land_at - 25.0) > 0.001:
		return _fail("跳过 15 秒这一轮后，下一轮应仍是 25 秒")
	var again := drop.tick(9.0, _world(_hard_grid(), {}, powerups, {}, 1), _rng(1))
	if not again.land.is_empty() or absf(drop.elapsed - 23.5) > 0.001 or absf(drop.next_land_at - 35.0) > 0.001:
		return _fail("下一轮仍然没有空地时应继续跳过")

	var live := Airdrop.new()
	var grid := _open_grid()
	var bombs := {}
	var live_powers := {}
	var lethal := {}
	var warn := live.tick(13.5, _world(grid, bombs, live_powers, lethal, 2), _rng(9))
	if warn.warn.is_empty():
		return _fail("应能进入预告")
	var cell := Vector2i(int(live.pending.x), int(live.pending.y))
	bombs[3] = {"x": cell.x, "y": cell.y}
	var cancelled := live.tick(1.5, _world(grid, bombs, live_powers, lethal, 2), _rng(9))
	if not cancelled.cancel or not cancelled.land.is_empty() or not live_powers.is_empty():
		return _fail("预告格被炸弹占住后应取消落地")
	if absf(live.next_land_at - 25.0) > 0.001:
		return _fail("取消后应进入下一轮")

	var burned := Airdrop.new()
	var burn_powers := {}
	var burn_lethal := {}
	warn = burned.tick(13.5, _world(grid, {}, burn_powers, burn_lethal, 1), _rng(10))
	cell = Vector2i(int(burned.pending.x), int(burned.pending.y))
	burn_lethal[cell] = true
	cancelled = burned.tick(1.5, _world(grid, {}, burn_powers, burn_lethal, 1), _rng(10))
	if not cancelled.cancel or not burn_powers.is_empty():
		return _fail("预告格变成致死格后不应生成道具")

	var raced := Airdrop.new()
	var raced_powers := {}
	warn = raced.tick(13.5, _world(grid, {}, raced_powers, {}, 8), _rng(11))
	cell = Vector2i(int(raced.pending.x), int(raced.pending.y))
	raced_powers[4] = {"x": cell.x, "y": cell.y, "kind": PlayerStats.Kind.SPEED}
	cancelled = raced.tick(1.5, _world(grid, {}, raced_powers, {}, 8), _rng(11))
	if not cancelled.cancel or raced_powers.has(8):
		return _fail("预告格已经有道具时不应再写一件")

	var reset_drop := Airdrop.new()
	reset_drop.tick(13.5, _world(grid, {}, {}, {}, 1), _rng(12))
	if reset_drop.pending.is_empty():
		return _fail("重置前应处于预告")
	reset_drop.reset()
	if absf(reset_drop.elapsed) > 0.001 or absf(reset_drop.next_land_at - 15.0) > 0.001 or not reset_drop.pending.is_empty():
		return _fail("reset 没有清掉时钟或预告")
	var after := reset_drop.tick(13.4, _world(grid, {}, {}, {}, 1), _rng(13))
	if not after.warn.is_empty():
		return _fail("重置后不应立刻预告")
	after = reset_drop.tick(0.1, _world(grid, {}, {}, {}, 1), _rng(14))
	if after.warn.is_empty():
		return _fail("重置后再过 13.5 秒应重新预告")
	print("[verify_airdrop] 跳过与重置通过")
	return true


func _kinds() -> bool:
	var counts := [0, 0, 0, 0, 0]
	var drop := Airdrop.new()
	var rng := _rng(21)
	var delta := 15.0
	for _i in 80:
		var powers := {}
		var ev := drop.tick(delta, _world(_open_grid(), {}, powers, {}, 1), rng)
		delta = 10.0
		if ev.land.is_empty():
			return _fail("开阔图每一轮都应落地")
		var kind := int(ev.land.kind)
		if kind < 0 or kind > PlayerStats.Kind.PIERCE:
			return _fail("种类越界")
		counts[kind] += 1
	for k in counts:
		if k < 4:
			return _fail("五种道具没有摊开 %s" % str(counts))
	print("[verify_airdrop] 种类通过 ", counts)
	return true


func _scene() -> bool:
	var gs = root.get_node("GameState")
	gs.players = {1: {"name": "测试", "color_idx": 0, "ready": true}}
	gs.in_match = true
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	if not game.has_method("_tick_airdrop"):
		return _fail("game_root 没有接入空投")

	game._rpc_setup_match(1, {1: {"name": "测试", "color_idx": 0, "ready": true}}, Arena.MapId.OPEN)
	if absf(game.airdrop.elapsed) > 0.001 or absf(game.airdrop.next_land_at - 15.0) > 0.001:
		return _fail("开局空投时钟不是 0 / 15")
	game._tick_airdrop(13.5)
	if game.fx_layer.get_node_or_null("AirdropMark") == null:
		return _fail("13.5 秒没有预告标记")
	if not game.powerups.is_empty():
		return _fail("预告时场上不该有空投道具")
	game._tick_airdrop(1.5)
	if game.fx_layer.get_node_or_null("AirdropMark") != null:
		return _fail("落地后预告标记还在")
	if game.powerups.size() != 1:
		return _fail("15 秒应生成 1 个道具，实际 %d" % game.powerups.size())
	for pid in game.powerups.keys():
		var p: Dictionary = game.powerups[pid]
		var cell := Vector2i(int(p.x), int(p.y))
		if Airdrop.near_spawn(cell):
			return _fail("场景落点靠出生点太近")
		if game.sudden.is_lethal(cell):
			return _fail("场景落点是致死格")
		if int(p.kind) < 0 or int(p.kind) > PlayerStats.Kind.PIERCE:
			return _fail("场景道具种类越界")
		if game.powerups_layer.get_node_or_null("Powerup_%d" % int(pid)) == null:
			return _fail("落地没有生成道具节点")

	game._rpc_setup_match(2, {1: {"name": "测试", "color_idx": 0, "ready": true}}, Arena.MapId.OPEN)
	if absf(game.airdrop.elapsed) > 0.001 or not game.airdrop.pending.is_empty() or not game.powerups.is_empty():
		return _fail("再来一局没有重置空投")
	if game.fx_layer.get_node_or_null("AirdropMark") != null:
		return _fail("再来一局还留着预告")
	game._tick_airdrop(13.4)
	if game.fx_layer.get_node_or_null("AirdropMark") != null:
		return _fail("重置后 13.4 秒不应预告")

	for y in Arena.ROWS:
		for x in Arena.COLS:
			game.grid[y][x] = Arena.CELL_HARD
	game.grid[1][1] = Arena.CELL_EMPTY
	var before: PackedInt32Array = PlayerStats.pack(game.player_stats[1])
	game._tick_airdrop(1.6)
	if not game.powerups.is_empty():
		return _fail("投在玩家脚下应立刻拾取")
	if game.fx_layer.get_node_or_null("AirdropMark") != null:
		return _fail("拾取后预告还在")
	var after: PackedInt32Array = PlayerStats.pack(game.player_stats[1])
	var changed := false
	for i in before.size():
		if int(before[i]) != int(after[i]):
			changed = true
	if not changed:
		return _fail("脚下空投没有改变属性")

	game._rpc_setup_match(3, {1: {"name": "测试", "color_idx": 0, "ready": true}}, Arena.MapId.OPEN)
	for y in Arena.ROWS:
		for x in Arena.COLS:
			game.grid[y][x] = Arena.CELL_HARD
	game._tick_airdrop(14.5)
	if not game.powerups.is_empty() or game.fx_layer.get_node_or_null("AirdropMark") != null:
		return _fail("场景上没有空地时不应预告或生成")
	if absf(game.airdrop.next_land_at - 25.0) > 0.001:
		return _fail("场景跳过本轮后下一落地应是 25 秒")

	game.match_over = true
	game._tick_airdrop(30.0)
	if not game.powerups.is_empty():
		return _fail("对局结束后不应再空投")
	print("[verify_airdrop] 场景通过")
	return true
