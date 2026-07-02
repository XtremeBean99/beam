extends Area2D
## In-world checkpoint: a breathing ensō ring the player passes through to set
## their respawn point and refill health. Drawn procedurally for the ink aesthetic.

signal activated(pos: Vector2)

@export var radius := 28.0
@export var line_width := 3.0
@export var color := Color(0.35, 0.6, 0.95, 0.55)
@export var active_color := Color(0.8, 0.92, 1.0, 0.9)

var _active := false
var _breathe := 0.0
var _close_t := 0.0
var _closing := false


func _ready() -> void:
	add_to_group("checkpoints")
	body_entered.connect(_on_body_entered)
	# Circle collision roughly matching the visual ring.
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius + 10.0
	col.shape = shape
	add_child(col)


func _process(delta: float) -> void:
	_breathe += delta * 1.5
	if _closing:
		_close_t += delta * 2.0
		if _close_t >= 1.0:
			_closing = false
	queue_redraw()


func _draw() -> void:
	if _closing and _close_t >= 1.0:
		return  # fully closed, invisible

	var r := radius + sin(_breathe) * 1.5
	var alpha := color.a
	var c := color
	var fill_target := 1.0

	if not _active and not _closing:
		# Breathing ring: draw a nearly-complete circle with a small gap.
		var gap := 0.18 + sin(_breathe * 0.7) * 0.05
		var start_angle := -PI / 2.0
		var end_angle := start_angle + TAU - gap
		var steps := 64
		var points := PackedVector2Array()
		for i in range(steps + 1):
			var t := float(i) / float(steps)
			var angle := lerpf(start_angle, end_angle, t)
			points.append(Vector2(cos(angle), sin(angle)) * r)
		if points.size() >= 2:
			draw_polyline(points, c, line_width, true)
	elif _closing:
		# Ring is closing — draw an arc that shrinks.
		var fill := 1.0 - _close_t
		var start_angle := -PI / 2.0
		var end_angle := start_angle + TAU * fill
		var steps := maxi(3, int(64.0 * fill))
		var points := PackedVector2Array()
		for i in range(steps + 1):
			var angle := lerpf(start_angle, end_angle, float(i) / float(steps))
			points.append(Vector2(cos(angle), sin(angle)) * r)
		if points.size() >= 2:
			draw_polyline(points, active_color, line_width, true)
	else:
		# Activated: draw a closed, glowing circle.
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, active_color, line_width)

	# Subtle glow dot at the center when inactive.
	if not _active:
		draw_circle(Vector2.ZERO, 2.5, Color(c.r, c.g, c.b, c.a * 0.5))


func _on_body_entered(body: Node2D) -> void:
	if _active or not body.is_in_group("player"):
		return
	_active = true
	_closing = true
	_close_t = 0.0
	activated.emit(global_position)

	# Refill the player's health.
	if body.has_method("hurt"):
		pass  # health is set by main.gd via the checkpoint logic
