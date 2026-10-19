extends Node2D
## Bomb visual. Fuse / blast / kick slide simulated on authority (game_root.gd).

var _age: float = 0.0
var _body: Polygon2D
var _tile: int = 48


func setup(bid: int, cell: Vector2i, tile: int) -> void:
	name = "Bomb_%d" % bid
	_tile = tile
	set_meta("cell", cell)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)
	_body = Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(Vector2(cos(a), sin(a)) * 14.0)
	_body.polygon = pts
	_body.color = Color(0.1, 0.1, 0.12)
	add_child(_body)
	# Fuse spark
	var spark := Polygon2D.new()
	spark.polygon = PackedVector2Array([
		Vector2(-3, -18), Vector2(3, -18), Vector2(2, -10), Vector2(-2, -10)
	])
	spark.color = Color(1.0, 0.55, 0.1)
	spark.name = "Spark"
	add_child(spark)
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
		_body.color = Color(0.1 + t * 0.45, 0.08, 0.08)
