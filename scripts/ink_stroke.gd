@tool
extends Node2D
class_name InkStroke

## A single hand-drawn terrain stroke: renders as a glowing monochrome line
## (Line2D) and builds matching collision. Open strokes become one convex quad per
## segment (robust, no concave decomposition); closed paths use their outline
## directly. Authored terrain and (future) effects share this primitive.

@export var points: PackedVector2Array:
	set(value):
		points = value
		_rebuild()

## Collision thickness in world units (the visible line is thinner).
@export var thickness: float = 16.0:
	set(value):
		thickness = value
		_rebuild()

## Bright core color (monochrome void-and-glow look).
@export var core_color: Color = Color(0.92, 0.96, 1.0, 1.0)
## Faint wider underlay that reads as glow.
@export var glow_color: Color = Color(0.55, 0.7, 0.95, 0.25)
@export var core_width: float = 4.0
@export var glow_width: float = 12.0

var _glow: Line2D
var _core: Line2D
var _body: StaticBody2D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in [_glow, _core, _body]:
		if child and is_instance_valid(child):
			child.queue_free()
	_glow = null
	_core = null
	_body = null
	if points.size() < 2:
		return

	# --- Visual: faint wide glow under a bright thin core ---
	_glow = _make_line(glow_width, glow_color)
	_core = _make_line(core_width, core_color)
	add_child(_glow)
	add_child(_core)

	# --- Collision ---
	# (Skipped in the editor so authoring doesn't spawn physics bodies.)
	if not Engine.is_editor_hint():
		_body = StaticBody2D.new()
		_body.collision_layer = 1
		_body.collision_mask = 0
		if points.size() >= 3 and points[0].distance_to(points[points.size() - 1]) < 2.0:
			# Closed path (letters / filled shapes) → use the outline directly.
			var poly := CollisionPolygon2D.new()
			poly.polygon = points
			_body.add_child(poly)
		else:
			# Open stroke → one convex quad per segment. Independent convex pieces
			# avoid the costly/fragile concave decomposition of a single ribbon and
			# the self-intersections an offset polyline produces on tight bends.
			_add_segment_collision(_body, points, thickness)
		add_child(_body)


func _make_line(width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	return line


## Build collision as one convex quad per polyline segment, parented to `body`.
## Each quad is independent, so there is no concave decomposition and no miter
## self-intersection; consecutive quads overlap at the joints to fill corners.
func _add_segment_collision(body: StaticBody2D, pts: PackedVector2Array, th: float) -> void:
	var half := th * 0.5
	for i in range(pts.size() - 1):
		if pts[i].distance_to(pts[i + 1]) < 0.001:
			continue
		var cp := CollisionPolygon2D.new()
		cp.polygon = segment_quad(pts[i], pts[i + 1], half)
		body.add_child(cp)


## Pure helper: the convex quad for one segment a→b, offset by `half` either side.
## Static so it can be unit-tested without a node in the tree.
static func segment_quad(a: Vector2, b: Vector2, half: float) -> PackedVector2Array:
	var perp := (b - a).orthogonal().normalized() * half
	return PackedVector2Array([a + perp, b + perp, b - perp, a - perp])
