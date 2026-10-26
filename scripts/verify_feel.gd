extends SceneTree
## 无界面冒烟：放弹者穿自己的炸弹、踢弹被硬墙挡住、突然死亡、再来一局清火。

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
		push_error("[verify_feel] 失败：没有玩家")
		quit(1)
		return

	# --- 1）放弹者穿弹：放下炸弹，再从同一格走开 ---
	var start: Vector2i = game.player_nodes[pid].get_meta("cell")
	# 清掉移动冷却。
	game.player_stats[pid].move_cd = 0.0
	game._try_place_bomb(pid)
	if game.bombs.is_empty():
		push_error("[verify_feel] 失败：炸弹没有放下")
		quit(1)
		return
	var bid := -1
	for k in game.bombs.keys():
		if int(game.bombs[k].get("owner", -1)) == pid and int(k) > bid:
			bid = int(k)
	if bool(game.bombs[bid].get("solid", true)):
		push_error("[verify_feel] 失败：新炸弹对放弹者应还不是实体")
		quit(1)
		return
	# 找一格相邻的空地。
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
		push_error("[verify_feel] 失败：走不开炸弹（旁边没有空格）")
		quit(1)
		return
	var after: Vector2i = game.player_nodes[pid].get_meta("cell")
	if after == start:
		push_error("[verify_feel] 失败：放弹者走不出炸弹那一格")
		quit(1)
		return
	if not bool(game.bombs[bid].get("solid", false)):
		push_error("[verify_feel] 失败：放弹者离开后炸弹应变成实体")
		quit(1)
		return
	print("[verify_feel] 放弹者穿弹通过")

	# --- 2）踢弹滑行被硬墙挡住 ---
	# 给踢弹，把炸弹放在硬墙旁边，再朝墙踢。
	game.player_stats[pid].kick = 1
	game.player_stats[pid].move_cd = 0.0
	# 清掉旧炸弹。
	game.bombs.clear()
	game._clear_bomb_visuals()
	# 玩家放到 (1,1)，左边就是围边硬墙；试着向左踢进硬墙。
	game.player_nodes[pid].set_meta("cell", Vector2i(1, 1))
	game.player_nodes[pid].position = game._cell_to_pos(Vector2i(1, 1))
	# 炸弹若在 (2,1)、人在 (1,1)，向右踢打不中墙。炸弹得夹在人和墙之间。
	# 摆法：炸弹在 (1,1)，人在 (2,1)，向左踢向 (0,1) 的硬墙。
	game.bombs[99] = {
		"x": 1, "y": 1, "owner": pid, "timer": 99.0, "range": 2,
		"solid": true, "slide_dx": 0, "slide_dy": 0, "slide_cd": 0.0,
	}
	game._spawn_bomb_visual(99, Vector2i(1, 1))
	game.player_nodes[pid].set_meta("cell", Vector2i(2, 1))
	game.player_stats[pid].move_cd = 0.0
	var kicked: bool = game._try_kick_bomb(99, -1, 0) # 朝围边硬墙
	if kicked:
		push_error("[verify_feel] 失败：踢进硬墙应失败")
		quit(1)
		return
	if int(game.bombs[99].x) != 1 or int(game.bombs[99].y) != 1:
		push_error("[verify_feel] 失败：踢向硬墙时炸弹却动了")
		quit(1)
		return
	# 踢进空地应该成功。若 (3,1) 是空的就用它。
	# 人在 (2,1)，炸弹在 (3,1)，向 +x 踢。
	game.bombs.erase(99)
	game._clear_bomb_visuals()
	# 找一条能踢的空走廊。
	var kick_ok := false
	for y in range(1, game.ROWS - 1):
		for x in range(1, game.COLS - 3):
			if game.grid[y][x] != game.Cell.EMPTY:
				continue
			if game.grid[y][x + 1] != game.Cell.EMPTY:
				continue
			# 炸弹放在 (x,y)，向 +x 踢。
			game.bombs[77] = {
				"x": x, "y": y, "owner": pid, "timer": 99.0, "range": 2,
				"solid": true, "slide_dx": 0, "slide_dy": 0, "slide_cd": 0.0,
			}
			if game._try_kick_bomb(77, 1, 0):
				if int(game.bombs[77].x) == x + 1:
					kick_ok = true
					# 下一步若有硬墙柱，就滑到它前面停下。
					break
			game.bombs.erase(77)
		if kick_ok:
			break
	if not kick_ok:
		push_error("[verify_feel] 失败：踢进空地失败了")
		quit(1)
		return
	print("[verify_feel] 踢弹滑行 / 硬墙阻挡通过")

	# --- 3）爆炸规则：硬墙挡住，软墙被清掉并停下 ---
	var g: Array = []
	for y in 5:
		var row: Array = []
		for x in 5:
			row.append(0)
		g.append(row)
	g[2][0] = 1 # 中心左侧硬墙
	g[2][4] = 2 # 右侧软墙
	var r = BlastRules.compute_rays(g, Vector2i(2, 2), 3, 5, 5)
	var hits: Array = r.hit
	var softs: Array = r.cleared_soft
	# 不应包含 (0,2) 硬墙；应包含 (4,2) 软墙并在那里停下。
	for h in hits:
		if h == Vector2i(0, 2):
			push_error("[verify_feel] 失败：爆炸穿过了硬墙")
			quit(1)
			return
	if Vector2i(4, 2) not in hits:
		push_error("[verify_feel] 失败：软墙没有被命中")
		quit(1)
		return
	if Vector2i(4, 2) not in softs:
		push_error("[verify_feel] 失败：软墙不在清除列表里")
		quit(1)
		return
	print("[verify_feel] 爆炸规则通过")

	# --- 4）突然死亡启动；第一圈之后间隔 15 秒 ---
	if absf(SuddenDeath.INTERVAL - 15.0) > 0.01:
		push_error("[verify_feel] 失败：间隔应为 15 秒，实际 %s" % str(SuddenDeath.INTERVAL))
		quit(1)
		return
	game.sudden.reset()
	game.sudden.elapsed = SuddenDeath.START_AT - 0.01
	game.sudden._pulse_left = 0.0
	var before_lethal: int = game.sudden.lethal.size()
	var tr: Dictionary = game.sudden.tick(0.05, game.COLS, game.ROWS, game.grid, game.Cell.HARD)
	if not tr.just_activated and not game.sudden.active:
		tr = game.sudden.tick(0.0, game.COLS, game.ROWS, game.grid, game.Cell.HARD)
	game.sudden.active = true
	game.sudden._pulse_left = 0.0
	tr = game.sudden.tick(0.01, game.COLS, game.ROWS, game.grid, game.Cell.HARD)
	if game.sudden.lethal.is_empty() and tr.new_cells.is_empty():
		game.sudden.reset()
		game.sudden.elapsed = SuddenDeath.START_AT
		game.sudden.active = false
		game.sudden._pulse_left = 0.0
		game._tick_sudden_death(0.01)
	if not game.sudden.active:
		push_error("[verify_feel] 失败：突然死亡没有启动")
		quit(1)
		return
	game.sudden._pulse_left = 0.0
	game._tick_sudden_death(0.01)
	if game.sudden.lethal.is_empty():
		push_error("[verify_feel] 失败：突然死亡推进后没有致死格")
		quit(1)
		return
	if absf(game.sudden.next_pulse_in() - SuddenDeath.INTERVAL) > 0.05:
		push_error("[verify_feel] 失败：缩圈后下一拍应为间隔时长")
		quit(1)
		return
	# 间隔之内不再缩新的一圈。
	var lethal_after: int = game.sudden.lethal.size()
	game._tick_sudden_death(1.0)
	if game.sudden.lethal.size() != lethal_after:
		push_error("[verify_feel] 失败：间隔未到就又缩了一圈")
		quit(1)
		return
	print("[verify_feel] 突然死亡通过 致死格=", game.sudden.lethal.size(), "（之前 ", before_lethal, "）间隔=", SuddenDeath.INTERVAL)

	# --- 5）再来一局清掉火焰 ---
	game._restart_match()
	await process_frame
	if game.sudden.active or not game.sudden.lethal.is_empty():
		push_error("[verify_feel] 失败：再来一局没有清掉突然死亡")
		quit(1)
		return
	if not game._sd_visuals.is_empty():
		push_error("[verify_feel] 失败：再来一局后突然死亡画面还在")
		quit(1)
		return
	print("[verify_feel] 再来一局清火通过")

	# 套用踢弹道具。
	game._apply_powerup(pid, game.PKind.KICK)
	if int(game.player_stats[pid].kick) != 1:
		push_error("[verify_feel] 失败：踢弹道具")
		quit(1)
		return
	print("[verify_feel] 踢弹道具通过")

	# --- 6）踢弹规则：放弹者穿过、被挡、踢出去 ---
	var sample := {
		1: {"x": 2, "y": 2, "owner": 1, "solid": false},
	}
	var open_slide := func(_dest: Vector2i) -> bool:
		return true
	var shut_slide := func(_dest: Vector2i) -> bool:
		return false
	var enter: int = KickRules.classify_enter(1, sample, 1, false, 1, 0, shut_slide)
	if enter != KickRules.Enter.WALK:
		push_error("[verify_feel] 失败：放弹者应能穿过自己刚放的炸弹")
		quit(1)
		return
	enter = KickRules.classify_enter(1, sample, 2, false, 1, 0, open_slide)
	if enter != KickRules.Enter.BLOCKED:
		push_error("[verify_feel] 失败：没有踢弹的其他人不能走进刚放的炸弹")
		quit(1)
		return
	enter = KickRules.classify_enter(1, sample, 2, true, 1, 0, open_slide)
	if enter != KickRules.Enter.KICK:
		push_error("[verify_feel] 失败：目标空着时踢弹应推动刚放的炸弹")
		quit(1)
		return
	sample[1]["solid"] = true
	enter = KickRules.classify_enter(1, sample, 2, true, 1, 0, shut_slide)
	if enter != KickRules.Enter.BLOCKED:
		push_error("[verify_feel] 失败：踢向被挡的格子应停下")
		quit(1)
		return
	enter = KickRules.classify_enter(1, sample, 2, true, 1, 0, open_slide)
	if enter != KickRules.Enter.KICK:
		push_error("[verify_feel] 失败：目标空着时应允许踢")
		quit(1)
		return
	print("[verify_feel] 踢弹分类通过")

	# --- 7）只推进时钟不产生致死格；同步会把已过时间对齐 ---
	var clock := SuddenDeath.new()
	clock.advance_elapsed(SuddenDeath.START_AT + 5.0)
	if clock.active or not clock.lethal.is_empty():
		push_error("[verify_feel] 失败：只推进时间却改了安全区")
		quit(1)
		return
	game._rpc_sync_match_clock(42.0, false)
	if absf(float(game.sudden.elapsed) - 42.0) > 0.001:
		push_error("[verify_feel] 失败：时钟同步没有生效")
		quit(1)
		return
	print("[verify_feel] 时钟同步通过")

	# --- 8）缩圈吞掉炸弹和道具，不再炸一次 ---
	game.bombs[56] = {
		"x": 4, "y": 1, "owner": pid, "timer": 9.0, "range": 2,
		"solid": true, "slide_dx": 0, "slide_dy": 0, "slide_cd": 0.0,
	}
	game._spawn_bomb_visual(56, Vector2i(4, 1))
	game.powerups[9] = {"x": 4, "y": 1, "kind": 0}
	game._apply_sudden_ring([Vector2i(4, 1)], PackedInt32Array([56]), PackedInt32Array([9]))
	if game.bombs.has(56) or game.powerups.has(9) or not game.sudden.is_lethal(Vector2i(4, 1)):
		push_error("[verify_feel] 失败：缩圈没有吞掉炸弹或道具")
		quit(1)
		return
	var swallowed: Node = game.entities.get_node_or_null("Bomb_56")
	if swallowed != null and not swallowed.is_queued_for_deletion():
		push_error("[verify_feel] 失败：被吞掉的炸弹画面还在")
		quit(1)
		return
	print("[verify_feel] 缩圈吞物通过")

	# --- 9）踢进已有火焰会引爆 ---
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
		push_error("[verify_feel] 失败：踢进火里的炸弹应引爆")
		quit(1)
		return
	if game.map_layer.get_child_count() != tiles_before:
		push_error("[verify_feel] 失败：重绘把整张地图重建了")
		quit(1)
		return
	print("[verify_feel] 踢进火里并重绘通过")

	# --- 10）走进踢弹引爆的火焰里会死 ---
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
		push_error("[verify_feel] 失败：走进踢弹引爆的火焰应死亡")
		quit(1)
		return
	print("[verify_feel] 走进踢弹火焰通过")

	# --- 11）穿透射线：默认停在软墙；有穿透则继续；硬墙始终挡住 ---
	var pg: Array = []
	for y in 5:
		var row: Array = []
		for x in 7:
			row.append(BlastRules.CELL_EMPTY)
		pg.append(row)
	var origin := Vector2i(1, 2)
	pg[2][2] = BlastRules.CELL_SOFT
	pg[2][3] = BlastRules.CELL_SOFT
	pg[2][4] = BlastRules.CELL_EMPTY
	pg[2][5] = BlastRules.CELL_HARD
	pg[2][6] = BlastRules.CELL_SOFT
	var plain: Dictionary = BlastRules.compute_rays(pg, origin, 5, 7, 5)
	var plain_off: Dictionary = BlastRules.compute_rays(pg, origin, 5, 7, 5, false)
	var pierced: Dictionary = BlastRules.compute_rays(pg, origin, 5, 7, 5, true)
	if plain.hit != plain_off.hit or plain.cleared_soft != plain_off.cleared_soft:
		push_error("[verify_feel] 失败：默认穿透应等于 pierce=false")
		quit(1)
		return
	if Vector2i(2, 2) not in plain.hit or Vector2i(2, 2) not in plain.cleared_soft:
		push_error("[verify_feel] 失败：不穿透应命中第一块软墙")
		quit(1)
		return
	if Vector2i(3, 2) in plain.hit or Vector2i(4, 2) in plain.hit:
		push_error("[verify_feel] 失败：不穿透的射线穿过了软墙")
		quit(1)
		return
	if Vector2i(3, 2) not in pierced.hit or Vector2i(3, 2) not in pierced.cleared_soft:
		push_error("[verify_feel] 失败：穿透应清掉第二块软墙")
		quit(1)
		return
	if Vector2i(4, 2) not in pierced.hit:
		push_error("[verify_feel] 失败：穿透应穿过软墙继续打到空地")
		quit(1)
		return
	if Vector2i(5, 2) in pierced.hit or Vector2i(6, 2) in pierced.hit or Vector2i(6, 2) in pierced.cleared_soft:
		push_error("[verify_feel] 失败：穿透应停在硬墙前，硬墙后面不算命中")
		quit(1)
		return
	print("[verify_feel] 穿透爆炸规则通过")

	# --- 12）局内：放下的那一刻把穿透抄到炸弹上 ---
	game.bombs.clear()
	game._clear_bomb_visuals()
	game.alive[pid] = true
	game.player_stats[pid].bombs = game.MAX_BOMBS
	game.player_stats[pid].range = 4
	game.player_stats[pid].pierce = 0
	# y=3 这一行：软墙、软墙、空地、硬墙、软墙。y=9 是捡完穿透之后放的炸弹。
	for row_y in [3, 9]:
		game.grid[row_y][1] = game.Cell.EMPTY
		game.grid[row_y][2] = game.Cell.SOFT
		game.grid[row_y][3] = game.Cell.SOFT
		game.grid[row_y][4] = game.Cell.EMPTY
		game.grid[row_y][5] = game.Cell.HARD
		game.grid[row_y][6] = game.Cell.SOFT
	game.player_nodes[pid].set_meta("cell", Vector2i(1, 3))
	game.player_nodes[pid].position = game._cell_to_pos(Vector2i(1, 3))
	var ids_before: Array = game.bombs.keys()
	game._try_place_bomb(pid)
	var bid_a := -1
	for k in game.bombs.keys():
		if not ids_before.has(k):
			bid_a = int(k)
			break
	if bid_a < 0 or int(game.bombs[bid_a].get("pierce", -1)) != 0:
		push_error("[verify_feel] 失败：捡穿透之前放的炸弹应记下 pierce=0")
		quit(1)
		return
	game.powerups[8801] = {"x": 8, "y": 3, "kind": game.PKind.PIERCE}
	game._try_pickup_at(pid, Vector2i(8, 3))
	if int(game.player_stats[pid].get("pierce", 0)) != 1:
		push_error("[verify_feel] 失败：拾取应把穿透设为 1")
		quit(1)
		return
	if int(game.bombs[bid_a].get("pierce", -1)) != 0:
		push_error("[verify_feel] 失败：拾取追溯改了已经放下去的炸弹")
		quit(1)
		return
	if not str(game.stats_label.text).contains("穿透 开"):
		push_error("[verify_feel] 失败：界面缺少「穿透 开」，实际 %s" % game.stats_label.text)
		quit(1)
		return
	game.player_nodes[pid].set_meta("cell", Vector2i(1, 9))
	game.player_nodes[pid].position = game._cell_to_pos(Vector2i(1, 9))
	ids_before = game.bombs.keys()
	game._try_place_bomb(pid)
	var bid_b := -1
	for k in game.bombs.keys():
		if not ids_before.has(k):
			bid_b = int(k)
			break
	if bid_b < 0 or int(game.bombs[bid_b].get("pierce", -1)) != 1:
		push_error("[verify_feel] 失败：捡到之后放的炸弹应记下 pierce=1")
		quit(1)
		return
	game.player_nodes[pid].set_meta("cell", Vector2i(11, 1))
	game.player_nodes[pid].position = game._cell_to_pos(Vector2i(11, 1))
	game._explode(bid_a)
	if int(game.grid[3][2]) != game.Cell.EMPTY or int(game.grid[3][3]) != game.Cell.SOFT:
		push_error("[verify_feel] 失败：不穿透爆炸应停在第一块软墙")
		quit(1)
		return
	if int(game.grid[3][6]) != game.Cell.SOFT or int(game.grid[3][5]) != game.Cell.HARD:
		push_error("[verify_feel] 失败：不穿透爆炸改了第一块软墙后面的格子")
		quit(1)
		return
	game._explode(bid_b)
	if int(game.grid[9][2]) != game.Cell.EMPTY or int(game.grid[9][3]) != game.Cell.EMPTY:
		push_error("[verify_feel] 失败：穿透爆炸应清掉射程内每一块软墙")
		quit(1)
		return
	if int(game.grid[9][5]) != game.Cell.HARD or int(game.grid[9][6]) != game.Cell.SOFT:
		push_error("[verify_feel] 失败：穿透爆炸应停在硬墙，硬墙后的软墙留下")
		quit(1)
		return
	print("[verify_feel] 穿透放置与爆炸通过")

	print("[verify_feel] 成功")
	quit(0)
