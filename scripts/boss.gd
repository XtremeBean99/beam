extends "res://scripts/enemy_base.gd"

## Grand Wizard boss — land-based enemy. Walks terrain, patrols, chases the
## player, and periodically casts fireballs. Defeated by stomps, slide-kills, or
## the player's own fireballs. Shows a centred health bar at the top of the screen.
##
## Shared contact/damage/death logic lives in EnemyBase.

const SPEED := 120.0            # patrol walk speed (faster than the snail's 55)
const CHASE_SPEED := 180.0      # pursuit speed
const CHASE_RANGE := 600.0      # starts chasing once player is within this range
const CAST_INTERVAL := 2.2
const WINDUP := 0.45            # fire-animation lead before the projectile launches

const EnemyFireball := preload("res://scenes/enemy_fireball.tscn")

## Patrol half-width from spawn point.
@export var patrol_range := 300.0
## Health thresholds for phase transitions (fraction of max_health, descending).
## E.g. [1.0, 0.5] = phase 1 at full HP, phase 2 at half HP.
@export var phase_thresholds: Array[float] = [1.0, 0.5]
## Chase speed multiplier per phase (index matches phase_thresholds).
@export var phase_speeds: Array[float] = [1.0, 1.4]
## Fireball cast interval per phase.
@export var phase_cast_intervals: Array[float] = [2.2, 1.2]
## Number of fireballs per cast per phase.
@export var phase_cast_count: Array[int] = [1, 2]

@onready var _bar_fill: ColorRect = $BossHUD/Center/Bar/Fill
@onready var _hud_root: CanvasLayer = $BossHUD
@onready var _name_label: Label = $BossHUD/Center/NameLabel

var _home := Vector2.ZERO
var _cast_timer := 0.0
var _casting := false
var _bar_full := 0.0
var _current_phase := 0
var _phase_health_trigger := 0.0


func _enemy_ready() -> void:
	death_frame_start = 1          # boss death includes the first enemy-death frame
	slide_one_shot = false         # slides only chip the boss; it must be worn down
	probe_ahead = 36.0
	step_tolerance = 28.0
	probe_up = 40.0
	probe_down = 50.0
	_home = global_position
	sprite.play("idle")
	floor_max_angle = deg_to_rad(70)
	floor_snap_length = 14.0
	if body_shape and body_shape.shape is CapsuleShape2D:
		_foot = (body_shape.position.y + body_shape.shape.height * 0.5) * scale.y
	_bar_full = _bar_fill.size.x
	_update_bar()
	if _name_label:
		_name_label.text = "Grand Wizard"
	# Phase tracking.
	_current_phase = 0
	_update_phase()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_exclude_player_once()

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	# ----- AI: chase or patrol -----
	var chasing := false
	if is_instance_valid(_player_ref):
		var to_player := _player_ref.global_position - global_position
		if to_player.length() < CHASE_RANGE:
			chasing = true
			direction = signf(to_player.x)

	var speed := CHASE_SPEED * _phase_speed() if chasing else SPEED
	if is_on_floor() and _should_turn():
		direction *= -1.0
	velocity.x = direction * speed

	# Patrol band — don't walk past the home band when not chasing.
	if not chasing:
		if global_position.x > _home.x + patrol_range:
			direction = -1.0
		elif global_position.x < _home.x - patrol_range:
			direction = 1.0

	sprite.flip_h = direction > 0.0

	# ----- Fireball casting -----
	if is_instance_valid(_player_ref):
		_cast_timer += delta
		var interval := _phase_cast_interval()
		if _cast_timer >= interval and not _casting:
			_cast()

	move_and_slide()


# ----- Fireball cast -----

func _cast() -> void:
	_cast_timer = 0.0
	_casting = true
	sprite.play("fire")
	await get_tree().create_timer(WINDUP).timeout
	if is_dead or not is_instance_valid(_player_ref):
		_casting = false
		if not is_dead:
			sprite.play("idle")
		return
	var count := _phase_cast_count()
	for i in range(count):
		var proj := EnemyFireball.instantiate()
		get_parent().add_child(proj)
		proj.global_position = global_position
		var target_dir := _player_ref.global_position - global_position
		# Spread multiple fireballs in a small fan.
		if count > 1:
			var spread := deg_to_rad(20.0 * (float(i) / float(count - 1) - 0.5))
			target_dir = target_dir.rotated(spread)
		if proj.has_method("launch"):
			proj.launch(target_dir)
	if count > 1:
		await get_tree().create_timer(0.15).timeout  # brief gap between volleys
	await get_tree().create_timer(0.35).timeout
	_casting = false
	if not is_dead:
		sprite.play("idle")


# ----- Phase system -----

func _update_phase() -> void:
	var hp_frac := float(health) / float(max_health)
	for i in range(phase_thresholds.size() - 1, -1, -1):
		if hp_frac <= phase_thresholds[i] and i > _current_phase:
			_current_phase = i
			# Enrage visual: red tint that fades.
			if sprite:
				sprite.modulate = Color(1.4, 0.6, 0.6, 1.0)
				var t := create_tween()
				t.tween_property(sprite, "modulate", Color.WHITE, 0.5)
			break


func _phase_speed() -> float:
	var idx := mini(_current_phase, phase_speeds.size() - 1)
	return phase_speeds[idx] if idx >= 0 else 1.0


func _phase_cast_interval() -> float:
	var idx := mini(_current_phase, phase_cast_intervals.size() - 1)
	return phase_cast_intervals[idx] if idx >= 0 else CAST_INTERVAL


func _phase_cast_count() -> int:
	var idx := mini(_current_phase, phase_cast_count.size() - 1)
	return phase_cast_count[idx] if idx >= 0 else 1


# ----- Health bar + death HUD -----

func _on_damaged() -> void:
	_update_bar()
	_update_phase()


func _on_death() -> void:
	_hud_root.visible = false


func _update_bar() -> void:
	if _bar_fill and _bar_full > 0.0:
		_bar_fill.size.x = _bar_full * clampf(float(health) / float(max_health), 0.0, 1.0)
