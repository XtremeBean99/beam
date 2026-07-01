extends Node2D

@onready var level_root = $LevelRoot
@onready var player = $LevelRoot/Player
@onready var pause_overlay = $HUD/PauseOverlay
@onready var settings_menu = $HUD/SettingsMenu
@onready var transition = $Transition
@onready var level_complete = $OverlayLayer/LevelComplete
@onready var time_label = $HUD/StatsPanel/VBox/TimeRow/Value
@onready var score_label = $HUD/StatsPanel/VBox/ScoreRow/Value
@onready var kills_label = $HUD/StatsPanel/VBox/KillsRow/Value
@onready var charge_enso = $HUD/StatsPanel/VBox/ChargeRow/Enso
@onready var pips = [
	$HUD/StatsPanel/VBox/HealthRow/Pips/Pip1,
	$HUD/StatsPanel/VBox/HealthRow/Pips/Pip2,
	$HUD/StatsPanel/VBox/HealthRow/Pips/Pip3,
]

const PIP_FULL := Color(0.85, 0.92, 1.0, 1.0)
const PIP_EMPTY := Color(0.28, 0.32, 0.4, 0.5)

## Campaign order. Index 0 is the level baked into Main.tscn as LevelRoot; later
## indices are swapped in by load_level() when the player clears a level.
const LEVELS := [
	"res://scenes/levels/level1.tscn",
	"res://scenes/levels/level2.tscn",
	"res://scenes/levels/level3.tscn",
]

var score := 0
var kills := 0
var is_paused := false
var _total_collectables := 0
var _collected_count := 0
var _elapsed := 0.0
var _level_done := false
var _level_index := 0
# Score/kills as they were at the start of the current attempt (level spawn or
# last respawn); restored on death so a failed run doesn't keep its progress.
var _score_checkpoint := 0
var _kills_checkpoint := 0
var _reloading := false   # guards against overlapping level reloads
# Boss-room completion: the enemies whose spawn position falls inside the level's
# "Bossroom" panel. Clearing all of them (or all collectables) completes the level.
var _bossroom_rect := Rect2()
var _bossroom_enemies: Array = []
var _bossroom_dead := 0
# Whole-run totals for the speedrun timer + end screen (persist across levels; only
# reset when Main.tscn reloads for a fresh run).
var _run_time := 0.0
var _run_finished := false
var _run_tokens_collected := 0
var _run_tokens_total := 0


func _ready() -> void:
	_setup_level()
	_update_health()
	_update_score()
	_update_kills()
	_update_charge()
	pause_overlay.hide()
	settings_menu.hide()
	level_complete.hide()
	# NB: do not hide the Transition CanvasLayer here — it manages its own
	# ColorRect visibility, and hiding the layer stops its fade from rendering.

	settings_menu.closed.connect(_on_settings_closed)
	$HUD/PauseOverlay/Center/VBox/ResumeButton.pressed.connect(_on_resume_pressed)
	$HUD/PauseOverlay/Center/VBox/RestartButton.pressed.connect(_on_restart_pressed)
	$HUD/PauseOverlay/Center/VBox/SettingsButton.pressed.connect(_on_settings_pressed)
	$HUD/PauseOverlay/Center/VBox/QuitButton.pressed.connect(_on_quit_pressed)
	$HUD/EndLevelButton.pressed.connect(_trigger_level_complete)

	# Level-complete wiring
	level_complete.continue_pressed.connect(_on_level_continue)

	# Beam-done + fall-off signals from the level
	if level_root and level_root.has_signal("beam_done"):
		level_root.beam_done.connect(_on_beam_done)
	if level_root and level_root.has_signal("player_fell"):
		level_root.player_fell.connect(_on_player_fell)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pause") and not settings_menu.visible and not _level_done:
		_toggle_pause()

	if not _level_done and not is_paused:
		_elapsed += delta

	# The run timer counts continuously across levels (not per-level), stopping only
	# when the whole run is finished. Drives the live HUD clock + the end screen.
	if not _run_finished and not is_paused:
		_run_time += delta
	if is_instance_valid(time_label):
		time_label.text = _format_time(_run_time)


