extends "res://scripts/enemy_base.gd"

## Shielded enemy: carries a shield that blocks stomps and fireballs. Must be
## stunned with a slide first (which breaks the shield), then can be damaged
## normally. After a cooldown the shield regenerates.

const PATROL_SPEED := 40.0
const SHIELD_REGEN_TIME := 4.0

var _shield_up := true
var _shield_timer := 0.0


func _enemy_ready() -> void:
	slide_one_shot = false   # slide stuns instead of killing
	floor_max_angle = deg_to_rad(70)
	floor_snap_length = 14.0
	if body_shape and body_shape.shape is CapsuleShape2D:
		_foot = (body_shape.position.y + body_shape.shape.height * 0.5) * scale.y


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_exclude_player_once()

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0
		if _should_turn():
			direction *= -1.0
	velocity.x = direction * PATROL_SPEED
	sprite.flip_h = direction > 0.0

	# Shield regeneration timer.
	if not _shield_up:
		_shield_timer += delta
		if _shield_timer >= SHIELD_REGEN_TIME:
			_shield_up = true
			_shield_timer = 0.0
			# Visual: modulate to show shield is back.
			sprite.modulate = Color(0.5, 0.5, 1.0, 1.0)  # blue tint = shielded
			var t := create_tween()
			t.tween_property(sprite, "modulate", Color.WHITE, 0.15)

	move_and_slide()


## Override contact: slide stuns and removes shield; stomps/fireballs are
## blocked while the shield is up.
func _on_contact(body: Node2D) -> void:
	if is_dead or not body.is_in_group("player"):
		return
	if not (body.has_method("hurt") and body.alive):
		return

	# Slide: breaks the shield. If shield was already down, it kills.
	if body.is_sliding:
		if _shield_up:
			_shield_up = false
			_shield_timer = 0.0
			# Visual: flash red to show shield broken.
			sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
		else:
			take_damage(max_health, signf(body.velocity.x))
		return

	# Stomp or fireball: blocked by shield.
	if _shield_up:
		player_hit.emit(body)
		return

	# Shield is down — normal combat rules apply.
	if body.velocity.y > 0.0 and body.global_position.y < global_position.y:
		take_damage(1, 0.0)
		if body.has_method("stomp_bounce"):
			body.stomp_bounce()
	else:
		player_hit.emit(body)
