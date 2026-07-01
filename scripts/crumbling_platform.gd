extends StaticBody2D

## A platform that crumbles when the player lands on it. It holds its first frame
## until a player touches it, then plays the crumble animation at 1 fps and frees
## itself — dropping whatever was standing on it. Place instances and position them;
## the frames are loaded from assets/images/ENVIRONMENT/crumbling/.

const FRAME_COUNT := 10
const CRUMBLE_FPS := 3.0   # animation speed once triggered

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _detector: Area2D = $Detector

var _triggered := false


func _ready() -> void:
	_build_frames()
	_sprite.animation = "crumble"
	_sprite.frame = 0
	_sprite.pause()                      # hold the first (intact) frame
	_detector.body_entered.connect(_on_body_entered)


## Build the crumble SpriteFrames from the extracted GIF frames, non-looping at 1 fps.
func _build_frames() -> void:
	var sf := SpriteFrames.new()
	sf.add_animation("crumble")
	sf.set_animation_loop("crumble", false)
	sf.set_animation_speed("crumble", CRUMBLE_FPS)
	for i in range(FRAME_COUNT):
		var tex := load("res://assets/images/ENVIRONMENT/crumbling/frame%d.png" % i)
		if tex:
			sf.add_frame("crumble", tex)
	_sprite.sprite_frames = sf


func _on_body_entered(body: Node2D) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	_triggered = true
	_sprite.play("crumble")
	# Collision stays until the animation ends, so the platform holds the player up
	# while it visibly crumbles, then vanishes and drops them.
	await _sprite.animation_finished
	queue_free()
