class_name CameraRig
extends Node3D
## Орбитальная камера вокруг центра поля.
## Правая кнопка мыши + движение — вращение, колесо мыши — приближение.

@export var min_distance := 4.0
@export var max_distance := 25.0
@export var mouse_sensitivity := 0.008
@export var screen_offset := 0.12  ## Сдвиг кадра вбок (доля расстояния), чтобы поле не пряталось под панелью.
@export var auto_rotate := 0.0     ## Скорость автоповорота, рад/с (0 — выключен).

var distance := 10.0
var _yaw := deg_to_rad(20.0)
var _pitch := deg_to_rad(-50.0)
var _dragging := false
var _focused := false

@onready var camera: Camera3D = $Camera3D


## Наводит камеру на точку и подбирает расстояние под размер поля.
## Первый раз — мгновенно, дальше — плавным перелётом.
func focus(target: Vector3, board_size: float) -> void:
	var new_distance := clampf(board_size * 1.2 + 3.0, min_distance, max_distance)
	if not _focused:
		_focused = true
		position = target
		distance = new_distance
		_apply()
		return
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", target, 0.8)
	tween.tween_property(self, "distance", new_distance, 0.8)


func _process(delta: float) -> void:
	if auto_rotate != 0.0 and not _dragging:
		_yaw += auto_rotate * delta
	_apply()


func _apply() -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)
	camera.h_offset = distance * screen_offset


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance - 0.8)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance + 0.8)
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity,
				deg_to_rad(-85.0), deg_to_rad(-15.0))
