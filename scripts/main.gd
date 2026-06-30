extends Node2D

@onready var player = $LevelRoot/Player
@onready var pause_overlay = $HUD/PauseOverlay
@onready var settings_menu = $HUD/SettingsMenu
@onready var score_label = $HUD/StatsPanel/VBox/ScoreRow/Value
@onready var kills_label = $HUD/StatsPanel/VBox/KillsRow/Value
@onready var pips = [
	$HUD/StatsPanel/VBox/HealthRow/Pips/Pip1,
	$HUD/StatsPanel/VBox/HealthRow/Pips/Pip2,
	$HUD/StatsPanel/VBox/HealthRow/Pips/Pip3,
]

const PIP_FULL := Color(0.85, 0.92, 1.0, 1.0)
const PIP_EMPTY := Color(0.28, 0.32, 0.4, 0.5)

var score := 0
var kills := 0
var is_paused := false


func _ready() -> void:
	_setup_level()
	_update_health()
	_update_score()
	_update_kills()
	pause_overlay.hide()
	settings_menu.hide()
	settings_menu.closed.connect(_on_settings_closed)
	$HUD/PauseOverlay/Center/VBox/ResumeButton.pressed.connect(_on_resume_pressed)
	$HUD/PauseOverlay/Center/VBox/SettingsButton.pressed.connect(_on_settings_pressed)
	$HUD/PauseOverlay/Center/VBox/QuitButton.pressed.connect(_on_quit_pressed)


func _process(_delta) -> void:
	if Input.is_action_just_pressed("pause") and not settings_menu.visible:
		_toggle_pause()


func _setup_level() -> void:
	for collectable in get_tree().get_nodes_in_group("collectables"):
		if collectable.has_signal("collected") and not collectable.collected.is_connected(increase_score):
			collectable.collected.connect(increase_score)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_signal("player_hit") and not enemy.player_hit.is_connected(_on_player_hit):
			enemy.player_hit.connect(_on_player_hit)
		if enemy.has_signal("died") and not enemy.died.is_connected(_on_enemy_died):
			enemy.died.connect(_on_enemy_died)

	if player and player.has_signal("player_died") and not player.player_died.is_connected(_on_player_died):
		player.player_died.connect(_on_player_died)


func _on_player_hit(body) -> void:
	if body.has_method("hurt") and body.alive:
		body.hurt()
		_update_health()


func _on_enemy_died() -> void:
	kills += 1
	_update_kills()


func _on_player_died() -> void:
	await get_tree().create_timer(1.2).timeout
	get_tree().reload_current_scene()


func increase_score() -> void:
	score += 1
	_update_score()


func _update_score() -> void:
	score_label.text = str(score)


func _update_kills() -> void:
	kills_label.text = str(kills)


func _update_health() -> void:
	var hp: int = player.health if is_instance_valid(player) else 0
	for i in range(pips.size()):
		pips[i].color = PIP_FULL if i < hp else PIP_EMPTY


func _toggle_pause() -> void:
	is_paused = not is_paused
	get_tree().paused = is_paused
	pause_overlay.visible = is_paused
	if is_paused:
		$HUD/PauseOverlay/Center/VBox/ResumeButton.grab_focus()


func _on_resume_pressed() -> void:
	_toggle_pause()


func _on_settings_pressed() -> void:
	pause_overlay.hide()
	settings_menu.open()


func _on_settings_closed() -> void:
	if is_paused:
		pause_overlay.show()
		$HUD/PauseOverlay/Center/VBox/ResumeButton.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
