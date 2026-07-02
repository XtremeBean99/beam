extends Node2D

## Generic hand-drawn ("ink") level controller — used by level1, level2 and
## level3. Terrain is built at runtime by the InkTerrain child from the extracted
## strokes. Provides fall-respawn and the collect-all → beam-of-light exit sequence.

signal beam_done
signal player_fell   # player dropped below fall_limit → main restarts the level

@onready var player: Node2D = $Player

## World-Y below which the player is considered to have fallen off the level.
## Auto-tuned at startup from the actual terrain extent (see _compute_fall_limit);
## this exported value is only the fallback if no terrain is found.
@export var fall_limit: float = 7000.0

## How far below the lowest terrain the player must drop before the level restarts.
## Small enough that falling off feels immediate, large enough not to false-trigger.
const FALL_MARGIN := 700.0

var _spawn := Vector2.ZERO
var _checkpoint := Vector2.ZERO  # most recent checkpoint position
var _has_checkpoint := false
var _beam_active := false
var _fell := false


const VoidBackgroundScript = preload("res://scripts/void_background.gd")


func _ready() -> void:
	if player:
		_spawn = player.global_position
		_checkpoint = _spawn
	_compute_fall_limit()
	# Wire checkpoints.
	for cp in get_tree().get_nodes_in_group("checkpoints"):
		if is_ancestor_of(cp) and cp.has_signal("activated") and not cp.activated.is_connected(_on_checkpoint):
			cp.activated.connect(_on_checkpoint)
	# Ambient parallax background — spawned here so every level gets it without
	# per-scene wiring (preloaded by path; see main.gd's GhostRunner note).
	add_child(VoidBackgroundScript.new())


## Set fall_limit just below the lowest point of the built terrain so a player who
## drops off the bottom restarts quickly, instead of falling through empty space for
## seconds until a hand-set (and often far-too-deep) limit. The Terrain child builds
## its InkStroke pieces during its own _ready, which runs before this node's _ready.
func _compute_fall_limit() -> void:
	var terrain := get_node_or_null("Terrain")
	if terrain == null:
		return
	var lowest := -INF
	for stroke in terrain.get_children():
		if not ("points" in stroke):
			continue
		for p in stroke.points:
			lowest = maxf(lowest, stroke.global_position.y + p.y)
	if lowest > -INF:
		fall_limit = lowest + FALL_MARGIN


func _on_checkpoint(pos: Vector2) -> void:
	_checkpoint = pos
	_has_checkpoint = true
	# Refill the player's health when activating a checkpoint.
	if is_instance_valid(player) and "health" in player:
		player.health = 3
		if player.has_signal("health_changed"):
			player.health_changed.emit()


## Where the player should respawn: latest checkpoint, or the level start.
func get_spawn_position() -> Vector2:
	return _checkpoint if _has_checkpoint else _spawn


func _process(_delta: float) -> void:
	if _beam_active or _fell:
		return
	if player and is_instance_valid(player) and player.global_position.y > fall_limit:
		# Dropping below the level kills the player outright. The death animation
		# plays against the dark void (the camera is a child of the player, so it
		# stays centred), then main.gd restarts the level off death_finished. Guard
		# so this fires once, not every frame until the reload.
		_fell = true
		if player.has_method("die"):
			player.die()
		else:
			player_fell.emit()  # fallback for players without a death path


const DOOR_TEXTURE := preload("res://assets/images/ENVIRONMENT/door.png")
## On-screen height of the spawned exit door, in world pixels (door.png is square).
const DOOR_HEIGHT := 320.0

## Called by main.gd when the level is cleared (all collectables OR all boss-room
## enemies). An exit door materialises at `pos` — wherever the last collectable was
## grabbed or the last boss-room enemy fell — then beam_done drives the level-clear
## screen. Replaces the old beam-of-light transport.
func show_exit_door(pos: Vector2) -> void:
	if _beam_active:
		return
	_beam_active = true

	# Freeze the player for the clear sequence (if one is still around).
	if is_instance_valid(player):
		player.input_locked = true

	var door := Sprite2D.new()
	door.texture = DOOR_TEXTURE
	door.global_position = pos
	door.z_index = 100
	door.scale = Vector2.ZERO
	door.modulate.a = 0.0
	# Force the door art to a white silhouette so it reads white regardless of the
	# source colours (uses the shared shader; keeps the modulate-driven fade-in).
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/white_silhouette.gdshader")
	door.material = mat
	# Square source → uniform scale that yields DOOR_HEIGHT on screen.
	var target_scale := DOOR_HEIGHT / float(DOOR_TEXTURE.get_height())
	add_child(door)

	var t := create_tween().set_parallel(true)
	t.tween_property(door, "scale", Vector2(target_scale, target_scale), 0.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(door, "modulate:a", 1.0, 0.4)

	# Let the door read on screen before the level-complete screen takes over.
	await get_tree().create_timer(1.0).timeout
	beam_done.emit()
