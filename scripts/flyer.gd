extends "res://scripts/enemy_base.gd"

## Floating enemy ("the watcher"). Hovers in place, bobbing up and down while
## drifting left/right across a patrol band. It ignores terrain (it flies), so
## movement is driven directly rather than through gravity. Combat mirrors the
## snail: stomp it from above, slide-kill at speed, or hit it with a fireball;
## any other contact hurts the player.
##
## Shared contact/damage/death logic lives in EnemyBase.

const SPEED := 70.0            # horizontal drift speed while patrolling
const BOB_AMPLITUDE := 26.0    # vertical bob height
const BOB_SPEED := 2.2         # bob frequency
const CHASE_SPEED := 150.0     # pursuit speed (player runs faster, but flies straight)
const CHASE_RANGE := 540.0     # starts pursuing once the player is within this range

## Half-width of the horizontal patrol, measured from the spawn point.
@export var patrol_range := 220.0
## When true, the flyer pursues the player within CHASE_RANGE; otherwise it patrols.
@export var chases := true

var _home := Vector2.ZERO
var _phase := 0.0


func _enemy_ready() -> void:
	direction = 1.0
	_home = global_position


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_exclude_player_once()

	_phase += delta * BOB_SPEED

	# Chase the player when in range; otherwise patrol the home band.
	var chasing := false
	if chases and is_instance_valid(_player_ref):
		var to_player: Vector2 = _player_ref.global_position - global_position
		if to_player.length() < CHASE_RANGE:
			chasing = true
			global_position += to_player.normalized() * CHASE_SPEED * delta
			if absf(to_player.x) > 1.0:
				direction = signf(to_player.x)
			# Track the patrol anchor to wherever the chase ends, so resuming the
			# patrol doesn't snap back to the original spawn point.
			_home = global_position

	if not chasing:
		# Horizontal drift, reversing at the edges of the patrol band.
		var x := global_position.x + direction * SPEED * delta
		if x > _home.x + patrol_range:
			direction = -1.0
		elif x < _home.x - patrol_range:
			direction = 1.0
		# Vertical bob around the home height.
		global_position = Vector2(x, _home.y + sin(_phase) * BOB_AMPLITUDE)

	sprite.flip_h = direction < 0.0