func _setup_level() -> void:
	# Count and wire collectables — only those belonging to the CURRENT level.
	# A just-replaced level is still queue_free()-ing this frame, so its leftover
	# collectables would otherwise inflate the total and the level could never
	# auto-complete (e.g. after a death/restart).
	_total_collectables = 0
	for collectable in get_tree().get_nodes_in_group("collectables"):
		if level_root and not level_root.is_ancestor_of(collectable):
			continue
		_total_collectables += 1
		if collectable.has_signal("collected") and not collectable.collected.is_connected(_on_collectable_collected):
			collectable.collected.connect(_on_collectable_collected)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if level_root and not level_root.is_ancestor_of(enemy):
			continue
		if enemy.has_signal("player_hit") and not enemy.player_hit.is_connected(_on_player_hit):
			enemy.player_hit.connect(_on_player_hit)
		if enemy.has_signal("died") and not enemy.died.is_connected(_on_enemy_died):
			enemy.died.connect(_on_enemy_died)

	if player and player.has_signal("death_finished") and not player.death_finished.is_connected(_on_player_died):
		player.death_finished.connect(_on_player_died)

	if player and player.has_signal("health_changed") and not player.health_changed.is_connected(_update_health):
		player.health_changed.connect(_update_health)

	_compute_bossroom()


## Classify the current level's enemies against its "Bossroom" panel (a Control
## placed directly under the level root). Membership is frozen at spawn so an enemy
## that later wanders out of the rect still counts toward clearing the room.
func _compute_bossroom() -> void:
	_bossroom_enemies.clear()
	_bossroom_dead = 0
	_bossroom_rect = Rect2()
	var panel: Node = level_root.find_child("Bossroom", true, false) if level_root else null
	if panel == null or not (panel is Control):
		return
	# Read the rect straight from the offsets (world coords, since the panel is a
	# direct child of the level root at the origin) to avoid Control-layout timing.
	_bossroom_rect = Rect2(
		Vector2(panel.offset_left, panel.offset_top),
		Vector2(panel.offset_right - panel.offset_left, panel.offset_bottom - panel.offset_top))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if level_root and not level_root.is_ancestor_of(enemy):
			continue
		if _bossroom_rect.has_point(enemy.global_position):
			_bossroom_enemies.append(enemy)


func _on_collectable_collected(source) -> void:
	if _level_done:
		return
	_collected_count += 1
	score += 1
	_update_score()

	if _total_collectables > 0 and _collected_count >= _total_collectables:
		var pos: Vector2 = source.global_position if is_instance_valid(source) else Vector2.INF
		_trigger_level_complete(pos)


## Begins the level-clear sequence: an exit door appears at `door_pos` (the last
## collectable/boss-room enemy), then the level-complete screen. Called when all
## collectables are gathered, all boss-room enemies are cleared, or by the
## "END LEVEL (TEST)" HUD button (which passes no position → falls back to player).
func _trigger_level_complete(door_pos: Vector2 = Vector2.INF) -> void:
	if _level_done:
		return
	_level_done = true
	# Bank this level's tokens toward the whole-run total (counted once, at clear).
	_run_tokens_collected += _collected_count
	_run_tokens_total += _total_collectables
	$HUD.hide()  # hide the HUD (incl. the test button) during the exit sequence
	if door_pos == Vector2.INF:
		door_pos = player.global_position if is_instance_valid(player) else Vector2.ZERO
	if level_root and level_root.has_method("show_exit_door"):
		level_root.show_exit_door(door_pos)
	else:
		_show_level_complete()


func _on_beam_done() -> void:
	# Beam transport finished — fade to black, reveal the level-complete screen,
	# then fade back in over it. Timer-driven (not the transition's signal) so the
	# sequence can never stall.
	transition.fade_to_black(0.6)
	await get_tree().create_timer(0.6).timeout
	_show_level_complete()
	transition.fade_from_black(0.5)


