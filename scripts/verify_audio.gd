extends SceneTree
## Headless: audio files, buses, mute persistence, and music-switch rules.
## Run: godot --headless --path . -s res://scripts/verify_audio.gd


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
	print("[verify_audio] SUCCESS")
	quit(0)


func _check_files(audio) -> bool:
	if FileAccess.file_exists("res://scripts/sfx.gd"):
		push_error("[verify_audio] FAIL: scripts/sfx.gd should be retired")
		return false
	for track in ["lobby", "match", "sudden_death", "win", "lose"]:
		var path := str(audio.music_path(track))
		if path == "" or not ResourceLoader.exists(path):
			push_error("[verify_audio] FAIL: missing music %s" % path)
			return false
		var stream: AudioStream = audio.stream_for(track)
		if stream == null or not (stream is AudioStreamOggVorbis):
			push_error("[verify_audio] FAIL: %s did not load as ogg" % track)
			return false
		var ogg := stream as AudioStreamOggVorbis
		var should_loop: bool = track != "win" and track != "lose"
		if ogg.loop != should_loop:
			push_error("[verify_audio] FAIL: %s loop=%s" % [track, ogg.loop])
			return false
	for name in ["place_bomb", "boom", "kick", "death", "pickup", "ui_click", "enter_room", "ready"]:
		var sfx_path := str(audio.sfx_path(name))
		if not ResourceLoader.exists(sfx_path):
			push_error("[verify_audio] FAIL: missing sfx %s" % sfx_path)
			return false
		if audio.stream_for(name) == null:
			push_error("[verify_audio] FAIL: sfx %s did not load" % name)
			return false
	var lobby := FileAccess.get_file_as_string("res://scripts/lobby.gd")
	var scene := FileAccess.get_file_as_string("res://scenes/lobby.tscn")
	var game := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	if lobby.find("request_music(\"lobby\")") < 0 or scene.find("音乐") < 0 or scene.find("音效") < 0:
		push_error("[verify_audio] FAIL: lobby music hook missing")
		return false
	if game.find("place_bomb") < 0 or game.find("sudden_death") < 0 or game.find("_play_outcome_jingle") < 0:
		push_error("[verify_audio] FAIL: match audio hook missing")
		return false
	print("[verify_audio] files OK")
	return true


func _check_buses() -> bool:
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("Sfx")
	if music < 0 or sfx < 0:
		push_error("[verify_audio] FAIL: buses music=%d sfx=%d" % [music, sfx])
		return false
	if AudioServer.get_bus_send(music) != "Master" or AudioServer.get_bus_send(sfx) != "Master":
		push_error("[verify_audio] FAIL: bus send")
		return false
	var music_db := AudioServer.get_bus_volume_db(music)
	if music_db > -5.0:
		push_error("[verify_audio] FAIL: music bus should sit under SFX, db=%s" % music_db)
		return false
	print("[verify_audio] buses OK music_db=%s" % music_db)
	return true


func _check_logic() -> bool:
	var rules := preload("res://autoload/Audio.gd")
	if rules.can_output(false, false) or rules.can_output(true, true) or rules.can_output(false, true):
		push_error("[verify_audio] FAIL: can_output should require a gesture and a display")
		return false
	if not rules.can_output(true, false):
		push_error("[verify_audio] FAIL: unlocked desktop should be allowed")
		return false
	if absf(rules.fade_sec("", "lobby")) > 0.001 or absf(rules.fade_sec("lobby", "lobby")) > 0.001:
		push_error("[verify_audio] FAIL: same-track fade")
		return false
	if rules.fade_sec("lobby", "match") < 0.3 or rules.fade_sec("match", "win") > 0.35:
		push_error("[verify_audio] FAIL: fade lengths")
		return false
	if rules.use_hard_cut(0, 1000) or not rules.use_hard_cut(1000, 1050) or rules.use_hard_cut(1000, 1200):
		push_error("[verify_audio] FAIL: hard cut window")
		return false
	print("[verify_audio] switch logic OK")
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
	audio.play_music("not-a-track")
	audio.request_music("lobby")
	if str(audio.current_track) != "lobby":
		push_error("[verify_audio] FAIL: lobby track %s" % audio.current_track)
		return false
	audio.play_music("match")
	audio.play_music("sudden_death")
	audio.play_music("win")
	audio.play_music("lose")
	audio.request_music("lobby")
	if str(audio.current_track) != "lobby":
		push_error("[verify_audio] FAIL: return lobby %s" % audio.current_track)
		return false
	if int(audio.audible_starts) != before:
		push_error("[verify_audio] FAIL: headless should not start audible playback")
		return false
	if audio.play_sfx("boom"):
		push_error("[verify_audio] FAIL: headless play_sfx returned true")
		return false
	audio.set_music_muted(true)
	audio.set_sfx_muted(true)
	if not audio.music_muted or not audio.sfx_muted:
		push_error("[verify_audio] FAIL: mute flags")
		return false
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")):
		push_error("[verify_audio] FAIL: music bus not muted")
		return false
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("Sfx")):
		push_error("[verify_audio] FAIL: sfx bus not muted")
		return false
	var cfg := ConfigFile.new()
	if cfg.load("user://audio.cfg") != OK:
		push_error("[verify_audio] FAIL: audio.cfg not written")
		return false
	if not bool(cfg.get_value("audio", "music_muted", false)):
		push_error("[verify_audio] FAIL: music mute not persisted")
		return false
	audio.set_music_muted(false)
	audio.set_sfx_muted(false)
	if audio.music_muted or audio.sfx_muted or AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")):
		push_error("[verify_audio] FAIL: unmute")
		return false
	audio.gesture_unlocked = false
	audio.current_track = ""
	audio.request_music("match")
	if str(audio.current_track) != "match":
		push_error("[verify_audio] FAIL: locked request lost the track")
		return false
	if int(audio.audible_starts) != before:
		push_error("[verify_audio] FAIL: locked headless request became audible")
		return false
	print("[verify_audio] playback OK")
	return true
