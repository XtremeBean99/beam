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

const SLIDE_ACCEL = 6400.0       # snappier ramp so slides reach speed fast
const SLIDE_DRAG = 280.0         # settle toward target when over it
const SLIDE_BASE = 2.6           # flat slide is much faster than walking
const SLIDE_GAIN = 4.5           # extra slide speed per unit slope (steeper = faster)
const SLIDE_MAX_SPEED = 1800.0   # high cap so slides can really build up
const SLIDE_MIN_SPEED = 24.0     # low bar to START a slide (> END for hysteresis)
const SLIDE_END_SPEED = 12.0     # slide ends gracefully once it slows below this
const SLIDE_KICK_DELAY = 1.0     # hold plain crouch for the first second of a slide
const SLIDE_ANIM_MIN = 400.0   # below this, hold the crouched first frame
const SLIDE_ANIM_MAX = 950.0   # at/above this, fully-extended kick frame
const SLIDE_ANIM = "crouch-kick"
const SLIDE_LAUNCH_FRICTION = 160.0   # gentle deceleration when sliding off edges
const SLIDE_AIR_ANIM_FRAMES = 6       # sustained airborne frames before the flying-kick anim (debounce)
const SLIDE_MAX_UP_SPEED = 220.0      # cap on upward slide velocity so curves/crests don't launch the player

const HURT_ANIMS = ["hurt"]
const KNOCKBACK_FORCE = 400.0
const INVINCIBLE_MS = 1000.0
const MAX_WALL_JUMPS = 1
const MAX_FIREBALL_CHARGES := 3
const KILLS_PER_CHARGE := 3
const FIREBALL_GROUND_ONLY := false  # fireball usable in the air (opened up from spec A2)

var alive: bool = true
var health: int = 3
var invincible: bool = false
var is_busy: bool = false        # blocks movement input during the hurt animation
var input_locked: bool = false   # set by level scripts to freeze the player (beam transport, etc.)
var fireball_charges := 0
var _kill_since_charge := 0
var is_sliding: bool = false
var slide_dir: float = 1.0
var slide_timer: float = 0.0
var facing_right: bool = true
var floor_angle: float = 0.0
var _prev_floor_normal := Vector2.UP
var _slide_off_floor_frames := 0  # debounced airborne counter for slide animation
var _slide_anim_fast := false     # latched crouch(false)/kick(true) state, speed-hysteresis
var wall_jumps_used: int = 0
var air_time: float = 0.0
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var air_jumps_left: int = MAX_AIR_JUMPS
var _was_touching_wall := false   # rising-edge detection for the air-jump refill

signal player_died
signal death_finished   # emitted after the death animation completes (drives respawn)
signal health_changed


func _ready():
	add_to_group("player")
	var frames = animated_sprite_2d.sprite_frames
	for anim in HURT_ANIMS:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)
	# Punch must be non-looping so the fireball coroutine can await its finish.
	if frames.has_animation("punch"):
		frames.set_animation_loop("punch", false)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	floor_max_angle = deg_to_rad(72)
	floor_snap_length = 40.0


func _on_animation_finished():
	# The stun (hurt) animation only releases movement control; the invincibility
	# window is owned by the INVINCIBLE_MS timer in hurt() so i-frames outlast the
	# short animation and the player can move while still briefly invulnerable.
	if animated_sprite_2d.animation in HURT_ANIMS:
		is_busy = false


func hurt():
	if not alive or invincible:
		return
	health -= 1
	health_changed.emit()
	_hit_feedback()
	if health <= 0:
		die()
	else:
		invincible = true
		is_busy = true
		animated_sprite_2d.play("hurt")
		await get_tree().create_timer(INVINCIBLE_MS / 1000.0).timeout
		invincible = false
		animated_sprite_2d.modulate = Color.WHITE


## Kill the player outright, regardless of remaining health. Used both by lethal
## damage (via hurt) and by falling off the map. Plays the death animation, then
## emits death_finished so main.gd can restart the level.
func die():
	if not alive:
		return
	alive = false
	health = 0
	health_changed.emit()
	is_busy = true
	invincible = true   # ignore further hits during the death animation
	player_died.emit()
	animated_sprite_2d.play("hurt")
	set_physics_process(false)
	await animated_sprite_2d.animation_finished
	# Respawn/cleanup is owned by main.gd (it reloads the level, which frees
	# this node) — do not self-free here, to avoid a double-free race.
	death_finished.emit()


