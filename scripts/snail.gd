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
var health_bar_visible: bool = false
var health_bar_bg: ColorRect
var health_bar_fill: ColorRect


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
	_show_health_bar()
	if health <= 0:
		is_dead = true
		collision_shape_2d.disabled = true
		if health_bar_bg: health_bar_bg.queue_free()
		animated_sprite_2d.play("running")
		animated_sprite_2d.modulate = Color.RED
		await get_tree().create_timer(0.4).timeout
		queue_free()
	else:
		position.x += knockback_dir * 60.0
		animated_sprite_2d.modulate = Color.WHITE
		await get_tree().create_timer(0.1).timeout
		animated_sprite_2d.modulate = Color.WHITE


func _show_health_bar() -> void:
	if health_bar_visible:
		_update_health_bar()
		return
	health_bar_visible = true
	
	health_bar_bg = ColorRect.new()
	health_bar_bg.size = Vector2(40, 5)
	health_bar_bg.position = Vector2(-20, -50)
	health_bar_bg.color = Color(0.15, 0.15, 0.15, 0.8)
	add_child(health_bar_bg)
	
	health_bar_fill = ColorRect.new()
	health_bar_fill.size = Vector2(40, 5)
	health_bar_fill.position = Vector2(-20, -50)
	health_bar_fill.color = Color(0.9, 0.15, 0.15, 0.9)
	add_child(health_bar_fill)
	
	_update_health_bar()


func _update_health_bar() -> void:
	if not health_bar_fill:
		return
	var ratio: float = float(health) / float(MAX_HEALTH)
	health_bar_fill.size.x = 40.0 * ratio
