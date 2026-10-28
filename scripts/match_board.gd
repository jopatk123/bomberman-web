class_name MatchBoard
extends RefCounted
## 地图地块、角色 / 炸弹 / 道具节点，以及短暂的爆炸和突然死亡特效。
## 不决定移动、爆炸或胜负。
## 像素地块，加上角色、爆炸、软墙碎裂贴图。突然死亡用危险格贴图。


const TILE := 48
const TEX_FLOOR_A: Texture2D = preload("res://assets/art/pixel/tiles/floor_a.png")
const TEX_FLOOR_B: Texture2D = preload("res://assets/art/pixel/tiles/floor_b.png")
const TEX_HARD: Texture2D = preload("res://assets/art/pixel/tiles/hard.png")
const TEX_SOFT: Texture2D = preload("res://assets/art/pixel/tiles/soft.png")
const TEX_BLAST_CENTER: Texture2D = preload("res://assets/art/pixel/fx/blast_center.png")
const TEX_BLAST_H: Texture2D = preload("res://assets/art/pixel/fx/blast_h.png")
const TEX_BLAST_V: Texture2D = preload("res://assets/art/pixel/fx/blast_v.png")
const TEX_SOFT_BREAK: Array[Texture2D] = [
	preload("res://assets/art/pixel/fx/soft_break_0.png"),
	preload("res://assets/art/pixel/fx/soft_break_1.png"),
	preload("res://assets/art/pixel/fx/soft_break_2.png"),
]
const TEX_SD_HAZARD: Array[Texture2D] = [
	preload("res://assets/art/pixel/fx/sd_hazard_0.png"),
	preload("res://assets/art/pixel/fx/sd_hazard_1.png"),
	preload("res://assets/art/pixel/fx/sd_hazard_2.png"),
]


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


func play_boom(bid: int, hit_cells: Array, sfx: Node, cleared_soft: Array = []) -> void:
	free_bomb(bid)
	if sfx and sfx.has_method("play_boom"):
		sfx.play_boom()
	var hit_set: Dictionary = {}
	for c in hit_cells:
		hit_set[c] = true
	var center: Vector2i = hit_cells[0] if not hit_cells.is_empty() else Vector2i(-1, -1)
	for c in hit_cells:
		var spr := Sprite2D.new()
		spr.texture = _blast_tex_for(c, center, hit_set)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.centered = true
		spr.position = cell_to_pos(c)
		spr.z_index = 3
		fx_layer.add_child(spr)
		var timer := fx_layer.get_tree().create_timer(0.32)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(spr):
				spr.queue_free()
		)
	for c in cleared_soft:
		_play_soft_shatter(c)


func _blast_tex_for(cell: Vector2i, center: Vector2i, hit_set: Dictionary) -> Texture2D:
	if cell == center:
		return TEX_BLAST_CENTER
	if cell.y == center.y:
		return TEX_BLAST_H
	if cell.x == center.x:
		return TEX_BLAST_V
	# 万一出现斜向命中，用邻格方向挑一张横或竖的焰贴图。
	var left := hit_set.has(cell + Vector2i(-1, 0))
	var right := hit_set.has(cell + Vector2i(1, 0))
	if left or right:
		return TEX_BLAST_H
	return TEX_BLAST_V


