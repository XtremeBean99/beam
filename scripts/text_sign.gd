@tool
extends Node2D
class_name TextSign

## Always-visible world-space tutorial sign: an outlined Label centered on this
## node's origin. Lives in world space (moves with the level, not the screen), so
## place it next to the thing it explains. Edit `text` / `font_size` per instance.

@export_multiline var text: String = "":
	set(value):
		text = value
		_apply()

@export var font_size: int = 64:
	set(value):
		font_size = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	var label := get_node_or_null("Label") as Label
	if label == null:
		return
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
