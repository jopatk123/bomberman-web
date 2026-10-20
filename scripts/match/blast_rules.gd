class_name BlastRules
extends RefCounted
## Predictable blast / chain / soft-clear rules (authority computes, clients apply packs).
##
## RULES (documented + enforced by compute_rays):
## 1. Blast travels orthogonally up to `blast_range` cells from the bomb center.
## 2. HARD wall: ray STOPS; cell is NOT hit. Pierce never passes a hard wall.
## 3. SOFT wall: cell IS hit, soft is destroyed. Without pierce the ray STOPS.
##    With pierce the ray CONTINUES through that soft, up to `blast_range`.
## 4. EMPTY: cell is hit; ray continues.
## 5. Chain: any other bomb whose cell is in hit_cells detonates (caller recurses).
## 6. Powerups sitting in hit cells are destroyed by the caller, EXCEPT powerups
##    freshly spawned from soft walls cleared by THIS same explosion.
## 7. Multi-player same-cell races: authority processes moves/pickups in call order only.
## 8. Kick into a powerup cell: bomb does NOT enter / collect — stops before (see game_root).

const CELL_EMPTY := 0
const CELL_HARD := 1
const CELL_SOFT := 2


## Returns { "hit": Array[Vector2i], "cleared_soft": Array[Vector2i] }
## `pierce` defaults to false so existing callers keep "soft stops the ray".
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
