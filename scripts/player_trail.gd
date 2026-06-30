extends Node2D

## Player afterglow trail — spawns fading white afterimages during fast states
## (slide, wall-jump, double jump, high speed). Uses additive blending for a
## luminous look.

@export var emit_interval := 0.04   # seconds between afterimages
@export var fade_time := 0.25       # seconds for an afterimage to fade out
@export var speed_threshold := 400.0 # min horizontal speed to trigger trail
@export var enabled := true

var _timer := 0.0
var _trail_burst := 0.0  # short burst after wall-jump / double-jump
var _was_on_wall := false
var _was_air_jumps := 0
var _shared_material: CanvasItemMaterial

@onready var _player: CharacterBody2D = get_parent()


func _ready() -> void:
	_shared_material = CanvasItemMaterial.new()
	_shared_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


func _process(delta: float) -> void:
	if not enabled or not is_instance_valid(_player) or not _player.alive:
		return

	var sprite: AnimatedSprite2D = _player.get_node_or_null("AnimatedSprite2D")
	if not sprite:
		return

	# Detect wall-jump and double-jump moments for a burst of trail.
	if not _player.is_on_floor():
		if _player.is_on_wall() and not _was_on_wall:
			_trail_burst = 0.25  # just touched a wall — burst
		var jumps_now := _player.air_jumps_left
		if jumps_now < _was_air_jumps and _was_air_jumps > 0:
			_trail_burst = 0.25  # just double-jumped — burst
		_was_air_jumps = jumps_now
	else:
		_was_air_jumps = _player.air_jumps_left
	_was_on_wall = _player.is_on_wall()
	_trail_burst = maxf(0.0, _trail_burst - delta)

	var should_trail := false

	# Fast states that produce a trail — use velocity.length() so diagonal/
	# slope-decomposed speed counts correctly.
	var speed := _player.velocity.length()
	if _player.is_sliding and speed >= speed_threshold:
		should_trail = true
	elif not _player.is_on_floor() and speed >= speed_threshold:
		should_trail = true
	elif _trail_burst > 0.0:
		should_trail = true

	if should_trail:
		_timer += delta
		if _timer >= emit_interval:
			_timer = fmod(_timer, emit_interval)
			_spawn_afterimage(sprite)
	else:
		_timer = 0.0


func _spawn_afterimage(source: AnimatedSprite2D) -> void:
	var img := Sprite2D.new()
	img.texture = source.sprite_frames.get_frame_texture(
		source.animation, source.frame)
	img.global_position = source.global_position
	img.global_rotation = source.global_rotation
	img.scale = source.global_scale
	img.flip_h = source.flip_h
	img.centered = source.centered
	img.offset = source.offset
	img.modulate = Color(1.0, 1.0, 1.0, 0.5)
	img.material = _shared_material
	img.z_index = -2
	img.show_behind_parent = true

	get_parent().add_child(img)

	var t := create_tween()
	t.tween_property(img, "modulate:a", 0.0, fade_time)
	t.tween_callback(img.queue_free)
