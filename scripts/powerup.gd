extends Node2D
## 道具外观。拾取判定和归属在权威端（game_root.gd）。
## 五种图标各有一个场景（scenes/game/powerup_*.tscn），这里只做呼吸缩放与 meta。

enum Kind { BOMB = 0, RANGE = 1, SPEED = 2, KICK = 3, PIERCE = 4 }

var kind: int = Kind.BOMB
var _pulse: float = 0.0


func setup(pid: int, cell: Vector2i, pkind: int, tile: int) -> void:
	name = "Powerup_%d" % pid
	kind = pkind
	set_meta("cell", cell)
	set_meta("powerup_id", pid)
	set_meta("kind", pkind)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)


func _process(delta: float) -> void:
	_pulse += delta * 4.0
	var s := 1.0 + 0.08 * sin(_pulse)
	scale = Vector2(s, s)