func _show_level_complete() -> void:
	# The final level ends the whole run: show the end screen (total time + tokens %)
	# instead of the per-level stats. Continue from either goes through _on_level_continue.
	if _level_index >= LEVELS.size() - 1:
		_run_finished = true   # freeze the speedrun clock
		var pct := 100
		if _run_tokens_total > 0:
			pct = int(round(100.0 * float(_run_tokens_collected) / float(_run_tokens_total)))
		level_complete.show_endgame(_run_time, pct)
	else:
		level_complete.show_stats(_elapsed, score, kills)


## Format seconds as M:SS.cc for the HUD clock and the end screen.
func _format_time(t: float) -> String:
	var m := int(t / 60.0)
	var s := int(fmod(t, 60.0))
	var cs := int(fmod(t, 1.0) * 100.0)
	return "%d:%02d.%02d" % [m, s, cs]


func _on_level_continue() -> void:
	# Advance to the next level in the campaign; loop back to the title once the
	# final level is cleared.
	transition.fade_to_black(0.4)
	await get_tree().create_timer(0.4).timeout
	get_tree().paused = false
	if _level_index + 1 < LEVELS.size():
		_level_index += 1
		load_level(LEVELS[_level_index])
		# New attempt baseline: carry the cumulative score/kills into the next level.
		_score_checkpoint = score
		_kills_checkpoint = kills
		transition.fade_from_black(0.5)
	else:
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")


func _on_player_hit(body) -> void:
	if body.has_method("hurt") and body.alive:
		body.hurt()
		_update_health()


func _on_enemy_died(enemy = null) -> void:
	kills += 1
	_update_kills()
	# Credit fireball charge (player handles the "per 3 kills" gating)
	if is_instance_valid(player) and player.has_method("add_charge"):
		player.add_charge()

	# Boss-room clear: once every enemy that spawned inside the Bossroom panel is
	# dead, the level completes with the door at this last enemy's death spot.
	if enemy != null and not _level_done and _bossroom_enemies.has(enemy):
		_bossroom_dead += 1
		if _bossroom_enemies.size() > 0 and _bossroom_dead >= _bossroom_enemies.size():
			_trigger_level_complete(enemy.global_position)
	_update_charge()


func _on_player_died() -> void:
	# Driven by the player's death_finished signal (fired when the death animation
	# completes), so the respawn is synced to the animation rather than a fixed delay.
	_restart_level(0.4, 0.5)


func _on_player_fell() -> void:
	# Falling off the level restarts it from the current attempt's checkpoint.
	_restart_level(0.4, 0.5)


## Reload the CURRENT level (not back at level 1), rolling score/kills back to their
## values at the start of this attempt. Guarded so overlapping triggers (death, a
## fall, the restart button) can't reload twice.
func _restart_level(fade_out: float = 0.4, fade_in: float = 0.5) -> void:
	if _reloading:
		return
	_reloading = true
	transition.fade_to_black(fade_out)
	await get_tree().create_timer(fade_out).timeout
	score = _score_checkpoint
	kills = _kills_checkpoint
	load_level(LEVELS[_level_index])
	transition.fade_from_black(fade_in)
	_reloading = false


## Level-loading helper — swaps the LevelRoot child for a new level scene.
## Drives campaign progression (clear/continue) and current-level respawn on death.
func load_level(level_path: String) -> void:
	level_complete.hide()
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
		if level_root and level_root.has_signal("player_fell") and not level_root.player_fell.is_connected(_on_player_fell):
			level_root.player_fell.connect(_on_player_fell)
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
	if not is_instance_valid(charge_enso):
		return
	var charges := 0
	var fill := 0.0
	if is_instance_valid(player):
		charges = player.fireball_charges
		if player.has_method("charge_progress"):
			fill = player.charge_progress()
	charge_enso.set_state(fill, charges)


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


func _on_restart_pressed() -> void:
	# Restart the current level from its checkpoint (same rollback as a death).
	is_paused = false
	pause_overlay.hide()
	get_tree().paused = false
	_restart_level(0.3, 0.4)


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