func apply_knockback(from_direction):
	velocity.x = from_direction * KNOCKBACK_FORCE
	velocity.y = -200.0


# Brief white flash, camera shake, and a hit sound when the player is damaged.
func _hit_feedback() -> void:
	animated_sprite_2d.modulate = Color(2.5, 2.5, 2.5, 1.0)
	var t := create_tween()
	t.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.22)
	_shake_camera(7.0, 0.28)
	if has_node("PistolSound"):
		$PistolSound.play()


func _shake_camera(strength: float, dur: float) -> void:
	var cam := get_node_or_null("Camera2D")
	if cam == null:
		return
	var st := create_tween()
	var steps := 5
	var slice := dur / float(steps + 1)
	for i in range(steps):
		var amt := strength * (1.0 - float(i) / float(steps))
		st.tween_property(cam, "offset", Vector2(randf_range(-amt, amt), randf_range(-amt, amt)), slice)
	st.tween_property(cam, "offset", Vector2.ZERO, slice)


# Called by an enemy when the player lands on its head: bounce up and refund the
# mid-air jump so stomps can be chained.
func stomp_bounce():
	velocity.y = STOMP_BOUNCE
	air_jumps_left = MAX_AIR_JUMPS
	if has_node("KickSound"):
		$KickSound.play()


