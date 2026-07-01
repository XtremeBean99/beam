extends "res://scripts/enemy_base.gd"

## Ground-patrolling enemy. Gravity pulls it onto the ink line below; it walks
## along the surface and turns around at the ends of the line or at sharp
## turns/bends (so it never walks off or past a corner). Landing on its head
## stomps it; touching it any other way hurts the player.
##
## Shared contact/damage/death logic lives in EnemyBase.

const SPEED := 55.0


func _enemy_ready() -> void:
	floor_max_angle = deg_to_rad(70)
	floor_snap_length = 14.0
	if body_shape and body_shape.shape is CapsuleShape2D:
		# Scale by the node's own scale so a scaled-up variant probes the ground
		# at its true foot height.
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
	velocity.x = direction * SPEED
	sprite.flip_h = direction > 0.0
	move_and_slide()
