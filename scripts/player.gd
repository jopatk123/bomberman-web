extends Node2D
## Visual + cell meta for a bomber. Simulation lives on the authority (game_root.gd).
## meta: cell (Vector2i), peer_id (int)

func setup(peer_id: int, cell: Vector2i, color: Color, display_name: String, tile: int) -> void:
	name = "Player_%d" % peer_id
	set_meta("cell", cell)
	set_meta("peer_id", peer_id)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)
	])
	body.color = color
	add_child(body)
	var label := Label.new()
	label.text = display_name
	label.position = Vector2(-24, -36)
	label.add_theme_font_size_override("font_size", 12)
	add_child(label)


func set_cell(cell: Vector2i, tile: int) -> void:
	set_meta("cell", cell)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)


func mark_dead() -> void:
	modulate = Color(0.3, 0.3, 0.3, 0.5)
