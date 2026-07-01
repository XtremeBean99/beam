extends Node2D

## Player afterglow trail — spawns fading white afterimages during fast states
## (slide, airborne, wall-jump, double-jump). Uses a white-silhouette shader
## with additive blending for a crisp, non-blurry luminous look.

@export var emit_interval := 0.02   # seconds between afterimages
@export var fade_time := 0.12       # seconds for an afterimage to fade out (short → hugs the body)
@export var speed_threshold := 400.0 # min horizontal speed to trigger trail
@export var enabled := true

var _timer := 0.0
var _trail_burst := 0.0  # short burst after wall-jump / double-jump
var _was_on_wall := false
var _was_air_jumps := 0
var _white_shader: ShaderMaterial

@onready var _player: CharacterBody2D = get_parent()


func _ready() -> void:
	# White-silhouette shader — ignores texture colour, outputs pure white.
	# Additive blend is handled by the shader itself (render_mode blend_add).
	_white_shader = ShaderMaterial.new()
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
render_mode blend_add;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(1.0, 1.0, 1.0, tex.a * COLOR.a);
}
"""
	_white_shader.shader = s


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
		var jumps_now: int = _player.air_jumps_left
		if jumps_now < _was_air_jumps and _was_air_jumps > 0:
			_trail_burst = 0.25  # just double-jumped — burst
		_was_air_jumps = jumps_now
	else:
		_was_air_jumps = _player.air_jumps_left
	_was_on_wall = _player.is_on_wall()
	_trail_burst = maxf(0.0, _trail_burst - delta)

	var should_trail := false

	# Fast states that produce a trail.
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
	img.flip_h = source.flip_h
	img.centered = source.centered
	img.offset = source.offset
	img.modulate = Color(1.0, 1.0, 1.0, 0.45)
	img.material = _white_shader.duplicate()
	img.z_index = -1

	# Afterimages must live in WORLD space (a sibling of the player), not under the
	# player — otherwise they ride along with it and the scaled/translated player
	# transform throws them badly off. The global_* transform is also set AFTER
	# add_child so it resolves against the real parent, not an assumed identity.
	var world := _player.get_parent()
	if world == null:
		return
	world.add_child(img)
	img.global_position = source.global_position
	img.global_rotation = source.global_rotation
	img.global_scale = source.global_scale

	var t := create_tween()
	t.tween_property(img, "modulate:a", 0.0, fade_time)
	t.tween_callback(img.queue_free)
