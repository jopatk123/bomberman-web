class_name PowerupDrop
extends RefCounted
## Soft-wall drops. The caller supplies the random roll so this stays deterministic in tests.
## Inserts accepted drops into `powerups`. RPC packing stays with the caller.


const CHANCE := 0.38


## `roll` is a uniform 0..1 sample. Returns the new powerup id, or -1 when nothing drops.
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


## Returns {spawned, next_id}. `spawned` entries are {id, x, y, kind}.
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
