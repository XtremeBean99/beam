extends Node2D
@onready var score_label = $HUD/ScorePanel/ScoreLabel
@onready var health_label = $HUD/HealthPanel/HealthLabel
@onready var player = $LevelRoot/Player
@onready var pause_overlay = $HUD/PauseOverlay
@onready var draw_trail = $DrawTrail

const PLATFORM_LIFETIME = 8.0
const PLATFORM_THICKNESS = 16.0
const PLATFORM_SPACING = 14.0
const MAX_DRAW_POINTS = 120

var score = 0
var is_paused = false
var is_drawing = false
var draw_points = []
var active_platform = null


func _ready():
	_setup_level()
	_update_health_display()
	pause_overlay.hide()
	draw_trail.width = PLATFORM_THICKNESS
	draw_trail.default_color = Color(0.25, 0.75, 0.45, 0.8)
	draw_trail.top_level = true


func _process(_delta):
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()

	if Input.is_action_just_pressed("draw"):
		_start_drawing()
	elif Input.is_action_just_released("draw"):
		_finish_drawing()

	if is_drawing:
		_continue_drawing()


func _start_drawing():
	if active_platform:
		_remove_platform()
	is_drawing = true
	draw_trail.clear_points()
	draw_points.clear()
	var pos = draw_trail.get_global_mouse_position()
	draw_points.append(pos)
	draw_trail.add_point(pos)


func _continue_drawing():
	var pos = draw_trail.get_global_mouse_position()
	var last = draw_points[draw_points.size() - 1]
	if pos.distance_to(last) < PLATFORM_SPACING:
		return
	draw_points.append(pos)
	draw_trail.add_point(pos)
	if draw_points.size() > MAX_DRAW_POINTS:
		draw_points.pop_front()
		draw_trail.remove_point(0)


func _finish_drawing():
	is_drawing = false
	if draw_points.size() < 2:
		return
	_build_thick_platform()


func _build_thick_platform():
	var half = PLATFORM_THICKNESS * 0.5
	var poly = PackedVector2Array()
	var n = draw_points.size()

	# Build top edge: offset each point perpendicular "up" (left of direction)
	for i in range(n):
		var perp = _get_perpendicular(i, n)
		poly.append(draw_points[i] + perp * half)

	# Build bottom edge: offset each point perpendicular "down" (right of direction), reversed
	for i in range(n - 1, -1, -1):
		var perp = _get_perpendicular(i, n)
		poly.append(draw_points[i] - perp * half)

	var body = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0

	var col = CollisionPolygon2D.new()
	col.polygon = poly
	body.add_child(col)

	add_child(body)
	active_platform = body
	_fade_platform(body)


func _get_perpendicular(i, n):
	# Compute direction at point i (average of incoming and outgoing segments)
	var dir = Vector2.ZERO
	if i > 0:
		dir += (draw_points[i] - draw_points[i - 1]).normalized()
	if i < n - 1:
		dir += (draw_points[i + 1] - draw_points[i]).normalized()
	if dir.length() < 0.001:
		return Vector2(0, -1)  # default: up
	dir = dir.normalized()
	# Perpendicular (counter-clockwise 90 degrees = left relative to direction)
	return Vector2(-dir.y, dir.x)


func _remove_platform_body(body):
	if is_instance_valid(body):
		body.queue_free()
	if active_platform == body:
		active_platform = null


func _remove_platform():
	if active_platform and is_instance_valid(active_platform):
		active_platform.queue_free()
	active_platform = null


func _fade_platform(body):
	var tween = create_tween()
	tween.tween_interval(PLATFORM_LIFETIME - 0.5)
	tween.tween_property(body, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_remove_platform_body.bind(body))


func _setup_level():
	for collectable in get_tree().get_nodes_in_group("collectables"):
		if collectable.has_signal("collected") and not collectable.collected.is_connected(increase_score):
			collectable.collected.connect(increase_score)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_signal("player_hit") and not enemy.player_hit.is_connected(_on_player_hit):
			enemy.player_hit.connect(_on_player_hit)

	if player and player.has_signal("player_died"):
		if not player.player_died.is_connected(_on_player_died):
			player.player_died.connect(_on_player_died)


func _on_player_hit(body):
	if body.has_method("hurt") and body.alive:
		body.hurt()
		_update_health_display()


func _on_player_died():
	await get_tree().create_timer(1.5).timeout
	get_tree().reload_current_scene()


func _update_health_display():
	if player and player.has_method("hurt"):
		health_label.text = "HP: %d" % player.health


func increase_score():
	score += 1
	score_label.text = "SCORE: %s" % score


func _toggle_pause():
	is_paused = not is_paused
	get_tree().paused = is_paused
	pause_overlay.visible = is_paused


func _on_resume_pressed():
	_toggle_pause()


func _on_quit_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
