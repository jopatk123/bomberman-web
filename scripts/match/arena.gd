class_name Arena
extends RefCounted
## Classic 13×11 arena: hard border, odd pillars, soft walls, four corner spawns.
## Pure data — no nodes. Cell values match BlastRules / game_root Cell enum.

const COLS := 13
const ROWS := 11
const CELL_EMPTY := 0
const CELL_HARD := 1
const CELL_SOFT := 2
const SOFT_CHANCE := 0.55


static func empty_grid() -> Array:
	var grid: Array = []
	for y in ROWS:
		var row: Array = []
		for x in COLS:
			var cell := CELL_EMPTY
			if x == 0 or y == 0 or x == COLS - 1 or y == ROWS - 1:
				cell = CELL_HARD
			elif x % 2 == 0 and y % 2 == 0:
				cell = CELL_HARD
			row.append(cell)
		grid.append(row)
	return grid


static func spawn_cells() -> Array[Vector2i]:
	return [
		Vector2i(1, 1),
		Vector2i(COLS - 2, 1),
		Vector2i(1, ROWS - 2),
		Vector2i(COLS - 2, ROWS - 2),
	]


## Spawn cells and their orthogonal neighbors stay empty so players can leave.
static func place_soft_walls(grid: Array, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var keep_clear: Dictionary = {}
	for s in spawn_cells():
		keep_clear[s] = true
		var adj: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for d in adj:
			keep_clear[s + d] = true
	for y in range(1, ROWS - 1):
		for x in range(1, COLS - 1):
			if int(grid[y][x]) != CELL_EMPTY:
				continue
			if keep_clear.has(Vector2i(x, y)):
				continue
			if rng.randf() < SOFT_CHANCE:
				grid[y][x] = CELL_SOFT
