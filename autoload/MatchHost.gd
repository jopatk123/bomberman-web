extends Node
## 每个房间码一个对局节点，各端都在 /root/MatchHost/<房间码>。
## 离线单机仍直接切到 game.tscn，不走这里。

const GAME_SCENE := "res://scenes/game.tscn"

var _packed: PackedScene


func open_room(code: String) -> Node2D:
	var norm := RoomCodes.normalize(code)
	if norm == "":
		return null
	var existing := get_node_or_null(NodePath(norm))
	if existing is Node2D:
		return existing
	if _packed == null:
		_packed = load(GAME_SCENE)
	var node := _packed.instantiate() as Node2D
	node.name = norm
	node.set_meta("room_code", norm)
	add_child(node)
	return node


func close_room(code: String) -> void:
	var norm := RoomCodes.normalize(code)
	if norm == "":
		return
	var existing := get_node_or_null(NodePath(norm))
	if existing:
		existing.queue_free()


func has_room(code: String) -> bool:
	var norm := RoomCodes.normalize(code)
	return norm != "" and get_node_or_null(NodePath(norm)) != null
