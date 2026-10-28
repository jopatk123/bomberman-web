class_name Airdrop
extends RefCounted
## 定时空投。对局开始后 FIRST_AT 秒落地第一件，之后每 INTERVAL 秒一件。
## 落地前 WARN_SEC 秒选出格子并预告；没有合法格，或预告格在落地前变成非法，就跳过这一轮。
## 不替代软墙掉落。随机数由调用方传入。真正写入道具字典时复用 PowerupDrop.consider。


const FIRST_AT := 15.0
const INTERVAL := 10.0
const WARN_SEC := 1.5
## 切比雪夫距离。出生点这个半径内可以投，但还有更远的空地就不用，减少开局白嫖。
const SPAWN_AVOID := 2

var elapsed: float = 0.0
## 下一轮应当落地的时刻。
var next_land_at: float = FIRST_AT
## 正在预告的格子。空字典表示没有预告。字段：x, y, kind。
var pending: Dictionary = {}


func reset() -> void:
	elapsed = 0.0
	next_land_at = FIRST_AT
	pending = {}


## 权威端每帧调用一次。
## world 需要 grid / cols / rows / bombs / powerups / lethal / next_id。
## bombs、powerups 的形状与 game_root 运行时字典一致。lethal 是 Vector2i → true。
## 返回 {warn, land, cancel, next_id}。
## warn 为 {x, y, kind} 或空；land 为 {id, x, y, kind} 或空。
## cancel 表示预告过、但落地前格子不再合法。没选中格子而跳过时 cancel 为 false。
## 落地成功时已经用 PowerupDrop.consider 写入 powerups，next_id 是下一个可用 id。
func tick(delta: float, world: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var next_id := int(world.get("next_id", 1))
	var result := {
		"warn": {},
		"land": {},
		"cancel": false,
		"next_id": next_id,
	}
	if delta < 0.0:
		delta = 0.0
	elapsed += delta
	var grid: Array = world.get("grid", [])
	var cols := int(world.get("cols", 0))
	var rows := int(world.get("rows", 0))
	var bombs: Dictionary = world.get("bombs", {})
	var powerups: Dictionary = world.get("powerups", {})
	var lethal: Dictionary = world.get("lethal", {})

	if pending.is_empty() and elapsed >= next_land_at - WARN_SEC:
		var cell := pick_cell(grid, cols, rows, bombs, powerups, lethal, rng)
		if cell.x < 0:
			# 这一轮没有落点。不预告，直接拨到下一轮。
			_finish_round()
		else:
			var kind := rng.randi_range(0, PlayerStats.Kind.PIERCE)
			pending = {"x": cell.x, "y": cell.y, "kind": kind}
			result.warn = pending.duplicate()

	if not pending.is_empty() and elapsed >= next_land_at:
		var cell := Vector2i(int(pending.x), int(pending.y))
		var kind := int(pending.kind)
		pending = {}
		if not is_legal_cell(cell, grid, cols, rows, bombs, powerups, lethal):
			result.cancel = true
			_finish_round()
		else:
			# roll 传 0：空投不走软墙的 38% 抽样，格子合法就写入。
			var pid := PowerupDrop.consider(cell, powerups, lethal, 0.0, kind, next_id)
			if pid < 0:
				result.cancel = true
				_finish_round()
			else:
				result.land = {"id": pid, "x": cell.x, "y": cell.y, "kind": kind}
				result.next_id = pid + 1
				_finish_round()
	return result


## 掉帧跨过整轮时只结算当前这一轮，把后面的时刻拨走，避免一次补出一串道具。
func _finish_round() -> void:
	next_land_at += INTERVAL
	while elapsed >= next_land_at:
		next_land_at += INTERVAL


## 合法落点：空地、没有炸弹、没有道具、不是致死格。
static func is_legal_cell(
	cell: Vector2i,
	grid: Array,
	cols: int,
	rows: int,
	bombs: Dictionary,
	powerups: Dictionary,
	lethal: Dictionary
) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
		return false
	if int(grid[cell.y][cell.x]) != Arena.CELL_EMPTY:
		return false
	if lethal.has(cell):
		return false
	if _powerup_at(powerups, cell):
		return false
	if _bomb_at(bombs, cell):
		return false
	return true


## 有远离出生点的格子就只在那些格子里抽；否则退回出生点附近。没有格子时返回 (-1, -1)。
static func pick_cell(
	grid: Array,
	cols: int,
	rows: int,
	bombs: Dictionary,
	powerups: Dictionary,
	lethal: Dictionary,
	rng: RandomNumberGenerator
) -> Vector2i:
	var preferred: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			var cell := Vector2i(x, y)
			if not is_legal_cell(cell, grid, cols, rows, bombs, powerups, lethal):
				continue
			if near_spawn(cell):
				fallback.append(cell)
			else:
				preferred.append(cell)
	var pool: Array[Vector2i] = preferred if not preferred.is_empty() else fallback
	if pool.is_empty():
		return Vector2i(-1, -1)
	return pool[rng.randi_range(0, pool.size() - 1)]


static func near_spawn(cell: Vector2i, radius: int = SPAWN_AVOID) -> bool:
	for s in Arena.spawn_cells():
		if maxi(absi(cell.x - s.x), absi(cell.y - s.y)) <= radius:
			return true
	return false


static func _powerup_at(powerups: Dictionary, cell: Vector2i) -> bool:
	for p in powerups.values():
		if typeof(p) != TYPE_DICTIONARY:
			continue
		if int(p.get("x", -999)) == cell.x and int(p.get("y", -999)) == cell.y:
			return true
	return false


static func _bomb_at(bombs: Dictionary, cell: Vector2i) -> bool:
	for b in bombs.values():
		if typeof(b) != TYPE_DICTIONARY:
			continue
		if int(b.get("x", -999)) == cell.x and int(b.get("y", -999)) == cell.y:
			return true
	return false
