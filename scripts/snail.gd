extends CharacterBody2D

## Ground-patrolling enemy. Gravity pulls it onto the ink line below; it walks
## along the surface and turns around at the ends of the line or at sharp
## turns/bends (so it never walks off or past a corner). Landing on its head
## stomps it; touching it any other way hurts the player.

signal player_hit
signal died

const SPEED := 55.0
const GRAVITY := 980.0
const MAX_HEALTH := 3
const SLIDE_KILL_SPEED := 400.0  # min slide speed to kill on contact
const PROBE_AHEAD := 26.0     # how far ahead to look for ground (world units)
const STEP_TOLERANCE := 26.0  # ground-height change ahead that counts as a turn/edge

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var contact: Area2D = $ContactArea

var direction := -1.0
var health := MAX_HEALTH
var is_dead := false
var alive := true            # kept for compatibility with main.gd's hurt() checks
var _foot := 60.0            # local-space offset from origin to the capsule bottom
var _excluded_player := false


func _ready() -> void:
	add_to_group("enemies")
	floor_max_angle = deg_to_rad(70)
	floor_snap_length = 14.0
	contact.body_entered.connect(_on_contact)
	if body_shape and body_shape.shape is CapsuleShape2D:
		_foot = body_shape.position.y + body_shape.shape.height * 0.5


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	# Terrain and the player share collision layer 1; exclude the player from this
	# body's collisions so the snail isn't nudged by it (contact runs via ContactArea).
	if not _excluded_player:
		var p := get_tree().get_first_node_in_group("player")
		if p and p is PhysicsBody2D:
			add_collision_exception_with(p)
		_excluded_player = true
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0
		if _should_turn():
			direction *= -1.0
	velocity.x = direction * SPEED
	sprite.flip_h = direction > 0.0
	move_and_slide()


# Look ahead along the surface: turn at the end of the line (no ground ahead) or
# at a sharp turn/bend/wall (ground height changes more than the tolerance).
func _should_turn() -> bool:
	var space := get_world_2d().direct_space_state
	var foot_y := global_position.y + _foot
	var ahead_x := global_position.x + direction * PROBE_AHEAD
	var q := PhysicsRayQueryParameters2D.create(
		Vector2(ahead_x, foot_y - 30.0), Vector2(ahead_x, foot_y + 40.0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	return absf(hit.position.y - foot_y) > STEP_TOLERANCE


func _on_contact(body: Node2D) -> void:
	if is_dead or not body.is_in_group("player"):
		return
	if not (body.has_method("hurt") and body.alive):
		return
	# Slide-kill: fast slide into the enemy from the side kills it.
	# Uses velocity.length() so slope-decomposed speed on inclines counts correctly.
	if body.is_sliding and body.velocity.length() >= SLIDE_KILL_SPEED:
		take_damage(1, sign(body.velocity.x))
		return
	# Stomp: player is above the snail and moving downward.
	if body.velocity.y > 0.0 and body.global_position.y < global_position.y:
		take_damage(1, 0.0)
		if body.has_method("stomp_bounce"):
			body.stomp_bounce()
	else:
		player_hit.emit(body)


func take_damage(amount: int, _knockback_dir: float) -> void:
	if is_dead:
		return
	health -= amount
	if health <= 0:
		is_dead = true
		alive = false
		died.emit()
		contact.set_deferred("monitoring", false)
		body_shape.set_deferred("disabled", true)
		var t := create_tween()
		t.tween_property(sprite, "modulate:a", 0.0, 0.25)
		t.tween_callback(queue_free)
	else:
		# Brief monochrome hit-flash.
		sprite.modulate = Color(2.2, 2.2, 2.2, 1.0)
		var t := create_tween()
		t.tween_property(sprite, "modulate", Color.WHITE, 0.15)
