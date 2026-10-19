class_name KickRules
extends RefCounted
## Bomb kick / owner bomb-pass helpers (authority uses these; RPC stays in game_root).
##
## RULES:
## 1. Owner may walk off the cell of a bomb they just placed (owner pass).
## 2. Others cannot enter a bomb cell unless they have kick and the next cell
##    along the kick direction is free for the bomb to slide into.
## 3. Kick slides one cell in the move direction when possible; soft walls are
##    NOT destroyed by kick; bomb stops before hard/soft/bomb/player/powerup/edge.
## 4. Kick into a powerup cell: bomb does not enter or collect the powerup.

## Returns bomb id on cell, or -1.
static func bomb_id_at(bombs: Dictionary, cell: Vector2i) -> int:
	for bid in bombs.keys():
		var b: Dictionary = bombs[bid]
		if int(b.x) == cell.x and int(b.y) == cell.y:
			return int(bid)
	return -1


## Can this peer step onto `next` which currently has bomb `bid`?
static func can_enter_bomb_cell(
	bid: int,
	bombs: Dictionary,
	peer_id: int,
	has_kick: bool,
	dx: int,
	dy: int,
	can_slide_to: Callable
) -> bool:
	if not bombs.has(bid):
		return false
	var b: Dictionary = bombs[bid]
	# Owner standing on own bomb may leave any direction onto empty — handled by caller
	# walking OFF; entering another bomb:
	if has_kick:
		var dest := Vector2i(int(b.x) + dx, int(b.y) + dy)
		return bool(can_slide_to.call(dest))
	return false


## True if owner is allowed to leave their bomb cell (always, once placed).
static func owner_may_leave(bid: int, bombs: Dictionary, peer_id: int) -> bool:
	if not bombs.has(bid):
		return true
	return int(bombs[bid].get("owner", 0)) == peer_id


## Destination blocked for a sliding bomb?
static func slide_blocked(
	dest: Vector2i,
	cols: int,
	rows: int,
	grid: Array,
	cell_hard: int,
	cell_soft: int,
	bombs: Dictionary,
	player_cells: Array,
	powerup_cells: Array
) -> bool:
	if dest.x < 0 or dest.y < 0 or dest.x >= cols or dest.y >= rows:
		return true
	var t: int = int(grid[dest.y][dest.x])
	if t == cell_hard or t == cell_soft:
		return true
	if bomb_id_at(bombs, dest) >= 0:
		return true
	for pc in player_cells:
		if pc == dest:
			return true
	for uc in powerup_cells:
		if uc == dest:
			return true
	return false
