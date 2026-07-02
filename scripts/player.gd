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
const SLIDE_GAIN = 4.5           # extra slide speed (× SPEED) at full steepness — steeper = faster
const SLIDE_MAX_SPEED = 1800.0   # high cap so slides can really build up
const SLIDE_MIN_SPEED = 24.0     # low bar to START a slide (> END for hysteresis)
const SLIDE_END_SPEED = 12.0     # slide ends gracefully once it slows below this
const SLIDE_KICK_DELAY = 1.0     # hold plain crouch for the first second of a slide
const SLIDE_ANIM_MIN = 400.0   # below this, hold the crouched first frame
const SLIDE_ANIM_MAX = 950.0   # at/above this, fully-extended kick frame
const SLIDE_ANIM = "crouch-kick"
const SLIDE_LAUNCH_FRICTION = 160.0   # gentle deceleration when sliding off edges
const SLIDE_AIR_ANIM_FRAMES = 12      # sustained airborne frames (~0.2 s) before the flying-kick anim —
									  # long enough that contact flicker on faceted curves never triggers it
const SLIDE_SNAP_FACTOR = 1.5         # floor snap per frame-of-travel while sliding (keeps contact on convex curves)
const SLIDE_SNAP_MAX = 60.0           # hard cap on slide snap — a longer reach can teleport-grab geometry
									  # the player never actually touched and wedge them against it
const SLIDE_STUCK_DIST = 10.0         # minimum real progress (px) a live slide must make...
const SLIDE_STUCK_TIME = 0.25         # ...within this window, else the slide is force-ended (wedge guard)
const SLIDE_ROT_SPEED = 14.0          # sprite rotation smoothing rate on slopes (rad-ish/s, exponential)
const SLIDE_MAX_FLOOR_DEG = 75.0      # max floor angle during a slide, RELATIVE to the tracked up_direction.
									  # Since up_direction follows the surface, every orientation (walls,
									  # loops, ceilings) is rideable — this only rejects sudden per-frame
									  # spikes such as the stroke quads' corner facets
