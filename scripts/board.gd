class_name Board
extends Node3D
## Игровое поле: строит клетки, стены, цель и интерактивные объекты
## (ключи, двери, кнопки, силовые поля) по карте уровня и отвечает
## на вопрос «что находится в клетке?».

const FLOOR_CHARS := [".", "S", "G", "K", "B"]

var width := 0
var height := 0
var start_cell := Vector2i.ZERO
var goal_cell := Vector2i.ZERO

var _rows: Array[String] = []
var _goal_crystal: Node3D
var _crystal_y := 0.45  ## Базовая высота кристалла над клеткой (при покачивании).
var _keys := {}      ## Клетка -> модель ключа.
var _doors := {}     ## Клетка -> запертая дверь (удаляется при открытии).
var _gates := {}     ## Клетка -> силовое поле.
var _buttons := {}   ## Клетка -> кнопка.
var _gates_open := false
var _time := 0.0

# Материалы из палитры игры (см. palette.gd): светлые и мятные плитки с тёмными
# боками-«обводкой», тёмно-зелёные стены, жёлтая цель, коралловые ключ и дверь.
var _top_mat_a := make_material(Palette.MAIN)
var _top_mat_b := make_material(Palette.SECONDARY)
var _side_mat := make_material(Palette.STROKE)
var _wall_mat := make_material(Palette.BACKGROUND.lightened(0.12))
var _wall_cap_mat := make_material(Palette.SECONDARY.darkened(0.15))
var _goal_mat := make_material(Palette.HIGHLIGHT, 1.4)
var _key_mat := make_material(Palette.TERTIARY, 0.3)
var _door_mat := make_material(Palette.TERTIARY)
var _door_band_mat := make_material(Palette.STROKE)
var _button_mat := make_material(Palette.TERTIARY, 0.6)
var _button_on_mat := make_material(Palette.SECONDARY, 0.8)
var _gate_mat := _make_gate_material()
var _dust_mat := _make_dust_material()


## Создаёт материал заданного цвета. emission > 0 — объект светится.
static func make_material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat


## Загружает 3D-модель из набора Kenney Platformer Kit (CC0) и красит её
## материалом из палитры игры. Если файл не найден — возвращает null.
static func load_model(model_name: String, mat: Material) -> Node3D:
	var scene := load("res://assets/kenney/models/%s.glb" % model_name) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	_apply_material(model, mat)
	return model


static func _apply_material(node: Node, mat: Material) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = mat


## Модель ключа (используется и на поле, и над роботом): Kenney, а если файла
## нет — собранная из простых фигур.
static func make_key_model(mat: Material) -> Node3D:
	var kenney := load_model("key", mat)
	if kenney:
		# Ключ у Kenney стоит на «земле»: центрируем по высоте, чтобы он парил ровно.
		kenney.position.y = -0.11
		var holder := Node3D.new()
		holder.add_child(kenney)
		return holder
	var root := Node3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.06
	ring.outer_radius = 0.12
	var ring_part := _part(ring, mat, Vector3(-0.12, 0, 0))
	ring_part.rotation.x = PI / 2.0
	root.add_child(ring_part)
	root.add_child(_part(_box_mesh(Vector3(0.26, 0.05, 0.05)), mat, Vector3(0.06, 0, 0)))
	root.add_child(_part(_box_mesh(Vector3(0.04, 0.09, 0.05)), mat, Vector3(0.15, -0.05, 0)))
	root.add_child(_part(_box_mesh(Vector3(0.03, 0.07, 0.05)), mat, Vector3(0.08, -0.04, 0)))
	return root


