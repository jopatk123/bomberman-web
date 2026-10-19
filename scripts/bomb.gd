extends Node2D
## Bomb visual. Fuse / blast simulated on authority (game_root.gd).
## Default fuse 2s, cross range 2 — see game_root constants.

func setup(bid: int, cell: Vector2i, tile: int) -> void:
	name = "Bomb_%d" % bid
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)
	var poly := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(Vector2(cos(a), sin(a)) * 14.0)
	poly.polygon = pts
	poly.color = Color(0.1, 0.1, 0.12)
	add_child(poly)
