extends Node2D
@onready var score_label = $HUD/ScorePanel/ScoreLabel
@onready var health_label = $HUD/HealthPanel/HealthLabel
@onready var player = $LevelRoot/Player
@onready var pause_overlay = $HUD/PauseOverlay
@onready var draw_trail = $DrawTrail

const PLATFORM_LIFETIME = 8.0
const PLATFORM_SPACING = 28.0
const MAX_PLATFORMS = 200
const PLATFORM_WIDTH = 30.0
const PLATFORM_HEIGHT = 8.0

var score = 0
var is_paused = false
var is_drawing = false
var last_draw_point = Vector2.ZERO
var platforms = []


func _ready():
	_setup_level()
	_update_health_display()
	pause_overlay.hide()
	draw_trail.width = 3.0
	draw_trail.default_color = Color(0.3, 0.8, 0.5, 0.7)
	draw_trail.top_level = true


func _process(_delta):
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()

	if Input.is_action_just_pressed("draw"):
		_start_drawing()
	elif Input.is_action_just_released("draw"):
		_stop_drawing()

	if is_drawing:
		_continue_drawing()


func _start_drawing():
	is_drawing = true
	draw_trail.clear_points()
	last_draw_point = draw_trail.get_global_mouse_position()
	draw_trail.add_point(last_draw_point)


func _stop_drawing():
	is_drawing = false


func _continue_drawing():
	var mouse_pos = draw_trail.get_global_mouse_position()
	if mouse_pos.distance_to(last_draw_point) < PLATFORM_SPACING:
		return
	draw_trail.add_point(mouse_pos)
	_create_platform(last_draw_point, mouse_pos)
	last_draw_point = mouse_pos


func _create_platform(from, to):
	var mid = (from + to) * 0.5
	var dir = to - from
	var length = dir.length()

	var body = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = mid

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(length + PLATFORM_WIDTH, PLATFORM_HEIGHT)
	shape.shape = rect
	body.add_child(shape)

	var color_rect = ColorRect.new()
	color_rect.size = Vector2(length + PLATFORM_WIDTH, PLATFORM_HEIGHT)
	color_rect.position = -color_rect.size * 0.5
	color_rect.color = Color(0.3, 0.8, 0.5, 0.6)
	body.add_child(color_rect)

	add_child(body)
	platforms.append(body)

	if platforms.size() > MAX_PLATFORMS:
		var oldest = platforms.pop_front()
		oldest.queue_free()

	_fade_platform(body)


func _fade_platform(body):
	var tween = create_tween()
	tween.tween_interval(PLATFORM_LIFETIME - 0.5)
	tween.tween_property(body, "modulate:a", 0.0, 0.5)
	await tween.finished
	if is_instance_valid(body):
		body.queue_free()
		platforms.erase(body)


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