func _physics_process(delta):
	if not alive or input_locked:
		return

	var just_landed := false
	if not is_on_floor():
		air_time += delta
	else:
		if air_time >= 0.1:
			wall_jumps_used = 0
		just_landed = air_time > 0.0
		air_time = 0.0

	if not is_finite(velocity.x):
		velocity.x = 0.0
	if not is_finite(velocity.y):
		velocity.y = 0.0

	var direction = Input.get_axis("left", "right")
	var crouching = Input.is_action_pressed("crouch") and is_on_floor()

	# Landing into a held crouch carries the jump's momentum straight into a slide.
	if just_landed and Input.is_action_pressed("crouch") and not is_sliding and not is_busy and velocity.length() >= SLIDE_MIN_SPEED:
		is_sliding = true
		slide_dir = signf(velocity.x) if absf(velocity.x) > 1.0 else signf(velocity.y)
		if slide_dir == 0.0:
			slide_dir = 1.0 if facing_right else -1.0  # never start a directionless slide
		slide_timer = 0.0
		floor_max_angle = PI
		_prev_floor_normal = get_floor_normal()
		_slide_off_floor_frames = 0
		_slide_anim_fast = false

	# Fireball shoot — spends a charge, ground-only by default.
	if Input.is_action_just_pressed("shoot") and fireball_charges > 0 and not is_busy and not is_sliding:
		if not FIREBALL_GROUND_ONLY or is_on_floor():
			_shoot_fireball()

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

	# Touching a wall (airborne) refreshes the air jump, but only on the rising
	# edge of contact. Refilling every frame let a player double-jump in place
	# against a single wall forever; requiring a fresh touch keeps wall chains
	# fluid without the infinite-climb exploit.
	var touching_wall := is_on_wall() and not is_on_floor()
	if touching_wall and not _was_touching_wall:
		air_jumps_left = MAX_AIR_JUMPS
	_was_touching_wall = touching_wall

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
	elif jump_buffer_timer > 0.0 and not is_on_floor() and not is_on_wall() and air_jumps_left > 0 and not is_busy and not is_sliding:
		# Double jump — used when no coyote/ground jump is available. Slides are
		# excluded here so the slide block below owns the airborne slide double-jump
		# (which cancels the kick instead of launching upward).
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
		floor_max_angle = PI
		_prev_floor_normal = get_floor_normal()
		_slide_off_floor_frames = 0
		_slide_anim_fast = false

	if is_sliding:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			# Jump from ground slide — stay in slide state through the air.
			velocity.y = JUMP_VELOCITY
			jump_buffer_timer = 0.0
			coyote_timer = 0.0
			jump_sound.play()
			floor_angle = 0.0
			_slide_off_floor_frames = SLIDE_AIR_ANIM_FRAMES + 2
		elif Input.is_action_just_pressed("jump") and not is_on_floor() and air_jumps_left > 0 and not is_busy:
			# Double-jump during an airborne slide CANCELS the flying kick: kill all
			# momentum and drop straight down instead of launching upward.
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
			floor_max_angle = deg_to_rad(72)
			_slide_off_floor_frames = 0
			_slide_anim_fast = false
			velocity = Vector2.ZERO
			air_jumps_left -= 1
			jump_buffer_timer = 0.0
		elif not is_on_floor():
			# Airborne slide — carry momentum with gentle drag.
			# Slide state persists until landing (allows airborne slide-kills).
			floor_angle = 0.0
			slide_timer += delta
			if direction != 0:
				slide_dir = sign(direction)
			velocity.x = move_toward(velocity.x, 0.0, SLIDE_LAUNCH_FRICTION * delta)
			# End slide only when speed drops to a crawl in air.
			if absf(velocity.x) < SLIDE_END_SPEED:
				is_sliding = false
				slide_timer = 0.0
				floor_max_angle = deg_to_rad(72)
			_slide_off_floor_frames = min(_slide_off_floor_frames + 1, SLIDE_AIR_ANIM_FRAMES * 2)
		elif not Input.is_action_pressed("crouch"):
			# Released crouch on ground — end slide.
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
			floor_max_angle = deg_to_rad(72)
		else:
			# Normal ground slide — slope-based acceleration.
			_slide_off_floor_frames = 0
			slide_timer += delta
			if direction != 0:
				slide_dir = sign(direction)
			var normal = get_floor_normal()
			var surface_right = Vector2(-normal.y, normal.x)
			# Clamp sprite rotation so it never flips sideways on steep walls.
			floor_angle = clampf(surface_right.angle(), deg_to_rad(-50), deg_to_rad(50))

			# Signed speed along the surface. surface_right.x > 0 on any real floor, so
			# this basis stays stable across faceted/curved terrain — no sign flips of
			# the kind that used to snag the slide to a stop mid-curve.
			var current_speed = velocity.dot(surface_right)

			# Gravity along the slope carries momentum THROUGH curves: descents speed up,
			# ascents bleed off. This replaces the old per-facet slope boost + curve
			# magnetism, which stalled and stuck the player on curved terrain.
			current_speed += GRAVITY * surface_right.y * delta

			# Keep a lively cruising speed in the slide direction so flat and curved
			# stretches never decay to a halt and strand the player; gravity stacks on
			# top for descents (and the cap keeps it sane).
			var cruise := SPEED * SLIDE_BASE * slide_dir
			if absf(current_speed) < SPEED * SLIDE_BASE or signf(current_speed) != slide_dir:
				current_speed = move_toward(current_speed, cruise, SLIDE_ACCEL * delta)
			current_speed = clampf(current_speed, -SLIDE_MAX_SPEED, SLIDE_MAX_SPEED)

			velocity = surface_right * current_speed
			# Never let the slide fling the player upward off a curve/crest.
			if velocity.y < -SLIDE_MAX_UP_SPEED:
				velocity.y = -SLIDE_MAX_UP_SPEED

			if absf(current_speed) < SLIDE_END_SPEED:
				is_sliding = false
				slide_timer = 0.0
				floor_angle = 0.0
				floor_max_angle = deg_to_rad(72)

	# Horizontal movement (when not sliding) — accel/friction for momentum
	if not is_sliding:
		var accel = RUN_ACCEL if is_on_floor() else AIR_ACCEL
		var friction = RUN_FRICTION if is_on_floor() else AIR_FRICTION
		if (crouching or is_busy) or direction == 0:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		else:
			velocity.x = move_toward(velocity.x, direction * SPEED, accel * delta)

	# Animation — slide takes priority so uneven ground doesn't flicker fall frames.
	if not is_busy:
		if is_sliding:
			if _slide_off_floor_frames >= SLIDE_AIR_ANIM_FRAMES:
				# Sustained airborne slide → flying-kick air attack. Debounced so the
				# brief is_on_floor() blips on faceted terrain don't flicker into it.
				animated_sprite_2d.play("flying-kick")
			else:
				# Grounded slide: crouch (slow) vs kick (fast) chosen by speed with a
				# wide hysteresis band (SLIDE_ANIM_MIN..MAX) so speeds hovering near
				# the boundary latch instead of flickering between the two frames.
				var slide_speed := velocity.length()
				if slide_speed >= SLIDE_ANIM_MAX:
					_slide_anim_fast = true
				elif slide_speed <= SLIDE_ANIM_MIN:
					_slide_anim_fast = false
				var slide_anim := SLIDE_ANIM if _slide_anim_fast else "crouch"
				if animated_sprite_2d.animation != slide_anim:
					animated_sprite_2d.animation = slide_anim
				animated_sprite_2d.pause()
				animated_sprite_2d.frame = 1
		elif not is_on_floor():
			if is_on_wall() and velocity.y > 0:
				animated_sprite_2d.play("fall")
			elif velocity.y < 0:
				animated_sprite_2d.play("jump")
			else:
				animated_sprite_2d.play("fall")
		elif crouching:
			animated_sprite_2d.play("crouch")
		elif abs(velocity.x) > 1:
			animated_sprite_2d.play("walk")
		else:
			animated_sprite_2d.play("idle")

	# Invincibility blink — after the initial hit flash (which owns the sprite while
	# is_busy), flicker the sprite so the vulnerability window is readable.
	if invincible and not is_busy:
		var blink_on := int(Time.get_ticks_msec() / 90.0) % 2 == 0
		animated_sprite_2d.modulate.a = 0.35 if blink_on else 1.0

	move_and_slide()

	# Jam guard: a slide that's blocked (real movement ≈ 0 despite a live slide) ends,
	# so the player can't get stuck grinding into a wall in slide state. is_on_wall()
	# is unreliable here because floor_max_angle = PI while sliding treats walls as floor.
	if is_sliding and slide_timer > 0.08 and get_real_velocity().length() < SLIDE_END_SPEED:
		is_sliding = false
		slide_timer = 0.0
		floor_max_angle = deg_to_rad(72)

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


