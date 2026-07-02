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
	_show_best_run()

	# Gentle breathing on the prompt so the title reads as alive.
	var tween := create_tween().set_loops()
	tween.tween_property(_prompt, "modulate:a", 0.25, 1.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_prompt, "modulate:a", 0.9, 1.0).set_trans(Tween.TRANS_SINE)

	# Fade the whole menu in from black on load — matches the in-game transitions.
	modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

	# Slow breathing on the title's glow shadow (ink pulse).
	var title: Label = $Center/VBox/Title
	var glow := create_tween().set_loops()
	glow.tween_method(func(v: float):
		title.add_theme_color_override(
			"font_shadow_color", Color(0.35, 0.6, 0.95, v)),
		0.55, 0.25, 1.8).set_trans(Tween.TRANS_SINE)
	glow.tween_method(func(v: float):
		title.add_theme_color_override(
			"font_shadow_color", Color(0.35, 0.6, 0.95, v)),
		0.25, 0.55, 1.8).set_trans(Tween.TRANS_SINE)


## Show the persisted fastest full-run time (written by main.gd), if one exists.
func _show_best_run() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://best_run.cfg") != OK:
		return
	var best := float(cfg.get_value("run", "best_time", -1.0))
	if best <= 0.0:
		return
	var label: Label = $Center/VBox/BestRun
	label.text = "BEST RUN  —  %d:%02d.%02d" % [
		int(best / 60.0), int(fmod(best, 60.0)), int(fmod(best, 1.0) * 100.0)]
	label.show()


func _open_settings() -> void:
	$Center.hide()
	_settings.open()


func _close_settings() -> void:
	$Center.show()
	_play.grab_focus()
# EOF
