class_name MatchHud
extends RefCounted
## Match labels and the end panel. It displays decisions made elsewhere.


const HELP := "WASD/方向键移动 · 空格放炸弹 · 道具：蓝B+炸弹 / 红R+火力 / 青S+移速 / 紫K踢弹 / 黄P穿透"

var status_label: Label
var stats_label: Label
var spec_label: Label
var help_label: Label
var sd_label: Label
var end_panel: PanelContainer
var end_title: Label
var rematch_btn: Button
var back_btn: Button
var lobby_btn: Button
var _sd_key: String = ""


func bind(
	status: Label,
	stats: Label,
	spec: Label,
	help: Label,
	sd: Label,
	panel: PanelContainer,
	title: Label,
	rematch: Button,
	back: Button,
	lobby: Button
) -> void:
	status_label = status
	stats_label = stats
	spec_label = spec
	help_label = help
	sd_label = sd
	end_panel = panel
	end_title = title
	rematch_btn = rematch
	back_btn = back
	lobby_btn = lobby


func prepare(is_dedicated: bool) -> void:
	end_panel.visible = false
	spec_label.visible = false
	if sd_label:
		sd_label.visible = false
	if help_label:
		help_label.text = HELP
	if is_dedicated:
		back_btn.visible = false
		rematch_btn.visible = false
		lobby_btn.visible = false


func set_status(text: String) -> void:
	if status_label:
		status_label.text = text


func hide_end() -> void:
	end_panel.visible = false
	spec_label.visible = false


func invalidate_sudden_death() -> void:
	_sd_key = ""


func refresh_stats(my_id: int, stats: Dictionary, placed: int) -> void:
	if stats_label == null:
		return
	if my_id == 0:
		stats_label.text = ""
		return
	stats_label.text = PlayerStats.format_hud(stats, placed)


func refresh_spectator(my_id: int, match_over: bool, is_alive: bool) -> void:
	if spec_label == null:
		return
	if my_id == 0 or match_over or is_alive:
		spec_label.visible = false
		return
	spec_label.visible = true
	spec_label.text = "已阵亡 · 观战中"


func refresh_sudden_death(
	active: bool, elapsed: float, start_at: float, match_over: bool, next_pulse: float = 0.0
) -> void:
	if sd_label == null:
		return
	var key := "hide"
	var text := ""
	if not match_over:
		if active:
			var secs: int = maxi(0, int(ceili(next_pulse)))
			key = "pulse:%d" % secs
			if secs > 0:
				text = "突然死亡 · %d 秒后缩圈" % secs
			else:
				text = "突然死亡 · 安全区收缩中"
		else:
			var left: float = maxf(0.0, start_at - elapsed)
			if left <= 30.0 and left > 0.0:
				key = "cd:%d" % int(ceili(left))
				text = "突然死亡倒计时 %d 秒" % int(ceili(left))
	if key == _sd_key:
		return
	_sd_key = key
	sd_label.visible = key != "hide"
	if key != "hide":
		sd_label.text = text


func show_end(winner_name: String) -> void:
	if winner_name.is_empty():
		set_status("对局结束：平局")
		end_title.text = "对局结束\n平局"
	else:
		set_status("对局结束：%s 获胜！" % winner_name)
		end_title.text = "对局结束\n%s 获胜！" % winner_name
	end_panel.visible = true


func refresh_rematch(allowed: bool) -> void:
	if rematch_btn == null:
		return
	rematch_btn.visible = allowed
	rematch_btn.disabled = not allowed
	rematch_btn.text = "再来一局"
