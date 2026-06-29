extends CharacterBody2D
@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var jump_sound = $JumpSound
@onready var kick_sound = $KickSound
@onready var punch_sound = $PunchSound
@onready var attack_hitbox = $AttackHitbox
var attack_collision
var attack_hitbox_active = false

const SPEED = 300.0
const JUMP_VELOCITY = -700.0
const WALL_JUMP_HORIZONTAL = 400.0
const WALL_JUMP_VERTICAL = -550.0
const WALL_SLIDE_GRAVITY = 300.0
const GRAVITY = 980.0

const SLIDE_SPEED = 650.0
const SLIDE_FRICTION = 0.92
const SLIDE_KICK_THRESHOLD = 0.55
const SLIDE_MIN_SPEED = 40.0
const SLIDE_STOP_SPEED = 25.0
const SLOPE_SLIDE_THRESHOLD = 0.08

const ATTACK_ANIMS = ["punch", "crouch-kick", "kick", "flying-kick"]
const HURT_ANIMS = ["hurt"]
const ATTACK_DAMAGE = 1
const KNOCKBACK_FORCE = 400.0
const INVINCIBLE_MS = 1000.0

var alive = true
var health = 3
var invincible = false
var is_attacking = false
var is_sliding = false
var slide_dir = 1.0
var slide_timer = 0.0
var facing_right = true
var floor_angle = 0.0
var shoot_cooldown = 0.0
const SHOOT_COOLDOWN = 0.4
var fireball_scene = preload("res://scenes/fireball.tscn")

signal player_died


func _ready():
	add_to_group("player")
	var frames = animated_sprite_2d.sprite_frames
	for anim in ATTACK_ANIMS + HURT_ANIMS:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 6.0
	attack_collision = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(50, 30)
	attack_collision.shape = rect
	attack_collision.position = Vector2(30, -5)
	attack_collision.disabled = true
	attack_hitbox.add_child(attack_collision)
	attack_hitbox.collision_layer = 4
	attack_hitbox.collision_mask = 1
	attack_hitbox.body_entered.connect(_on_attack_hit)
	attack_hitbox.area_entered.connect(_on_attack_hit_area)


func _on_animation_finished():
	if animated_sprite_2d.animation in ATTACK_ANIMS:
		is_attacking = false
		attack_collision.disabled = true
	elif animated_sprite_2d.animation in HURT_ANIMS:
		invincible = false
		is_attacking = false


func hurt():
	if not alive or invincible:
		return
	health -= 1
	if health <= 0:
		alive = false
		is_attacking = true
		player_died.emit()
		animated_sprite_2d.play("hurt")
		set_physics_process(false)
		await animated_sprite_2d.animation_finished
		queue_free()
	else:
		invincible = true
		is_attacking = true
		animated_sprite_2d.play("hurt")
		await get_tree().create_timer(INVINCIBLE_MS / 1000.0).timeout
		invincible = false
		is_attacking = false


func apply_knockback(from_direction):
	velocity.x = from_direction * KNOCKBACK_FORCE
	velocity.y = -200.0


