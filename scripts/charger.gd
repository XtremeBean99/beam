extends "res://scripts/enemy_base.gd"

## Charger: ground enemy that patrols slowly until the player enters detection
## range, then charges at high speed. The charge has a cooldown. Slide-kills and
## stomps work normally; fireballs one-shot it.

const PATROL_SPEED := 50.0
const CHARGE_SPEED := 400.0
const DETECT_RANGE := 350.0
const CHARGE_COOLDOWN := 2.5
const CHARGE_DURATION := 0.8

enum State { PATROL, CHARGING, COOLDOWN }

var _state := State.PATROL
var _charge_timer := 0.0
var _charge_dir := 0.0


func _enemy_ready() -> void:
	slide_one_shot = true
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

	match _state:
		State.PATROL:
			if _should_turn():
				direction *= -1.0
			velocity.x = direction * PATROL_SPEED
			# Detect player within range — enter charge.
			if is_instance_valid(_player_ref):
				var dist := _player_ref.global_position.distance_to(global_position)
				if dist < DETECT_RANGE:
					_state = State.CHARGING
					_charge_timer = 0.0
					_charge_dir = signf(_player_ref.global_position.x - global_position.x)
					if _charge_dir == 0:
						_charge_dir = direction

		State.CHARGING:
			velocity.x = _charge_dir * CHARGE_SPEED
			_charge_timer += delta
			if _charge_timer >= CHARGE_DURATION:
				_state = State.COOLDOWN
				_charge_timer = 0.0
				direction = _charge_dir

		State.COOLDOWN:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
			_charge_timer += delta
			if _charge_timer >= CHARGE_COOLDOWN:
				_state = State.PATROL

	sprite.flip_h = direction > 0.0
	move_and_slide()
