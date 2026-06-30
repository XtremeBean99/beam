extends Node

## Self-contained tests for InkStroke polygon-generation helpers
## (_perpendicular, _build_thick_polygon).

var _passed := 0
var _failed := 0


func _ready() -> void:
	_run_all()
	prints("\nInkStroke tests: %d passed, %d failed" % [_passed, _failed])


func _run_all() -> void:
	_test_perpendicular()
	_test_thick_polygon()


func _assert(condition: bool, msg: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL: ", msg)


func _assert_true(condition: bool, msg: String) -> void:
	_assert(condition, msg)


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


func _build_thick_polygon(pts: PackedVector2Array, th: float) -> PackedVector2Array:
	var half := th * 0.5
	var n := pts.size()
	var poly := PackedVector2Array()
	for i in range(n):
		poly.append(pts[i] + _perpendicular(pts, i, n) * half)
	for i in range(n - 1, -1, -1):
		poly.append(pts[i] - _perpendicular(pts, i, n) * half)
	return poly


# --- _perpendicular ---------------------------------------------------------

func _test_perpendicular() -> void:
	prints("_perpendicular...")

	# Horizontal line: both neighbours point right → averaged dir (1,0)
	# Perpendicular of (1,0) is (0,1) which is DOWN in Godot (+y down)
	var pts_h := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)])
	var r := _perpendicular(pts_h, 1, 3)
	_assert_true(r.dot(Vector2(0, 1)) > 0.99, "horizontal → perpendicular points down")

	# Vertical line: both neighbours point down → averaged dir (0,1)
	# Perpendicular of (0,1) is (-1,0) or (1,0) — horizontal
	var pts_v := PackedVector2Array([Vector2(0, 0), Vector2(0, 100), Vector2(0, 200)])
	r = _perpendicular(pts_v, 1, 3)
	_assert_true(absf(r.dot(Vector2(1, 0))) > 0.99, "vertical → perpendicular is horizontal")

	# Endpoint at index 0: only forward neighbour is (1,0)
	# Perpendicular is (0,1) pointing down
	var pts_end := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	r = _perpendicular(pts_end, 0, 2)
	_assert_true(r.dot(Vector2(0, 1)) > 0.99, "endpoint → perpendicular points down")

	# Isolated point fallback
	var pts_iso := PackedVector2Array([Vector2(0, 0)])
	r = _perpendicular(pts_iso, 0, 1)
	_assert_true(r == Vector2(0, -1), "isolated point → fallback (0, -1)")

	# Unit length
	var pts_diag := PackedVector2Array([Vector2(0, 0), Vector2(30, 40), Vector2(60, 80)])
	r = _perpendicular(pts_diag, 1, 3)
	_assert_true(r.length() >= 0.99 and r.length() <= 1.01, "result is unit length")


# --- _build_thick_polygon ---------------------------------------------------

func _test_thick_polygon() -> void:
	prints("_build_thick_polygon...")

	# 2-point horizontal line: same perpendicular at both ends → flat rectangle
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	var poly := _build_thick_polygon(pts, 16.0)
	_assert_true(poly.size() == 4, "2-point line → 4 vertices, got %d" % poly.size())

	# Width should equal thickness (top-to-bottom distance)
	var width := absf(poly[0].y - poly[poly.size() - 1].y)
	_assert_true(width >= 15.0 and width <= 17.0, "ribbon width ~thickness (%.1f)" % width)

	# Symmetry: midpoint of top[i] and bottom[i] near original pts[i]
	var pts_v := PackedVector2Array([Vector2(0, 0), Vector2(50, 30), Vector2(100, 0)])
	poly = _build_thick_polygon(pts_v, 16.0)
	var n := pts_v.size()
	for i in range(n):
		var top := poly[i]
		var bottom := poly[2 * n - 1 - i]
		var mid := (top + bottom) * 0.5
		_assert_true(mid.distance_to(pts_v[i]) < 2.0,
			"symmetry at point %d (offset %.2f < 2.0)" % [i, mid.distance_to(pts_v[i])])

	# All vertices within half-thickness + epsilon of centerline
	var pts3 := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)])
	poly = _build_thick_polygon(pts3, 20.0)
	for v in poly:
		var closest := 99999.0
		for p in pts3:
			closest = minf(closest, v.distance_to(p))
		_assert_true(closest < 18.0, "vertex within half-thickness+margin (%.2f < 18.0)" % closest)
