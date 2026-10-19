extends Node2D
## Visual pickup. Simulation / ownership lives on authority (game_root.gd).

enum Kind { BOMB = 0, RANGE = 1, SPEED = 2 }

const COLORS := {
	Kind.BOMB: Color(0.15, 0.35, 0.95),
	Kind.RANGE: Color(0.95, 0.35, 0.15),
	Kind.SPEED: Color(0.2, 0.85, 0.95),
}
const LABELS := {
	Kind.BOMB: "B+",
	Kind.RANGE: "R+",
	Kind.SPEED: "S+",
}

var kind: int = Kind.BOMB
var _pulse: float = 0.0


func setup(pid: int, cell: Vector2i, pkind: int, tile: int) -> void:
	name = "Powerup_%d" % pid
	kind = pkind
	set_meta("cell", cell)
	set_meta("powerup_id", pid)
	set_meta("kind", pkind)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)
	var col: Color = COLORS.get(pkind, Color.WHITE)

	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0, -14), Vector2(12, 0), Vector2(0, 14), Vector2(-12, 0)
	])
	diamond.color = col
	add_child(diamond)

	var rim := Polygon2D.new()
	rim.polygon = PackedVector2Array([
		Vector2(0, -10), Vector2(8, 0), Vector2(0, 10), Vector2(-8, 0)
	])
	rim.color = col.lightened(0.35)
	add_child(rim)

	var label := Label.new()
	label.text = str(LABELS.get(pkind, "?"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-12, -8)
	label.size = Vector2(24, 16)
	var font := load("res://assets/fonts/GameCJK.ttf")
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	add_child(label)

	set_process(true)


func _process(delta: float) -> void:
	_pulse += delta * 4.0
	var s := 1.0 + 0.08 * sin(_pulse)
	scale = Vector2(s, s)
