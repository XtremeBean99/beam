extends Node2D
# NB: no class_name — main.gd preloads this script by path. Global class names
# registered from files created outside the editor stay unresolved until a
# project rescan, and an unresolved name breaks every script referencing it.

## Translucent replay of the PREVIOUS attempt of this level (a racing ghost).
## main.gd records the player's pose at a fixed rate during each attempt and
## hands the samples to this node when the level (re)loads. Purely visual:
## no collision, no physics, no interaction with gameplay.

const SAMPLE_HZ = 30.0
const TINT = Color(0.6, 0.8, 1.0, 0.35)

var samples: Array = []           # [[pos, anim, frame, flip_h, rot], ...]
var sprite_frames: SpriteFrames = null
var sprite_scale: Vector2 = Vector2.ONE

var _sprite: AnimatedSprite2D = null
var _time: float = 0.0
var _done: bool = false


func _ready() -> void:
	if samples.is_empty() or sprite_frames == null:
		queue_free()
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = sprite_frames
	_sprite.scale = sprite_scale
	_sprite.modulate = TINT
	add_child(_sprite)
	z_index = -1   # always drawn behind the live player
	_apply_sample(0)


func _process(delta: float) -> void:
	if _done:
		return
	_time += delta
	var f: float = _time * SAMPLE_HZ
	var i: int = int(f)
	if i >= samples.size() - 1:
		_apply_sample(samples.size() - 1)
		_fade_out()
		return
	# Interpolate position between samples for smooth motion; the pose (frame,
	# flip, rotation) snaps to the nearest sample, which reads fine at 30 Hz.
	var a: Array = samples[i]
	var b: Array = samples[i + 1]
	var pa: Vector2 = a[0]
	var pb: Vector2 = b[0]
	global_position = pa.lerp(pb, f - float(i))
	_apply_pose(a)


func _apply_sample(i: int) -> void:
	var s: Array = samples[i]
	global_position = s[0]
	_apply_pose(s)


func _apply_pose(s: Array) -> void:
	var anim: String = s[1]
	if _sprite.sprite_frames.has_animation(anim):
		_sprite.animation = anim
		_sprite.frame = s[2]
	_sprite.flip_h = s[3]
	_sprite.rotation = s[4]
	_sprite.pause()   # poses are driven by the recording, not animation playback


func _fade_out() -> void:
	# The ghost finished its run: linger briefly, then dissolve.
	_done = true
	var t: Tween = create_tween()
	t.tween_interval(0.6)
	t.tween_property(self, "modulate:a", 0.0, 0.8)
	t.tween_callback(queue_free)
