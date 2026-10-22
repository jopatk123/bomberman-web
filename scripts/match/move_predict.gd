class_name MovePredict
extends RefCounted
## Client move chain. Index 0 is the last cell the host confirmed.
## Later entries are steps shown early. Host acks trim the chain; a repeated
## ack of the head means the in-flight steps were rejected.


## Returns {chain, show}. `show` is the cell the local pawn should draw.
static func ack(chain: Array, cell: Vector2i) -> Dictionary:
	var idx := -1
	for i in chain.size():
		if chain[i] == cell:
			idx = i
			break
	if idx < 0 or (idx == 0 and chain.size() > 1):
		return {"chain": [cell], "show": cell}
	if idx == 0:
		var show: Vector2i = chain[chain.size() - 1]
		return {"chain": chain.duplicate(), "show": show}
	var next: Array = []
	for i in range(idx, chain.size()):
		next.append(chain[i])
	return {"chain": next, "show": next[next.size() - 1]}
