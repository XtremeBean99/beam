extends Area2D
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var _visibility: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D

signal collected(source)
const ROTATION_SPEED := 2.0
var is_collected := false


func _ready() -> void:
	add_to_group("collectables")


func _process(delta: float) -> void:
	# Skip the idle spin while off-screen — cheap, but pointless for items the
	# player can't see (and there are many per level).
	if _visibility and not _visibility.is_on_screen():
		return
	animated_sprite_2d.rotation += ROTATION_SPEED * delta


func _on_body_entered(body: Node2D) -> void:
	if is_collected or not body.is_in_group("player"):
		return
	is_collected = true
	animated_sprite_2d.rotation = 0.0
	animated_sprite_2d.animation = "collected"
	if has_node("PickupSound"):
		$PickupSound.play()
	collected.emit(self)
	call_deferred("_disable_collision")


func _disable_collision() -> void:
	collision_shape_2d.disabled = true


func _on_animated_sprite_2d_animation_looped() -> void:
	if animated_sprite_2d.animation == "collected":
		queue_free()
