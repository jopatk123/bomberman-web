extends Node2D
## 角色外观，以及所在格的 meta。模拟在权威端（game_root.gd）。
## 节点 meta：格子 cell（Vector2i）、编号 peer_id（int）
## 轻量动效（呼吸 / 弹跳）与走路帧动画都在本脚本，不参与权威规则。

const SHEET_PATHS: Array[String] = [
	"res://assets/art/watercolor/entities/anim/player_blue_sheet.png",
	"res://assets/art/watercolor/entities/anim/player_red_sheet.png",
	"res://assets/art/watercolor/entities/anim/player_green_sheet.png",
	"res://assets/art/watercolor/entities/anim/player_yellow_sheet.png",
]

## 精灵表：idle + walk0..walk3，每帧 48×48
const FRAME_W := 48
const FRAME_H := 48
const FRAME_COUNT := 5
const IDLE_FRAME := 0
const WALK_FPS := 8.0
## 一次格子移动后，保持「在走」状态的毫秒数（覆盖常见 move_cd）
const MOVE_HOLD_MS := 280
const POS_EPS_SQ := 0.25

var _body: AnimatedSprite2D
var _color_idx: int = 0
var _last_pos: Vector2 = Vector2.ZERO
var _moving_until_ms: int = 0
var _face_left: bool = false
var _phase: float = 0.0
var _was_moving: bool = false


func setup(peer_id: int, cell: Vector2i, color: Color, display_name: String, tile: int) -> void:
	name = "Player_%d" % peer_id
	set_meta("cell", cell)
	set_meta("peer_id", peer_id)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)
	_last_pos = position
	_color_idx = _index_for(color)
	_phase = float(peer_id) * 0.37

	_body = AnimatedSprite2D.new()
	_body.name = "Body"
	_body.centered = true
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_body.sprite_frames = _build_frames(_color_idx)
	_body.animation = &"idle"
	_body.play(&"idle")
	add_child(_body)

	var label := Label.new()
	label.text = display_name
	label.position = Vector2(-24, -36)
	var font := load("res://assets/fonts/GameCJK.ttf")
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 0.98, 0.9, 1))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)


func _build_frames(color_idx: int) -> SpriteFrames:
	var sf := SpriteFrames.new()
	var sheet: Texture2D = load(SHEET_PATHS[color_idx % SHEET_PATHS.size()])
	var atlases: Array[AtlasTexture] = []
	for i in FRAME_COUNT:
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		at.filter_clip = true
		atlases.append(at)

	sf.add_animation(&"idle")
	sf.set_animation_loop(&"idle", true)
	sf.set_animation_speed(&"idle", 1.0)
	sf.add_frame(&"idle", atlases[IDLE_FRAME])

	sf.add_animation(&"walk")
	sf.set_animation_loop(&"walk", true)
	sf.set_animation_speed(&"walk", WALK_FPS)
	for i in range(1, FRAME_COUNT):
		sf.add_frame(&"walk", atlases[i])
	return sf


func _index_for(color: Color) -> int:
	var best_i := 0
	var best_d := 1.0e9
	var palette: Array = GameState.PLAYER_COLORS
	for i in palette.size():
		var c: Color = palette[i]
		var d: float = absf(c.r - color.r) + absf(c.g - color.g) + absf(c.b - color.b)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i % SHEET_PATHS.size()


func set_cell(cell: Vector2i, tile: int) -> void:
	set_meta("cell", cell)
	position = Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)
	set_moving(true)


## 外部（game_root / 预演）改完 position 后可调用；不调用也能靠位置差自动检测。
func set_moving(moving: bool) -> void:
	if moving:
		_moving_until_ms = Time.get_ticks_msec() + MOVE_HOLD_MS
	else:
		_moving_until_ms = 0


func notify_moved(from_pos: Vector2 = Vector2.INF) -> void:
	var prev: Vector2 = _last_pos if from_pos == Vector2.INF else from_pos
	var d: Vector2 = position - prev
	if absf(d.x) > 0.1:
		_face_left = d.x < 0.0
	set_moving(true)
	_last_pos = position


func mark_dead() -> void:
	modulate = Color(0.3, 0.3, 0.3, 0.5)
	set_moving(false)
	if _body:
		_body.pause()


func is_moving_visual() -> bool:
	return Time.get_ticks_msec() < _moving_until_ms


func _process(delta: float) -> void:
	if _body == null:
		return
	_detect_move_from_position()
	var moving := is_moving_visual()
	_sync_animation(moving)
	_apply_light_motion(delta, moving)


func _detect_move_from_position() -> void:
	var d: Vector2 = position - _last_pos
	if d.length_squared() > POS_EPS_SQ:
		if absf(d.x) > 0.1:
			_face_left = d.x < 0.0
		set_moving(true)
		_last_pos = position


func _sync_animation(moving: bool) -> void:
	_body.flip_h = _face_left
	if moving and not _was_moving:
		_body.play(&"walk")
	elif not moving and _was_moving:
		_body.play(&"idle")
	elif moving and _body.animation != &"walk":
		_body.play(&"walk")
	elif not moving and _body.animation != &"idle":
		_body.play(&"idle")
	_was_moving = moving


func _apply_light_motion(delta: float, moving: bool) -> void:
	_phase += delta
	if moving:
		# 走路时帧动画已含微弹，轻量 bob 减弱
		var bob := sin(_phase * 18.0) * 1.2
		_body.offset = Vector2(0.0, bob)
		var squash := 1.0 + sin(_phase * 18.0) * 0.04
		_body.scale = Vector2(1.0 / squash, squash)
	else:
		# 站立呼吸
		var breath := sin(_phase * 2.4) * 0.035
		_body.offset = Vector2(0.0, -breath * 8.0)
		_body.scale = Vector2(1.0 + breath, 1.0 - breath)
