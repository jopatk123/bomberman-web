class_name MatchBot
extends RefCounted
## 人机一步决策（Hard 默认）：先逃命，再捡邻格道具；
## 假想放弹后能 BFS 逃到安全格才炸软墙/对手；有踢弹时可踢开挡路弹；
## 兴趣按评分追道具/开图软墙/压人，并带禁回头与 stuck 扰动。
## 权威端对每个 MatchFill 人机调用；这里不发 RPC。

## 第一个补位槽。真实编号以 MatchFill.bot_peer_id(1) 为准。
const PEER_ID := -1001
const NAME := "人机1"
## 还在正常引信上的炸弹算危险。调试用的超长计时不算。
const DANGER_TIME := 2.05
## 连续 WAIT / 无效挪动达到此值则强制扰动。
const STUCK_LIMIT := 4

enum Action { WAIT = 0, MOVE = 1, BOMB = 2 }

const CELL_EMPTY := 0
const CELL_SOFT := 2

const _DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0),
]


## 视野 view：grid、cols、rows、cell、blast_range、can_place、bombs[]、others[]、
## lethal[]、powerups[]、pierce、has_kick、bomb_stock（还可再放几颗）、
## last_dx / last_dy / stuck / grind_x / grind_y（记忆，可选）。
## bombs[] 项：{x, y, timer, range, pierce}
## 返回 {action, dx, dy, mem}；mem 供权威端下一拍回填。
static func decide(view: Dictionary) -> Dictionary:
	var cell: Vector2i = view.cell
	var danger := _danger(view)
	var blocked := _blocked(view, cell)
	var last := Vector2i(int(view.get("last_dx", 0)), int(view.get("last_dy", 0)))
	var stuck := int(view.get("stuck", 0))
	var fleeing := danger.has(cell)

	if fleeing:
		var flee := _find_step(
			view, cell, blocked, danger, true,
			func(c: Vector2i) -> bool: return not danger.has(c),
			Vector2i.ZERO, true
		)
		if flee != Vector2i.ZERO:
			return _finish(_move(flee), view, cell, stuck, false)
		# 逃命时尝试踢开邻格挡路弹。
		var kick_out := _kick_escape_step(view, cell, danger, blocked)
		if kick_out != Vector2i.ZERO:
			return _finish(_move(kick_out), view, cell, stuck, false)
		return _finish(_wait(), view, cell, stuck + 1, false)

	var grab := _adjacent_powerup(view, cell, danger, blocked)
	if grab != Vector2i.ZERO:
		return _finish(_move(grab), view, cell, 0, false)

	if bool(view.get("can_place", false)) and _worth_placing(view, cell, danger, blocked):
		return _finish({"action": Action.BOMB, "dx": 0, "dy": 0}, view, cell, 0, true)

	var step := _scored_interest_step(view, cell, blocked, danger, last, stuck)
	if step != Vector2i.ZERO:
		return _finish(_move(step), view, cell, 0, false)

	# stuck / 无目标：扰动到非回头的安全邻格。
	var nudge := _stuck_nudge(view, cell, blocked, danger, last)
	if nudge != Vector2i.ZERO:
		return _finish(_move(nudge), view, cell, 0, false)
	return _finish(_wait(), view, cell, stuck + 1, false)


static func _finish(decision: Dictionary, view: Dictionary, cell: Vector2i, stuck: int, placed: bool) -> Dictionary:
	var dx := int(decision.get("dx", 0))
	var dy := int(decision.get("dy", 0))
	var action := int(decision.get("action", Action.WAIT))
	var mem := {
		"last_dx": dx if action == Action.MOVE else int(view.get("last_dx", 0)),
		"last_dy": dy if action == Action.MOVE else int(view.get("last_dy", 0)),
		"stuck": stuck if action == Action.WAIT else 0,
		"grind_x": int(view.get("grind_x", -1)),
		"grind_y": int(view.get("grind_y", -1)),
	}
	if placed:
		# 记下本拍优先清理的邻接软墙，减少原地磨箱。
		var soft := _nearest_soft(view, cell)
		if soft != Vector2i(-1, -1):
			mem.grind_x = soft.x
			mem.grind_y = soft.y
	elif action == Action.MOVE and stuck >= STUCK_LIMIT:
		mem.grind_x = -1
		mem.grind_y = -1
	decision["mem"] = mem
	return decision


