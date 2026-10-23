class_name MatchBoard
extends RefCounted
## Map tiles, pawn/bomb/powerup nodes, and short-lived blast or sudden-death polygons.
## Does not decide movement, blasts, or wins.
## Phase A pixel tiles: empty checker, hard, soft. Blast and sudden-death FX stay polygons.


const TILE := 48
const TEX_FLOOR_A: Texture2D = preload("res://assets/art/pixel/tiles/floor_a.png")
const TEX_FLOOR_B: Texture2D = preload("res://assets/art/pixel/tiles/floor_b.png")
const TEX_HARD: Texture2D = preload("res://assets/art/pixel/tiles/hard.png")
const TEX_SOFT: Texture2D = preload("res://assets/art/pixel/tiles/soft.png")

var map_layer: Node2D
var entities: Node2D
var powerups_layer: Node2D
var fx_layer: Node2D
var cols: int = 13
var rows: int = 11
var map_sprites: Array = []
var sd_visuals: Dictionary = {}


func bind(map: Node2D, ents: Node2D, drops: Node2D, fx: Node2D, grid_cols: int, grid_rows: int) -> void:
	map_layer = map
	entities = ents
	powerups_layer = drops
	fx_layer = fx
	cols = grid_cols
	rows = grid_rows


func cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)


func tile_texture(grid: Array, x: int, y: int) -> Texture2D:
	match int(grid[y][x]):
		Arena.CELL_HARD:
			return TEX_HARD
		Arena.CELL_SOFT:
			return TEX_SOFT
		_:
			return TEX_FLOOR_A if (x + y) % 2 == 0 else TEX_FLOOR_B


func draw_map(grid: Array, host: Node2D) -> void:
	for c in map_layer.get_children():
		(c as Node).queue_free()
	map_sprites.clear()
	for y in rows:
		var row: Array = []
		for x in cols:
			var spr := _make_tile(grid, x, y)
			map_layer.add_child(spr)
			row.append(spr)
		map_sprites.append(row)
	var map_w := cols * TILE
	var map_h := rows * TILE
	host.position = Vector2((960 - map_w) * 0.5, (720 - map_h) * 0.5 - 20)


func repaint_cells(grid: Array, cells: Array, host: Node2D) -> void:
	if map_sprites.size() != rows:
		draw_map(grid, host)
		return
	for c in cells:
		var x: int = int(c.x)
		var y: int = int(c.y)
		if y < 0 or y >= rows or x < 0 or x >= cols:
			continue
		var row: Array = map_sprites[y]
		if x >= row.size():
			draw_map(grid, host)
			return
		var spr: Sprite2D = row[x]
		if is_instance_valid(spr):
			spr.texture = tile_texture(grid, x, y)


func _make_tile(grid: Array, x: int, y: int) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(x * TILE, y * TILE)
	spr.texture = tile_texture(grid, x, y)
	return spr


func make_player(peer_id: int, cell: Vector2i, color: Color, display_name: String) -> Node2D:
	var root := Node2D.new()
	root.set_script(load("res://scripts/player.gd"))
	root.setup(peer_id, cell, color, display_name, TILE)
	return root


func clear_players() -> void:
	_free_prefix(entities, "Player_")


func spawn_bomb(bid: int, cell: Vector2i) -> void:
	if entities.get_node_or_null("Bomb_%d" % bid):
		return
	var root := Node2D.new()
	root.set_script(load("res://scripts/bomb.gd"))
	root.setup(bid, cell, TILE)
	entities.add_child(root)


func clear_bombs() -> void:
	_free_prefix(entities, "Bomb_")


func move_bomb(bid: int, cell: Vector2i) -> void:
	var node := entities.get_node_or_null("Bomb_%d" % bid)
	if node == null:
		return
	if node.has_method("set_cell"):
		node.set_cell(cell)
	else:
		node.position = cell_to_pos(cell)


func free_bomb(bid: int) -> void:
	var node := entities.get_node_or_null("Bomb_%d" % bid)
	if node:
		node.queue_free()


func spawn_powerup(pid: int, cell: Vector2i, kind: int) -> void:
	if powerups_layer.get_node_or_null("Powerup_%d" % pid):
		return
	var root := Node2D.new()
	root.set_script(load("res://scripts/powerup.gd"))
	root.setup(pid, cell, kind, TILE)
	powerups_layer.add_child(root)


func clear_powerup_nodes() -> void:
	if powerups_layer:
		for c in powerups_layer.get_children():
			(c as Node).queue_free()


func remove_powerup(pid: int) -> void:
	var n := powerups_layer.get_node_or_null("Powerup_%d" % pid)
	if n:
		n.queue_free()


func play_boom(bid: int, hit_cells: Array, sfx: Node) -> void:
	free_bomb(bid)
	if sfx and sfx.has_method("play_boom"):
		sfx.play_boom()
	for c in hit_cells:
		var flash := Polygon2D.new()
		flash.polygon = PackedVector2Array([
			Vector2(4, 4), Vector2(TILE - 4, 4), Vector2(TILE - 4, TILE - 4), Vector2(4, TILE - 4)
		])
		flash.position = Vector2(c.x * TILE, c.y * TILE)
		flash.color = Color(1.0, 0.75, 0.2, 0.9)
		fx_layer.add_child(flash)
		var core := Polygon2D.new()
		core.polygon = PackedVector2Array([
			Vector2(14, 14), Vector2(TILE - 14, 14), Vector2(TILE - 14, TILE - 14), Vector2(14, TILE - 14)
		])
		core.position = Vector2(c.x * TILE, c.y * TILE)
		core.color = Color(1.0, 0.95, 0.6, 0.95)
		fx_layer.add_child(core)
		var timer := fx_layer.get_tree().create_timer(0.28)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(flash):
				flash.queue_free()
			if is_instance_valid(core):
				core.queue_free()
		)


func pulse_player(node: Node2D, still_alive: Callable) -> void:
	node.modulate = Color(1.4, 1.4, 1.2, 1.0)
	var timer := node.get_tree().create_timer(0.15)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(node) and bool(still_alive.call()):
			node.modulate = Color.WHITE
	)


func add_sudden_death(cells: Array) -> void:
	for c in cells:
		var key := "%d,%d" % [c.x, c.y]
		if sd_visuals.has(key):
			continue
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(2, 2), Vector2(TILE - 2, 2), Vector2(TILE - 2, TILE - 2), Vector2(2, TILE - 2)
		])
		poly.position = Vector2(c.x * TILE, c.y * TILE)
		poly.color = Color(0.95, 0.25, 0.1, 0.72)
		poly.z_index = 2
		fx_layer.add_child(poly)
		sd_visuals[key] = poly


func clear_sudden_death() -> void:
	for key in sd_visuals.keys():
		var n: Node = sd_visuals[key]
		if is_instance_valid(n):
			n.queue_free()
	sd_visuals.clear()


func _free_prefix(parent: Node, prefix: String) -> void:
	if parent == null:
		return
	for c in parent.get_children():
		var n := c as Node
		if n.name.begins_with(prefix):
			n.queue_free()
