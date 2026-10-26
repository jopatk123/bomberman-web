class_name KickRules
extends RefCounted
## 踢弹，以及放弹者穿过自己刚放的炸弹（权威端用；RPC 留在 game_root）。
##
## 规则：
## 1. 放弹者在离开那一格之前可以穿过去（此时炸弹还不是实体）。
##    离开之后，炸弹对所有人（包括自己）都变成实体。
## 2. 实体炸弹挡住进入，除非走路的人有踢弹，且沿移动方向的下一格能接住炸弹。
## 3. 踢弹一格一格滑。踢弹不炸软墙。
##    硬墙、软墙、炸弹、玩家、道具、地图边缘都会让炸弹停在前面。
## 4. 踢进有道具的格子：炸弹不进入，也不捡道具。
## 5. 突然死亡的格子不挡住滑行。调用方在炸弹进入已有火焰时引爆。
##    缩圈盖住炸弹时直接吞掉，不再额外炸一次（这条在 game_root）。

enum Enter { BLOCKED, WALK, KICK }


## 返回这一格上的炸弹 id，没有则 -1。
static func bomb_id_at(bombs: Dictionary, cell: Vector2i) -> int:
	for bid in bombs.keys():
		var b: Dictionary = bombs[bid]
		if int(b.x) == cell.x and int(b.y) == cell.y:
			return int(bid)
	return -1


## `peer_id` 能不能踩上当前放着炸弹 `bid` 的那一格。
## `can_slide_to` 用炸弹的目标格调用，返回是否滑得过去。
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


## 滑行目标格是否被挡住。
## `player_cells` 和 `powerup_cells` 是集合：Vector2i → true。
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