const SLIDE_STEEP_ASCENT = 0.9        # steepness (|tangent.y|, ≈ >64°) above which ASCENDING slides run on
									  # carried momentum + gravity only — fast entries climb high, but the
									  # player cannot ride up a near-vertical wall forever on free energy.
									  # Below this, the cruise target assists ascents so steep lines stay fast

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
var _slide_off_floor_frames := 0  # debounced airborne counter for slide animation
var _slide_normal := Vector2.UP   # last REAL slide surface normal (corner-facet frames reuse it)
var _slide_normal_rejects := 0    # consecutive rejected normals (genuine hairpins get accepted eventually)
var _slide_stuck_pos := Vector2.ZERO  # last position at which the slide had made real progress
var _slide_stuck_time := 0.0          # time since the slide last made real progress
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
## damage (via hurt) and by falling off the map. Shatters the player into ink
## fragments, then emits death_finished so main.gd can restart the level.
func die():
	if not alive:
		return
	alive = false
	health = 0
	health_changed.emit()
	is_busy = true
	invincible = true   # ignore further hits during the death animation
	player_died.emit()

	# ---- Death shatter: spawn ink fragments that fly outward ----
	var shatter_count := 14
	for i in range(shatter_count):
		var frag := Sprite2D.new()
		frag.texture = animated_sprite_2d.sprite_frames.get_frame_texture("idle", 0) if animated_sprite_2d.sprite_frames.has_animation("idle") else null
		if frag.texture == null:
			continue
		frag.global_position = global_position
		frag.scale = Vector2(0.35, 0.35)
		frag.modulate = Color.WHITE
		frag.z_index = 200
		get_parent().add_child(frag)
		var angle := randf_range(0, TAU)
		var speed := randf_range(80.0, 220.0)
		var vel := Vector2(cos(angle), sin(angle)) * speed
		var tween := create_tween().set_parallel(true)
		tween.tween_property(frag, "position", frag.position + vel * 0.6, 0.5).set_ease(Tween.EASE_OUT)
		tween.tween_property(frag, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
		tween.tween_property(frag, "rotation", randf_range(-4.0, 4.0), 0.5)
		tween.tween_callback(frag.queue_free).set_delay(0.55)

	# Hide the player sprite.
	animated_sprite_2d.visible = false

	# Brief pause for the shatter to read, then emit the signal that triggers
	# the level reload (driven by main.gd).
	await get_tree().create_timer(0.45).timeout
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
		floor_max_angle = deg_to_rad(SLIDE_MAX_FLOOR_DEG)
		_slide_off_floor_frames = 0
		_slide_anim_fast = false
		_slide_normal = get_floor_normal()
		_slide_normal_rejects = 0
		_slide_stuck_pos = global_position
		_slide_stuck_time = 0.0

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
				# Reduced gravity while pressed into the wall (was mistakenly
				# WALL_SLIDE_GRAVITY / GRAVITY * delta ≈ 0, freezing the player on walls).
				velocity.y += WALL_SLIDE_GRAVITY * delta
				velocity.y = minf(velocity.y, WALL_SLIDE_GRAVITY)
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
		floor_max_angle = deg_to_rad(SLIDE_MAX_FLOOR_DEG)
		_slide_off_floor_frames = 0
		_slide_anim_fast = false
		_slide_normal = get_floor_normal()
		_slide_normal_rejects = 0
		_slide_stuck_pos = global_position
		_slide_stuck_time = 0.0

	# Start slide on a WALL: pressing crouch while airborne against any surface
	# grabs it and rides it — ALL surfaces are slideable, near-vertical lines
	# included. Momentum is projected onto the surface so a fall becomes a ride.
	if Input.is_action_just_pressed("crouch") and not is_on_floor() and is_on_wall() and not is_busy and not is_sliding and velocity.length() >= SLIDE_MIN_SPEED:
		is_sliding = true
		var wn: Vector2 = get_wall_normal()
		var wall_tangent: Vector2 = Vector2(-wn.y, wn.x)
		var along: float = velocity.dot(wall_tangent)
		slide_dir = signf(along) if absf(along) > 1.0 else (1.0 if facing_right else -1.0)
		velocity = wall_tangent * along   # carry momentum into the ride
		slide_timer = 0.0
		floor_max_angle = deg_to_rad(SLIDE_MAX_FLOOR_DEG)
		_slide_off_floor_frames = 0
		_slide_anim_fast = false
		_slide_normal = wn
		_slide_normal_rejects = 0
		_slide_stuck_pos = global_position
		_slide_stuck_time = 0.0
		# Make THIS frame's move_and_slide treat the wall as floor already.
		up_direction = wn

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
			_end_slide()
			_slide_off_floor_frames = 0
			_slide_anim_fast = false
			velocity = Vector2.ZERO
			air_jumps_left -= 1
			jump_buffer_timer = 0.0
		elif not is_on_floor():
			# Airborne slide — carry momentum with gentle drag; ramp/crest launches
			# keep their FULL velocity (no artificial up-speed cap — with proper
			# surface tracking below, glitch launches no longer happen, and a curve
			# that flings you skyward is the level design working as intended).
			# Slide state persists until landing (allows airborne slide-kills).
			floor_angle = 0.0
			floor_snap_length = 40.0
			slide_timer += delta
			if direction != 0:
				slide_dir = sign(direction)
			velocity.x = move_toward(velocity.x, 0.0, SLIDE_LAUNCH_FRICTION * delta)
			# End slide only when speed drops to a crawl in air.
			if absf(velocity.x) < SLIDE_END_SPEED:
				_end_slide()
			_slide_off_floor_frames = min(_slide_off_floor_frames + 1, SLIDE_AIR_ANIM_FRAMES * 2)
		elif not Input.is_action_pressed("crouch"):
			# Released crouch on ground — end slide.
			_end_slide()
		else:
			# Normal ground slide — slope-based acceleration with FULL surface
			# following: up_direction (set after move_and_slide, below) tracks the
			# surface, so steep lines, curves, walls and loops are all rideable.
			_slide_off_floor_frames = 0
			slide_timer += delta
			if direction != 0:
				slide_dir = sign(direction)
			# NB: every declaration below is explicitly typed. `:=` inference from
			# an untyped (Variant) expression is a COMPILE error in Godot that an
			# external syntax check cannot catch — one such line silently killed
			# this whole script, leaving the player frozen at spawn.
			var normal: Vector2 = _slide_surface_normal()
			var surface_right: Vector2 = Vector2(-normal.y, normal.x)
			# Clamp sprite rotation so it never flips sideways on steep walls.
			floor_angle = clampf(surface_right.angle(), deg_to_rad(-50), deg_to_rad(50))

			# Signed speed along the surface.
			var current_speed: float = velocity.dot(surface_right)

			# Gravity along the slope carries momentum THROUGH curves: descents speed
			# up, ascents bleed off — real physics, so curved terrain reads naturally.
			current_speed += GRAVITY * surface_right.y * delta

			# Target slide speed scales with STEEPNESS (|surface_right.y|: 0 flat →
			# 1 vertical), so steep descents and moderate ascents are always fast.
			# The regulation is SKIPPED on steep ascents (> SLIDE_STEEP_ASCENT):
			# those run on carried momentum + gravity, so a fast entry climbs a wall
			# spectacularly high but cannot ride upward forever on free energy.
			var steepness: float = absf(surface_right.y)
			var ascending: bool = current_speed * surface_right.y < 0.0
			var target: float = SPEED * (SLIDE_BASE + SLIDE_GAIN * steepness)
			var cruise: float = target * slide_dir
			if (absf(current_speed) < target or signf(current_speed) != slide_dir) \
					and not (ascending and steepness > SLIDE_STEEP_ASCENT):
				current_speed = move_toward(current_speed, cruise, SLIDE_ACCEL * delta)
			current_speed = clampf(current_speed, -SLIDE_MAX_SPEED, SLIDE_MAX_SPEED)

			velocity = surface_right * current_speed
			# Velocity is left EXACTLY along the surface — any clamp on a component
			# here breaks the along-slope direction and bleeds speed via projection.

			# Speed-scaled floor snap: at slide speeds (up to 1800 px/s ≈ 30 px/frame)
			# the fixed 40 px snap loses contact over convex curves, flickering the
			# slide into its airborne branch where launch friction kills it. Snapping
			# proportionally to per-frame travel keeps the player glued through curves.
			# (Snap acts along -up_direction, which tracks the surface — see below —
			# so this holds on walls and loops too, not just floors.)
			floor_snap_length = clampf(
				absf(current_speed) * delta * SLIDE_SNAP_FACTOR, 40.0, SLIDE_SNAP_MAX)

			if absf(current_speed) < SLIDE_END_SPEED:
				_end_slide()

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

	if not is_sliding:
		floor_snap_length = 40.0  # restore default snap whenever no slide owns it

	# Keep the slide's speed MAGNITUDE across slope/facet changes. With the default
	# (false), move_and_slide preserves only the horizontal component when the floor
	# angle changes, which bled speed at every facet joint — the main reason steep
	# and curved sections still felt slow after the target-speed fix.
	floor_constant_speed = is_sliding

	move_and_slide()

	# Wedge guard: a live slide must make real POSITIONAL progress. The previous
	# velocity-based jam check missed snap-oscillation wedges — a body jittering
	# in place against snapped geometry keeps instantaneous velocity above any
	# threshold while the player is visibly stuck (hovering, inputs inert). No
	# ~10 px of net movement within 0.25 s force-ends the slide; _end_slide()
	# restores world-up and default snap, so gravity resolves the wedge.
	if is_sliding:
		if global_position.distance_to(_slide_stuck_pos) > SLIDE_STUCK_DIST:
			_slide_stuck_pos = global_position
			_slide_stuck_time = 0.0
		else:
			_slide_stuck_time += delta
			if _slide_stuck_time >= SLIDE_STUCK_TIME:
				_end_slide()

	# SURFACE FOLLOWING — the heart of ride-anything sliding. While a grounded
	# slide is live, "up" for the floor system is the current surface normal, so
	# floor snapping presses the player INTO whatever is being ridden. With the
	# default world-up, snap pulls straight down, which detaches the slide on
	# anything steeper than ~60° (steep lines felt broken) and caused the pogo
	# cycle on curves: re-attach, get flung along a steep facet, detach — the
	# "flying kick drifting upward" glitch. Every non-slide state restores world-up.
	if is_sliding and is_on_floor():
		up_direction = _slide_surface_normal()
	elif up_direction != Vector2.UP:
		up_direction = Vector2.UP

	if not is_sliding and floor_angle != 0:
		floor_angle = 0.0
	# Smooth the sprite's slope rotation so faceted curves read as one continuous
	# surface instead of the sprite snapping to a new angle at every segment joint.
	animated_sprite_2d.rotation = lerp_angle(
		animated_sprite_2d.rotation, floor_angle, 1.0 - exp(-SLIDE_ROT_SPEED * delta))

	if direction == 1.0:
		animated_sprite_2d.flip_h = false
		facing_right = true
	elif direction == -1.0:
		animated_sprite_2d.flip_h = true
		facing_right = false
	if is_sliding:
		animated_sprite_2d.flip_h = (slide_dir < 0)


## Common slide teardown — EVERY way a slide can end funnels through here so no
## slide state can leak into normal movement. A leaked up_direction in particular
## made move_and_slide treat the real floor as a wall: the body wedged in a hover
## with gravity skipped (a "floor" was still reported) and inputs inert.
func _end_slide() -> void:
	is_sliding = false
	slide_timer = 0.0
	floor_angle = 0.0
	floor_max_angle = deg_to_rad(72)
	floor_snap_length = 40.0
	up_direction = Vector2.UP
	_slide_stuck_time = 0.0


## The slide's surface normal, filtered against corner-facet spikes: the stroke
## collision is overlapping quads whose joints and end caps expose sudden
## sideways/backward facets. A normal that turns more than ~72° in one frame is
## rejected in favour of the last real surface (its tangent would slam velocity
## in a wrong — often upward — direction). A genuine hairpin that PERSISTS is
## accepted after a few frames so the filter can never wedge the slide.
func _slide_surface_normal() -> Vector2:
	var n := get_floor_normal()
	if n.dot(_slide_normal) < 0.3:
		_slide_normal_rejects += 1
		if _slide_normal_rejects < 4:
			return _slide_normal
	_slide_normal_rejects = 0
	_slide_normal = n
	return n


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
# EOF
