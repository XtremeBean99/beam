@tool
extends Node2D
class_name InkStroke

## A single hand-drawn terrain stroke: renders as a glowing monochrome line
## (Line2D) and builds matching collision by thickening the polyline into a
## CollisionPolygon2D. Authored terrain and (future) effects share this primitive.
##
## The polyline-thickening math is migrated from the retired player-drawn
## platform mechanic (old main.gd _build_thick_platform / _get_perpendicular).

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

	# --- Collision: thicken the polyline into a solid polygon ---
	# (Skipped in the editor so authoring doesn't spawn physics bodies.)
	if not Engine.is_editor_hint():
		_body = StaticBody2D.new()
		_body.collision_layer = 1
		_body.collision_mask = 0
		var poly := CollisionPolygon2D.new()
		poly.polygon = _build_thick_polygon(points, thickness)
		_body.add_child(poly)
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


func _build_thick_polygon(pts: PackedVector2Array, th: float) -> PackedVector2Array:
	var half := th * 0.5
	var n := pts.size()
	var poly := PackedVector2Array()
	# Top edge: offset each point along its averaged perpendicular.
	for i in range(n):
		poly.append(pts[i] + _perpendicular(pts, i, n) * half)
	# Bottom edge: opposite offset, reversed, to close the ribbon.
	for i in range(n - 1, -1, -1):
		poly.append(pts[i] - _perpendicular(pts, i, n) * half)
	return poly


func _perpendicular(pts: PackedVector2Array, i: int, n: int) -> Vector2:
	var dir := Vector2.ZERO
	if i > 0:
		dir += (pts[i] - pts[i - 1]).normalized()
	if i < n - 1:
		dir += (pts[i + 1] - pts[i]).normalized()
	if dir.length() < 0.001:
		return Vector2(0, -1)
	dir = dir.normalized()
	return Vector2(-dir.y, dir.x)
