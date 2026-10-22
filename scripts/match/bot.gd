class_name MatchBot
extends RefCounted
## Solo opponent. Pure decision: flee blasts, bomb soft walls or the human, otherwise walk.
## game_root applies the result only while GameState.solo_bot is set. No RPC here.

const PEER_ID := 2
const NAME := "电脑"
## Bombs still on a normal fuse count as danger. Long debug timers do not.
const DANGER_TIME := 2.05

enum Action { WAIT = 0, MOVE = 1, BOMB = 2 }

const CELL_EMPTY := 0
const CELL_SOFT := 2

const _DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0),
]


## view: grid, cols, rows, cell, blast_range, can_place, bombs[], others[], lethal[]
## bombs[]: {x, y, timer, range, pierce}
## Returns {action, dx, dy}.
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
	# Range ≥ 1 always burns the four neighbors. Escape is step out, then aside.
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


static func _is_interest(view: Dictionary, cell: Vector2i, others: Array) -> bool:
	var grid: Array = view.grid
	var cols := int(view.cols)
	var rows := int(view.rows)
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


## BFS. allow_danger is for fleeing through a blast to the first safe cell.
## Returns the first step, or ZERO when nothing matches.
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
