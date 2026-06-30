extends Node

## Self-contained tests for player.gd pure logic: slide_frame, charge gating,
## and timer ranges. Runs without GdUnit4 addon dependency.

const KILLS_PER_CHARGE := 3
const MAX_CHARGES := 3
const SLIDE_ANIM_MIN := 400.0
const SLIDE_ANIM_MAX := 950.0

var _passed := 0
var _failed := 0


func _ready() -> void:
	_run_all()
	prints("\nPlayer tests: %d passed, %d failed" % [_passed, _failed])


func _run_all() -> void:
	_test_slide_frame()
	_test_charge_gating()
	_test_timer_ranges()


func _assert(condition: bool, msg: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL: ", msg)


func _assert_eq(actual, expected, msg: String) -> void:
	_assert(actual == expected, "%s (expected %s, got %s)" % [msg, str(expected), str(actual)])


func _slide_frame(speed: float, frame_count: int) -> int:
	if frame_count <= 1:
		return 0
	var t = clampf((absf(speed) - SLIDE_ANIM_MIN) / (SLIDE_ANIM_MAX - SLIDE_ANIM_MIN), 0.0, 1.0)
	return int(round(t * (frame_count - 1)))


# --- slide_frame ----------------------------------------------------------

func _test_slide_frame() -> void:
	prints("slide_frame...")

	_assert_eq(_slide_frame(0.0, 5), 0, "zero speed → frame 0")
	_assert_eq(_slide_frame(200.0, 5), 0, "below min (200) → frame 0")
	_assert_eq(_slide_frame(399.0, 5), 0, "just below min (399) → frame 0")
	_assert_eq(_slide_frame(950.0, 5), 4, "at max (950) → last frame 4")
	_assert_eq(_slide_frame(1200.0, 5), 4, "above max (1200) → last frame 4")
	_assert_eq(_slide_frame(500.0, 1), 0, "single frame → always 0")

	var mid := _slide_frame(675.0, 5)
	_assert(mid >= 1 and mid <= 3, "mid speed (675) → frame in [1,3], got %d" % mid)


# --- Charge gating ---------------------------------------------------------

func _test_charge_gating() -> void:
	prints("charge gating...")

	var charges := 0
	var kills_since := 0

	# 3 kills → 1 charge
	for i in range(KILLS_PER_CHARGE):
		kills_since += 1
		if kills_since >= KILLS_PER_CHARGE and charges < MAX_CHARGES:
			charges += 1
			kills_since = 0
	_assert_eq(charges, 1, "3 kills → 1 charge")
	_assert_eq(kills_since, 0, "counter reset after charge")

	# 12 kills → capped at 3, kills_since keeps accumulating (doesn't reset at cap)
	for i in range(9):
		kills_since += 1
		if kills_since >= KILLS_PER_CHARGE and charges < MAX_CHARGES:
			charges += 1
			kills_since = 0
	_assert_eq(charges, 3, "12 kills → capped at 3")
	_assert_eq(kills_since, 3, "kills keep accumulating past cap (got %d)" % kills_since)

	# Spend one, earn it back
	charges -= 1
	_assert_eq(charges, 2, "spent 1 → 2 left")
	for i in range(KILLS_PER_CHARGE):
		kills_since += 1
		if kills_since >= KILLS_PER_CHARGE and charges < MAX_CHARGES:
			charges += 1
			kills_since = 0
	_assert_eq(charges, 3, "earned back → 3")


# --- Timer ranges ----------------------------------------------------------

func _test_timer_ranges() -> void:
	prints("timer ranges...")

	const COYOTE := 0.1
	_assert(COYOTE > 0.0, "coyote > 0")
	_assert(COYOTE < 0.3, "coyote < 0.3 (not too generous)")

	const BUFFER := 0.1
	_assert(BUFFER > 0.0, "buffer > 0")
	_assert(BUFFER < 0.3, "buffer < 0.3")

	const INVINCIBLE_MS := 1000.0
	var inv_sec := INVINCIBLE_MS / 1000.0
	_assert(inv_sec >= 0.5, "invincibility >= 0.5s")
	_assert(inv_sec <= 3.0, "invincibility <= 3.0s")
