@tool
extends Node2D
## 对局画面：地块、角色、炸弹、道具、短暂特效。
## 只负责画；移动、爆炸、胜负都在 scripts/match/ 与 game_root.gd。
## 节点树在 scenes/game/board.tscn 里手工摆好，脚本只按运行时数据填内容。

const BLAST_LIFETIME := 0.32

const PLAYER_SCENE: PackedScene = preload("res://scenes/game/player.tscn")
const BOMB_SCENE: PackedScene = preload("res://scenes/game/bomb.tscn")
const POWERUP_SCENES: Array[PackedScene] = [
	preload("res://scenes/game/powerup_bomb.tscn"),
	preload("res://scenes/game/powerup_range.tscn"),
	preload("res://scenes/game/powerup_speed.tscn"),
	preload("res://scenes/game/powerup_kick.tscn"),
	preload("res://scenes/game/powerup_pierce.tscn"),
]
const BLAST_CENTER_SCENE: PackedScene = preload("res://scenes/game/blast_center.tscn")
const BLAST_H_SCENE: PackedScene = preload("res://scenes/game/blast_h.tscn")
const BLAST_V_SCENE: PackedScene = preload("res://scenes/game/blast_v.tscn")
const SOFT_BREAK_SCENE: PackedScene = preload("res://scenes/game/soft_break.tscn")
const SD_HAZARD_SCENE: PackedScene = preload("res://scenes/game/sd_hazard.tscn")
const AIRDROP_MARK_SCENE: PackedScene = preload("res://scenes/game/airdrop_mark.tscn")

## 地块 TileSet 的 source id：0 floor_a、1 floor_b、2 hard、3 soft。
const SRC_FLOOR_A := 0
const SRC_FLOOR_B := 1
const SRC_HARD := 2
const SRC_SOFT := 3

## sd_visuals: "x,y" → 缩圈危险格节点
var sd_visuals: Dictionary = {}

@onready var ground: TileMapLayer = $Ground
@onready var entities: Node2D = $Entities
@onready var powerups_layer: Node2D = $Powerups
@onready var fx_layer: Node2D = $FX


func _ready() -> void:
	# 编辑器里画一张经典图作预览；运行时由 draw_map 清掉重画。
	if Engine.is_editor_hint():
		draw_map(Arena.build_base_grid(0))


func cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * Arena.TILE + Arena.TILE * 0.5, cell.y * Arena.TILE + Arena.TILE * 0.5)


func draw_map(grid: Array) -> void:
	ground.clear()
	for y in grid.size():
		var row: Array = grid[y]
		for x in row.size():
			ground.set_cell(Vector2i(x, y), _source_for(int(row[x]), x, y), Vector2i.ZERO)


func repaint_cells(grid: Array, cells: Array) -> void:
	for c in cells:
		var x: int = int(c.x)
		var y: int = int(c.y)
		if y < 0 or y >= grid.size():
			continue
		if x < 0 or x >= (grid[y] as Array).size():
			continue
		ground.set_cell(Vector2i(x, y), _source_for(int(grid[y][x]), x, y), Vector2i.ZERO)


func _source_for(cell_value: int, x: int, y: int) -> int:
	match cell_value:
		Arena.CELL_HARD:
			return SRC_HARD
		Arena.CELL_SOFT:
			return SRC_SOFT
		_:
			return SRC_FLOOR_A if (x + y) % 2 == 0 else SRC_FLOOR_B


func make_player(peer_id: int, cell: Vector2i, color: Color, display_name: String) -> Node2D:
	var node: Node2D = PLAYER_SCENE.instantiate()
	node.setup(peer_id, cell, color, display_name, Arena.TILE)
	return node


func clear_players() -> void:
	_free_prefix(entities, "Player_")


func spawn_bomb(bid: int, cell: Vector2i) -> void:
	if entities.get_node_or_null("Bomb_%d" % bid):
		return
	var node: Node2D = BOMB_SCENE.instantiate()
	node.setup(bid, cell, Arena.TILE)
	entities.add_child(node)


func clear_bombs() -> void:
	_free_prefix(entities, "Bomb_")


func move_bomb(bid: int, cell: Vector2i) -> void:
	var node := entities.get_node_or_null("Bomb_%d" % bid)
	if node and node.has_method("set_cell"):
		node.set_cell(cell)


func free_bomb(bid: int) -> void:
	var node := entities.get_node_or_null("Bomb_%d" % bid)
	if node:
		node.queue_free()


func spawn_powerup(pid: int, cell: Vector2i, kind: int) -> void:
	if powerups_layer.get_node_or_null("Powerup_%d" % pid):
		return
	var scene: PackedScene = POWERUP_SCENES[clampi(kind, 0, POWERUP_SCENES.size() - 1)]
	var node: Node2D = scene.instantiate()
	node.setup(pid, cell, kind, Arena.TILE)
	powerups_layer.add_child(node)


func clear_powerup_nodes() -> void:
	for child in powerups_layer.get_children():
		child.queue_free()


func remove_powerup(pid: int) -> void:
	var node := powerups_layer.get_node_or_null("Powerup_%d" % pid)
	if node:
		node.queue_free()


