extends Node
## 背景音乐，以及可以叠在一起的音效。无界面和专用服保持静音。
## 网页要等用户点一下或按一下键才出声，避免一打开就刷自动播放错误。

const MUSIC := {
	"lobby": "res://assets/audio/bgm/lobby.ogg",
	"match": "res://assets/audio/bgm/match.ogg",
	"sudden_death": "res://assets/audio/bgm/sudden_death.ogg",
	"win": "res://assets/audio/bgm/win.ogg",
	"lose": "res://assets/audio/bgm/lose.ogg",
}
const SFX := {
	"place_bomb": "res://assets/audio/sfx/place_bomb.ogg",
	"boom": "res://assets/audio/sfx/boom.ogg",
	"kick": "res://assets/audio/sfx/kick.ogg",
	"death": "res://assets/audio/sfx/death.ogg",
	"pickup": "res://assets/audio/sfx/pickup.ogg",
	"ui_click": "res://assets/audio/sfx/ui_click.ogg",
	"enter_room": "res://assets/audio/sfx/enter_room.ogg",
	"ready": "res://assets/audio/sfx/ready.ogg",
}
const LOOPING := ["lobby", "match", "sudden_death"]
const MUSIC_DB := {
	"lobby": -3.0,
	"match": -1.0,
	"sudden_death": 0.0,
	"win": 0.5,
	"lose": -1.0,
}
const SFX_DB := {
	"place_bomb": -6.0,
	"boom": 2.0,
	"kick": -2.0,
	"death": -1.0,
	"pickup": -3.0,
	"ui_click": -12.0,
	"enter_room": -6.0,
	"ready": -6.0,
}
const _SAVE_PATH := "user://audio.cfg"
const _VOICE_CAP := 8
const _HARD_CUT_MS := 80

var music_muted := false
var sfx_muted := false
var gesture_unlocked := false
var current_track := ""
var audible_starts := 0

var _pending := ""
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _fade_t := 1.0
var _fade_dur := 0.45
var _from_db := 0.0
var _to_db := 0.0
var _started_ms := 0
var _voices: Array[AudioStreamPlayer] = []
var _voice_cursor := 0


static func can_output(unlocked: bool, headless: bool) -> bool:
	return unlocked and not headless


static func fade_sec(prev: String, nxt: String) -> float:
	if prev == "" or prev == nxt:
		return 0.0
	if nxt == "win" or nxt == "lose":
		return 0.28
	return 0.45


static func use_hard_cut(since_ms: int, now_ms: int) -> bool:
	return since_ms > 0 and (now_ms - since_ms) < _HARD_CUT_MS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for _i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		add_child(player)
		_players.append(player)
	_load_streams()
	_load_settings()
	_apply_mute()


func _input(event: InputEvent) -> void:
	if gesture_unlocked or not _is_gesture(event):
		return
	unlock_from_gesture()


func _process(delta: float) -> void:
	if _fade_t >= 1.0 or _players.size() < 2:
		return
	_fade_t = minf(1.0, _fade_t + delta / maxf(_fade_dur, 0.01))
	var incoming := _players[_active]
	var outgoing := _players[1 - _active]
	incoming.volume_db = _to_db + linear_to_db(maxf(_fade_t, 0.0001))
	outgoing.volume_db = _from_db + linear_to_db(maxf(1.0 - _fade_t, 0.0001))
	if _fade_t >= 1.0:
		outgoing.stop()


func unlock_from_gesture() -> void:
	if gesture_unlocked:
		return
	gesture_unlocked = true
	if _pending == "":
		return
	var track := _pending
	current_track = ""
	play_music(track)


func request_music(track: String) -> void:
	play_music(track)


func play_music(track: String) -> void:
	if not MUSIC.has(track):
		return
	var prev := current_track
	if track == current_track and (_bed_playing() or not _output_allowed()):
		_pending = track
		return
	current_track = track
	_pending = track
	if not _output_allowed():
		return
	_begin_bed(prev, track)


