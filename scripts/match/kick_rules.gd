class_name KickRules
extends RefCounted
## Bomb kick / owner bomb-pass helpers (authority uses these; RPC stays in game_root).
##
## RULES:
## 1. Owner may walk through a bomb they just placed until they leave that cell
##    (non-solid). After they leave, the bomb is solid for everyone including them.
## 2. A solid bomb blocks entry unless the walker has kick AND the next cell
##    along the move can accept the bomb.
## 3. Kick slides one cell at a time. Soft walls are NOT destroyed by kick.
##    A bomb stops before hard/soft/bomb/player/powerup/edge.
## 4. Kick into a powerup cell: the bomb does not enter or collect the powerup.
## 5. A sudden-death cell does not block the slide. The caller detonates the bomb
##    when it enters existing fire. A shrink ring that covers a bomb consumes it
##    without an extra blast (that path lives in game_root).

enum Enter { BLOCKED, WALK, KICK }


## Returns bomb id on cell, or -1.
static func bomb_id_at(bombs: Dictionary, cell: Vector2i) -> int:
	for bid in bombs.keys():
		var b: Dictionary = bombs[bid]
		if int(b.x) == cell.x and int(b.y) == cell.y:
			return int(bid)
	return -1


## How `peer_id` may step onto the cell that currently holds bomb `bid`.
## `can_slide_to` is called with the bomb's destination cell and returns bool.
static func classify_enter(
	bid: int,
	bombs: Dictionary,
	peer_id: int,
	has_kick: bool,
	dx: int,
	dy: int,
	can_slide_to: Callable
) -> Enter:
	if not bombs.has(bid):
		return Enter.WALK
	var b: Dictionary = bombs[bid]
	var solid: bool = bool(b.get("solid", true))
	var is_owner := int(b.get("owner", 0)) == peer_id
	if not solid and is_owner:
		return Enter.WALK
	if has_kick:
		var dest := Vector2i(int(b.x) + dx, int(b.y) + dy)
		if bool(can_slide_to.call(dest)):
			return Enter.KICK
	return Enter.BLOCKED


## Destination blocked for a sliding bomb?
## `player_cells` and `powerup_cells` are sets: Vector2i -> true.
static func slide_blocked(
	dest: Vector2i,
	cols: int,
	rows: int,
	grid: Array,
	cell_hard: int,
	cell_soft: int,
	bombs: Dictionary,
	player_cells: Dictionary,
	powerup_cells: Dictionary
) -> bool:
	if dest.x < 0 or dest.y < 0 or dest.x >= cols or dest.y >= rows:
		return true
	var t: int = int(grid[dest.y][dest.x])
	if t == cell_hard or t == cell_soft:
		return true
	if bomb_id_at(bombs, dest) >= 0:
		return true
	if player_cells.has(dest):
		return true
	if powerup_cells.has(dest):
		return true
	return false
