extends CanvasLayer

## Reusable ink-wipe / fade transition. Renders over everything.
## Usage: add to Main.tscn, call fade_to_black() / fade_from_black().

@onready var _color: ColorRect = $ColorRect


func _ready() -> void:
	_color.modulate.a = 0.0
	_color.hide()


func fade_to_black(duration: float = 0.5) -> void:
	_color.modulate.a = 0.0
	_color.show()
	var t := create_tween()
	t.tween_property(_color, "modulate:a", 1.0, duration)


func fade_from_black(duration: float = 0.5) -> void:
	_color.modulate.a = 1.0
	_color.show()
	var t := create_tween()
	t.tween_property(_color, "modulate:a", 0.0, duration)
	t.tween_callback(_color.hide)
