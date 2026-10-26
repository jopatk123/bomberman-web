extends Node2D
## 炸弹外观。引信、爆炸、踢弹滑行都在权威端算（game_root.gd）。

const TEX_BOMB: Texture2D = preload("res://assets/art/pixel/entities/bomb.png")

var _age: float = 0.0
var _body: Sprite2D
var _tile: int = 48


func setup(bid: int, cell: Vector2i, tile: int) -> void:
	name = "Bomb_%d" % bid
	_tile = tile
	set_meta("cell", cell)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)
	_body = Sprite2D.new()
	_body.name = "Body"
	_body.texture = TEX_BOMB
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body.centered = true
	add_child(_body)
	set_process(true)


func set_cell(cell: Vector2i) -> void:
	set_meta("cell", cell)
	position = Vector2(cell.x * _tile + _tile * 0.5, cell.y * _tile + _tile * 0.5)


func _process(delta: float) -> void:
	_age += delta
	var pulse := 1.0 + 0.12 * sin(_age * 10.0)
	scale = Vector2(pulse, pulse)
	if _body:
		var t := clampf(_age / 2.0, 0.0, 1.0)
		# 引信烧完前略偏暖色；火花已经画在贴图上。
		_body.modulate = Color(1.0 + t * 0.35, 1.0 - t * 0.15, 1.0 - t * 0.25, 1.0)
