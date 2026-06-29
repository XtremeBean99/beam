extends Node2D
@onready var score_label = $HUD/ScorePanel/ScoreLabel
@onready var health_label = $HUD/HealthPanel/HealthLabel
@onready var player = $LevelRoot/Player
@onready var pause_overlay = $HUD/PauseOverlay

var score = 0
var is_paused = false


func _ready():
	_setup_level()
	_update_health_display()
	pause_overlay.hide()


func _process(_delta):
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()


func _setup_level():
	for collectable in get_tree().get_nodes_in_group("collectables"):
		if collectable.has_signal("collected") and not collectable.collected.is_connected(increase_score):
			collectable.collected.connect(increase_score)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_signal("player_hit") and not enemy.player_hit.is_connected(_on_player_hit):
			enemy.player_hit.connect(_on_player_hit)

	if player and player.has_signal("player_died"):
		if not player.player_died.is_connected(_on_player_died):
			player.player_died.connect(_on_player_died)


func _on_player_hit(body):
	if body.has_method("hurt") and body.alive:
		body.hurt()
		_update_health_display()


func _on_player_died():
	await get_tree().create_timer(1.5).timeout
	get_tree().reload_current_scene()


func _update_health_display():
	if player and player.has_method("hurt"):
		health_label.text = "HP: %d" % player.health


func increase_score():
	score += 1
	score_label.text = "SCORE: %s" % score


func _toggle_pause():
	is_paused = not is_paused
	get_tree().paused = is_paused
	pause_overlay.visible = is_paused


func _on_resume_pressed():
	_toggle_pause()


func _on_quit_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
