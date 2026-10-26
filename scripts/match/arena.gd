class_name Arena
extends RefCounted
## 经典 13×11 场地：硬墙围边、四角出生点，软墙按种子铺。
## 纯数据，没有节点。格子取值与 BlastRules / game_root 的 Cell 枚举一致。

const COLS := 13
const ROWS := 11
const CELL_EMPTY := 0
const CELL_HARD := 1
const CELL_SOFT := 2
const SOFT_CHANCE := 0.55

## 只给大厅用：开局时再落到一张具体地图。
const MAP_RANDOM := 4  # OptionButton 把 -1 当成「用下标」；随机值必须落在布局钳制范围之外

enum MapId { CLASSIC = 0, OPEN = 1, CROSS = 2, MAZE = 3 }


static func clamp_map_id(id: int) -> int:
	return clampi(id, int(MapId.CLASSIC), int(MapId.MAZE))


static func is_random_map(id: int) -> bool:
	return int(id) == MAP_RANDOM


## 大厅允许的偏好：随机，或一张具体地图。
static func lobby_map_id(id: int) -> int:
	if is_random_map(id):
		return MAP_RANDOM
	return clamp_map_id(id)


## 本局实际布局。偏好是随机时在这里抽一张。
static func resolve_map_id(id: int) -> int:
	if is_random_map(id):
		return randi_range(int(MapId.CLASSIC), int(MapId.MAZE))
	return clamp_map_id(id)


static func map_name(id: int) -> String:
	if is_random_map(id):
		return "随机"
	match clamp_map_id(id):
		MapId.CLASSIC:
			return "经典"
		MapId.OPEN:
			return "开阔"
		MapId.CROSS:
			return "十字"
		MapId.MAZE:
			return "迷宫"
		_:
			return "经典"


static func map_desc(id: int) -> String:
	if is_random_map(id):
		return "开局时在四种地图里随机"
	match clamp_map_id(id):
		MapId.CLASSIC:
			return "标准柱阵，攻守均衡"
		MapId.OPEN:
			return "无内柱，火力对轰"
		MapId.CROSS:
			return "中央十字硬墙，分割战场"
		MapId.MAZE:
			return "走廊密布，绕路突袭"
		_:
			return ""


## 经典硬墙布局的别名，给旧调用方留着。
static func empty_grid() -> Array:
	return build_base_grid(MapId.CLASSIC)


static func build_base_grid(map_id: int = MapId.CLASSIC) -> Array:
	match clamp_map_id(map_id):
		MapId.OPEN:
			return _border_only_grid()
		MapId.CROSS:
			return _cross_grid()
		MapId.MAZE:
			return _maze_grid()
		_:
			return _classic_grid()


static func build_match_grid(map_id: int, soft_seed: int) -> Array:
	var grid := build_base_grid(map_id)
	place_soft_walls(grid, soft_seed)
	return grid


static func spawn_cells() -> Array[Vector2i]:
	return [
		Vector2i(1, 1),
		Vector2i(COLS - 2, 1),
		Vector2i(1, ROWS - 2),
		Vector2i(COLS - 2, ROWS - 2),
	]


## 出生格及其上下左右邻格：不能是硬墙，也不能被软墙堵住。
static func spawn_clear_cells() -> Dictionary:
	var keep_clear: Dictionary = {}
	for s in spawn_cells():
		keep_clear[s] = true
		var adj: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
		]
		for d in adj:
			keep_clear[s + d] = true
	return keep_clear


## 出生格和正交邻格保持空着，玩家才能走出来。
static func place_soft_walls(grid: Array, seed: int, soft_chance: float = SOFT_CHANCE) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var keep_clear := spawn_clear_cells()
	for y in range(1, ROWS - 1):
		for x in range(1, COLS - 1):
			if int(grid[y][x]) != CELL_EMPTY:
				continue
			if keep_clear.has(Vector2i(x, y)):
				continue
			if rng.randf() < soft_chance:
				grid[y][x] = CELL_SOFT


static func count_hard(grid: Array) -> int:
	var n := 0
	for y in ROWS:
		for x in COLS:
			if int(grid[y][x]) == CELL_HARD:
				n += 1
	return n


static func _border_only_grid() -> Array:
	var grid: Array = []
	for y in ROWS:
		var row: Array = []
		for x in COLS:
			var cell := CELL_EMPTY
			if x == 0 or y == 0 or x == COLS - 1 or y == ROWS - 1:
				cell = CELL_HARD
			row.append(cell)
		grid.append(row)
	return grid


static func _classic_grid() -> Array:
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


## 经典柱阵，再加上正中一行一列的十字硬墙。
## 每边留出 3 格走廊，四角仍然互相走得到。
static func _cross_grid() -> Array:
	var grid := _classic_grid()
	var keep_clear := spawn_clear_cells()
	var mid_x := COLS / 2
	var mid_y := ROWS / 2
	for x in range(1, COLS - 1):
		var c := Vector2i(x, mid_y)
		if not keep_clear.has(c):
			grid[mid_y][x] = CELL_HARD
	for y in range(1, ROWS - 1):
		var c := Vector2i(mid_x, y)
		if not keep_clear.has(c):
			grid[y][mid_x] = CELL_HARD
	var clear_cells: Array[Vector2i] = [
		Vector2i(mid_x, 2), Vector2i(mid_x - 1, 2), Vector2i(mid_x + 1, 2),
		Vector2i(mid_x, 8), Vector2i(mid_x - 1, 8), Vector2i(mid_x + 1, 8),
		Vector2i(2, mid_y), Vector2i(2, mid_y - 1), Vector2i(2, mid_y + 1),
		Vector2i(10, mid_y), Vector2i(10, mid_y - 1), Vector2i(10, mid_y + 1),
	]
	for c in clear_cells:
		if c.x <= 0 or c.y <= 0 or c.x >= COLS - 1 or c.y >= ROWS - 1:
			continue
		if keep_clear.has(c):
			continue
		grid[c.y][c.x] = CELL_EMPTY
	return grid


## 经典柱阵再堵几段走廊；留下的开口仍把四角连在一起。
static func _maze_grid() -> Array:
	var grid := _classic_grid()
	var keep_clear := spawn_clear_cells()
	# 柱子之间额外堵上硬墙（y=2/5/8 和 x=6 的通道留空）。
	var extra: Array[Vector2i] = [
		Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 6), Vector2i(3, 7),
		Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 6), Vector2i(9, 7),
		Vector2i(5, 3), Vector2i(7, 3), Vector2i(5, 7), Vector2i(7, 7),
		Vector2i(4, 5), Vector2i(8, 5), Vector2i(5, 4), Vector2i(7, 4),
		Vector2i(5, 6), Vector2i(7, 6),
	]
	for c in extra:
		if keep_clear.has(c):
			continue
		if c.x <= 0 or c.y <= 0 or c.x >= COLS - 1 or c.y >= ROWS - 1:
			continue
		grid[c.y][c.x] = CELL_HARD
	return grid
