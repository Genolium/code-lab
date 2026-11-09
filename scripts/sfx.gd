extends Node
## Звуки и музыка (автозагрузка Sfx).
## Все звуки и фоновая мелодия синтезируются программно при запуске игры,
## поэтому это собственные ассеты проекта, не требующие сторонних лицензий.

const RATE := 22050
const POOL_SIZE := 8

var world_muted := false  ## Глушит звуки игрового мира (демо в главном меню).

var _sounds := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_task := -1
var _music_stream: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_pool.append(player)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)

	_build_sounds()
	_load_kenney_sounds()
	# Музыка генерируется несколько секунд — делаем это в фоновом потоке.
	if DisplayServer.get_name() != "headless":
		_music_task = WorkerThreadPool.add_task(_build_music)


func _process(_delta: float) -> void:
	if _music_task != -1 and WorkerThreadPool.is_task_completed(_music_task):
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		_music.stream = _music_stream
		_music.play()


func _exit_tree() -> void:
	if _music_task != -1:
		WorkerThreadPool.wait_for_task_completion(_music_task)


## Проигрывает звук интерфейса или игры по имени.
func play(sound: String, pitch_variation := 0.0) -> void:
	var stream: AudioStream = _pick(_sounds.get(sound))
	if stream == null:
		return
	var player := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


## Звук игрового мира (с лёгким разбросом высоты, чтобы не надоедал).
func world(sound: String) -> void:
	if not world_muted:
		play(sound, 0.06)


# --- Звуки Kenney (CC0) ---

## Готовые звуки из наборов Kenney заменяют синтезированные с тем же именем.
## Если файл не найден, остаётся синтезированный вариант.
## Источники: Interface Sounds, Impact Sounds, Sci-fi Sounds, Music Jingles (kenney.nl, CC0).
func _load_kenney_sounds() -> void:
	var dir := "res://assets/kenney/audio/"
	var files := {
		"click": ["click_001"],
		"turn": ["toggle_002"],
		"step": ["footstep_concrete_000", "footstep_concrete_001", "footstep_concrete_002",
				"footstep_concrete_003", "footstep_concrete_004"],
		"bump": ["impactMetal_medium_000"],
		"pickup": ["confirmation_002"],
		"door": ["doorOpen_000"],
		"button": ["impactPlate_light_000"],
		"gate": ["forceField_000"],
		"fail": ["error_006"],
		"win": ["jingles_PIZZI00"],
	}
	for sound: String in files:
		var variants := []
		for file: String in files[sound]:
			var stream := load(dir + file + ".ogg") as AudioStream
			if stream:
				variants.append(stream)
		if not variants.is_empty():
			_sounds[sound] = variants


## Из списка вариантов выбирает случайный; одиночный звук возвращает как есть.
func _pick(entry: Variant) -> AudioStream:
	if entry is Array:
		return entry[randi() % entry.size()]
	return entry


# --- Синтез звуков ---

func _build_sounds() -> void:
	_sounds["click"] = _synth(0.05, func(t: float) -> float:
		return sin(TAU * 1300.0 * t) * 0.22 * exp(-t * 90.0))
	_sounds["step"] = _synth(0.12, func(t: float) -> float:
		return tanh(2.5 * sin(_sweep(t, 0.12, 210.0, 130.0))) * 0.3 * exp(-t * 26.0))
	_sounds["turn"] = _synth(0.14, func(t: float) -> float:
		return sin(_sweep(t, 0.14, 330.0, 520.0)) * 0.3 * exp(-t * 14.0))
	_sounds["bump"] = _synth(0.25, func(t: float) -> float:
		return (randf() * 2.0 - 1.0) * 0.35 * exp(-t * 30.0) + sin(TAU * 75.0 * t) * 0.6 * exp(-t * 14.0))
	_sounds["fall"] = _synth(0.8, func(t: float) -> float:
		return sin(_sweep(t, 0.8, 760.0, 70.0)) * 0.3 * (1.0 - t / 0.8))
	_sounds["pickup"] = _synth(0.4, func(t: float) -> float:
		return _notes(t, [880.0, 1174.7, 1568.0], 0.07, 14.0) * 0.26)
	_sounds["door"] = _synth(0.55, func(t: float) -> float:
		return tanh(2.0 * sin(_sweep(t, 0.55, 150.0, 380.0))) * 0.2 * (0.65 + 0.35 * sin(TAU * 16.0 * t)))
	_sounds["gate"] = _sounds.get("door")
	_sounds["button"] = _synth(0.3, func(t: float) -> float:
		return sin(TAU * 520.0 * t) * 0.3 * exp(-t * 12.0) + (randf() * 2.0 - 1.0) * 0.25 * exp(-t * 90.0))
	_sounds["win"] = _synth(1.1, func(t: float) -> float:
		return _notes(t, [523.25, 659.25, 783.99, 1046.5], 0.11, 4.5) * 0.28)
	_sounds["fail"] = _synth(0.55, func(t: float) -> float:
		return _notes(t, [311.1, 233.1], 0.17, 6.0, true) * 0.22)


