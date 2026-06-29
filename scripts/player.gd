extends CharacterBody2D
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var jump_sound: AudioStreamPlayer2D = $JumpSound
@onready var kick_sound: AudioStreamPlayer2D = $KickSound
@onready var punch_sound: AudioStreamPlayer2D = $PunchSound
@onready var pistol_sound: AudioStreamPlayer2D = $PistolSound


const SPEED = 300.0
const JUMP_VELOCITY = -700.0

var health = 100
var alive = true

# Attacks that play once and lock out other animations until they finish.
const ATTACK_ANIMS = ["punch", "crouch-kick", "kick", "flying-kick"]

# True while an attack animation is playing so it can't be interrupted.
var is_attacking := false

const SLIDE_SPEED := 520.0
const SLIDE_FRICTION := 0.88
const SLIDE_KICK_THRESHOLD := 0.55

var is_sliding := false
var slide_dir := 1.0
var slide_timer := 0.0


func _ready() -> void:
	# Attack animations must not loop so animation_finished fires and clears
	# the attacking state. (They're authored as looping in the scene.)
	var frames := animated_sprite_2d.sprite_frames
	for anim in ATTACK_ANIMS:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)


func _on_animation_finished() -> void:
	if animated_sprite_2d.animation in ATTACK_ANIMS:
		is_attacking = false


func _physics_process(delta: float) -> void:
	
	if health <= 0:
		alive = false 
		return
	
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	var direction := Input.get_axis("left", "right")
	var crouching := Input.is_action_pressed("crouch") and is_on_floor()

	# Handle attacks (can't start a new one mid-attack).
	if not is_attacking:
		if Input.is_action_just_pressed("punch") and is_on_floor():
			# crouch + punch = crouch-kick, otherwise a standing punch.
			is_attacking = true
			if crouching:
				animated_sprite_2d.play("crouch-kick")
				kick_sound.play()
			else:
				animated_sprite_2d.play("punch")
				punch_sound.play()
		elif Input.is_action_just_pressed("kick"):
			# Airborne kick = flying-kick, otherwise a standing kick.
			is_attacking = true
			if is_on_floor():
				animated_sprite_2d.play("kick")
			else:
				animated_sprite_2d.play("flying-kick")
			kick_sound.play()

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_attacking:
		velocity.y = JUMP_VELOCITY
		jump_sound.play()

	# Get the input direction and handle the movement/deceleration.
	if Input.is_action_just_pressed("crouch") and is_on_floor() and not is_attacking and not is_sliding and abs(velocity.x) > 80:
		is_sliding = true
		slide_dir = sign(velocity.x)
		slide_timer = 0.0
		velocity.x = SLIDE_SPEED * slide_dir

	if is_sliding:
		slide_timer += delta
		velocity.x *= SLIDE_FRICTION
		if slide_timer >= SLIDE_KICK_THRESHOLD and not is_attacking:
			is_attacking = true
			is_sliding = false
			slide_timer = 0.0
			animated_sprite_2d.play("crouch-kick")
			kick_sound.play()
		elif abs(velocity.x) < 40:
			is_sliding = false
			slide_timer = 0.0
	elif crouching or (is_attacking and is_on_floor()):
		velocity.x = move_toward(velocity.x, 0, SPEED)
	elif direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	# Pick the animation, but never override an in-progress attack.
	# Use play() (not just .animation =) so looping playback resumes after a
	# non-looping attack animation finishes and stops the sprite.
	if not is_attacking:
		if not is_on_floor():
			# Rising = jump, descending = fall.
			if velocity.y < 0:
				animated_sprite_2d.play("jump")
			else:
				animated_sprite_2d.play("fall")
		elif is_sliding:
			animated_sprite_2d.play("crouch")
		elif crouching:
			animated_sprite_2d.play("crouch")
		elif velocity.x > 1 or velocity.x < -1:
			animated_sprite_2d.play("walk")
		else:
			animated_sprite_2d.play("idle")

	move_and_slide()

	if direction == 1.0:
		animated_sprite_2d.flip_h = false
	elif direction == -1.0:
		animated_sprite_2d.flip_h = true
	if is_sliding:
		animated_sprite_2d.flip_h = (slide_dir < 0)
		
func hurt() -> void:
	pistol_sound.play()
	health -= 10 
	animated_sprite_2d.animation = "hurt"
