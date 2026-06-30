extends Control

## Charge ensō — a circular arc that fills as kills accumulate toward the next
## fireball charge. Glows when a charge is ready. Drawn procedurally for the
## hand-drawn ensō look, with a slight wobble.

@export var radius := 18.0
@export var line_width := 3.0
@export var base_color := Color(0.35, 0.6, 0.95, 0.3)
@export var ready_color := Color(0.8, 0.92, 1.0, 0.9)

var _fill := 0.0         # 0.0 = empty, 1.0 = full (i.e., one charge ready)
var _charges := 0
var _wobble := 0.0
var _glow_phase := 0.0
var _dirty := true        # redraw only when state changes or animating


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2 + 10, radius * 2 + 10)


func _process(delta: float) -> void:
	_wobble += delta * 1.3
	if _charges > 0:
		_glow_phase += delta * 3.0
	if _dirty or _charges > 0:  # always animate when glowing; lazy when idle
		queue_redraw()
		if _fill == 0.0 and _charges == 0:
			_dirty = false  # settled — stop redrawing until next set_state()


func set_state(fill: float, charges: int) -> void:
	_fill = clampf(fill, 0.0, 1.0)
	_charges = clampi(charges, 0, 999)
	_dirty = true


func _draw() -> void:
	var center := size * 0.5
	var r := radius + sin(_wobble) * 0.5  # slight breathing wobble
	var color := ready_color if _charges > 0 else base_color
	if _charges > 0:
		# Pulsing glow when ready
		color.a = lerpf(0.6, 0.95, (sin(_glow_phase) + 1.0) * 0.5)

	var points := PackedVector2Array()
	var segments := 64
	var start_angle := -PI / 2.0  # start from top
	# The ensō is an incomplete circle — draw only the filled portion.
	var end_angle := start_angle + TAU * _fill
	# Leave a small intentional gap at the end for the ensō aesthetic.
	var gap := 0.15
	if _fill < 1.0:
		end_angle -= gap * (1.0 - _fill)

	var steps := maxi(2, int(float(segments) * _fill))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := lerpf(start_angle, end_angle, t)
		points.append(center + Vector2(cos(angle), sin(angle)) * r)

	if points.size() >= 2:
		draw_polyline(points, color, line_width, true)

	# Draw charge pips (small dots) for each ready charge
	if _charges > 0:
		for i in range(_charges):
			var dot_angle := start_angle + float(i) * 0.5
			var dot_pos := center + Vector2(cos(dot_angle), sin(dot_angle)) * (r + 6)
			draw_circle(dot_pos, 2.5, ready_color)
