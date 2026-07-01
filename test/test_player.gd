extends Node

## Tests for player.gd's real logic: the fireball charge gating (via the actual
## add_charge() method) and the tuning constants. Instantiating the player script
## bare is fine here — add_charge() only touches plain integer state, not nodes.

const PlayerScript = preload("res://scripts/player.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	_run_all()
	prints("\nPlayer tests: %d passed, %d failed" % [_passed, _failed])


func _run_all() -> void:
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


# --- Charge gating (real add_charge) ----------------------------------------

func _test_charge_gating() -> void:
	prints("charge gating...")

	var p = PlayerScript.new()

	# 3 kills → 1 charge.
	p.add_charge(); p.add_charge(); p.add_charge()
	_assert_eq(p.fireball_charges, 1, "3 kills → 1 charge")

	# Plenty of kills → capped at MAX_FIREBALL_CHARGES.
	for i in range(30):
		p.add_charge()
	_assert_eq(p.fireball_charges, p.MAX_FIREBALL_CHARGES, "kills cap at max charges")

	# No banking past the cap: after spending one, it takes a FULL KILLS_PER_CHARGE
	# to earn it back (kills at the cap must not be hoarded).
	p.fireball_charges -= 1
	for i in range(p.KILLS_PER_CHARGE - 1):
		p.add_charge()
	_assert_eq(p.fireball_charges, p.MAX_FIREBALL_CHARGES - 1, "partial kills don't refill (no banking)")
	p.add_charge()
	_assert_eq(p.fireball_charges, p.MAX_FIREBALL_CHARGES, "full KILLS_PER_CHARGE refills the spent charge")

	p.free()


# --- Tuning constants -------------------------------------------------------

func _test_timer_ranges() -> void:
	prints("timer ranges...")

	var p = PlayerScript.new()

	_assert(p.COYOTE_TIME > 0.0, "coyote > 0")
	_assert(p.COYOTE_TIME < 0.3, "coyote < 0.3 (not too generous)")

	_assert(p.JUMP_BUFFER_TIME > 0.0, "buffer > 0")
	_assert(p.JUMP_BUFFER_TIME < 0.3, "buffer < 0.3")

	var inv_sec: float = p.INVINCIBLE_MS / 1000.0
	_assert(inv_sec >= 0.5, "invincibility >= 0.5s")
	_assert(inv_sec <= 3.0, "invincibility <= 3.0s")

	p.free()
