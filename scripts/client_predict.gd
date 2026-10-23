class_name ClientPredict
extends RefCounted
## Local pawn chain and the bomb ghost shown before the host confirms.
## MovePredict owns the ack rules. This type only stores the chain and the ghost node.


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


## Returns the cell the pawn should draw after this host ack.
func ack_cell(cell: Vector2i) -> Vector2i:
	var reconciled: Dictionary = MovePredict.ack(cells, cell)
	cells = reconciled.chain
	return reconciled.show


## Appends one predicted step when `can_step` accepts the destination.
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
		# Detach now so the next ghost keeps the "BombGhost" name this frame.
		if ghost.get_parent():
			ghost.get_parent().remove_child(ghost)
		ghost.queue_free()
	ghost = null
