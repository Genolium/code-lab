class_name Interpreter
extends Node
## Интерпретатор программы пользователя.
##
## Программа — дерево узлов-словарей:
##   {"id": 1, "cmd": "forward"}                                — действие робота;
##   {"id": 2, "cmd": "repeat", "count": 3, "body": [...]}      — цикл;
##   {"id": 3, "cmd": "if", "cond": "blocked", "body": [...]}   — условие.
## Интерпретатор обходит дерево рекурсивно, дожидается окончания анимации
## каждого действия и сообщает о ходе выполнения через сигналы.
## Как только робот встаёт на цель, выполнение завершается успехом.
## В пошаговом режиме перед каждым действием ждёт вызова advance().

signal step_started(node_id: int)                ## Начал выполняться узел программы.
signal finished(success: bool, message: String)  ## Программа завершилась.
signal _step_requested

const MAX_ACTIONS := 300  ## Защита от слишком долгих программ.

## Служебные результаты выполнения (не текст ошибки).
const GOAL_REACHED := "@goal"
const STOPPED := "@stop"

@export var pause_between_steps := 0.1

var robot: Robot
var board: Board
var is_running := false
var step_mode := false  ## Пошаговый режим.

var _stop_requested := false
var _actions := 0


func run(program: Array) -> void:
	is_running = true
	_stop_requested = false
	_actions = 0

	var result: String = await _run_block(program)

	is_running = false
	match result:
		GOAL_REACHED:
			finished.emit(true, "Уровень пройден!")
		STOPPED:
			finished.emit(false, "Выполнение остановлено.")
		"":
			finished.emit(false, "Программа закончилась, но робот не дошёл до цели.")
		_:
			finished.emit(false, result)


## Просит остановиться: текущее действие доиграет до конца, следующие — нет.
func stop() -> void:
	_stop_requested = true
	_step_requested.emit()


## Пошаговый режим: разрешает выполнить следующее действие.
func advance() -> void:
	_step_requested.emit()


## Выполняет команды блока по порядку. Возвращает "" или причину остановки.
func _run_block(block: Array) -> String:
	for node in block:
		if _stop_requested:
			return STOPPED
		var result: String = await _run_node(node)
		if result != "":
			return result
	return ""


func _run_node(node: Dictionary) -> String:
	step_started.emit(node["id"])
	if step_mode and node["cmd"] != "repeat":
		await _step_requested
		if _stop_requested:
			return STOPPED

	match node["cmd"]:
		"repeat":
			for i in int(node["count"]):
				var result: String = await _run_block(node["body"])
				if result != "":
					return result
			return ""
		"if":
			# Короткая пауза, чтобы было видно, что робот «проверяет» условие.
			await _pause()
			if check_condition(node["cond"]):
				return await _run_block(node["body"])
			return ""
		_:
			_actions += 1
			if _actions > MAX_ACTIONS:
				return "Слишком много действий: возможно, цикл повторяется слишком много раз."
			var error: String = await _execute(node["cmd"])
			if error != "":
				return error
			if robot.cell == board.goal_cell:
				return GOAL_REACHED
			await _pause()
			return ""


## Проверяет условие блока «Если впереди …».
func check_condition(cond: String) -> bool:
	var ahead := robot.cell + robot.direction
	match cond:
		"blocked":
			return not board.is_floor(ahead)
		"free":
			return board.is_floor(ahead)
	return false


## Выполняет одно действие робота. Возвращает "" или текст ошибки.
func _execute(command: String) -> String:
	match command:
		"forward":
			return await robot.move_forward()
		"left":
			await robot.turn(true)
		"right":
			await robot.turn(false)
		"take":
			if not board.take_key(robot.cell):
				return "Здесь нечего взять."
			await robot.pick_up()
		"open":
			var target := robot.cell + robot.direction
			if not board.has_locked_door(target):
				return "Перед роботом нет запертой двери."
			if robot.keys <= 0:
				return "У робота нет ключа."
			robot.use_key()
			await board.open_door(target)
		_:
			return "Неизвестная команда: %s" % command
	return ""


func _pause() -> void:
	var speed := maxf(float(Game.settings["speed"]), 0.1)
	# false — таймер останавливается, когда игра на паузе.
	await get_tree().create_timer(pause_between_steps / speed, false).timeout