func _physics_process(delta):
	if not alive:
		return

	shoot_cooldown = max(0.0, shoot_cooldown - delta)

	if not is_finite(velocity.x):
		velocity.x = 0.0
	if not is_finite(velocity.y):
		velocity.y = 0.0

	if not is_on_floor():
		if is_on_wall() and velocity.y > 0:
			velocity.y = velocity.y + (WALL_SLIDE_GRAVITY / GRAVITY) * delta
		else:
			velocity.y = velocity.y + GRAVITY * delta

	var direction = Input.get_axis("left", "right")
	var crouching = Input.is_action_pressed("crouch") and is_on_floor()

	if Input.is_action_just_pressed("jump") and is_on_wall() and not is_on_floor() and not is_attacking:
		var wall_normal = get_wall_normal()
		velocity.x = wall_normal.x * WALL_JUMP_HORIZONTAL
		velocity.y = WALL_JUMP_VERTICAL
		jump_sound.play()

	elif not is_attacking:
		if Input.is_action_just_pressed("punch") and is_on_floor():
			is_attacking = true
			if crouching:
				animated_sprite_2d.play("crouch-kick")
				kick_sound.play()
			else:
				animated_sprite_2d.play("punch")
				punch_sound.play()
			_enable_hitbox()
		elif Input.is_action_just_pressed("kick"):
			is_attacking = true
			if is_on_floor():
				animated_sprite_2d.play("kick")
			else:
				animated_sprite_2d.play("flying-kick")
			kick_sound.play()
			_enable_hitbox()

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_attacking:
		velocity.y = JUMP_VELOCITY
		jump_sound.play()

	# --- Slide / Slope Movement ---
	if not is_sliding and is_on_floor() and crouching and not is_attacking and not direction:
		# Crouching on a slope: slide downhill
		var normal = get_floor_normal()
		var slope = abs(normal.x)
		if slope > SLOPE_SLIDE_THRESHOLD:
			is_sliding = true
			slide_dir = -sign(normal.x)
			slide_timer = 0.0

	# Shooting — ranged fireball attack
	if Input.is_action_just_pressed("shoot") and shoot_cooldown <= 0.0 and not is_attacking:
		_shoot_fireball()

	if Input.is_action_just_pressed("crouch") and is_on_floor() and not is_attacking and not is_sliding and abs(velocity.x) >= SLIDE_MIN_SPEED:
		is_sliding = true
		slide_dir = sign(velocity.x)
		slide_timer = 0.0

	if is_sliding:
		slide_timer += delta

		var normal = get_floor_normal()
		var slope = abs(normal.x)

		# Surface tangent pointing right (downhill for rightward slopes)
		var surface_right = Vector2(-normal.y, normal.x)
		floor_angle = surface_right.angle()

		# Compute slide velocity along the surface
		var current_speed = velocity.x * surface_right.x + velocity.y * surface_right.y
		if abs(current_speed) < SLIDE_STOP_SPEED and slope < 0.02:
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
			velocity = Vector2.ZERO
		else:
			# Friction
			current_speed *= SLIDE_FRICTION
			# Gravity along the slope (always downhill, independent of direction)
			if slope > 0.01:
				var grav_downhill = GRAVITY * slope * delta
				# Determine if we're going downhill or uphill along surface_right
				# If moving right and slope goes down to the right, surface_right.y < 0 => downhill
				# Add or subtract gravity based on direction relative to downhill
				if current_speed >= 0:
					current_speed += grav_downhill
				else:
					current_speed -= grav_downhill
			# Apply velocity along tangent
			velocity = surface_right * current_speed

		# Auto-kick or stop
		if slide_timer >= SLIDE_KICK_THRESHOLD and not is_attacking:
			is_attacking = true
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
			animated_sprite_2d.play("crouch-kick")
			kick_sound.play()
			_enable_hitbox()
	elif crouching or (is_attacking and is_on_floor()):
		velocity.x = move_toward(velocity.x, 0, SPEED)
	elif direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	if not is_attacking:
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

	# Reset rotation if not sliding
	if not is_sliding and floor_angle != 0:
		floor_angle = 0.0

	# Apply slope rotation to sprite
	animated_sprite_2d.rotation = floor_angle

	if direction == 1.0:
		animated_sprite_2d.flip_h = false
		facing_right = true
	elif direction == -1.0:
		animated_sprite_2d.flip_h = true
		facing_right = false
	if is_sliding:
		animated_sprite_2d.flip_h = (slide_dir < 0)


func _on_attack_hit(body):
	if body.has_method("take_damage"):
		var knockback_dir = 1.0 if facing_right else -1.0
		body.take_damage(ATTACK_DAMAGE, knockback_dir)


func _on_attack_hit_area(area):
	if area.has_method("take_damage"):
		var knockback_dir = 1.0 if facing_right else -1.0
		area.take_damage(ATTACK_DAMAGE, knockback_dir)


func _enable_hitbox():
	var offset_x = 30.0 if facing_right else -30.0
	var offset_y = -5.0
	var hitbox_height = 30.0
	if is_sliding or (Input.is_action_pressed("crouch") and is_on_floor()):
		offset_y = 8.0
		hitbox_height = 20.0
	attack_collision.position = Vector2(offset_x, offset_y)
	attack_collision.shape.size = Vector2(50, hitbox_height)
	attack_collision.disabled = false
	attack_hitbox_active = true


func _shoot_fireball():
	var fb = fireball_scene.instantiate()
	fb.direction = 1.0 if facing_right else -1.0
	fb.position = global_position + Vector2(40.0 * fb.direction, -10.0)
	get_parent().add_child(fb)
	shoot_cooldown = SHOOT_COOLDOWN