func play_boom(bid: int, hit_cells: Array, sfx: Node, cleared_soft: Array = []) -> void:
	free_bomb(bid)
	if sfx and sfx.has_method("play_boom"):
		sfx.play_boom()
	# 碎箱音效与 boom 并存；整次爆炸只播一次，不按格叠播
	if not cleared_soft.is_empty() and sfx and sfx.has_method("play_sfx"):
		sfx.play_sfx("soft_break")
	var hit_set: Dictionary = {}
	for c in hit_cells:
		hit_set[c] = true
	var center: Vector2i = hit_cells[0] if not hit_cells.is_empty() else Vector2i(-1, -1)
	for c in hit_cells:
		var scene := _blast_scene_for(c, center, hit_set)
		var fx: Sprite2D = scene.instantiate()
		fx.position = cell_to_pos(c)
		fx.z_index = 3
		fx_layer.add_child(fx)
		var timer := fx.get_tree().create_timer(BLAST_LIFETIME)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(fx):
				fx.queue_free()
		)
	for c in cleared_soft:
		_play_soft_shatter(c)


func _blast_scene_for(cell: Vector2i, center: Vector2i, hit_set: Dictionary) -> PackedScene:
	if cell == center:
		return BLAST_CENTER_SCENE
	if cell.y == center.y:
		return BLAST_H_SCENE
	if cell.x == center.x:
		return BLAST_V_SCENE
	# 万一出现斜向命中，用邻格方向挑一张横或竖的焰贴图。
	var left := hit_set.has(cell + Vector2i(-1, 0))
	var right := hit_set.has(cell + Vector2i(1, 0))
	if left or right:
		return BLAST_H_SCENE
	return BLAST_V_SCENE


func _play_soft_shatter(cell: Vector2i) -> void:
	var fx: AnimatedSprite2D = SOFT_BREAK_SCENE.instantiate()
	fx.position = cell_to_pos(cell)
	fx.z_index = 4
	fx_layer.add_child(fx)
	fx.play(&"play")
	fx.animation_finished.connect(fx.queue_free)


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
		var fx: AnimatedSprite2D = SD_HAZARD_SCENE.instantiate()
		fx.position = cell_to_pos(c)
		fx.z_index = 2
		fx.modulate = Color(1.6, 1.35, 1.1, 1.0)
		fx.scale = Vector2(0.35, 0.35)
		fx.frame = 0
		fx_layer.add_child(fx)
		sd_visuals[key] = fx
		_animate_sd_appear(fx)


func _animate_sd_appear(fx: AnimatedSprite2D) -> void:
	if fx_layer == null or not is_instance_valid(fx):
		return
	var tree := fx_layer.get_tree()
	# 先弹出并闪一帧，再收成轻轻的循环脉动。
	var t1 := tree.create_timer(0.06)
	t1.timeout.connect(func() -> void:
		if not is_instance_valid(fx):
			return
		fx.frame = 1
		fx.scale = Vector2(1.15, 1.15)
		fx.modulate = Color(1.8, 1.5, 1.2, 1.0)
	)
	var t2 := tree.create_timer(0.14)
	t2.timeout.connect(func() -> void:
		if not is_instance_valid(fx):
			return
		fx.frame = 2
		fx.scale = Vector2(1.0, 1.0)
	)
	var t3 := tree.create_timer(0.26)
	t3.timeout.connect(func() -> void:
		if not is_instance_valid(fx):
			return
		fx.frame = 0
		fx.modulate = Color(1.0, 1.0, 1.0, 0.92)
		_loop_sd_pulse(fx, 0)
	)


func _loop_sd_pulse(fx: AnimatedSprite2D, phase: int) -> void:
	if fx_layer == null or not is_instance_valid(fx):
		return
	fx.frame = 1 if (phase % 2) == 0 else 0
	fx.modulate = Color(1.25, 1.1, 1.0, 1.0) if (phase % 2) == 0 else Color(1.0, 1.0, 1.0, 0.88)
	var wait := 0.55 if (phase % 2) == 0 else 0.7
	var timer := fx_layer.get_tree().create_timer(wait)
	timer.timeout.connect(func() -> void:
		_loop_sd_pulse(fx, phase + 1)
	)


func show_airdrop_mark(cell: Vector2i) -> void:
	clear_airdrop_mark()
	if fx_layer == null:
		return
	# 一整格预告：降落伞、木箱、四角括号。闪烁只改透明度。
	var mark: Sprite2D = AIRDROP_MARK_SCENE.instantiate()
	mark.name = "AirdropMark"
	mark.position = Vector2(cell.x * Arena.TILE, cell.y * Arena.TILE)
	mark.z_index = 2
	fx_layer.add_child(mark)
	if mark.is_inside_tree():
		var tw := mark.create_tween()
		tw.set_loops(0)
		tw.tween_property(mark, "modulate:a", 0.45, 0.28)
		tw.tween_property(mark, "modulate:a", 1.0, 0.28)


func clear_airdrop_mark() -> void:
	if fx_layer == null:
		return
	var existing := fx_layer.get_node_or_null("AirdropMark")
	if existing:
		existing.free()


func clear_sudden_death() -> void:
	for key in sd_visuals.keys():
		var node: Node = sd_visuals[key]
		if is_instance_valid(node):
			node.queue_free()
	sd_visuals.clear()


func _free_prefix(parent: Node, prefix: String) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		var node := child as Node
		if node.name.begins_with(prefix):
			node.queue_free()
