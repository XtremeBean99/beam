extends Node

## Tests for InkStroke's real collision-geometry helper (segment_quad). These call
## the production static method directly rather than a local copy, so they fail if
## the shipping geometry changes.

var _passed := 0
var _failed := 0


func _ready() -> void:
	_run_all()
	prints("\nInkStroke tests: %d passed, %d failed" % [_passed, _failed])


func _run_all() -> void:
	_test_segment_quad()


func _assert(condition: bool, msg: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL: ", msg)


func _assert_true(condition: bool, msg: String) -> void:
	_assert(condition, msg)


# --- InkStroke.segment_quad -------------------------------------------------

func _test_segment_quad() -> void:
	prints("segment_quad...")

	var half := 8.0
	var a := Vector2(0, 0)
	var b := Vector2(100, 0)
	var q := InkStroke.segment_quad(a, b, half)

	_assert_true(q.size() == 4, "quad has 4 vertices, got %d" % q.size())

	# The midpoints of the two end edges sit on the original endpoints.
	_assert_true(((q[0] + q[3]) * 0.5).distance_to(a) < 0.01, "start edge midpoint == a")
	_assert_true(((q[1] + q[2]) * 0.5).distance_to(b) < 0.01, "end edge midpoint == b")

	# Each vertex is exactly half-thickness off the centerline.
	_assert_true(absf(q[0].distance_to(a) - half) < 0.01, "vertex offset == half-thickness")

	# Ribbon width (top-to-bottom for a horizontal segment) equals the thickness.
	var width := absf(q[0].y - q[3].y)
	_assert_true(absf(width - 2.0 * half) < 0.01, "ribbon width == thickness (%.2f)" % width)

	# A 45° segment still yields a unit-perpendicular offset of `half`.
	var dq := InkStroke.segment_quad(Vector2(0, 0), Vector2(30, 40), 10.0)
	_assert_true(absf(dq[0].distance_to(Vector2(0, 0)) - 10.0) < 0.01, "diagonal offset == half")
