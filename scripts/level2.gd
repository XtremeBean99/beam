extends Node2D

## Level 2 — the hand-drawn "map2" world. Terrain is built at runtime by the
## InkTerrain child from the extracted strokes. Provides a simple fall-respawn so
## dropping off the floating ink platforms returns the player to the spawn point
## instead of falling forever. (Enemies, collectables, and the collect-all
## beam-of-light exit arrive in a later pass.)

@onready var player: Node2D = $Player

const FALL_LIMIT := 2600.0

var _spawn := Vector2.ZERO


func _ready() -> void:
	if player:
		_spawn = player.global_position


func _process(_delta: float) -> void:
	if player and is_instance_valid(player) and player.global_position.y > FALL_LIMIT:
		player.global_position = _spawn
		player.velocity = Vector2.ZERO
