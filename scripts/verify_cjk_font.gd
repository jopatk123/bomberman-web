extends SceneTree
## Headless: ensure CJK font loads and can measure Chinese glyphs.

func _init() -> void:
	var font: Font = load("res://assets/fonts/GameCJK.ttf")
	if font == null:
		push_error("GameCJK.ttf failed to load")
		quit(1)
		return
	var theme: Theme = load("res://assets/ui/default_theme.tres")
	if theme == null:
		push_error("default_theme.tres failed to load")
		quit(2)
		return
	var sample := "摸鱼炸弹人 对局进行中 获胜"
	var sz := font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if sz.x < 8.0:
		push_error("CJK string size too small: %s" % sz)
		quit(3)
		return
	print("CJK_FONT_OK size=", sz, " theme_font=", theme.default_font != null)
	quit(0)
