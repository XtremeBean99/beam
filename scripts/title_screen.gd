extends Control

## Start menu: Play / Settings / Quit, with the shared volume settings panel.

const GAME_SCENE := "res://scenes/Main.tscn"

@onready var _play: Button = $Center/VBox/Menu/Play
@onready var _settings_btn: Button = $Center/VBox/Menu/Settings
@onready var _quit: Button = $Center/VBox/Menu/Quit
@onready var _settings: Control = $SettingsMenu
@onready var _prompt: Label = $Center/VBox/Prompt


func _ready() -> void:
	_play.pressed.connect(func(): get_tree().change_scene_to_file(GAME_SCENE))
	_settings_btn.pressed.connect(_open_settings)
	_quit.pressed.connect(func(): get_tree().quit())
	_settings.hide()
	_settings.closed.connect(_close_settings)
	_play.grab_focus()

	# Gentle breathing on the prompt so the title reads as alive.
	var tween := create_tween().set_loops()
	tween.tween_property(_prompt, "modulate:a", 0.25, 1.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_prompt, "modulate:a", 0.9, 1.0).set_trans(Tween.TRANS_SINE)


func _open_settings() -> void:
	$Center.hide()
	_settings.open()


func _close_settings() -> void:
	$Center.show()
	_play.grab_focus()
