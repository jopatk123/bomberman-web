extends SceneTree
## 无界面：确认中文字体能载入，并能量出汉字字形。

func _init() -> void:
	var font: Font = load("res://assets/fonts/GameCJK.ttf")
	if font == null:
		push_error("GameCJK.ttf 载入失败")
		quit(1)
		return
	var theme: Theme = load("res://assets/ui/default_theme.tres")
	if theme == null:
		push_error("default_theme.tres 载入失败")
		quit(2)
		return
	var sample := "摸鱼炸弹人 对局进行中 获胜"
	var sz := font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if sz.x < 8.0:
		push_error("中文字形尺寸过小：%s" % sz)
		quit(3)
		return
	if font is FontFile:
		var file := font as FontFile
		if file.antialiasing == TextServer.FONT_ANTIALIASING_NONE:
			push_error("中文字体抗锯齿应开启（水彩 UI）")
			quit(4)
			return
		if file.subpixel_positioning != TextServer.SUBPIXEL_POSITIONING_DISABLED:
			push_error("中文字体开了亚像素定位")
			quit(5)
			return
		if file.hinting != TextServer.HINTING_NONE:
			push_error("中文字体开了微调")
			quit(6)
			return
	print("中文字体通过 尺寸=", sz, " 主题字体=", theme.default_font != null)
	quit(0)
