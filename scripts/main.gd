extends Node2D

@onready var level_root = $LevelRoot
@onready var player = $LevelRoot/Player
@onready var pause_overlay = $HUD/PauseOverlay
@onready var settings_menu = $HUD/SettingsMenu
@onready var transition = $Transition
@onready var level_complete = $LevelComplete
@onready var score_label = $HUD/StatsPanel/VBox/ScoreRow/Value
@onready var kills_label = $HUD/StatsPanel/VBox/KillsRow/Value
@onready var charge_label = $HUD/StatsPanel/VBox/ChargeRow/Value
@onready var charge_enso = $HUD/ChargeEnso
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
var _total_collectables := 0
var _collected_count := 0
var _elapsed := 0.0
var _level_done := false


func _ready() -> void:
	_setup_level()
	_update_health()
	_update_score()
	_update_kills()
	_update_charge()
	pause_overlay.hide()
	settings_menu.hide()
	transition.hide()
	level_complete.hide()

	settings_menu.closed.connect(_on_settings_closed)
	$HUD/PauseOverlay/Center/VBox/ResumeButton.pressed.connect(_on_resume_pressed)
	$HUD/PauseOverlay/Center/VBox/SettingsButton.pressed.connect(_on_settings_pressed)
	$HUD/PauseOverlay/Center/VBox/QuitButton.pressed.connect(_on_quit_pressed)

	# Level-complete wiring
	level_complete.continue_pressed.connect(_on_level_continue)

	# Transition wiring — when fade-to-black finishes, show level-complete screen.
	transition.faded_out.connect(_on_transition_faded_out)

	# Beam-done signal from the level
	if level_root and level_root.has_signal("beam_done"):
		level_root.beam_done.connect(_on_beam_done)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pause") and not settings_menu.visible and not _level_done:
		_toggle_pause()

	if not _level_done and not is_paused:
		_elapsed += delta


func _setup_level() -> void:
	# Count collectables
	var all_collectables := get_tree().get_nodes_in_group("collectables")
	_total_collectables = all_collectables.size()
	for collectable in all_collectables:
		if collectable.has_signal("collected") and not collectable.collected.is_connected(_on_collectable_collected):
			collectable.collected.connect(_on_collectable_collected)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_signal("player_hit") and not enemy.player_hit.is_connected(_on_player_hit):
			enemy.player_hit.connect(_on_player_hit)
		if enemy.has_signal("died") and not enemy.died.is_connected(_on_enemy_died):
			enemy.died.connect(_on_enemy_died)

	if player and player.has_signal("player_died") and not player.player_died.is_connected(_on_player_died):
		player.player_died.connect(_on_player_died)


func _on_collectable_collected() -> void:
	if _level_done:
		return
	_collected_count += 1
	score += 1
	_update_score()

	if _total_collectables > 0 and _collected_count >= _total_collectables:
		_level_done = true
		# Hide HUD during the beam sequence
		$HUD.hide()
		# Trigger the beam transport on the level
		if level_root and level_root.has_method("start_beam_transport"):
			level_root.start_beam_transport()
		else:
			# Fallback: skip straight to the level-complete screen
			_show_level_complete()


func _on_beam_done() -> void:
	# Beam transport finished — fade to black, then show level-complete.
	transition.fade_to_black(0.7)


func _on_transition_faded_out() -> void:
	_show_level_complete()
	transition.fade_from_black(0.5)


func _show_level_complete() -> void:
	level_complete.show_stats(_elapsed, score, kills)


func _on_level_continue() -> void:
	# Reload the current scene (only one level exists for now).
	# When more levels are added, this becomes load_level("levelN").
	transition.fade_to_black(0.4)
	await transition.faded_out
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_player_hit(body) -> void:
	if body.has_method("hurt") and body.alive:
		body.hurt()
		_update_health()


func _on_enemy_died() -> void:
	kills += 1
	_update_kills()
	# Credit fireball charge (player handles the "per 3 kills" gating)
	if is_instance_valid(player) and player.has_method("add_charge"):
		player.add_charge()
	_update_charge()


func _on_player_died() -> void:
	await get_tree().create_timer(1.2).timeout
	get_tree().reload_current_scene()


## Level-loading helper — swaps the LevelRoot child for a new level scene.
## Groundwork for multi-level flow. Currently unused (single level).
func load_level(level_path: String) -> void:
	if level_root:
		level_root.queue_free()
	var packed := load(level_path) as PackedScene
	if packed:
		var instance := packed.instantiate()
		instance.name = "LevelRoot"
		add_child(instance)
		move_child(instance, 0)  # place behind HUD and overlays
		level_root = instance
		player = level_root.get_node_or_null("Player")
		_total_collectables = 0
		_collected_count = 0
		_elapsed = 0.0
		_level_done = false
		if level_root and level_root.has_signal("beam_done") and not level_root.beam_done.is_connected(_on_beam_done):
			level_root.beam_done.connect(_on_beam_done)
		$HUD.show()
		_setup_level()
		_update_health()
		_update_score()
		_update_kills()
		_update_charge()


func _update_score() -> void:
	score_label.text = str(score)


func _update_kills() -> void:
	kills_label.text = str(kills)


func _update_charge() -> void:
	var c := 0
	var kills_toward := 0
	if is_instance_valid(player):
		c = player.fireball_charges
		kills_toward = player._kill_since_charge
	charge_label.text = str(c)
	if charge_enso:
		charge_enso.set_state(float(kills_toward) / float(player.KILLS_PER_CHARGE), c)


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
