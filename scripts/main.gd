extends Node3D
## Игровая сцена: связывает поле, робота, интерпретатор и редактор программы.
##
## Программа пользователя — дерево узлов-словарей (формат описан в interpreter.gd).
## Новые команды добавляются в «текущий блок» (_cursor): в корень программы
## или в тело выбранного блока «Повторить» / «Если». Команды можно перетаскивать
## мышью: из палитры в программу и внутри программы.

const COLOR_OK := Palette.OK
const COLOR_ERROR := Palette.ERROR
const COLOR_HINT := Palette.HINT
const INDENT := 20

@onready var board: Board = $Board
@onready var robot: Robot = $Robot
@onready var interpreter: Interpreter = $Interpreter
@onready var camera_rig: CameraRig = $CameraRig

@onready var level_title: Label = %LevelTitle
@onready var level_hint: Label = %LevelHint
@onready var command_buttons: HFlowContainer = %CommandButtons
@onready var program_header: Label = %ProgramHeader
@onready var cursor_label: Label = %CursorLabel
@onready var exit_block_button: Button = %ExitBlockButton
@onready var program_scroll: ScrollContainer = %ProgramScroll
@onready var program_list: VBoxContainer = %ProgramList
@onready var speed_label: Label = %SpeedLabel
@onready var speed_slider: HSlider = %SpeedSlider
@onready var run_button: Button = %RunButton
@onready var step_button: Button = %StepButton
@onready var stop_button: Button = %StopButton
@onready var clear_button: Button = %ClearButton
@onready var hint_button: Button = %HintButton
@onready var status_label: Label = %StatusLabel
@onready var next_button: Button = %NextButton
@onready var menu_button: Button = %MenuButton

var level_index := 0
var level: Dictionary
var program: Array = []

var _cursor: Array = []  ## Блок, в который добавляются новые команды.
var _rows := {}          ## Номер узла -> кнопка-заголовок строки (для подсветки).
var _highlighted: Button
var _hint_stage := 0
var _pause_layer: CanvasLayer


