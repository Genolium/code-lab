extends Node
## Глобальное состояние игры (автозагрузка Game): прогресс, настройки,
## переходы между сценами. Данные сохраняются в user://codelab_save.cfg
## (на Windows: %APPDATA%\Godot\app_userdata\CodeLab 3D).

signal settings_changed

const SAVE_PATH := "user://codelab_save.cfg"
const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

var settings := {"master": 0.8, "music": 0.5, "sfx": 0.8, "speed": 1.0}
var completed: Array[int] = []
var start_level := 0
var persist := true  ## false — ничего не сохранять (например, при автотесте).


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--selftest" in OS.get_cmdline_user_args():
		persist = false
	_ensure_bus("Music")
	_ensure_bus("SFX")
	load_data()
	apply_audio()
	# Звук щелчка для всех кнопок интерфейса.
	get_tree().node_added.connect(_on_node_added)


func is_completed(index: int) -> bool:
	return index in completed


func mark_completed(index: int) -> void:
	if index not in completed:
		completed.append(index)
		save_data()


func first_unfinished_level() -> int:
	for i in Levels.LIST.size():
		if not is_completed(i):
			return i
	return 0


func set_setting(key: String, value: float) -> void:
	settings[key] = value
	apply_audio()
	settings_changed.emit()
	save_data()


func play_level(index: int) -> void:
	start_level = index
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func go_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func apply_audio() -> void:
	_set_bus_volume("Master", settings["master"])
	_set_bus_volume("Music", settings["music"])
	_set_bus_volume("SFX", settings["sfx"])


func save_data() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	cfg.set_value("progress", "completed", completed)
	cfg.save(SAVE_PATH)


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in settings:
		settings[key] = float(cfg.get_value("settings", key, settings[key]))
	completed.assign(cfg.get_value("progress", "completed", []))


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.001)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(Sfx.play.bind("click"))
