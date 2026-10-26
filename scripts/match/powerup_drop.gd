class_name PowerupDrop
extends RefCounted
## 软墙掉落。随机数由调用方传入，测试里才能复现。
## 接受的掉落写进 `powerups`。RPC 打包仍由调用方做。


const CHANCE := 0.38


## `roll` 是 0 到 1 的均匀抽样。返回新道具 id；没掉则 -1。
static func consider(
	cell: Vector2i,
	powerups: Dictionary,
	lethal: Dictionary,
	roll: float,
	kind: int,
	next_id: int
) -> int:
	if roll > CHANCE:
		return -1
	for p in powerups.values():
		if int(p.x) == cell.x and int(p.y) == cell.y:
			return -1
	if lethal.has(cell):
		return -1
	var pid := next_id
	powerups[pid] = {"x": cell.x, "y": cell.y, "kind": kind}
	return pid


## 返回 {spawned, next_id}。`spawned` 每一项是 {id, x, y, kind}。
static func roll(
	cleared: Array,
	powerups: Dictionary,
	lethal: Dictionary,
	rng: RandomNumberGenerator,
	next_id: int
) -> Dictionary:
	var spawned: Array = []
	var cursor := next_id
	for c in cleared:
		var cell := c as Vector2i
		var sample := rng.randf()
		if sample > CHANCE:
			continue
		if _occupied(cell, powerups) or lethal.has(cell):
			continue
		var kind := rng.randi_range(0, PlayerStats.Kind.PIERCE)
		var pid := consider(cell, powerups, lethal, sample, kind, cursor)
		if pid < 0:
			continue
		cursor = pid + 1
		spawned.append({"id": pid, "x": cell.x, "y": cell.y, "kind": kind})
	return {"spawned": spawned, "next_id": cursor}


static func _occupied(cell: Vector2i, powerups: Dictionary) -> bool:
	for p in powerups.values():
		if int(p.x) == cell.x and int(p.y) == cell.y:
			return true
	return false


static func pack(spawned: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in spawned:
		out.append(int(s.id))
		out.append(int(s.x))
		out.append(int(s.y))
		out.append(int(s.kind))
	return out