func _ready() -> void:
	Sfx.world_muted = false
	interpreter.robot = robot
	interpreter.board = board
	interpreter.step_started.connect(_on_step_started)
	interpreter.finished.connect(_on_program_finished)

	run_button.pressed.connect(_on_run_pressed)
	step_button.pressed.connect(_on_step_pressed)
	stop_button.pressed.connect(interpreter.stop)
	clear_button.pressed.connect(_on_clear_pressed)
	hint_button.pressed.connect(_on_hint_pressed)
	next_button.pressed.connect(_on_next_pressed)
	exit_block_button.pressed.connect(_on_exit_block_pressed)
	menu_button.pressed.connect(_set_paused.bind(true))
	speed_slider.value_changed.connect(_on_speed_changed)
	Game.settings_changed.connect(_on_settings_changed)
	_on_settings_changed()

	# Перетаскивание на свободное место списка — в конец текущего блока.
	program_list.mouse_filter = Control.MOUSE_FILTER_PASS
	program_scroll.set_drag_forwarding(Callable(), _can_drop_data, _drop_on_list)

	_build_pause_menu()
	load_level(Game.start_level)

	var args := OS.get_cmdline_user_args()
	# Автопроверка: -- --selftest проходит все уровни эталонными решениями.
	if "--selftest" in args:
		_run_selftest()
	# Демонстрация: -- --show=5 открывает уровень 5 с эталонным решением.
	for arg in args:
		if arg.begins_with("--show="):
			load_level(arg.trim_prefix("--show=").to_int() - 1)
			_load_solution()
		elif arg == "--pause":
			_set_paused(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func load_level(index: int) -> void:
	level_index = clampi(index, 0, Levels.LIST.size() - 1)
	Game.start_level = level_index
	level = Levels.LIST[level_index]
	_reset_world()
	camera_rig.focus(board.get_center(), maxf(board.width, board.height))

	level_title.text = "Уровень %d из %d. %s" % [level_index + 1, Levels.LIST.size(), level["name"]]
	level_hint.text = level["hint"]
	_build_command_buttons()
	program = []
	_cursor = program
	_refresh_program()
	_hint_stage = 0
	hint_button.text = "Подсказка"
	_set_status("Составьте программу и нажмите «Запуск».")
	next_button.visible = false
	_set_running_ui(false)


func _reset_world() -> void:
	board.build(level)
	robot.place(board, board.start_cell, level["start_dir"])


# --- Палитра команд ---

func _build_command_buttons() -> void:
	_clear_children(command_buttons)
	for command in level["commands"]:
		var button := Button.new()
		button.text = Levels.COMMAND_TITLES[command]
		button.custom_minimum_size = Vector2(96, 40)
		button.tooltip_text = "Нажмите, чтобы добавить, или перетащите в нужное место программы"
		button.pressed.connect(_add_command.bind(command))
		button.set_drag_forwarding(_drag_new.bind(command, button), Callable(), Callable())
		command_buttons.add_child(button)


func _add_command(command: String) -> void:
	if interpreter.is_running:
		return
	if _count_nodes(program) >= level["max_commands"]:
		_set_status("Достигнут лимит команд для этого уровня.", COLOR_ERROR)
		return
	var node := _new_node(command)
	_cursor.append(node)
	# После добавления блока новые команды сразу попадают внутрь него.
	if node.has("body"):
		_cursor = node["body"]
	_refresh_program()


func _new_node(command: String) -> Dictionary:
	var node := {"id": Levels.new_id(), "cmd": command}
	if command == "repeat":
		node["count"] = 3
		node["body"] = []
	elif command == "if":
		node["cond"] = "blocked"
		node["body"] = []
	return node


# --- Отображение программы ---

func _refresh_program() -> void:
	_clear_children(program_list)
	_rows.clear()
	_highlighted = null
	if program.is_empty():
		program_list.add_child(_make_hint_label("Пока пусто: нажимайте кнопки команд выше или перетаскивайте их сюда.", 0))
	else:
		_render_block(program, 0)

	program_header.text = "Программа: %d / %d" % [_count_nodes(program), level["max_commands"]]
	var owner := _find_owner(_cursor, program)
	if owner.is_empty():
		cursor_label.text = "Команды добавляются в программу"
		exit_block_button.visible = false
	else:
		cursor_label.text = "Команды добавляются в блок «%s»" % _node_title(owner)
		exit_block_button.visible = true


func _render_block(block: Array, depth: int) -> void:
	for node in block:
		var row := HBoxContainer.new()
		var indent := Control.new()
		indent.custom_minimum_size.x = depth * INDENT
		row.add_child(indent)

		var title := Button.new()
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.clip_text = true
		title.text = Levels.COMMAND_TITLES[node["cmd"]]
		title.tooltip_text = "Перетащите, чтобы переместить команду"
		title.set_drag_forwarding(
			_drag_move.bind(block, node, title),
			_can_drop_on_row.bind(block, node),
			_drop_on_row.bind(block, node, title))
		row.add_child(title)

		if node["cmd"] == "repeat":
			var spin := SpinBox.new()
			spin.min_value = 1
			spin.max_value = 30
			spin.value = node["count"]
			spin.suffix = "раз"
			spin.value_changed.connect(func(value: float) -> void: node["count"] = int(value))
			row.add_child(spin)
		elif node["cmd"] == "if":
			var option := OptionButton.new()
			for cond in Levels.COND_TITLES:
				option.add_item(Levels.COND_TITLES[cond])
				option.set_item_metadata(option.item_count - 1, cond)
				if cond == node["cond"]:
					option.select(option.item_count - 1)
			option.item_selected.connect(
				func(index: int) -> void: node["cond"] = option.get_item_metadata(index))
			row.add_child(option)

		if node.has("body"):
			title.tooltip_text = "Нажмите, чтобы добавлять команды внутрь блока; перетащите, чтобы переместить"
			title.pressed.connect(_select_block.bind(node["body"]))
			if is_same(node["body"], _cursor):
				title.theme_type_variation = &"SelectedButton"
		title.set_meta("base_variation", title.theme_type_variation)

		var delete := Button.new()
		delete.text = " × "
		delete.tooltip_text = "Удалить команду"
		delete.pressed.connect(_remove_node.bind(block, node))
		row.add_child(delete)

		program_list.add_child(row)
		_rows[node["id"]] = title

		if node.has("body"):
			if node["body"].is_empty():
				program_list.add_child(_make_hint_label("(пусто — добавьте команды)", depth + 1))
			else:
				_render_block(node["body"], depth + 1)


func _select_block(body: Array) -> void:
	if interpreter.is_running:
		return
	_cursor = body
	_refresh_program()


func _on_exit_block_pressed() -> void:
	var parent = _find_parent(_cursor, program)
	_cursor = parent if parent != null else program
	_refresh_program()


func _remove_node(block: Array, node: Dictionary) -> void:
	if interpreter.is_running:
		return
	block.remove_at(_index_of(block, node))
	# Если удалили блок, в котором стоял курсор, возвращаемся в корень.
	if not _block_in_tree(_cursor, program):
		_cursor = program
	_refresh_program()


# --- Перетаскивание (drag & drop) ---

func _drag_new(_pos: Vector2, command: String, source: Control) -> Variant:
	if interpreter.is_running:
		return null
	source.set_drag_preview(_make_drag_preview(Levels.COMMAND_TITLES[command]))
	return {"dnd": "new", "cmd": command}


func _drag_move(_pos: Vector2, block: Array, node: Dictionary, source: Control) -> Variant:
	if interpreter.is_running:
		return null
	source.set_drag_preview(_make_drag_preview(_node_title(node)))
	return {"dnd": "move", "node": node, "from": block}


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return not interpreter.is_running and data is Dictionary and data.has("dnd")


func _can_drop_on_row(pos: Vector2, data: Variant, _block: Array, node: Dictionary) -> bool:
	if not _can_drop_data(pos, data):
		return false
	return not (data["dnd"] == "move" and is_same(data["node"], node))


## Верхняя половина строки — вставить перед командой; нижняя — после неё
## (а для блока — в начало его тела).
func _drop_on_row(pos: Vector2, data: Variant, block: Array, node: Dictionary, title: Control) -> void:
	var target := block
	var index := _index_of(block, node)
	if pos.y > title.size.y * 0.5:
		if node.has("body"):
			target = node["body"]
			index = 0
		else:
			index += 1
	_place(data, target, index)


func _drop_on_list(_pos: Vector2, data: Variant) -> void:
	_place(data, _cursor, _cursor.size())


func _place(data: Dictionary, target: Array, index: int) -> void:
	var node: Dictionary
	if data["dnd"] == "new":
		if _count_nodes(program) >= level["max_commands"]:
			_set_status("Достигнут лимит команд для этого уровня.", COLOR_ERROR)
			return
		node = _new_node(data["cmd"])
	else:
		node = data["node"]
		# Блок нельзя переместить внутрь самого себя.
		if node.has("body") and _block_in_tree(target, node["body"]):
			return
		var from: Array = data["from"]
		var old := _index_of(from, node)
		if old == -1:
			return
		from.remove_at(old)
		if is_same(from, target) and old < index:
			index -= 1
	target.insert(clampi(index, 0, target.size()), node)
	if not _block_in_tree(_cursor, program):
		_cursor = program
	# Перестраиваем список после завершения обработки перетаскивания.
	_refresh_program.call_deferred()


func _make_drag_preview(text: String) -> Control:
	var button := Button.new()
	button.text = text
	button.modulate = Color(1, 1, 1, 0.85)
	return button


# --- Запуск программы ---

func _start(step_by_step: bool) -> void:
	if program.is_empty():
		_set_status("Программа пуста: добавьте команды.", COLOR_ERROR)
		return
	_reset_world()
	interpreter.step_mode = step_by_step
	_set_running_ui(true)
	_set_status("Пошаговый режим: нажимайте «Шаг»." if step_by_step else "Выполнение…")
	interpreter.run(program)


func _on_run_pressed() -> void:
	if not interpreter.is_running:
		_start(false)
	elif interpreter.step_mode:
		# Из пошагового режима — продолжить до конца.
		interpreter.step_mode = false
		interpreter.advance()
		_set_status("Выполнение…")


func _on_step_pressed() -> void:
	if not interpreter.is_running:
		_start(true)
	else:
		interpreter.step_mode = true
		interpreter.advance()


## Подсвечивает жёлтым команду, которая сейчас выполняется.
func _on_step_started(node_id: int) -> void:
	_clear_highlight()
	_highlighted = _rows.get(node_id)
	if _highlighted:
		_highlighted.theme_type_variation = &"StepButton"
		program_scroll.ensure_control_visible(_highlighted)


func _clear_highlight() -> void:
	if is_instance_valid(_highlighted):
		_highlighted.theme_type_variation = _highlighted.get_meta("base_variation", &"")
	_highlighted = null


func _on_program_finished(success: bool, message: String) -> void:
	_set_running_ui(false)
	_clear_highlight()
	if success:
		Sfx.play("win")
		board.celebrate()
		Game.mark_completed(level_index)
		if level_index + 1 < Levels.LIST.size():
			_set_status("Уровень пройден! Команд использовано: %d." % _count_nodes(program), COLOR_OK)
			next_button.visible = true
		else:
			_set_status("Поздравляем! Все уровни пройдены.", COLOR_OK)
	else:
		if message != "Выполнение остановлено.":
			Sfx.play("fail")
		_set_status(message, COLOR_ERROR)


func _on_clear_pressed() -> void:
	program = []
	_cursor = program
	_refresh_program()
	_reset_world()
	_set_status("Программа очищена.")


func _on_hint_pressed() -> void:
	_hint_stage += 1
	if _hint_stage == 1:
		_set_status("Подсказка: " + level["tip"], COLOR_HINT)
		hint_button.text = "Показать решение"
	else:
		_load_solution()
		_set_status("Загружено эталонное решение. Разберитесь, как оно работает, и нажмите «Запуск».", COLOR_HINT)


func _load_solution() -> void:
	program = Levels.to_program(level["solution"])
	_cursor = program
	_refresh_program()


func _on_next_pressed() -> void:
	load_level(level_index + 1)


func _on_speed_changed(value: float) -> void:
	Game.set_setting("speed", value)


func _on_settings_changed() -> void:
	speed_slider.set_value_no_signal(Game.settings["speed"])
	speed_label.text = "Скорость: %.2f×" % Game.settings["speed"]


func _set_running_ui(running: bool) -> void:
	for button in command_buttons.get_children():
		(button as Button).disabled = running
	clear_button.disabled = running
	hint_button.disabled = running
	exit_block_button.disabled = running
	stop_button.disabled = not running


# --- Пауза ---

func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_layer.visible = paused


func _build_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 10
	_pause_layer.visible = false
	add_child(_pause_layer)

	var dim := ColorRect.new()
	dim.color = Color(Palette.STROKE, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Пауза"
	title.theme_type_variation = &"HeaderLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	box.add_child(_menu_button("Продолжить", _set_paused.bind(false), true))
	box.add_child(_menu_button("Начать уровень заново", _restart_level))
	box.add_child(_menu_button("В главное меню", Game.go_to_menu))
	box.add_child(HSeparator.new())
	box.add_child(SettingsPanel.new())


func _restart_level() -> void:
	_set_paused(false)
	interpreter.stop()
	load_level(level_index)


func _menu_button(text: String, callback: Callable, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	if accent:
		button.theme_type_variation = &"AccentButton"
	button.pressed.connect(callback)
	return button


# --- Работа с деревом программы ---

## Общее число команд в программе (блок считается одной командой).
func _count_nodes(block: Array) -> int:
	var total := 0
	for node in block:
		total += 1
		if node.has("body"):
			total += _count_nodes(node["body"])
	return total


func _index_of(block: Array, node: Dictionary) -> int:
	for i in block.size():
		if is_same(block[i], node):
			return i
	return -1


## Находит узел, телом которого является target. {} — если это корень.
func _find_owner(target: Array, block: Array) -> Dictionary:
	for node in block:
		if node.has("body"):
			if is_same(node["body"], target):
				return node
			var found := _find_owner(target, node["body"])
			if not found.is_empty():
				return found
	return {}


## Находит блок, внутри которого лежит блок target. null — если не найден.
func _find_parent(target: Array, block: Array) -> Variant:
	for node in block:
		if node.has("body"):
			if is_same(node["body"], target):
				return block
			var found = _find_parent(target, node["body"])
			if found != null:
				return found
	return null


func _block_in_tree(target: Array, block: Array) -> bool:
	if is_same(target, block):
		return true
	for node in block:
		if node.has("body") and _block_in_tree(target, node["body"]):
			return true
	return false


func _node_title(node: Dictionary) -> String:
	match node["cmd"]:
		"repeat":
			return "Повторить %d раз" % node["count"]
		"if":
			return "Если впереди %s" % Levels.COND_TITLES[node["cond"]]
	return Levels.COMMAND_TITLES[node["cmd"]]


# --- Вспомогательное ---

func _set_status(text: String, color := Palette.PARAGRAPH) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)


func _make_hint_label(text: String, depth: int) -> Label:
	var label := Label.new()
	label.text = "      ".repeat(depth) + text
	label.modulate = Color(1, 1, 1, 0.5)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _run_selftest() -> void:
	Engine.time_scale = 4.0
	var all_ok := true
	for i in Levels.LIST.size():
		load_level(i)
		_load_solution()
		_start(false)
		var result: Array = await interpreter.finished
		print("SELFTEST level %d: %s (%s)" % [i + 1, "OK" if result[0] else "FAIL", result[1]])
		all_ok = all_ok and result[0]
	print("SELFTEST RESULT: ", "PASSED" if all_ok else "FAILED")
	get_tree().quit(0 if all_ok else 1)
