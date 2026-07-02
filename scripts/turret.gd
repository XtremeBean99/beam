extends "res://scripts/enemy_base.gd"

## Stationary turret enemy: sits on terrain and fires projectiles at the player
## at regular intervals. Cannot be stomped (spike-top), but slides and fireballs
## destroy it. Uses the shared enemy_fireball projectile.

const FIRE_INTERVAL := 2.0
const WINDUP := 0.4
const RANGE := 700.0

const EnemyFireball := preload("res://scenes/enemy_fireball.tscn")

var _fire_timer := 0.0


func _enemy_ready() -> void:
	slide_one_shot = true
	floor_max_angle = deg_to_rad(70)
	floor_snap_length = 14.0


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_exclude_player_once()

	# Gravity — turret sits on terrain.
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	# Face the player.
	if is_instance_valid(_player_ref):
		direction = signf(_player_ref.global_position.x - global_position.x)
		if direction == 0:
			direction = -1.0
		sprite.flip_h = direction > 0.0

	# Fire at the player when in range.
	_fire_timer += delta
	if _fire_timer >= FIRE_INTERVAL and is_instance_valid(_player_ref):
		var dist := _player_ref.global_position.distance_to(global_position)
		if dist < RANGE:
			_fire_timer = 0.0
			_fire()

	move_and_slide()


## Override: turrets cannot be stomped (they have spikes on top). The base
## _on_contact checks velocity.y > 0 && player above; we pre-empt that by
## handling contact ourselves. Actually, the base class handles stomp vs hurt
## correctly — we just make stomps hurt the player instead.
func _on_contact(body: Node2D) -> void:
	if is_dead or not body.is_in_group("player"):
		return
	if not (body.has_method("hurt") and body.alive):
		return
	# Slide-kill always works.
	if body.is_sliding:
		take_damage(max_health, signf(body.velocity.x))
		return
	# Stomping a turret hurts the player (spike top).
	if body.velocity.y > 0.0 and body.global_position.y < global_position.y:
		player_hit.emit(body)
	else:
		player_hit.emit(body)


func _fire() -> void:
	if is_dead:
		return
	sprite.play("fire") if sprite.sprite_frames.has_animation("fire") else null
	await get_tree().create_timer(WINDUP).timeout
	if is_dead or not is_instance_valid(_player_ref):
		return
	var proj := EnemyFireball.instantiate()
	get_parent().add_child(proj)
	proj.global_position = global_position
	if proj.has_method("launch"):
		proj.launch(_player_ref.global_position - global_position)