static func _move(step: Vector2i) -> Dictionary:
	return {"action": Action.MOVE, "dx": step.x, "dy": step.y}


static func _wait() -> Dictionary:
	return {"action": Action.WAIT, "dx": 0, "dy": 0}


static func _danger(view: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var cols := int(view.cols)
	var rows := int(view.rows)
	for bomb in view.get("bombs", []):
		if float(bomb.get("timer", 0.0)) > DANGER_TIME:
			continue
		var origin := Vector2i(int(bomb.x), int(bomb.y))
		var rays := BlastRules.compute_rays(
			view.grid, origin, int(bomb.get("range", 1)), cols, rows, bool(bomb.get("pierce", false))
		)
		for c in rays.hit:
			out[c] = true
	for c in view.get("lethal", []):
		out[c] = true
	return out


static func _blocked(view: Dictionary, origin: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	for bomb in view.get("bombs", []):
		var c := Vector2i(int(bomb.x), int(bomb.y))
		if c != origin:
			out[c] = true
	for o in view.get("others", []):
		out[o] = true
	for c in view.get("lethal", []):
		out[c] = true
	return out


## 假想在 cell 放弹：有用（清软墙或打到人）且 BFS 能走到火线外安全格。
static func _worth_placing(view: Dictionary, cell: Vector2i, danger: Dictionary, blocked: Dictionary) -> bool:
	var cols := int(view.cols)
	var rows := int(view.rows)
	var rng := int(view.get("blast_range", 2))
	var rays := BlastRules.compute_rays(
		view.grid, cell, rng, cols, rows, bool(view.get("pierce", false))
	)
	var hits: Array = rays.hit
	var cleared: Array = rays.cleared_soft
	var useful := not cleared.is_empty()
	if not useful:
		for o in view.get("others", []):
			if o in hits:
				useful = true
				break
	if not useful:
		return false
	return _can_escape_after_place(view, cell, danger, blocked, hits)


static func _can_escape_after_place(
	view: Dictionary,
	cell: Vector2i,
	danger: Dictionary,
	blocked: Dictionary,
	hits: Array
) -> bool:
	var new_danger: Dictionary = danger.duplicate()
	for h in hits:
		new_danger[h] = true
	var blocked2: Dictionary = blocked.duplicate()
	# 放下去的弹占格，逃生路径不能再踩回来。
	blocked2[cell] = true
	# 允许沿火线走（与真人一样先迈进射线再拐出），目标必须是安全格。
	var step := _find_step(
		view, cell, blocked2, new_danger, true,
		func(c: Vector2i) -> bool: return not new_danger.has(c),
		Vector2i.ZERO, true
	)
	return step != Vector2i.ZERO


static func _adjacent_powerup(view: Dictionary, cell: Vector2i, danger: Dictionary, blocked: Dictionary) -> Vector2i:
	for raw in view.get("powerups", []):
		var p := raw as Vector2i
		if absi(p.x - cell.x) + absi(p.y - cell.y) != 1:
			continue
		if not _standable(view, p) or blocked.has(p) or danger.has(p):
			continue
		return p - cell
	return Vector2i.ZERO


static func _nearest_soft(view: Dictionary, cell: Vector2i) -> Vector2i:
	var cols := int(view.cols)
	var rows := int(view.rows)
	var grid: Array = view.grid
	for d in _DIRS:
		var n: Vector2i = cell + d
		if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
			continue
		if int(grid[n.y][n.x]) == CELL_SOFT:
			return n
	return Vector2i(-1, -1)


## 在可达格里打分，走向最高分目标；禁立刻回头（除非无其它步）。
static func _scored_interest_step(
	view: Dictionary,
	origin: Vector2i,
	blocked: Dictionary,
	danger: Dictionary,
	last: Vector2i,
	stuck: int
) -> Vector2i:
	var grind := Vector2i(int(view.get("grind_x", -1)), int(view.get("grind_y", -1)))
	var best_score := -1
	var best_dist := 9999
	var best_goal := Vector2i.ZERO
	var dist_map := _flood(view, origin, blocked, danger, false)
	for c in dist_map.keys():
		if c == origin:
			continue
		var dist: int = int(dist_map[c])
		var score := _score_cell(view, c, dist, grind, stuck)
		if score <= 0:
			continue
		if score > best_score or (score == best_score and dist < best_dist):
			best_score = score
			best_dist = dist
			best_goal = c
	if best_goal == Vector2i.ZERO:
		return Vector2i.ZERO
	var step := _step_toward(view, origin, best_goal, blocked, danger, false)
	if step == Vector2i.ZERO:
		return Vector2i.ZERO
	# 禁回头：若存在其它能靠近目标的邻步，则不用 -last。
	if last != Vector2i.ZERO and step == -last:
		var alt := _alternate_first_step(view, origin, best_goal, blocked, danger, last)
		if alt != Vector2i.ZERO:
			return alt
	return step


static func _score_cell(view: Dictionary, cell: Vector2i, dist: int, grind: Vector2i, stuck: int) -> int:
	var score := 0
	var cols := int(view.cols)
	var rows := int(view.rows)
	var grid: Array = view.grid
	var rng := int(view.get("blast_range", 2))
	var stock := int(view.get("bomb_stock", 1))

	for raw in view.get("powerups", []):
		if (raw as Vector2i) == cell:
			# 远处道具也积极去拿。
			score += 140 - dist * 4
			break

	for d in _DIRS:
		var n: Vector2i = cell + d
		if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
			continue
		if int(grid[n.y][n.x]) != CELL_SOFT:
			continue
		var open := _soft_openness(view, n)
		var soft_score := 28 + open * 12 + mini(rng, 4) * 3
		if n == grind and stuck < STUCK_LIMIT:
			soft_score -= 45
		if stuck >= STUCK_LIMIT and n == grind:
			soft_score -= 80
		score += soft_score

	for o in view.get("others", []):
		var md := absi(o.x - cell.x) + absi(o.y - cell.y)
		if md == 1:
			# 贴身压迫；火力/余弹越多越想贴。
			score += 70 + rng * 8 + maxi(stock - 1, 0) * 12
		elif md <= rng and (o.x == cell.x or o.y == cell.y):
			# 同轴进入射程。
			score += 40 + rng * 5 + maxi(stock - 1, 0) * 8

	return score


## 软墙「开图」潜力：四周空地越多，越值得拆。
static func _soft_openness(view: Dictionary, soft: Vector2i) -> int:
	var n := 0
	for d in _DIRS:
		var c: Vector2i = soft + d
		if _standable(view, c):
			n += 1
	return n


static func _stuck_nudge(
	view: Dictionary,
	cell: Vector2i,
	blocked: Dictionary,
	danger: Dictionary,
	last: Vector2i
) -> Vector2i:
	var opts: Array[Vector2i] = []
	for d in _DIRS:
		if last != Vector2i.ZERO and d == -last:
			continue
		var n: Vector2i = cell + d
		if _can_enter(view, cell, n, blocked, danger, false, true):
			opts.append(d)
	if opts.is_empty():
		for d in _DIRS:
			var n2: Vector2i = cell + d
			if _can_enter(view, cell, n2, blocked, danger, false, true):
				opts.append(d)
	if opts.is_empty():
		return Vector2i.ZERO
	# 用格子坐标做稳定扰动，避免每帧真随机导致联机难复现。
	var idx := absi(cell.x * 31 + cell.y * 17 + int(view.get("stuck", 0))) % opts.size()
	return opts[idx]


static func _kick_escape_step(
	view: Dictionary,
	cell: Vector2i,
	danger: Dictionary,
	_blocked: Dictionary
) -> Vector2i:
	if not bool(view.get("has_kick", false)):
		return Vector2i.ZERO
	for d in _DIRS:
		var n: Vector2i = cell + d
		if not _bomb_at(view, n):
			continue
		if not _kick_dest_clear(view, n + d):
			continue
		# 踢完后自己站上原子弹格；该格若仍危险则只在「总比原地好」时用。
		if danger.has(n) and not danger.has(cell):
			continue
		return d
	return Vector2i.ZERO


static func _bomb_at(view: Dictionary, cell: Vector2i) -> bool:
	for bomb in view.get("bombs", []):
		if int(bomb.x) == cell.x and int(bomb.y) == cell.y:
			return true
	return false


## 踢弹滑入格是否为空地（无墙/弹/人/道具）。缩圈格不挡滑行。
static func _kick_dest_clear(view: Dictionary, dest: Vector2i) -> bool:
	if not _standable(view, dest):
		return false
	if _bomb_at(view, dest):
		return false
	for o in view.get("others", []):
		if o == dest:
			return false
	for raw in view.get("powerups", []):
		if (raw as Vector2i) == dest:
			return false
	return true


static func _standable(view: Dictionary, cell: Vector2i) -> bool:
	var cols := int(view.cols)
	var rows := int(view.rows)
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
		return false
	return int(view.grid[cell.y][cell.x]) == CELL_EMPTY


## 从 from 迈向 to 是否可走。has_kick 时，踩上可沿前进方向踢走的炸弹算可通行。
static func _can_enter(
	view: Dictionary,
	from: Vector2i,
	to: Vector2i,
	blocked: Dictionary,
	danger: Dictionary,
	allow_danger: bool,
	allow_kick: bool
) -> bool:
	if not _standable(view, to):
		return false
	if not allow_danger and danger.has(to):
		return false
	var has_bomb := _bomb_at(view, to)
	if has_bomb:
		if not (allow_kick and bool(view.get("has_kick", false))):
			return false
		var slide := to + (to - from)
		if not _kick_dest_clear(view, slide):
			return false
		return true
	# 无弹时仍尊重 others / lethal 阻挡。
	if blocked.has(to):
		return false
	return true


static func _find_step(
	view: Dictionary,
	origin: Vector2i,
	blocked: Dictionary,
	danger: Dictionary,
	allow_danger: bool,
	goal: Callable,
	_forbid_dir: Vector2i,
	allow_kick: bool
) -> Vector2i:
	var q: Array[Vector2i] = [origin]
	var prev: Dictionary = {origin: origin}
	var head := 0
	var found := Vector2i.ZERO
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c != origin and bool(goal.call(c)):
			found = c
			break
		for d in _DIRS:
			var n: Vector2i = c + d
			if prev.has(n):
				continue
			if not _can_enter(view, c, n, blocked, danger, allow_danger, allow_kick):
				continue
			prev[n] = c
			q.append(n)
	if found == Vector2i.ZERO:
		return Vector2i.ZERO
	var step_cell := found
	while prev[step_cell] != origin:
		step_cell = prev[step_cell]
	return step_cell - origin


static func _flood(
	view: Dictionary,
	origin: Vector2i,
	blocked: Dictionary,
	danger: Dictionary,
	allow_danger: bool
) -> Dictionary:
	var dist: Dictionary = {origin: 0}
	var q: Array[Vector2i] = [origin]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		var cd: int = int(dist[c])
		for d in _DIRS:
			var n: Vector2i = c + d
			if dist.has(n):
				continue
			if not _can_enter(view, c, n, blocked, danger, allow_danger, true):
				continue
			dist[n] = cd + 1
			q.append(n)
	return dist


static func _step_toward(
	view: Dictionary,
	origin: Vector2i,
	goal: Vector2i,
	blocked: Dictionary,
	danger: Dictionary,
	allow_danger: bool
) -> Vector2i:
	return _find_step(
		view, origin, blocked, danger, allow_danger,
		func(c: Vector2i) -> bool: return c == goal,
		Vector2i.ZERO, true
	)


static func _alternate_first_step(
	view: Dictionary,
	origin: Vector2i,
	goal: Vector2i,
	blocked: Dictionary,
	danger: Dictionary,
	forbid: Vector2i
) -> Vector2i:
	# 从 origin 的每个非 forbid 邻格出发，看能否到达 goal。
	for d in _DIRS:
		if d == forbid:
			continue
		var n: Vector2i = origin + d
		if not _can_enter(view, origin, n, blocked, danger, false, true):
			continue
		if n == goal:
			return d
		var reach := _flood_from(view, n, blocked, danger, false, origin)
		if reach.has(goal):
			return d
	return Vector2i.ZERO


static func _flood_from(
	view: Dictionary,
	start: Vector2i,
	blocked: Dictionary,
	danger: Dictionary,
	allow_danger: bool,
	also_block: Vector2i
) -> Dictionary:
	var blocked2: Dictionary = blocked.duplicate()
	if also_block != start:
		blocked2[also_block] = true
	var dist: Dictionary = {start: 0}
	var q: Array[Vector2i] = [start]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		var cd: int = int(dist[c])
		for d in _DIRS:
			var n: Vector2i = c + d
			if dist.has(n):
				continue
			if not _can_enter(view, c, n, blocked2, danger, allow_danger, true):
				continue
			dist[n] = cd + 1
			q.append(n)
	return dist
