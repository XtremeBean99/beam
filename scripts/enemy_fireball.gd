extends Area2D

## Projectile cast by the Wizard boss. Flies in a fixed direction and hurts the
## player on contact; despawns on terrain or after its lifetime. Distinct from the
## player's fireball (which targets enemies) — this one only affects the player.

const SPEED := 340.0
const LIFETIME := 10.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _velocity := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if sprite:
		sprite.play("default")


## Aim the projectile; call right after spawning.
func launch(dir: Vector2) -> void:
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	_velocity = dir.normalized() * SPEED
	rotation = _velocity.angle()


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		queue_free()
		return
	global_position += _velocity * delta


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("hurt"):
		body.hurt()
	# Any solid hit (player or terrain on layer 1) ends the projectile.
	queue_free()
