extends Control

## Large closing-ensō reward motif for the level-complete screen.
## Draws a thick circular arc that animates from incomplete to a full circle,
## then breathes gently.

@export var radius := 110.0
@export var line_width := 4.0
@export var color := Color(0.35, 0.6, 0.95, 0.5)
@export var glow_color := Color(0.6, 0.8, 1.0, 0.15)

var _fill := 0.0       # 0.0 = barely started, 1.0 = complete
var _breathe := 0.0
var _visible_t := 0.0
var _snap := true       # true during the closing animation; false during breathing


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2 + 40, radius * 2 + 40)
	modulate.a = 0.0
	set_process(false)  # only run while visible


func _process(delta: float) -> void:
	_breathe += delta
	_visible_t += delta
	queue_redraw()


func animate_close() -> void:
	_fill = 0.04  # start as a small arc
	set_process(true)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.7, 0.3)
	t.tween_property(self, "_fill", 1.0, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	t.tween_callback(func():
		_snap = false
		_start_breathing()
	)


func _start_breathing() -> void:
	var b := create_tween().set_loops()
	b.set_trans(Tween.TRANS_SINE)
	b.tween_property(self, "modulate:a", 0.3, 2.0)
	b.tween_property(self, "modulate:a", 0.65, 2.0)


func _draw() -> void:
	var center := size * 0.5

	# Soft outer glow
	var glow_r := radius + 8.0 + sin(_breathe * 0.5) * 3.0
	var glow_alpha := glow_color.a
	if _snap:
		glow_alpha = glow_alpha * _visible_t
	draw_arc(center, glow_r, 0, TAU * _fill, 64, Color(glow_color, glow_alpha), line_width + 6)

	# Main arc — the ensō stroke
	var r := radius
	var alpha := color.a
	var gap := 0.12
	var end_angle := TAU * _fill
	if _fill < 1.0:
		end_angle -= gap * (1.0 - _fill)

	var points := PackedVector2Array()
	var steps := maxi(3, int(64.0 * _fill))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := -PI / 2.0 + end_angle * t
		points.append(center + Vector2(cos(angle), sin(angle)) * r)

	if points.size() >= 2:
		# Draw with slight width variation for hand-drawn feel
		var w := line_width + sin(float(points.size()) * 0.3) * 0.5
		draw_polyline(points, Color(color, alpha), w, true)