## Полностью перестраивает поле по описанию уровня из Levels.LIST.
func build(level: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_goal_crystal = null
	_keys.clear()
	_doors.clear()
	_gates.clear()
	_buttons.clear()
	_gates_open = false

	_rows.assign(level["map"])
	height = _rows.size()
	width = 0
	for row in _rows:
		width = maxi(width, row.length())

	for z in height:
		for x in width:
			var cell := Vector2i(x, z)
			var ch := get_char(cell)
			if ch == "#":
				_add_wall(cell)
			elif ch != " ":
				_add_tile(cell, (x + z) % 2 == 0)
				match ch:
					"S":
						start_cell = cell
					"G":
						goal_cell = cell
						_add_goal(cell)
					"K":
						_add_key(cell)
					"L":
						_add_door(cell)
					"B":
						_add_button(cell)
					"D":
						_add_gate(cell)
	_add_dust()


## Символ карты в клетке; за пределами карты — пустота.
func get_char(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= height:
		return " "
	var row := _rows[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return " "
	return row[cell.x]


## Препятствие, в которое робот упирается (стена, закрытая дверь или поле).
func is_wall(cell: Vector2i) -> bool:
	var ch := get_char(cell)
	return ch == "#" or _doors.has(cell) or (ch == "D" and not _gates_open)


## Клетка, на которую можно встать.
func is_floor(cell: Vector2i) -> bool:
	var ch := get_char(cell)
	if ch in FLOOR_CHARS:
		return true
	if ch == "L":
		return not _doors.has(cell)
	if ch == "D":
		return _gates_open
	return false


## Название препятствия для сообщения об ошибке.
func obstacle_name(cell: Vector2i) -> String:
	if _doors.has(cell):
		return "запертую дверь"
	if get_char(cell) == "D":
		return "силовое поле"
	return "стену"


func has_locked_door(cell: Vector2i) -> bool:
	return _doors.has(cell)


## Подбирает ключ в клетке. Возвращает true, если ключ там был.
func take_key(cell: Vector2i) -> bool:
	if not _keys.has(cell):
		return false
	var key: Node3D = _keys[cell]
	_keys.erase(cell)
	Sfx.world("pickup")
	var tween := create_tween().set_parallel()
	tween.tween_property(key, "position:y", 1.3, 0.3)
	tween.tween_property(key, "scale", Vector3.ONE * 0.01, 0.3).set_delay(0.1)
	tween.chain().tween_callback(key.queue_free)
	return true


## Открывает запертую дверь: она уезжает под пол.
func open_door(cell: Vector2i) -> void:
	var door: Node3D = _doors[cell]
	_doors.erase(cell)
	Sfx.world("door")
	var tween := create_tween()
	tween.tween_property(door, "position:y", -1.1, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	door.visible = false


## Вызывается роботом, когда он встал в клетку.
func robot_entered(cell: Vector2i) -> void:
	if not _buttons.has(cell) or _gates_open:
		return
	_gates_open = true
	Sfx.world("button")
	Sfx.world("gate")
	var button: Node3D = _buttons[cell]
	_apply_material(button, _button_on_mat)
	if button is MeshInstance3D:
		(button as MeshInstance3D).material_override = _button_on_mat
	# Кнопка вдавливается в пол.
	create_tween().tween_property(button, "position:y", button.position.y - 0.06, 0.15)
	for gate: Node3D in _gates.values():
		# Поле «опускается» в пол: уменьшаем высоту и сдвигаем центр вниз.
		var tween := create_tween().set_parallel()
		tween.tween_property(gate, "scale:y", 0.02, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(gate, "position:y", 0.01, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(gate.hide)


## Праздничный салют над целью.
func celebrate() -> void:
	var particles := CPUParticles3D.new()
	particles.position = cell_to_world(goal_cell) + Vector3(0, 0.5, 0)
	particles.amount = 70
	particles.lifetime = 1.5
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = 2.5
	particles.initial_velocity_max = 5.0
	particles.gravity = Vector3(0, -7, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.3
	var mesh := _box_mesh(Vector3.ONE * 0.07)
	mesh.material = _goal_mat
	particles.mesh = mesh
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(2.5).timeout.connect(particles.queue_free)


## Переводит клетку карты в координаты 3D-мира (одна клетка = 1 метр).
func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, 0.0, cell.y)


func get_center() -> Vector3:
	return Vector3((width - 1) * 0.5, 0.0, (height - 1) * 0.5)


func _process(delta: float) -> void:
	_time += delta
	if _goal_crystal:
		_goal_crystal.rotation.y += delta * 1.5
		_goal_crystal.position.y = _crystal_y + sin(_time * 3.0) * 0.08
	for key: Node3D in _keys.values():
		key.rotation.y += delta * 2.0
		key.position.y = 0.4 + sin(_time * 2.5) * 0.06
	_gate_mat.albedo_color.a = 0.32 + 0.1 * sin(_time * 5.0)


# --- Построение объектов ---

func _add_tile(cell: Vector2i, even: bool) -> void:
	# Тело плитки (тёмные бока) и светлая верхняя пластина.
	_add_box(cell, Vector3(0.94, 0.34, 0.94), -0.23, _side_mat)
	_add_box(cell, Vector3(0.97, 0.06, 0.97), -0.03, _top_mat_a if even else _top_mat_b)


func _add_wall(cell: Vector2i) -> void:
	_add_box(cell, Vector3(0.96, 0.8, 0.96), 0.0, _wall_mat)
	_add_box(cell, Vector3(0.98, 0.06, 0.98), 0.42, _wall_cap_mat)


func _add_goal(cell: Vector2i) -> void:
	var goal := Node3D.new()
	goal.position = cell_to_world(cell)
	add_child(goal)

	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.38
	pad_mesh.bottom_radius = 0.38
	pad_mesh.height = 0.04
	goal.add_child(_part(pad_mesh, _goal_mat, Vector3(0, 0.02, 0)))

	# Кристалл-цель: модель jewel из Kenney (начало координат у основания)
	# или запасной вариант из простой фигуры.
	var jewel := load_model("jewel", _goal_mat)
	if jewel:
		jewel.scale = Vector3.ONE * 1.5
		_crystal_y = 0.28
		_goal_crystal = jewel
	else:
		var crystal_mesh := SphereMesh.new()
		crystal_mesh.radius = 0.16
		crystal_mesh.height = 0.4
		crystal_mesh.radial_segments = 4
		crystal_mesh.rings = 2
		_crystal_y = 0.45
		_goal_crystal = _part(crystal_mesh, _goal_mat, Vector3.ZERO)
	goal.add_child(_goal_crystal)

	var light := OmniLight3D.new()
	light.light_color = Palette.HIGHLIGHT
	light.light_energy = 1.5
	light.omni_range = 3.0
	light.position.y = 0.6
	goal.add_child(light)


func _add_key(cell: Vector2i) -> void:
	var key := make_key_model(_key_mat)
	key.position = cell_to_world(cell) + Vector3(0, 0.4, 0)
	key.scale = Vector3.ONE * 1.4
	add_child(key)
	_keys[cell] = key

	var light := OmniLight3D.new()
	light.light_color = Palette.TERTIARY
	light.light_energy = 0.8
	light.omni_range = 1.5
	key.add_child(light)


func _add_door(cell: Vector2i) -> void:
	var door := Node3D.new()
	door.position = cell_to_world(cell)
	door.add_child(_part(_box_mesh(Vector3(0.9, 0.95, 0.9)), _door_mat, Vector3(0, 0.47, 0)))
	# Дверь того же цвета, что и ключ: подсказка, что её открывает ключ.
	door.add_child(_part(_box_mesh(Vector3(0.94, 0.1, 0.94)), _door_band_mat, Vector3(0, 0.25, 0)))
	door.add_child(_part(_box_mesh(Vector3(0.94, 0.1, 0.94)), _door_band_mat, Vector3(0, 0.7, 0)))
	add_child(door)
	_doors[cell] = door


func _add_button(cell: Vector2i) -> void:
	var button := load_model("button-round", _button_mat)
	if button:
		button.scale = Vector3.ONE * 0.9
		button.position = cell_to_world(cell)
	else:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.26
		mesh.bottom_radius = 0.3
		mesh.height = 0.08
		button = _part(mesh, _button_mat, cell_to_world(cell) + Vector3(0, 0.04, 0))
	add_child(button)
	_buttons[cell] = button


func _add_gate(cell: Vector2i) -> void:
	var gate := _part(_box_mesh(Vector3(0.92, 1.0, 0.92)), _gate_mat,
			cell_to_world(cell) + Vector3(0, 0.5, 0))
	add_child(gate)
	_gates[cell] = gate


func _add_dust() -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 80
	particles.lifetime = 10.0
	particles.preprocess = 10.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(width * 0.5 + 3.0, 2.0, height * 0.5 + 3.0)
	particles.position = get_center() + Vector3(0, 1.0, 0)
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 0.03
	particles.initial_velocity_max = 0.12
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	quad.material = _dust_mat
	particles.mesh = quad
	add_child(particles)


func _add_box(cell: Vector2i, size: Vector3, y: float, mat: Material) -> void:
	add_child(_part(_box_mesh(size), mat, cell_to_world(cell) + Vector3(0.0, y, 0.0)))


static func _part(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	return inst


static func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _make_gate_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(Palette.TERTIARY, 0.4)
	return mat


static func _make_dust_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(Palette.SECONDARY, 0.5)
	return mat
