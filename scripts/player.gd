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

const SLIDE_SPEED = 650.0
const SLIDE_FRICTION = 0.88
const SLIDE_KICK_THRESHOLD = 0.55
const SLIDE_MIN_SPEED = 80.0
const SLIDE_STOP_SPEED = 40.0

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

signal player_died


func _ready():
	add_to_group("player")
	var frames = animated_sprite_2d.sprite_frames
	for anim in ATTACK_ANIMS + HURT_ANIMS:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
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

	if not is_finite(velocity.x):
		velocity.x = 0.0
	if not is_finite(velocity.y):
		velocity.y = 0.0

	if not is_on_floor():
		if is_on_wall() and velocity.y > 0:
			var g = abs(get_gravity())
			if g < 1.0:
				g = 980.0
			velocity.y += (WALL_SLIDE_GRAVITY / g) * delta
		else:
			velocity += get_gravity() * delta

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

	if Input.is_action_just_pressed("crouch") and is_on_floor() and not is_attacking and not is_sliding and abs(velocity.x) >= SLIDE_MIN_SPEED:
		is_sliding = true
		slide_dir = sign(velocity.x)
		slide_timer = 0.0
		velocity.x = SLIDE_SPEED * slide_dir

	if is_sliding:
		slide_timer += delta
		if slide_timer >= SLIDE_KICK_THRESHOLD and not is_attacking:
			is_attacking = true
			is_sliding = false
			slide_timer = 0.0
			animated_sprite_2d.play("crouch-kick")
			kick_sound.play()
			_enable_hitbox()
		elif abs(velocity.x) < SLIDE_STOP_SPEED:
			is_sliding = false
			slide_timer = 0.0
		else:
			velocity.x *= SLIDE_FRICTION
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
	attack_collision.position.x = offset_x
	attack_collision.disabled = false
	attack_hitbox_active = true
