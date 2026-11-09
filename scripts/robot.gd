class_name Robot
extends Node3D
## Робот: хранит своё положение на поле (клетку и направление), ключи
## и умеет анимированно выполнять элементарные действия.
## Модель собрана из простых фигур.

@export var step_time := 0.35  ## Длительность шага при скорости 1×, секунд.

var board: Board
var cell := Vector2i.ZERO
var direction := Vector2i(1, 0)
var keys := 0

var _yaw := 0.0
var _body: Node3D
var _key_icon: Node3D
var _lamp_mat: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	_build_model()


func _process(delta: float) -> void:
	# Мигающая лампочка на антенне и вращающийся ключ над головой.
	_time += delta
	_lamp_mat.emission_energy_multiplier = 0.5 + 1.0 * (0.5 + 0.5 * sin(_time * 4.0))
	if _key_icon.visible:
		_key_icon.rotation.y += delta * 2.5


## Ставит робота в клетку с заданным направлением (без анимации).
func place(target_board: Board, start_cell: Vector2i, start_dir: Vector2i) -> void:
	board = target_board
	cell = start_cell
	direction = start_dir
	keys = 0
	_key_icon.visible = false
	_body.position = Vector3.ZERO
	_yaw = atan2(-float(direction.x), -float(direction.y))
	position = board.cell_to_world(cell)
	rotation = Vector3(0.0, _yaw, 0.0)
	visible = true


## Длительность анимации с учётом выбранной скорости выполнения.
func duration(factor: float) -> float:
	return step_time * factor / maxf(float(Game.settings["speed"]), 0.1)


## Шаг вперёд. Возвращает "" при успехе или текст ошибки.
## Функция асинхронная: вызывать через await.
func move_forward() -> String:
	var next := cell + direction
	if board.is_wall(next):
		Sfx.world("bump")
		await _bump()
		return "Робот упёрся в %s." % board.obstacle_name(next)
	cell = next
	if not board.is_floor(next):
		Sfx.world("fall")
		await _fall()
		return "Робот упал с платформы."

	Sfx.world("step")
	var move := create_tween()
	move.tween_property(self, "position", board.cell_to_world(cell), duration(1.0)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var hop := create_tween()
	hop.tween_property(_body, "position:y", 0.08, duration(0.5))
	hop.tween_property(_body, "position:y", 0.0, duration(0.5))
	await move.finished
	board.robot_entered(cell)
	return ""


## Поворот на месте на 90°: left = true — налево, иначе направо.
func turn(left: bool) -> void:
	if left:
		direction = Vector2i(direction.y, -direction.x)
		_yaw += PI / 2.0
	else:
		direction = Vector2i(-direction.y, direction.x)
		_yaw -= PI / 2.0
	Sfx.world("turn")
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", _yaw, duration(0.7)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished


## Робот подобрал ключ: подпрыгивает, ключ появляется над головой.
func pick_up() -> void:
	keys += 1
	_key_icon.visible = true
	var tween := create_tween()
	tween.tween_property(_body, "position:y", 0.18, duration(0.35))
	tween.tween_property(_body, "position:y", 0.0, duration(0.35))
	await tween.finished


func use_key() -> void:
	keys -= 1
	_key_icon.visible = keys > 0


## Робот упирается в препятствие и отскакивает назад.
func _bump() -> void:
	var start := position
	var hit := start + Vector3(direction.x, 0.0, direction.y) * 0.25
	var tween := create_tween()
	tween.tween_property(self, "position", hit, duration(0.4))
	tween.tween_property(self, "position", start, duration(0.4))
	await tween.finished


## Робот съезжает в пустоту и падает.
func _fall() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", board.cell_to_world(cell), duration(0.6))
	tween.tween_property(self, "position:y", -6.0, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	visible = false


func _build_model() -> void:
	_body = Node3D.new()
	add_child(_body)

	var body_color := Board.make_material(Palette.BACKGROUND)
	var steel := Board.make_material(Palette.MAIN)
	var dark := Board.make_material(Palette.STROKE)
	var eye := Board.make_material(Palette.HIGHLIGHT, 2.0)
	_lamp_mat = Board.make_material(Palette.TERTIARY, 1.0)

	# Корпус и голова. «Перед» робота смотрит в сторону -Z.
	_add_part(_box(Vector3(0.55, 0.4, 0.5)), Vector3(0, 0.35, 0), body_color)
	_add_part(_box(Vector3(0.42, 0.3, 0.38)), Vector3(0, 0.72, 0), steel)
	# Глаза показывают направление взгляда.
	for x in [-0.1, 0.1]:
		_add_part(_sphere(0.05), Vector3(x, 0.74, -0.19), eye)
	# Антенна с лампочкой.
	_add_part(_cylinder(0.015, 0.2), Vector3(0, 0.97, 0), dark)
	_add_part(_sphere(0.045), Vector3(0, 1.09, 0), _lamp_mat)
	# Колёса.
	for x in [-0.3, 0.3]:
		for z in [-0.15, 0.15]:
			var wheel := _add_part(_cylinder(0.14, 0.1), Vector3(x, 0.14, z), dark)
			wheel.rotation.z = PI / 2.0

	# Ключ над головой (виден, когда робот несёт ключ).
	_key_icon = Board.make_key_model(Board.make_material(Palette.TERTIARY, 0.3))
	_key_icon.position = Vector3(0, 1.35, 0)
	_key_icon.visible = false
	_body.add_child(_key_icon)


func _add_part(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	_body.add_child(inst)
	return inst


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


func _cylinder(radius: float, h: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = h
	return mesh
