extends Area2D
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var timer: Timer = $Timer
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

signal player_hit

const SPEED: float = 100.0
const MAX_HEALTH: int = 3

var direction: float = -1.0
var health: int = MAX_HEALTH
var is_dead: bool = false


func _ready() -> void:
	add_to_group("enemies")


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	position.x += direction * SPEED * delta


func _on_timer_timeout() -> void:
	if is_dead:
		return
	direction *= -1
	animated_sprite_2d.flip_h = not animated_sprite_2d.flip_h


func _on_body_entered(body: Node2D) -> void:
	if is_dead:
		return
	if body.is_in_group("player") and body.has_method("hurt") and body.alive:
		emit_signal("player_hit", body)


func take_damage(amount: int, knockback_dir: float) -> void:
	if is_dead:
		return
	health -= amount
	if health <= 0:
		is_dead = true
		collision_shape_2d.disabled = true
		animated_sprite_2d.play("running")  # re-use running as death anim
		# Flash red then remove
		animated_sprite_2d.modulate = Color.RED
		await get_tree().create_timer(0.4).timeout
		queue_free()
	else:
		# Knockback
		position.x += knockback_dir * 60.0
		# Flash white briefly
		animated_sprite_2d.modulate = Color.WHITE
		await get_tree().create_timer(0.1).timeout
		animated_sprite_2d.modulate = Color.WHITE
