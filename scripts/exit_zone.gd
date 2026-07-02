extends Area2D

## Touch-to-finish exit for point-to-point movement levels (no tokens, no boss
## room). Drawn in code as a slowly breathing enso ring (glow + core, matching
## the ink aesthetic), so it needs no art asset. main.gd connects `reached` to
## the level-complete flow; the door then materialises here as usual.

signal reached(pos: Vector2)

const RADIUS = 52.0
const ARC_DEG = 300.0   # enso: deliberately incomplete circle
const CORE_COLOR = Color(0.92, 0.96, 1.0, 0.9)
const GLOW_COLOR = Color(0.55, 0.7, 0.95, 0.28)

var _ring: Node2D = null
var _triggered: bool = false


func _ready() -> void:
	add_to_group("exit_zone")
	body_entered.connect(_on_body_entered)
	_build_ring()
	var t: Tween = create_tween().set_loops()
	t.tween_property(_ring, "modulate:a", 0.55, 1.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(_ring, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)


func _build_ring() -> void:
	_ring = Node2D.new()
	add_child(_ring)
	var pts: PackedVector2Array = PackedVector2Array()
	var start: float = deg_to_rad(-90.0 - ARC_DEG * 0.5)
	var steps: int = 48
	for i in range(steps + 1):
		var a: float = start + deg_to_rad(ARC_DEG) * float(i) / float(steps)
		pts.append(Vector2(cos(a), sin(a)) * RADIUS)
	_add_line(pts, 13.0, GLOW_COLOR)
	_add_line(pts, 4.5, CORE_COLOR)


func _add_line(pts: PackedVector2Array, width: float, color: Color) -> void:
	var line: Line2D = Line2D.new()
	line.points = pts
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	_ring.add_child(line)


func _on_body_entered(body: Node2D) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	_triggered = true
	reached.emit(global_position)
	# Completion pop: the ring blooms outward and dissolves as the door takes over.
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(_ring, "scale", Vector2(1.6, 1.6), 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_ring, "modulate:a", 0.0, 0.4)
