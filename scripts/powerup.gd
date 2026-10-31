extends Node2D
## 道具外观。拾取判定和归属在权威端（game_root.gd）。

enum Kind { BOMB = 0, RANGE = 1, SPEED = 2, KICK = 3, PIERCE = 4 }

const TEX: Array[Texture2D] = [
	preload("res://assets/art/watercolor/entities/powerup_bomb.png"),
	preload("res://assets/art/watercolor/entities/powerup_range.png"),
	preload("res://assets/art/watercolor/entities/powerup_speed.png"),
	preload("res://assets/art/watercolor/entities/powerup_kick.png"),
	preload("res://assets/art/watercolor/entities/powerup_pierce.png"),
]

var kind: int = Kind.BOMB
var _pulse: float = 0.0


func setup(pid: int, cell: Vector2i, pkind: int, tile: int) -> void:
	name = "Powerup_%d" % pid
	kind = pkind
	set_meta("cell", cell)
	set_meta("powerup_id", pid)
	set_meta("kind", pkind)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)
	var icon := Sprite2D.new()
	icon.name = "Icon"
	icon.centered = true
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if pkind >= 0 and pkind < TEX.size():
		icon.texture = TEX[pkind]
	else:
		icon.texture = TEX[Kind.BOMB]
	add_child(icon)
	set_process(true)


func _process(delta: float) -> void:
	_pulse += delta * 4.0
	var s := 1.0 + 0.08 * sin(_pulse)
	scale = Vector2(s, s)
