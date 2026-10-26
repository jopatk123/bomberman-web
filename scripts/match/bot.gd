class_name MatchBot
extends RefCounted
## 一个角色在这一拍怎么走。先躲爆炸，旁边有道具就捡；
## 有退路才炸软墙或另一个人，否则就走路。
## 权威端对每个 MatchFill 人机调用一次。这里不发 RPC。

## 第一个补位槽。真实编号以 MatchFill.bot_peer_id(1) 为准。
const PEER_ID := -1001
const NAME := "人机1"
## 还在正常引信上的炸弹算危险。调试用的超长计时不算。
const DANGER_TIME := 2.05

enum Action { WAIT = 0, MOVE = 1, BOMB = 2 }

const CELL_EMPTY := 0
const CELL_SOFT := 2

const _DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0),
]


## 视野 view 包含：grid、cols、rows、cell、blast_range、can_place、bombs[]、others[]、lethal[]、powerups[]
## 炸弹列表 bombs[] 的每一项是 {x, y, timer, range, pierce}
## powerups[]：Vector2i 格子。决策只看这份视图，不读外部状态。
## 返回 {action, dx, dy}。
static func decide(view: Dictionary) -> Dictionary:
	var cell: Vector2i = view.cell
	var danger := _danger(view)
	var blocked := _blocked(view, cell)
	if danger.has(cell):
		var flee := _bfs(view, cell, blocked, danger, true, func(c: Vector2i) -> bool:
			return not danger.has(c)
		)
		if flee != Vector2i.ZERO:
			return _move(flee)
		return _wait()
	var grab := _adjacent_powerup(view, cell, danger, blocked)
	if grab != Vector2i.ZERO:
		return _move(grab)
	if bool(view.get("can_place", false)) and _worth_placing(view, cell, danger, blocked):
		return {"action": Action.BOMB, "dx": 0, "dy": 0}
	var others: Array = view.get("others", [])
	var step := _bfs(view, cell, blocked, danger, false, func(c: Vector2i) -> bool:
		return _is_interest(view, c, others)
	)
	if step != Vector2i.ZERO:
		return _move(step)
	for d in _DIRS:
		var n := cell + d
		if _standable(view, n) and not blocked.has(n) and not danger.has(n):
			return _move(d)
	return _wait()


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
	# 射程至少 1 时，四个邻格一定会被烧到。先迈出去，再侧到安全格。
	for d in _DIRS:
		var n: Vector2i = cell + d
		if not _standable(view, n) or blocked.has(n):
			continue
		for d2 in _DIRS:
			var m: Vector2i = n + d2
			if m == cell:
				continue
			if not _standable(view, m) or blocked.has(m):
				continue
			if m in hits or danger.has(m):
				continue
			return true
	return false


static func _adjacent_powerup(view: Dictionary, cell: Vector2i, danger: Dictionary, blocked: Dictionary) -> Vector2i:
	for raw in view.get("powerups", []):
		var p := raw as Vector2i
		if absi(p.x - cell.x) + absi(p.y - cell.y) != 1:
			continue
		if not _standable(view, p) or blocked.has(p) or danger.has(p):
			continue
		return p - cell
	return Vector2i.ZERO


static func _is_interest(view: Dictionary, cell: Vector2i, others: Array) -> bool:
	var grid: Array = view.grid
	var cols := int(view.cols)
	var rows := int(view.rows)
	for raw in view.get("powerups", []):
		if (raw as Vector2i) == cell:
			return true
	for d in _DIRS:
		var n: Vector2i = cell + d
		if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
			continue
		if int(grid[n.y][n.x]) == CELL_SOFT:
			return true
	for o in others:
		if absi(o.x - cell.x) + absi(o.y - cell.y) == 1:
			return true
	return false


static func _standable(view: Dictionary, cell: Vector2i) -> bool:
	var cols := int(view.cols)
	var rows := int(view.rows)
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
		return false
	return int(view.grid[cell.y][cell.x]) == CELL_EMPTY


## 广度优先搜索。allow_danger 用来穿过火区，找到第一格安全地。
## 返回第一步；没有符合的格子时返回 ZERO。
static func _bfs(
	view: Dictionary,
	origin: Vector2i,
	blocked: Dictionary,
	danger: Dictionary,
	allow_danger: bool,
	goal: Callable
) -> Vector2i:
	var q: Array[Vector2i] = [origin]
	var prev: Dictionary = {origin: origin}
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c != origin and bool(goal.call(c)):
			var step := c
			while prev[step] != origin:
				step = prev[step]
			return step - origin
		for d in _DIRS:
			var n: Vector2i = c + d
			if prev.has(n):
				continue
			if not _standable(view, n) or blocked.has(n):
				continue
			if not allow_danger and danger.has(n):
				continue
			prev[n] = c
			q.append(n)
	return Vector2i.ZERO
