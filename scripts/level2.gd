extends Node2D

## Level 2 — the hand-drawn "map2" world. Terrain is built at runtime by the
## InkTerrain child from the extracted strokes. Provides fall-respawn and the
## collect-all → beam-of-light exit sequence.

signal beam_done

@onready var player: Node2D = $Player

## World-Y below which the player is considered to have fallen off the level and
## is returned to spawn. Set generously below the lowest platform.
@export var fall_limit: float = 7000.0

var _spawn := Vector2.ZERO
var _beam_active := false


func _ready() -> void:
	if player:
		_spawn = player.global_position


func _process(_delta: float) -> void:
	if _beam_active:
		return
	if player and is_instance_valid(player) and player.global_position.y > fall_limit:
		player.global_position = _spawn
		player.velocity = Vector2.ZERO


## Called by main.gd when all collectables are gathered.
## Plays the beam-of-light transport sequence, then emits beam_done.
func start_beam_transport() -> void:
	if _beam_active or not is_instance_valid(player):
		return
	_beam_active = true

	# Lock player input during the sequence.
	player.input_locked = true

	# Create beam visuals in world space with high z_index so they render
	# above terrain and the camera follows the scene naturally.
	var beams := Node2D.new()
	beams.z_index = 100
	add_child(beams)

	var player_x := player.global_position.x

	# Outer glow — wide, soft column.
	var glow := ColorRect.new()
	glow.color = Color(0.35, 0.6, 0.95, 0.08)
	glow.size = Vector2(200, 0)
	glow.position = Vector2(player_x - 100, 0)
	beams.add_child(glow)

	# Core beam — narrow, bright column.
	var core := ColorRect.new()
	core.color = Color(0.8, 0.92, 1.0, 0.25)
	core.size = Vector2(16, 0)
	core.position = Vector2(player_x - 8, 0)
	beams.add_child(core)

	# Core center — brightest line.
	var center := ColorRect.new()
	center.color = Color(1.0, 1.0, 1.0, 0.4)
	center.size = Vector2(4, 0)
	center.position = Vector2(player_x - 2, 0)
	beams.add_child(center)

	# Extend beams downward to the player.
	var player_y := player.global_position.y
	var t_beam := create_tween().set_parallel(true)
	t_beam.tween_property(glow, "size:y", player_y + 100, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	t_beam.tween_property(core, "size:y", player_y + 60, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	t_beam.tween_property(center, "size:y", player_y + 40, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	# Brief pause after beam reaches the player, then dissolve.
	await get_tree().create_timer(0.6).timeout

	# Player dissolves — shrink and fade.
	var t_player := create_tween().set_parallel(true)
	t_player.tween_property(player, "scale", Vector2(0.01, 0.01), 0.5).set_ease(Tween.EASE_IN)
	if player.has_node("AnimatedSprite2D"):
		t_player.tween_property(player.get_node("AnimatedSprite2D"), "modulate:a", 0.0, 0.5)

	# Beam intensifies as player dissolves.
	var t_glow2 := create_tween().set_parallel(true)
	t_glow2.tween_property(glow, "color:a", 0.25, 0.4)
	t_glow2.tween_property(core, "color:a", 0.7, 0.4)
	t_glow2.tween_property(center, "color:a", 1.0, 0.4)

	await get_tree().create_timer(0.6).timeout
	beam_done.emit()