## Генерирует звук длительностью duration по формуле gen(t) -> [-1; 1].
func _synth(duration: float, gen: Callable) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		# Короткие нарастание и затухание убирают щелчки на краях.
		var envelope := minf(1.0, t / 0.004) * minf(1.0, (duration - t) / 0.03)
		var value: float = gen.call(t) * envelope
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	return _to_wav(data)


## Фаза тона, частота которого плавно меняется от f0 до f1 за время d.
func _sweep(t: float, d: float, f0: float, f1: float) -> float:
	return TAU * (f0 * t + (f1 - f0) * t * t / (2.0 * d))


## Последовательность нот (арпеджио) с затуханием каждой ноты.
func _notes(t: float, freqs: Array, step: float, decay: float, harsh := false) -> float:
	var i := mini(int(t / step), freqs.size() - 1)
	var local := t - i * step
	var f: float = freqs[i]
	var x := sin(TAU * f * t) + 0.3 * sin(TAU * 2.0 * f * t)
	if harsh:
		x = tanh(2.0 * x)
	return x * exp(-local * decay)


func _to_wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream


# --- Фоновая музыка ---

## Спокойная зацикленная мелодия: пэд из аккордов, арпеджио и бас.
## Последовательность аккордов: Am – F – C – G – Am – F – Dm – E.
func _build_music() -> void:
	var beat := 60.0 / 84.0
	var chord_len := beat * 4.0
	var eighth := beat / 2.0
	var chords := [
		[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62],
		[57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59],
	]
	var pattern := [0, 1, 2, 1, 2, 1, 0, 2]

	var freqs := []
	for chord in chords:
		var f := []
		for note in chord:
			f.append(440.0 * pow(2.0, (note - 69) / 12.0))
		freqs.append(f)

	var count := int(chord_len * chords.size() * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var ci := int(t / chord_len)
		var tc := t - ci * chord_len
		var f: Array = freqs[ci]
		var fade_out := minf(1.0, (chord_len - tc) / 0.05)

		var pad := 0.0
		for fr: float in f:
			pad += sin(TAU * fr * t) + 0.5 * sin(TAU * fr * 1.004 * t)
		pad *= 0.04 * minf(1.0, tc / 0.8) * minf(1.0, (chord_len - tc) / 0.5)

		var step := int(tc / eighth)
		var tl := tc - step * eighth
		var af: float = f[pattern[step % 8]] * 2.0
		var arp := (sin(TAU * af * t) + 0.25 * sin(TAU * af * 3.0 * t)) \
			* 0.09 * exp(-tl * 6.0) * minf(1.0, tl / 0.003) * minf(1.0, (eighth - tl) / 0.01)

		var bf: float = f[0] * 0.5
		var bass := sin(TAU * bf * t) * 0.15 * minf(1.0, tc / 0.02) * exp(-tc * 0.35) * fade_out

		var value := pad + arp + bass
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))

	var stream := _to_wav(data)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	_music_stream = stream
