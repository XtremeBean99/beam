extends Area2D
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

const ROTATION_SPEED := 2.0

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	animated_sprite_2d.rotation += ROTATION_SPEED * delta

func _on_body_entered(body: Node2D) -> void:
	animated_sprite_2d.rotation = 0.0
	animated_sprite_2d.animation = "collected"
