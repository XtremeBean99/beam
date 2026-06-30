extends CharacterBody2D

@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var jump_sound = $JumpSound

const SPEED = 300.0
const JUMP_VELOCITY = -700.0
const WALL_JUMP_HORIZONTAL = 400.0
const WALL_JUMP_VERTICAL = -550.0
const WALL_SLIDE_GRAVITY = 300.0
const GRAVITY = 980.0

const RUN_ACCEL = 2200.0
const RUN_FRICTION = 2600.0
const AIR_ACCEL = 1600.0
const AIR_FRICTION = 800.0
const FALL_GRAVITY_MULT = 1.25
const JUMP_CUT_MULT = 0.45
const COYOTE_TIME = 0.1
const JUMP_BUFFER_TIME = 0.1
const MAX_AIR_JUMPS = 1
const STOMP_BOUNCE = -560.0       # upward pop when bouncing off a stomped enemy

const SLIDE_ACCEL = 3500.0       # reach target quickly so even short lines get up to speed
const SLIDE_DRAG = 300.0         # settle toward target when over it
const SLIDE_BASE = 1.0           # flat slide == walking speed; any incline is faster
const SLIDE_GAIN = 2.0           # extra slide speed per unit slope (steeper = faster)
const SLIDE_MAX_SPEED = 800.0    # cap on slide speed
const SLIDE_MIN_SPEED = 30.0     # low bar to START a slide (> END for hysteresis)
const SLIDE_END_SPEED = 15.0     # slide ends gracefully once it slows below this
const SLIDE_KICK_DELAY = 1.0     # hold plain crouch for the first second of a slide
const SLIDE_ANIM_MIN = 400.0   # below this, hold the crouched first frame
const SLIDE_ANIM_MAX = 950.0   # at/above this, fully-extended kick frame
const SLIDE_ANIM = "crouch-kick"

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
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var air_jumps_left = MAX_AIR_JUMPS

signal player_died


func _ready():
	add_to_group("player")
	var frames = animated_sprite_2d.sprite_frames
	for anim in HURT_ANIMS:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	floor_max_angle = deg_to_rad(72)
	floor_snap_length = 40.0


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


# Called by an enemy when the player lands on its head: bounce up and refund the
# mid-air jump so stomps can be chained.
func stomp_bounce():
	velocity.y = STOMP_BOUNCE
	air_jumps_left = MAX_AIR_JUMPS


# Map a slide speed to a frame index of the crouch-kick animation.
# Slow slide → frame 0 (crouched); fast slide → last frame (extended kick).
func slide_frame(speed: float, frame_count: int) -> int:
	if frame_count <= 1:
		return 0
	var t = clampf((absf(speed) - SLIDE_ANIM_MIN) / (SLIDE_ANIM_MAX - SLIDE_ANIM_MIN), 0.0, 1.0)
	return int(round(t * (frame_count - 1)))


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
				velocity.y += GRAVITY * (FALL_GRAVITY_MULT if velocity.y > 0 else 1.0) * delta
		else:
			velocity.y += GRAVITY * (FALL_GRAVITY_MULT if velocity.y > 0 else 1.0) * delta

	# Coyote + jump buffer timers
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		air_jumps_left = MAX_AIR_JUMPS
	else:
		coyote_timer = max(0.0, coyote_timer - delta)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		jump_buffer_timer = max(0.0, jump_buffer_timer - delta)

	# Touching a wall (airborne) refreshes the air jump → fluid wall chains
	if is_on_wall() and not is_on_floor():
		air_jumps_left = MAX_AIR_JUMPS

	# Wall jump
	if Input.is_action_just_pressed("jump") and is_on_wall() and not is_on_floor() and not is_busy and wall_jumps_used < MAX_WALL_JUMPS:
		wall_jumps_used += 1
		var wall_normal = get_wall_normal()
		velocity.x = wall_normal.x * WALL_JUMP_HORIZONTAL
		velocity.y = WALL_JUMP_VERTICAL
		air_jumps_left = MAX_AIR_JUMPS
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		jump_sound.play()

	# Ground jump (coyote + buffered) and variable height
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and not is_sliding and not is_busy:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		jump_sound.play()
	elif jump_buffer_timer > 0.0 and not is_on_floor() and not is_on_wall() and air_jumps_left > 0 and not is_busy:
		# Double jump — used when no coyote/ground jump is available
		velocity.y = JUMP_VELOCITY
		air_jumps_left -= 1
		jump_buffer_timer = 0.0
		jump_sound.play()

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT_MULT

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
			jump_buffer_timer = 0.0
			coyote_timer = 0.0
			jump_sound.play()
		elif not is_on_floor() or not Input.is_action_pressed("crouch"):
			# Left the ground or released crouch — end slide, keep momentum.
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
		else:
			slide_timer += delta
			# Steer if a direction is held; otherwise keep gliding on momentum
			# (releasing left/right no longer kills the slide).
			if direction != 0:
				slide_dir = sign(direction)
			var normal = get_floor_normal()
			var slope = absf(normal.x)                        # sin(slope angle)
			# Right-pointing unit vector along the surface; its angle is the small
			# slope tilt (+/-theta), so the sprite never flips upside-down.
			var surface_right = Vector2(-normal.y, normal.x)
			floor_angle = surface_right.angle()
			var current_speed = velocity.dot(surface_right)   # signed: + = along +x
			# Speed is driven by slope STEEPNESS and is always a boost over walking,
			# regardless of travel direction — so steep lines are fast either way and
			# no slide gets misclassified as a slow "uphill".
			var target = minf(SPEED * (SLIDE_BASE + slope * SLIDE_GAIN), SLIDE_MAX_SPEED) * slide_dir
			var rate = SLIDE_ACCEL if absf(current_speed) < absf(target) else SLIDE_DRAG
			current_speed = move_toward(current_speed, target, rate * delta)
			# End once the slide has genuinely slowed to a crawl.
			if absf(current_speed) < SLIDE_END_SPEED:
				is_sliding = false
				slide_timer = 0.0
				floor_angle = 0.0
			else:
				velocity = surface_right * current_speed

	# Horizontal movement (when not sliding) — accel/friction for momentum
	if not is_sliding:
		var accel = RUN_ACCEL if is_on_floor() else AIR_ACCEL
		var friction = RUN_FRICTION if is_on_floor() else AIR_FRICTION
		if (crouching or is_busy) or direction == 0:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		else:
			velocity.x = move_toward(velocity.x, direction * SPEED, accel * delta)

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
			var frames = animated_sprite_2d.sprite_frames
			if slide_timer < SLIDE_KICK_DELAY or not frames.has_animation(SLIDE_ANIM):
				# First second of a slide: hold the plain crouch pose.
				animated_sprite_2d.play("crouch")
			else:
				# After the delay: scrub crouch-kick frames by speed
				# (only advances toward the full kick at higher speeds).
				animated_sprite_2d.animation = SLIDE_ANIM
				animated_sprite_2d.pause()
				var fc = frames.get_frame_count(SLIDE_ANIM)
				animated_sprite_2d.frame = slide_frame(velocity.length(), fc)
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
