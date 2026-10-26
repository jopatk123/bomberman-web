class_name BlastRules
extends RefCounted
## 可预期的爆炸、连环、清软墙规则（权威端算，客户端套用封包）。
##
## 规则（写在这里，并由 compute_rays 执行）：
## 1. 爆炸从炸弹中心沿上下左右走出，最远 `blast_range` 格。
## 2. 硬墙：射线停下，这一格不算命中。穿透也过不了硬墙。
## 3. 软墙：这一格命中，软墙被炸开。没有穿透时射线停在这里；
##    有穿透则穿过这块软墙继续走，直到用完 `blast_range`。
## 4. 空地：命中，射线继续。
## 5. 连环：另一颗炸弹若落在命中格上就会引爆（由调用方递归）。
## 6. 命中格上的道具由调用方清掉，但本轮爆炸刚从软墙里掉出来的道具除外。
## 7. 多人抢同一格：权威端只按调用顺序处理移动和拾取。
## 8. 踢进有道具的格子：炸弹不进入、也不捡道具，停在前一格（见 game_root）。

const CELL_EMPTY := 0
const CELL_HARD := 1
const CELL_SOFT := 2


## 返回 { "hit": Array[Vector2i], "cleared_soft": Array[Vector2i] }
## `pierce` 默认 false，旧调用方仍是「软墙挡住射线」。
static func compute_rays(
	grid: Array,
	origin: Vector2i,
	blast_range: int,
	cols: int,
	rows: int,
	pierce: bool = false
) -> Dictionary:
	var hit: Array[Vector2i] = [origin]
	var cleared: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for dir in dirs:
		for dist in range(1, blast_range + 1):
			var c: Vector2i = origin + dir * dist
			if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
				break
			var t: int = int(grid[c.y][c.x])
			if t == CELL_HARD:
				break
			hit.append(c)
			if t == CELL_SOFT:
				cleared.append(c)
				if not pierce:
					break
	return {"hit": hit, "cleared_soft": cleared}


static func cells_to_packed(cells: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in cells:
		out.append(int(c.x))
		out.append(int(c.y))
	return out


static func packed_to_cells(xy: PackedInt32Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(0, xy.size(), 2):
		out.append(Vector2i(xy[i], xy[i + 1]))
	return out
