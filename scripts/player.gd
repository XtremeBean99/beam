extends CharacterBody2D
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var jump_sound: AudioStreamPlayer2D = $JumpSound
@onready var kick_sound: AudioStreamPlayer2D = $KickSound
@onready var punch_sound: AudioStreamPlayer2D = $PunchSound
@onready var attack_hitbox: Area2D = $AttackHitbox
var attack_collision: CollisionShape2D
var attack_hitbox_active: bool = false

# Movement
const SPEED: float = 300.0
const JUMP_VELOCITY: float = -700.0
const WALL_JUMP_HORIZONTAL: float = 400.0
const WALL_JUMP_VERTICAL: float = -550.0
const WALL_SLIDE_GRAVITY: float = 300.0

# Slide
const SLIDE_SPEED: float = 650.0
const SLIDE_FRICTION: float = 0.88
const SLIDE_KICK_THRESHOLD: float = 0.55
const SLIDE_MIN_SPEED: float = 80.0
const SLIDE_STOP_SPEED: float = 40.0

# Combat
const ATTACK_ANIMS: Array[String] = ["punch", "crouch-kick", "kick", "flying-kick"]
const HURT_ANIMS: Array[String] = ["hurt"]
const ATTACK_DAMAGE: int = 1
const KNOCKBACK_FORCE: float = 400.0
const INVINCIBLE_MS: float = 1000.0

var alive: bool = true
var health: int = 3
var invincible: bool = false
var is_attacking: bool = false
var is_sliding: bool = false
var slide_dir: float = 1.0
var slide_timer: float = 0.0
var facing_right: bool = true

signal player_died


func _ready() -> void:
	add_to_group("player")
	var frames := animated_sprite_2d.sprite_frames
	for anim in ATTACK_ANIMS + HURT_ANIMS:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	# Create attack hitbox
	attack_collision = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(50, 30)
	attack_collision.shape = rect
	attack_collision.position = Vector2(30, -5)
	attack_collision.disabled = true
	attack_hitbox.add_child(attack_collision)
	attack_hitbox.body_entered.connect(_on_attack_hit)


func _on_animation_finished() -> void:
	if animated_sprite_2d.animation in ATTACK_ANIMS:
		is_attacking = false
		attack_collision.disabled = true
	elif animated_sprite_2d.animation in HURT_ANIMS:
		invincible = false
		is_attacking = false


func hurt() -> void:
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


func apply_knockback(from_direction: float) -> void:
	velocity.x = from_direction * KNOCKBACK_FORCE
	velocity.y = -200.0


func _physics_process(delta: float) -> void:
	if not alive:
		return

	# Gravity, reduced during wall slide
	if not is_on_floor():
		if is_on_wall() and velocity.y > 0:
			velocity += get_gravity() * delta * (WALL_SLIDE_GRAVITY / abs(get_gravity()))
		else:
			velocity += get_gravity() * delta

	var direction := Input.get_axis("left", "right")
	var crouching := Input.is_action_pressed("crouch") and is_on_floor()

	# Wall jump
	if Input.is_action_just_pressed("jump") and is_on_wall() and not is_on_floor() and not is_attacking:
		var wall_normal := get_wall_normal()
		velocity.x = wall_normal.x * WALL_JUMP_HORIZONTAL
		velocity.y = WALL_JUMP_VERTICAL
		jump_sound.play()

	# Attacks
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

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_attacking:
		velocity.y = JUMP_VELOCITY
		jump_sound.play()

	# Slide
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

	# Animation
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

	# Facing
	if direction == 1.0:
		animated_sprite_2d.flip_h = false
		facing_right = true
	elif direction == -1.0:
		animated_sprite_2d.flip_h = true
		facing_right = false
	if is_sliding:
		animated_sprite_2d.flip_h = (slide_dir < 0)


func _on_attack_hit(body: Node2D) -> void:
	if body.has_method("take_damage"):
		var knockback_dir := 1.0 if facing_right else -1.0
		body.take_damage(ATTACK_DAMAGE, knockback_dir)


func _enable_hitbox() -> void:
	var offset_x := 30.0 if facing_right else -30.0
	attack_collision.position.x = offset_x
	attack_collision.disabled = false
	attack_hitbox_active = true