## Called by main.gd when kills reach the threshold.
func add_charge() -> void:
	# At the cap, don't bank progress toward another charge (kills past the cap
	# were previously hoarded, letting a spent charge refill instantly).
	if fireball_charges >= MAX_FIREBALL_CHARGES:
		_kill_since_charge = 0
		return
	_kill_since_charge += 1
	if _kill_since_charge >= KILLS_PER_CHARGE:
		fireball_charges += 1
		_kill_since_charge = 0


func has_charge() -> bool:
	return fireball_charges > 0


## Progress (0..1) toward the next fireball charge, for the HUD ensō.
func charge_progress() -> float:
	if fireball_charges >= MAX_FIREBALL_CHARGES:
		return 0.0
	return clampf(float(_kill_since_charge) / float(KILLS_PER_CHARGE), 0.0, 1.0)


func _shoot_fireball() -> void:
	fireball_charges -= 1
	is_busy = true  # lock animation until punch completes

	# Play punch animation
	animated_sprite_2d.play("punch")
	if has_node("PunchSound"):
		$PunchSound.play()

	# Spawn fireball
	var fb_scene := preload("res://scenes/fireball.tscn")
	if fb_scene:
		var fb := fb_scene.instantiate()
		fb.global_position = global_position + Vector2((1.0 if facing_right else -1.0) * 30, -10)
		fb.direction = 1.0 if facing_right else -1.0
		get_parent().add_child(fb)

	# Return to idle after punch anim. `animation_finished` fires for whatever
	# animation completes next, so only release the busy lock if the punch is still
	# the active animation — otherwise a hit (which plays "hurt") would have us
	# clobber its state.
	await animated_sprite_2d.animation_finished
	if alive and animated_sprite_2d.animation == "punch":
		is_busy = false
		animated_sprite_2d.play("idle")
