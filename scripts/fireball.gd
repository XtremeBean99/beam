extends Area2D
@onready var animated_sprite_2d = $AnimatedSprite2D

const SPEED = 500.0
const LIFETIME = 3.0
const DAMAGE = 3  # one-shots a regular enemy (snail/flyer); boss takes several

var direction: float = 1.0
var timer: float = 0.0
var custom_velocity: Vector2 = Vector2.ZERO


func _ready():
	animated_sprite_2d.play("default")
	body_entered.connect(_on_hit)
	area_entered.connect(_on_hit_area)


func set_velocity(vel):
	custom_velocity = vel


func _physics_process(delta):
	timer += delta
	if timer > LIFETIME:
		queue_free()
		return
	if custom_velocity.length() > 0:
		position += custom_velocity * delta
	else:
		position.x += direction * SPEED * delta


func _on_hit(body):
	# Never hurt the player or stop on them; pass straight through.
	if body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(DAMAGE, direction)
	# Damageable enemy or solid terrain (layer 1) both stop the projectile.
	queue_free()


func _on_hit_area(area):
	# Damageable areas take a hit and stop the projectile; harmless areas
	# (e.g. collectables on the terrain layer) are ignored so the shot flies on.
	if area.is_in_group("player"):
		return
	if area.has_method("take_damage"):
		area.take_damage(DAMAGE, direction)
		queue_free()
