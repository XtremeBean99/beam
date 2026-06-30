extends Control

## Reusable volume settings panel (Master / Music / SFX). Reads and writes the
## Settings autoload. Emits `closed` when the player backs out, so whichever
## screen opened it (title or pause) can hide it again.

signal closed

@onready var _rows := {
	"Master": $Dim/Center/Panel/VBox/Master,
	"Music": $Dim/Center/Panel/VBox/Music,
	"SFX": $Dim/Center/Panel/VBox/SFX,
}


func _ready() -> void:
	for bus in _rows:
		var row: Node = _rows[bus]
		var slider: HSlider = row.get_node("Slider")
		var value: Label = row.get_node("Value")
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = Settings.get_volume(bus)
		value.text = "%d%%" % roundi(slider.value * 100.0)
		slider.value_changed.connect(_on_value_changed.bind(bus))
	$Dim/Center/Panel/VBox/Back.pressed.connect(_on_back)


func open() -> void:
	show()
	# Refresh from saved values and focus the first slider for keyboard users.
	for bus in _rows:
		var slider: HSlider = _rows[bus].get_node("Slider")
		slider.value = Settings.get_volume(bus)
	($Dim/Center/Panel/VBox/Master/Slider as HSlider).grab_focus()


func _on_value_changed(value: float, bus: String) -> void:
	Settings.set_volume(bus, value)
	(_rows[bus].get_node("Value") as Label).text = "%d%%" % roundi(value * 100.0)


func _on_back() -> void:
	hide()
	closed.emit()
