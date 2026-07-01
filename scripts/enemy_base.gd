class_name EnemyBase
extends CharacterBody2D

## Shared base for Beam's enemies (snail, flyer, boss). Centralises the parts that
## were previously copy-pasted across all three: the contact → damage rules
## (stomp / slide-kill / hurt-player), the monochrome hit-flash, the shared
## enemy-death animation, and ground-edge probing. Subclasses implement movement
## in their own _physics_process and override _enemy_ready() for per-type setup.

signal player_hit
signal died(enemy)

const GRAVITY := 980.0

## Hit points. Exported so per-instance variants can be authored from the scene.
@export var max_health := 3

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var contact: Area2D = $ContactArea

var health := 0
var is_dead := false
var alive := true            # mirrors main.gd's hurt() checks
var direction := -1.0
var _excluded_player := false
var _player_ref: Node2D = null

## First enemy-death frame this enemy uses (boss starts at 1, others at 2).
var death_frame_start := 2
## When true, a slide one-shots this enemy; when false (e.g. the boss) a slide
## only chips one hit point, so tougher enemies aren't trivially slide-killed.
var slide_one_shot := true

## Ground-edge probe tuning (used by ground enemies via _should_turn()).
var probe_ahead := 26.0
var step_tolerance := 26.0
var probe_up := 30.0
var probe_down := 40.0
var _foot := 60.0            # local-space offset from origin to the capsule bottom

# Death frames are identical across enemy types, so load them once and share.
static var _death_textures: Array = []


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	contact.body_entered.connect(_on_contact)
	# _enemy_ready() first so subclasses can set death_frame_start / probe tuning
	# before the shared death animation is assembled from those values.
	_enemy_ready()
	_build_death_animation()


## Override for per-type setup (home position, floor angles, foot offset, HUD…).
func _enemy_ready() -> void:
	pass


## Terrain and the player share collision layer 1; exclude the player from this
## body's collisions so it isn't nudged (contact runs through ContactArea). Caches
## the player reference. Call once at the top of _physics_process.
func _exclude_player_once() -> void:
	if _excluded_player:
		return
	var p := get_tree().get_first_node_in_group("player")
	if p and p is PhysicsBody2D:
		add_collision_exception_with(p)
		_player_ref = p
	_excluded_player = true


# Look ahead along the surface: report a turn at the end of the line (no ground
# ahead) or at a sharp bend/wall (ground height changes more than the tolerance).
func _should_turn() -> bool:
	var space := get_world_2d().direct_space_state
	var foot_y := global_position.y + _foot
	var ahead_x := global_position.x + direction * probe_ahead
	var q := PhysicsRayQueryParameters2D.create(
		Vector2(ahead_x, foot_y - probe_up), Vector2(ahead_x, foot_y + probe_down))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	return absf(hit.position.y - foot_y) > step_tolerance


func _on_contact(body: Node2D) -> void:
	if is_dead or not body.is_in_group("player"):
		return
	if not (body.has_method("hurt") and body.alive):
		return
	# Slide-kill: sliding into an enemy hits it at any slide speed. Regular enemies
	# are one-shot; tougher ones (slide_one_shot = false) only take a single hit.
	if body.is_sliding:
		take_damage(max_health if slide_one_shot else 1, signf(body.velocity.x))
		return
	# Stomp: player above the enemy and moving downward.
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
	_on_damaged()
	if health <= 0:
		is_dead = true
		alive = false
		died.emit(self)
		contact.set_deferred("monitoring", false)
		body_shape.set_deferred("disabled", true)
		_on_death()
		_die()
	else:
		# Brief monochrome hit-flash.
		sprite.modulate = Color(2.2, 2.2, 2.2, 1.0)
		var t := create_tween()
		t.tween_property(sprite, "modulate", Color.WHITE, 0.15)


## Hook: extra per-hit behaviour (e.g. the boss health bar). Runs for every hit,
## lethal or not, after health is decremented.
func _on_damaged() -> void:
	pass


## Hook: runs once when the enemy's health reaches zero, before the death anim.
func _on_death() -> void:
	pass


static func _load_death_textures() -> Array:
	if _death_textures.is_empty():
		for i in range(1, 10):  # enemy-death1 .. enemy-death9
			var path := "res://assets/images/SPRITES/fx/enemy-death/enemy-death-sprites/enemy-death%d.png" % i
			var tex := load(path)
			if tex:
				_death_textures.append(tex)
	return _death_textures


func _build_death_animation() -> void:
	var sf := sprite.sprite_frames
	if sf.has_animation("death"):
		return
	sf.add_animation("death")
	sf.set_animation_loop("death", false)
	sf.set_animation_speed("death", 10.0)
	var texs := _load_death_textures()
	for i in range(death_frame_start - 1, texs.size()):  # frame death_frame_start .. 9
		sf.add_frame("death", texs[i])


func _die() -> void:
	if sprite.sprite_frames.has_animation("death"):
		sprite.play("death")
		await sprite.animation_finished
	queue_free()
