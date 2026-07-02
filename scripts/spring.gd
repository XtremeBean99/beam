extends Area2D

## Jump-pad spring: launches the player skyward on contact. The visual is the
## jump-pad sprite (the scene's "Pad" node); if an instance has no Pad, a
## hand-inked zigzag coil is drawn in code as a fallback. Contact squashes the
## visual flat, flashes it bright, and fires the player up with a refreshed
## air jump so springs chain naturally into movement routes.

@export var launch_velocity: float = -1500.0   # upward speed given to the player

const COIL_HEIGHT = 64.0
const COIL_HALF_WIDTH = 24.0
const COIL_TURNS = 4
const PAD_HALF = 30.0
const CORE_COLOR = Color(0.92, 0.96, 1.0, 1.0)
const GLOW_COLOR = Color(0.55, 0.7, 0.95, 0.3)
const FLASH_COLOR = Color(2.2, 2.4, 3.0, 1.0)
const COOLDOWN = 0.15   # ignore re-triggers while the player is still overlapping

var _visual: Node2D = null
var _base_scale_y: float = 1.0   # squash tweens are RELATIVE to the visual's own scale
var _idle_tween: Tween = null
var _cooldown: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_build_visual()
	_base_scale_y = _visual.scale.y
	_start_idle_bob()


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


## Prefer the scene's jump-pad sprite as the animated visual; fall back to a
## code-drawn zigzag ink coil. Either way the visual is its own node, so
## squash/stretch never touches the collision shape.
func _build_visual() -> void:
	var pad: Sprite2D = get_node_or_null("Pad")
	if pad != null:
		_visual = pad
		return
	_visual = Node2D.new()
	add_child(_visual)

	var coil: PackedVector2Array = PackedVector2Array()
	coil.append(Vector2(0, 0))
	for i in range(COIL_TURNS):
		var y: float = -COIL_HEIGHT * (float(i) + 0.5) / float(COIL_TURNS)
		var x: float = COIL_HALF_WIDTH if i % 2 == 0 else -COIL_HALF_WIDTH
		coil.append(Vector2(x, y))
	coil.append(Vector2(0, -COIL_HEIGHT))
	_add_line(coil, 12.0, GLOW_COLOR)
	_add_line(coil, 4.0, CORE_COLOR)

	var pad_line: PackedVector2Array = PackedVector2Array([
		Vector2(-PAD_HALF, -COIL_HEIGHT), Vector2(PAD_HALF, -COIL_HEIGHT)])
	_add_line(pad_line, 14.0, GLOW_COLOR)
	_add_line(pad_line, 5.0, CORE_COLOR)


func _add_line(pts: PackedVector2Array, width: float, color: Color) -> void:
	var line: Line2D = Line2D.new()
	line.points = pts
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	_visual.add_child(line)


## Gentle breathing so the spring reads as alive (and as ink, not architecture).
func _start_idle_bob() -> void:
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_visual, "scale:y", _base_scale_y * 1.06, 0.9).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(_visual, "scale:y", _base_scale_y, 0.9).set_trans(Tween.TRANS_SINE)


func _on_body_entered(body: Node2D) -> void:
	if _cooldown > 0.0 or not body.is_in_group("player"):
		return
	_cooldown = COOLDOWN
	# Launch: replace vertical speed, keep horizontal momentum (guarded set/get
	# so this script never depends on the player's script compiling first).
	var v: Vector2 = body.get("velocity")
	v.y = launch_velocity
	body.set("velocity", v)
	body.set("air_jumps_left", body.get("MAX_AIR_JUMPS"))
	_play_launch_anim()
	if has_node("BoingSound"):
		$BoingSound.play()


## Squash flat, overshoot tall, settle. The idle bob owns scale:y too, so it is
## stopped for the launch and restarted when the launch finishes.
func _play_launch_anim() -> void:
	if _idle_tween != null:
		_idle_tween.kill()
	var t: Tween = create_tween()
	t.tween_property(_visual, "scale:y", _base_scale_y * 0.3, 0.05).set_trans(Tween.TRANS_QUAD)
	t.tween_property(_visual, "scale:y", _base_scale_y * 1.25, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_visual, "scale:y", _base_scale_y, 0.1)
	t.finished.connect(_start_idle_bob)
	var f: Tween = create_tween()
	f.tween_property(_visual, "modulate", FLASH_COLOR, 0.05)
	f.tween_property(_visual, "modulate", Color.WHITE, 0.3)
