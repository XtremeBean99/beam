#!/usr/bin/env -S godot -s
extends SceneTree

## Runs all self-contained test suites sequentially, then exits with status.

const TESTS := [
	"res://test/test_player.gd",
	"res://test/test_ink_stroke.gd",
]


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	call_deferred("run")


func run() -> void:
	var total_passed := 0
	var total_failed := 0

	prints("═══ Beam — Test Suite ═══\n")

	for path in TESTS:
		var result := await _run_one(path)
		total_passed += result[0]
		total_failed += result[1]

	prints("\n══════════════════════════════════")
	prints("  TOTAL: %d passed, %d failed" % [total_passed, total_failed])
	prints("══════════════════════════════════")

	if total_failed > 0:
		prints("SOME TESTS FAILED")
		quit(1)
	else:
		prints("ALL TESTS PASSED")
		quit(0)


func _run_one(path: String) -> Array:
	var gdscript: GDScript = load(path)
	if gdscript == null:
		printerr("Cannot load: ", path)
		return [0, 1]

	var instance: Node = gdscript.new()
	root.add_child(instance)

	# Wait for _ready to complete
	await process_frame
	await process_frame

	var p: int = 0
	var f: int = 0
	if "_passed" in instance:
		p = instance._passed
	if "_failed" in instance:
		f = instance._failed

	instance.queue_free()
	return [p, f]
