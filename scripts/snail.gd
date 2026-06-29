extends Area2D
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

signal player_hit
const SPEED = 100.0
var direction = -1.0

func _ready() -> void:
	add_to_group("enemies")

func _process(delta: float) -> void:
	position.x += direction * SPEED * delta 


func _on_timer_timeout() -> void:
	direction *= -1
	animated_sprite_2d.flip_h = !animated_sprite_2d.flip_h


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("hurt"):
		emit_signal("player_hit", body)
