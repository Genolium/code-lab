extends Node3D
## Главное меню. На фоне робот сам проходит финальный уровень (демо-режим),
## слева — панель с разделами: главная, выбор уровня, настройки, об игре.

@onready var board: Board = $Board
@onready var robot: Robot = $Robot
@onready var interpreter: Interpreter = $Interpreter
@onready var camera_rig: CameraRig = $CameraRig
@onready var content: VBoxContainer = %Content

var _demo_level: Dictionary
var _demo_program: Array


func _ready() -> void:
	# Автопроверка собранной игры: -- --selftest сразу открывает игровую сцену,
	# которая проходит все уровни и завершается с кодом 0 (успех) или 1 (ошибка).
	if "--selftest" in OS.get_cmdline_user_args():
		Game.play_level.call_deferred(0)
		return
	# В демо звуки робота отключены, чтобы не мешать музыке.
	Sfx.world_muted = true
	_demo_level = Levels.LIST[Levels.LIST.size() - 1]
	_demo_program = Levels.to_program(_demo_level["solution"])
	board.build(_demo_level)
	camera_rig.focus(board.get_center(), maxf(board.width, board.height))
	interpreter.robot = robot
	interpreter.board = board
	interpreter.finished.connect(_on_demo_finished)
	_start_demo()
	# Для скриншотов: -- --page=levels / settings / about открывает раздел сразу.
	match "".join(OS.get_cmdline_user_args()):
		"--page=levels":
			_show_levels()
		"--page=settings":
			_show_settings()
		"--page=about":
			_show_about()
		_:
			_show_main()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_main()


func _start_demo() -> void:
	board.build(_demo_level)
	robot.place(board, board.start_cell, _demo_level["start_dir"])
	interpreter.run(_demo_program)


func _on_demo_finished(success: bool, _message: String) -> void:
	if success:
		board.celebrate()
	await get_tree().create_timer(2.0).timeout
	_start_demo()


# --- Разделы меню ---

func _show_main() -> void:
	_clear()
	var done := Game.completed.size()
	var total := Levels.LIST.size()
	var play_text := "Играть" if done == 0 else ("Продолжить" if done < total else "Играть снова")
	_add_button(play_text, func() -> void: Game.play_level(Game.first_unfinished_level()), true)
	_add_button("Выбор уровня", _show_levels)
	_add_button("Настройки", _show_settings)
	_add_button("Об игре", _show_about)
	_add_button("Выход", get_tree().quit)
	content.add_child(_spacer())
	_add_label("Пройдено уровней: %d из %d" % [done, total], 0.7)


func _show_levels() -> void:
	_clear()
	_add_label("Выберите уровень", 1.0, 22)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for i in Levels.LIST.size():
		var button := Button.new()
		var mark := "\n✓ пройден" if Game.is_completed(i) else "\n "
		button.text = "%d. %s%s" % [i + 1, Levels.LIST[i]["name"], mark]
		button.custom_minimum_size = Vector2(205, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if Game.is_completed(i):
			button.theme_type_variation = &"AccentButton"
		button.pressed.connect(Game.play_level.bind(i))
		grid.add_child(button)
	content.add_child(grid)
	content.add_child(_spacer())
	_add_button("Назад", _show_main)


func _show_settings() -> void:
	_clear()
	_add_label("Настройки", 1.0, 22)
	content.add_child(SettingsPanel.new())
	content.add_child(_spacer())
	_add_button("Назад", _show_main)


func _show_about() -> void:
	_clear()
	_add_label("Об игре", 1.0, 22)
	_add_label("CodeLab 3D — обучающая 3D-игра-головоломка. Составляйте программы из команд, " +
		"циклов и условий, чтобы провести робота к цели.\n\n" +
		"Курсовой проект по дисциплине «Разработка интерактивных мультимедийных приложений».\n\n" +
		"Движок: Godot 4. Модели, звуки и музыка созданы программно.", 0.85)
	content.add_child(_spacer())
	_add_button("Назад", _show_main)


# --- Вспомогательное ---

func _clear() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()


func _add_button(text: String, callback: Callable, accent := false) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", 20)
	if accent:
		button.theme_type_variation = &"AccentButton"
	button.pressed.connect(callback)
	content.add_child(button)


func _add_label(text: String, alpha := 1.0, font_size := 16) -> void:
	var label := Label.new()
	label.text = text
	label.modulate.a = alpha
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 20:
		label.theme_type_variation = &"HeaderLabel"
	content.add_child(label)


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer
