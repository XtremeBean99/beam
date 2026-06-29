extends CharacterBody2D

@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var jump_sound = $JumpSound

const SPEED = 300.0
const JUMP_VELOCITY = -700.0
const WALL_JUMP_HORIZONTAL = 400.0
const WALL_JUMP_VERTICAL = -550.0
const WALL_SLIDE_GRAVITY = 300.0
const GRAVITY = 980.0

const SLIDE_ACCEL = 850.0
const SLIDE_FRICTION = 0.98
const SLIDE_FLAT_FRICTION = 0.995
const SLIDE_MIN_SPEED = 30.0
const SLIDE_STOP_SPEED = 20.0

const HURT_ANIMS = ["hurt"]
const KNOCKBACK_FORCE = 400.0
const INVINCIBLE_MS = 1000.0
const MAX_WALL_JUMPS = 1

var alive = true
var health = 3
var invincible = false
var is_busy = false        # blocks movement input during the hurt animation
var is_sliding = false
var slide_dir = 1.0
var slide_timer = 0.0
var facing_right = true
var floor_angle = 0.0
var wall_jumps_used = 0
var air_time = 0.0

signal player_died


func _ready():
	add_to_group("player")
	var frames = animated_sprite_2d.sprite_frames
	for anim in HURT_ANIMS:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	floor_max_angle = deg_to_rad(60)
	floor_snap_length = 6.0


func _on_animation_finished():
	if animated_sprite_2d.animation in HURT_ANIMS:
		invincible = false
		is_busy = false


func hurt():
	if not alive or invincible:
		return
	health -= 1
	if health <= 0:
		alive = false
		is_busy = true
		player_died.emit()
		animated_sprite_2d.play("hurt")
		set_physics_process(false)
		await animated_sprite_2d.animation_finished
		queue_free()
	else:
		invincible = true
		is_busy = true
		animated_sprite_2d.play("hurt")
		await get_tree().create_timer(INVINCIBLE_MS / 1000.0).timeout
		invincible = false
		is_busy = false


func apply_knockback(from_direction):
	velocity.x = from_direction * KNOCKBACK_FORCE
	velocity.y = -200.0


func _physics_process(delta):
	if not alive:
		return

	if not is_on_floor():
		air_time += delta
	elif air_time >= 0.1:
		air_time = 0.0
		wall_jumps_used = 0
	elif air_time > 0:
		air_time = 0.0

	if not is_finite(velocity.x):
		velocity.x = 0.0
	if not is_finite(velocity.y):
		velocity.y = 0.0

	var direction = Input.get_axis("left", "right")
	var crouching = Input.is_action_pressed("crouch") and is_on_floor()

	# Gravity / wall slide
	if not is_on_floor():
		if is_on_wall() and velocity.y > 0:
			var wall_normal = get_wall_normal()
			var pushing = direction != 0 and sign(direction) == -sign(wall_normal.x)
			if pushing:
				velocity.y += (WALL_SLIDE_GRAVITY / GRAVITY) * delta
			else:
				velocity.y += GRAVITY * delta
		else:
			velocity.y += GRAVITY * delta

	# Wall jump
	if Input.is_action_just_pressed("jump") and is_on_wall() and not is_on_floor() and not is_busy and wall_jumps_used < MAX_WALL_JUMPS:
		wall_jumps_used += 1
		var wall_normal = get_wall_normal()
		velocity.x = wall_normal.x * WALL_JUMP_HORIZONTAL
		velocity.y = WALL_JUMP_VERTICAL
		jump_sound.play()

	# Ground jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_busy:
		velocity.y = JUMP_VELOCITY
		jump_sound.play()

	# Start slide
	if Input.is_action_just_pressed("crouch") and is_on_floor() and not is_busy and not is_sliding and abs(velocity.x) >= SLIDE_MIN_SPEED:
		is_sliding = true
		slide_dir = sign(velocity.x)
		slide_timer = 0.0

	if is_sliding:
		if Input.is_action_just_pressed("jump"):
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
			velocity.y = JUMP_VELOCITY
			jump_sound.play()
		elif not is_on_floor() or not Input.is_action_pressed("crouch"):
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
		elif direction == 0:
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
			velocity.x = 0
		else:
			slide_timer += delta
			slide_dir = sign(direction)
			var normal = get_floor_normal()
			var slope = abs(normal.x)
			var surface_right = Vector2(-normal.y, normal.x)
			floor_angle = surface_right.angle()
			var current_speed = velocity.x * surface_right.x + velocity.y * surface_right.y
			if slope > 0.01:
				current_speed += SLIDE_ACCEL * slope * delta * slide_dir
				current_speed *= SLIDE_FRICTION
			else:
				current_speed *= SLIDE_FLAT_FRICTION
			if abs(current_speed) < SLIDE_STOP_SPEED:
				current_speed = SLIDE_STOP_SPEED * slide_dir
			velocity = surface_right * current_speed

	# Horizontal movement (when not sliding)
	if not is_sliding:
		if crouching or is_busy:
			velocity.x = move_toward(velocity.x, 0, SPEED)
		elif direction:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)

	# Animation
	if not is_busy:
		if not is_on_floor():
			if is_on_wall() and velocity.y > 0:
				animated_sprite_2d.play("fall")
			elif velocity.y < 0:
				animated_sprite_2d.play("jump")
			else:
				animated_sprite_2d.play("fall")
		elif is_sliding:
			animated_sprite_2d.play("crouch")
		elif crouching:
			animated_sprite_2d.play("crouch")
		elif abs(velocity.x) > 1:
			animated_sprite_2d.play("walk")
		else:
			animated_sprite_2d.play("idle")

	move_and_slide()

	if not is_sliding and floor_angle != 0:
		floor_angle = 0.0
	animated_sprite_2d.rotation = floor_angle

	if direction == 1.0:
		animated_sprite_2d.flip_h = false
		facing_right = true
	elif direction == -1.0:
		animated_sprite_2d.flip_h = true
		facing_right = false
	if is_sliding:
		animated_sprite_2d.flip_h = (slide_dir < 0)