func play_sfx(name: String) -> bool:
	if not SFX.has(name):
		return false
	if _headless() or sfx_muted:
		return false
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return false
	var voice := _voice()
	voice.stream = stream
	voice.volume_db = float(SFX_DB.get(name, 0.0))
	voice.play()
	return true


func play_boom() -> void:
	play_sfx("boom")


func play_pickup() -> void:
	play_sfx("pickup")


func set_music_muted(muted: bool) -> void:
	music_muted = muted
	_apply_mute()
	_save_settings()


func set_sfx_muted(muted: bool) -> void:
	sfx_muted = muted
	_apply_mute()
	_save_settings()


func music_path(track: String) -> String:
	return str(MUSIC.get(track, ""))


func sfx_path(name: String) -> String:
	return str(SFX.get(name, ""))


func stream_for(track: String) -> AudioStream:
	return _streams.get(track)


func _begin_bed(prev: String, track: String) -> void:
	var stream: AudioStream = _streams.get(track)
	if stream == null or _players.is_empty():
		return
	audible_starts += 1
	var now := Time.get_ticks_msec()
	var target := float(MUSIC_DB.get(track, 0.0))
	var hard := prev == "" or use_hard_cut(_started_ms, now)
	if hard:
		for player in _players:
			player.stop()
		_active = 0
		_fade_t = 1.0
		var player := _players[0]
		player.stream = stream
		player.volume_db = target
		player.play()
	else:
		var outgoing := _players[_active]
		_from_db = outgoing.volume_db
		_active = 1 - _active
		var incoming := _players[_active]
		incoming.stream = stream
		incoming.volume_db = -40.0
		incoming.play()
		_to_db = target
		_fade_dur = fade_sec(prev, track)
		if _fade_dur <= 0.0:
			_fade_dur = 0.45
		_fade_t = 0.0
	_started_ms = now


func _bed_playing() -> bool:
	for player in _players:
		if player.playing:
			return true
	return false


func _output_allowed() -> bool:
	return can_output(gesture_unlocked, _headless())


func _headless() -> bool:
	return OS.has_feature("headless") or DisplayServer.get_name() == "headless"


func _is_gesture(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false


func _voice() -> AudioStreamPlayer:
	for player in _voices:
		if not player.playing:
			return player
	if _voices.size() < _VOICE_CAP:
		var created := AudioStreamPlayer.new()
		created.bus = "Sfx"
		add_child(created)
		_voices.append(created)
		return created
	_voice_cursor = (_voice_cursor + 1) % _voices.size()
	return _voices[_voice_cursor]


func _load_streams() -> void:
	for track in MUSIC.keys():
		_streams[track] = _load_one(str(MUSIC[track]), track in LOOPING)
	for name in SFX.keys():
		_streams[name] = _load_one(str(SFX[name]), false)


func _load_one(path: String, loop: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_error("[Audio] 缺少 %s" % path)
		return null
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	return stream


func _ensure_buses() -> void:
	_ensure_bus("Music", -8.0)
	_ensure_bus("Sfx", 0.0)


func _ensure_bus(bus_name: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, volume_db)


func _apply_mute() -> void:
	var music_idx := AudioServer.get_bus_index("Music")
	var sfx_idx := AudioServer.get_bus_index("Sfx")
	if music_idx >= 0:
		AudioServer.set_bus_mute(music_idx, music_muted)
	if sfx_idx >= 0:
		AudioServer.set_bus_mute(sfx_idx, sfx_muted)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) != OK:
		return
	music_muted = bool(cfg.get_value("audio", "music_muted", false))
	sfx_muted = bool(cfg.get_value("audio", "sfx_muted", false))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_muted", music_muted)
	cfg.set_value("audio", "sfx_muted", sfx_muted)
	cfg.save(_SAVE_PATH)
