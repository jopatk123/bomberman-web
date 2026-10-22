extends Node
## Short synthesized stingers. No sample files. Silent under headless.

var _voices: Array[AudioStreamPlayer] = []


func play_boom() -> void:
	_play(_wav(_boom_samples()))


func play_pickup() -> void:
	_play(_wav(_pickup_samples()))


func _play(wav: AudioStreamWAV) -> void:
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		return
	var voice := _voice()
	voice.stream = wav
	voice.play()


func _voice() -> AudioStreamPlayer:
	for p in _voices:
		if not p.playing:
			return p
	var created := AudioStreamPlayer.new()
	add_child(created)
	_voices.append(created)
	return created


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var s := clampi(int(clampf(samples[i], -1.0, 1.0) * 32767.0), -32767, 32767)
		bytes.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	wav.data = bytes
	return wav


func _boom_samples() -> PackedFloat32Array:
	var rate := 22050
	var n := int(0.16 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB00B
	for i in n:
		var t := float(i) / float(rate)
		var env := (1.0 - t / 0.16)
		env = env * env
		var tone := sin(TAU * (180.0 - 90.0 * t / 0.16) * t)
		var noise := rng.randf_range(-1.0, 1.0)
		out[i] = env * (0.55 * tone + 0.45 * noise)
	return out


func _pickup_samples() -> PackedFloat32Array:
	var rate := 22050
	var n := int(0.09 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		var env := 1.0 - t / 0.09
		var freq := 660.0 if t < 0.04 else 990.0
		out[i] = env * 0.45 * sin(TAU * freq * t)
	return out
