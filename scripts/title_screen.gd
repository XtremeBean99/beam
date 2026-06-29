extends Control

# Start the game on any key press, mouse click, or the "Start" button.

const GAME_SCENE = "res://scenes/Main.tscn"


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	# Gentle pulsing on the prompt so it reads as interactive.
	var prompt := $CenterContainer/VBoxContainer/Prompt
	var tween := create_tween().set_loops()
	tween.tween_property(prompt, "modulate:a", 0.2, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and (event is InputEventKey or event is InputEventMouseButton):
		start_game()


func start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
