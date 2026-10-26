class_name MovePredict
extends RefCounted
## 客机移动链。下标 0 是主机最后确认的格子。
## 后面是提前画出来的步。主机确认会裁掉链头；
## 若再次确认的仍是链头，说明在途的那些步被拒绝了。


## 返回 {chain, show}。`show` 是本地角色该画在哪一格。
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
