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

@onready var _bar_fill: ColorRect = $BossHUD/Center/Bar/Fill
@onready var _hud_root: CanvasLayer = $BossHUD
@onready var _name_label: Label = $BossHUD/Center/NameLabel

var _home := Vector2.ZERO
var _cast_timer := 0.0
var _casting := false
var _bar_full := 0.0


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

	var speed := CHASE_SPEED if chasing else SPEED
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
		if _cast_timer >= CAST_INTERVAL and not _casting:
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
	var proj := EnemyFireball.instantiate()
	get_parent().add_child(proj)
	proj.global_position = global_position
	if proj.has_method("launch"):
		proj.launch(_player_ref.global_position - global_position)
	await get_tree().create_timer(0.35).timeout
	_casting = false
	if not is_dead:
		sprite.play("idle")


# ----- Health bar + death HUD -----

func _on_damaged() -> void:
	_update_bar()


func _on_death() -> void:
	_hud_root.visible = false


func _update_bar() -> void:
	if _bar_fill and _bar_full > 0.0:
		_bar_fill.size.x = _bar_full * clampf(float(health) / float(max_health), 0.0, 1.0)
