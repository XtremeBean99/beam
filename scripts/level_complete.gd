extends Control

## Level-complete screen — shown after the beam-of-light transports the player.
## Displays stats (time, score, kills) with the Ink & Circuit theme and a
## closing-ensō reward motif. Continue reloads the level.

signal continue_pressed

@onready var _panel: PanelContainer = $Center/Panel
@onready var _time_label: Label = $Center/Panel/VBox/Stats/TimeRow/Value
@onready var _score_label: Label = $Center/Panel/VBox/Stats/ScoreRow/Value
@onready var _kills_label: Label = $Center/Panel/VBox/Stats/KillsRow/Value
@onready var _continue_btn: Button = $Center/Panel/VBox/Continue
@onready var _enso: Control = $EnsoContainer/Enso


func _ready() -> void:
	hide()
	_continue_btn.pressed.connect(_on_continue)


func show_stats(elapsed: float, score: int, kills: int) -> void:
	var mins := int(elapsed / 60.0)
	var secs := int(fmod(elapsed, 60.0))
	_time_label.text = "%d:%02d" % [mins, secs]
	_score_label.text = str(score)
	_kills_label.text = str(kills)
	show()
	_continue_btn.grab_focus()
	_animate_enso()


func _animate_enso() -> void:
	# The ensō starts as an incomplete arc and closes as a reward motif,
	# accompanied by a glow pulse, then breathes gently.
	if _enso.has_method("animate_close"):
		_enso.animate_close()


func _on_continue() -> void:
	continue_pressed.emit()
