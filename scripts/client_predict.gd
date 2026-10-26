class_name ClientPredict
extends RefCounted
## 本地角色的预演链，以及主机确认前先画出来的影子炸弹。
## 确认规则在 MovePredict。这里只存这条链和影子节点。


var cells: Array = []
var ghost_gen: int = 0
var ghost: Node2D


func clear_chain() -> void:
	cells.clear()


func seed(cell: Vector2i) -> void:
	cells = [cell]


func tip(fallback: Vector2i) -> Vector2i:
	if not cells.is_empty():
		return cells[cells.size() - 1]
	return fallback


## 这次主机确认之后，角色该画在哪一格。
func ack_cell(cell: Vector2i) -> Vector2i:
	var reconciled: Dictionary = MovePredict.ack(cells, cell)
	cells = reconciled.chain
	return reconciled.show


## `can_step` 接受目标格时，追加一步预演。
func push_step(dir: Vector2i, origin: Vector2i, can_step: Callable) -> bool:
	if cells.is_empty():
		cells = [origin]
	var nxt: Vector2i = tip(origin) + dir
	if not bool(can_step.call(nxt)):
		return false
	cells.append(nxt)
	return true


func show_ghost(host: Node, entities: Node2D, cell: Vector2i, tile: int) -> void:
	clear_ghost()
	var gen := ghost_gen
	var root := Node2D.new()
	root.set_script(load("res://scripts/bomb.gd"))
	root.setup(0, cell, tile)
	root.name = "BombGhost"
	entities.add_child(root)
	ghost = root
	var timer := host.get_tree().create_timer(0.45)
	timer.timeout.connect(func() -> void:
		if gen == ghost_gen and host.is_inside_tree():
			clear_ghost()
	)


func clear_ghost() -> void:
	ghost_gen += 1
	if is_instance_valid(ghost):
		# 这一帧先摘下来，下一颗影子才能继续叫 BombGhost。
		if ghost.get_parent():
			ghost.get_parent().remove_child(ghost)
		ghost.queue_free()
	ghost = null
