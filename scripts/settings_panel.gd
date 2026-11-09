class_name SettingsPanel
extends VBoxContainer
## Панель настроек: громкость и скорость выполнения программы.
## Используется в главном меню и в меню паузы. Изменения сразу сохраняются.

## [Название, ключ настройки, минимум, максимум, шаг, формат]
const ITEMS := [
	["Общая громкость", "master", 0.0, 1.0, 0.05, "percent"],
	["Музыка", "music", 0.0, 1.0, 0.05, "percent"],
	["Звуки", "sfx", 0.0, 1.0, 0.05, "percent"],
	["Скорость выполнения", "speed", 0.5, 3.0, 0.25, "speed"],
]

var _sliders := {}
var _labels := {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	for item in ITEMS:
		var label := Label.new()
		add_child(label)
		var slider := HSlider.new()
		slider.min_value = item[2]
		slider.max_value = item[3]
		slider.step = item[4]
		slider.custom_minimum_size = Vector2(300, 26)
		slider.value = Game.settings[item[1]]
		slider.value_changed.connect(_on_value_changed.bind(item[1]))
		add_child(slider)
		_sliders[item[1]] = slider
		_labels[item[1]] = label
	Game.settings_changed.connect(_sync)
	_sync()


func _on_value_changed(value: float, key: String) -> void:
	Game.set_setting(key, value)


## Обновляет ползунки, если настройку изменили в другом месте.
func _sync() -> void:
	for item in ITEMS:
		var key: String = item[1]
		var value: float = Game.settings[key]
		_sliders[key].set_value_no_signal(value)
		var text := "%d%%" % roundi(value * 100.0) if item[5] == "percent" else "%.2f×" % value
		_labels[key].text = "%s: %s" % [item[0], text]