func _play_soft_shatter(cell: Vector2i) -> void:
	var spr := Sprite2D.new()
	spr.texture = TEX_SOFT_BREAK[0]
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.centered = true
	spr.position = cell_to_pos(cell)
	spr.z_index = 4
	fx_layer.add_child(spr)
	var tree := fx_layer.get_tree()
	for i in range(1, TEX_SOFT_BREAK.size()):
		var t := tree.create_timer(0.08 * float(i))
		var idx := i
		t.timeout.connect(func() -> void:
			if is_instance_valid(spr):
				spr.texture = TEX_SOFT_BREAK[idx]
		)
	var end_t := tree.create_timer(0.08 * float(TEX_SOFT_BREAK.size()) + 0.06)
	end_t.timeout.connect(func() -> void:
		if is_instance_valid(spr):
			spr.queue_free()
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
		var spr := Sprite2D.new()
		spr.texture = TEX_SD_HAZARD[0]
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.centered = true
		spr.position = cell_to_pos(c)
		spr.z_index = 2
		spr.modulate = Color(1.6, 1.35, 1.1, 1.0)
		spr.scale = Vector2(0.35, 0.35)
		fx_layer.add_child(spr)
		sd_visuals[key] = spr
		_animate_sd_appear(spr)


func _animate_sd_appear(spr: Sprite2D) -> void:
	if fx_layer == null or not is_instance_valid(spr):
		return
	var tree := fx_layer.get_tree()
	# 先弹出并闪一帧，再收成轻轻的循环脉动。
	var t1 := tree.create_timer(0.06)
	t1.timeout.connect(func() -> void:
		if not is_instance_valid(spr):
			return
		spr.texture = TEX_SD_HAZARD[1]
		spr.scale = Vector2(1.15, 1.15)
		spr.modulate = Color(1.8, 1.5, 1.2, 1.0)
	)
	var t2 := tree.create_timer(0.14)
	t2.timeout.connect(func() -> void:
		if not is_instance_valid(spr):
			return
		spr.texture = TEX_SD_HAZARD[2]
		spr.scale = Vector2(1.0, 1.0)
	)
	var t3 := tree.create_timer(0.26)
	t3.timeout.connect(func() -> void:
		if not is_instance_valid(spr):
			return
		spr.texture = TEX_SD_HAZARD[0]
		spr.modulate = Color(1.0, 1.0, 1.0, 0.92)
		_loop_sd_pulse(spr, 0)
	)


func _loop_sd_pulse(spr: Sprite2D, phase: int) -> void:
	if fx_layer == null or not is_instance_valid(spr):
		return
	var bright := (phase % 2) == 0
	spr.texture = TEX_SD_HAZARD[1 if bright else 0]
	spr.modulate = Color(1.25, 1.1, 1.0, 1.0) if bright else Color(1.0, 1.0, 1.0, 0.88)
	var wait := 0.55 if bright else 0.7
	var timer := fx_layer.get_tree().create_timer(wait)
	timer.timeout.connect(func() -> void:
		_loop_sd_pulse(spr, phase + 1)
	)


func show_airdrop_mark(cell: Vector2i) -> void:
	clear_airdrop_mark()
	if fx_layer == null:
		return
	var root := Node2D.new()
	root.name = "AirdropMark"
	root.z_index = 2
	root.position = Vector2(cell.x * TILE, cell.y * TILE)
	# 斜向阴影，再套一圈像素描边。
	root.add_child(_px_rect(Vector2(8, 10), Vector2(34, 34), Color(0, 0, 0, 0.45)))
	root.add_child(_px_rect(Vector2(6, 6), Vector2(36, 36), Color(0.1, 0.14, 0.22, 0.4)))
	var edge := Color(1.0, 0.92, 0.42, 1.0)
	root.add_child(_px_rect(Vector2(4, 4), Vector2(40, 2), edge))
	root.add_child(_px_rect(Vector2(4, 42), Vector2(40, 2), edge))
	root.add_child(_px_rect(Vector2(4, 4), Vector2(2, 40), edge))
	root.add_child(_px_rect(Vector2(42, 4), Vector2(2, 40), edge))
	fx_layer.add_child(root)
	if root.is_inside_tree():
		var tw := root.create_tween()
		tw.set_loops(0)
		tw.tween_property(root, "modulate:a", 0.45, 0.28)
		tw.tween_property(root, "modulate:a", 1.0, 0.28)


func clear_airdrop_mark() -> void:
	if fx_layer == null:
		return
	var n := fx_layer.get_node_or_null("AirdropMark")
	if n:
		n.free()


func _px_rect(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = pos
	rect.size = size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


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
