extends Node2D
## Visual + cell meta for a bomber. Simulation lives on the authority (game_root.gd).
## meta: cell (Vector2i), peer_id (int)

const TEX_PLAYERS: Array[Texture2D] = [
	preload("res://assets/art/pixel/entities/player_blue.png"),
	preload("res://assets/art/pixel/entities/player_red.png"),
	preload("res://assets/art/pixel/entities/player_green.png"),
	preload("res://assets/art/pixel/entities/player_yellow.png"),
]


func setup(peer_id: int, cell: Vector2i, color: Color, display_name: String, tile: int) -> void:
	name = "Player_%d" % peer_id
	set_meta("cell", cell)
	set_meta("peer_id", peer_id)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)

	var body := Sprite2D.new()
	body.name = "Body"
	body.texture = _texture_for(color)
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.centered = true
	add_child(body)

	var label := Label.new()
	label.text = display_name
	label.position = Vector2(-24, -36)
	var font := load("res://assets/fonts/GameCJK.ttf")
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 12)
	add_child(label)


func _texture_for(color: Color) -> Texture2D:
	var best_i := 0
	var best_d := 1.0e9
	var palette: Array = GameState.PLAYER_COLORS
	for i in palette.size():
		var c: Color = palette[i]
		var d: float = absf(c.r - color.r) + absf(c.g - color.g) + absf(c.b - color.b)
		if d < best_d:
			best_d = d
			best_i = i
	return TEX_PLAYERS[best_i % TEX_PLAYERS.size()]


func set_cell(cell: Vector2i, tile: int) -> void:
	set_meta("cell", cell)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)


func mark_dead() -> void:
	modulate = Color(0.3, 0.3, 0.3, 0.5)
