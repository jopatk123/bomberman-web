extends SceneTree
## 无界面：音频文件、总线、静音是否记住、切歌规则。
## 运行：godot --headless --path . -s res://scripts/verify_audio.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio := root.get_node("Audio")
	if not _check_files(audio):
		quit(1)
		return
	if not _check_buses():
		quit(1)
		return
	if not _check_logic():
		quit(1)
		return
	if not _check_playback(audio):
		quit(1)
		return
	print("[verify_audio] 成功")
	quit(0)


func _check_files(audio) -> bool:
	if FileAccess.file_exists("res://scripts/sfx.gd"):
		push_error("[verify_audio] 失败：scripts/sfx.gd 应该已经退役")
		return false
	for track in ["lobby", "match", "sudden_death", "win", "lose"]:
		var path := str(audio.music_path(track))
		if path == "" or not ResourceLoader.exists(path):
			push_error("[verify_audio] 失败：缺少音乐 %s" % path)
			return false
		var stream: AudioStream = audio.stream_for(track)
		if stream == null or not (stream is AudioStreamOggVorbis):
			push_error("[verify_audio] 失败：%s 没有按 ogg 载入" % track)
			return false
		var ogg := stream as AudioStreamOggVorbis
		var should_loop: bool = track != "win" and track != "lose"
		if ogg.loop != should_loop:
			push_error("[verify_audio] 失败：%s 循环=%s" % [track, ogg.loop])
			return false
	for name in ["place_bomb", "boom", "kick", "death", "pickup", "ui_click", "enter_room", "ready", "airdrop_land", "soft_break"]:
		var sfx_path := str(audio.sfx_path(name))
		if not ResourceLoader.exists(sfx_path):
			push_error("[verify_audio] 失败：缺少音效 %s" % sfx_path)
			return false
		if audio.stream_for(name) == null:
			push_error("[verify_audio] 失败：音效 %s 没有载入" % name)
			return false
	var lobby := FileAccess.get_file_as_string("res://scripts/lobby.gd")
	var scene := FileAccess.get_file_as_string("res://scenes/lobby.tscn")
	var game := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	if lobby.find("request_music(\"lobby\")") < 0 or scene.find("音乐") < 0 or scene.find("音效") < 0:
		push_error("[verify_audio] 失败：大厅音乐挂钩缺失")
		return false
	if game.find("place_bomb") < 0 or game.find("sudden_death") < 0 or game.find("_play_outcome_jingle") < 0:
		push_error("[verify_audio] 失败：对局音频挂钩缺失")
		return false
	if game.find("airdrop_land") < 0 or game.find("_rpc_airdrop_land") < 0:
		push_error("[verify_audio] 失败：空投落地音效挂钩缺失")
		return false
	var board := FileAccess.get_file_as_string("res://scripts/match_board.gd")
	if board.find("soft_break") < 0 or board.find("play_boom") < 0:
		push_error("[verify_audio] 失败：碎箱音效挂钩缺失")
		return false
	print("[verify_audio] 文件通过")
	return true


func _check_buses() -> bool:
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("Sfx")
	if music < 0 or sfx < 0:
		push_error("[verify_audio] 失败：总线 音乐=%d 音效=%d" % [music, sfx])
		return false
	if AudioServer.get_bus_send(music) != "Master" or AudioServer.get_bus_send(sfx) != "Master":
		push_error("[verify_audio] 失败：总线发送")
		return false
	var music_db := AudioServer.get_bus_volume_db(music)
	if music_db > -5.0:
		push_error("[verify_audio] 失败：音乐总线应挂在音效下面，分贝=%s" % music_db)
		return false
	print("[verify_audio] 总线通过 音乐分贝=%s" % music_db)
	return true


func _check_logic() -> bool:
	var rules := preload("res://autoload/Audio.gd")
	if rules.can_output(false, false) or rules.can_output(true, true) or rules.can_output(false, true):
		push_error("[verify_audio] 失败：能否出声应同时要求用户操作和显示器")
		return false
	if not rules.can_output(true, false):
		push_error("[verify_audio] 失败：已解锁的桌面端应允许出声")
		return false
	if absf(rules.fade_sec("", "lobby")) > 0.001 or absf(rules.fade_sec("lobby", "lobby")) > 0.001:
		push_error("[verify_audio] 失败：同一曲淡入淡出不对")
		return false
	if rules.fade_sec("lobby", "match") < 0.3 or rules.fade_sec("match", "win") > 0.35:
		push_error("[verify_audio] 失败：淡化时长不对")
		return false
	if rules.use_hard_cut(0, 1000) or not rules.use_hard_cut(1000, 1050) or rules.use_hard_cut(1000, 1200):
		push_error("[verify_audio] 失败：硬切窗口不对")
		return false
	print("[verify_audio] 切歌逻辑通过")
	return true


func _check_playback(audio) -> bool:
	var before := int(audio.audible_starts)
	audio.play_sfx("nope")
	audio.play_sfx("")
	audio.play_boom()
	audio.play_pickup()
	audio.play_sfx("place_bomb")
	audio.play_sfx("kick")
	audio.play_sfx("death")
	audio.play_sfx("ui_click")
	audio.play_sfx("enter_room")
	audio.play_sfx("ready")
	audio.play_sfx("airdrop_land")
	audio.play_sfx("soft_break")
	audio.play_music("not-a-track")
	audio.request_music("lobby")
	if str(audio.current_track) != "lobby":
		push_error("[verify_audio] 失败：大厅曲目 %s" % audio.current_track)
		return false
	audio.play_music("match")
	audio.play_music("sudden_death")
	audio.play_music("win")
	audio.play_music("lose")
	audio.request_music("lobby")
	if str(audio.current_track) != "lobby":
		push_error("[verify_audio] 失败：回到大厅曲目 %s" % audio.current_track)
		return false
	if int(audio.audible_starts) != before:
		push_error("[verify_audio] 失败：无界面不应真的出声")
		return false
	if audio.play_sfx("boom"):
		push_error("[verify_audio] 失败：无界面播放音效返回了真")
		return false
	audio.set_music_muted(true)
	audio.set_sfx_muted(true)
	if not audio.music_muted or not audio.sfx_muted:
		push_error("[verify_audio] 失败：静音标记不对")
		return false
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")):
		push_error("[verify_audio] 失败：音乐总线没有静音")
		return false
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("Sfx")):
		push_error("[verify_audio] 失败：音效总线没有静音")
		return false
	var cfg := ConfigFile.new()
	if cfg.load("user://audio.cfg") != OK:
		push_error("[verify_audio] 失败：没有写 audio.cfg")
		return false
	if not bool(cfg.get_value("audio", "music_muted", false)):
		push_error("[verify_audio] 失败：音乐静音没有记住")
		return false
	audio.set_music_muted(false)
	audio.set_sfx_muted(false)
	if audio.music_muted or audio.sfx_muted or AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")):
		push_error("[verify_audio] 失败：取消静音")
		return false
	audio.gesture_unlocked = false
	audio.current_track = ""
	audio.request_music("match")
	if str(audio.current_track) != "match":
		push_error("[verify_audio] 失败：未解锁时请求把曲目弄丢了")
		return false
	if int(audio.audible_starts) != before:
		push_error("[verify_audio] 失败：未解锁的无界面请求变成出声了")
		return false
	print("[verify_audio] 播放通过")
	return true
