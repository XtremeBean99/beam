extends Node2D

## Level 2 — the hand-drawn "map2" world. Terrain is built at runtime by the
## InkTerrain child from the extracted strokes. Provides a simple fall-respawn so
## dropping off the floating ink platforms returns the player to the spawn point
## instead of falling forever. (Enemies, collectables, and the collect-all
## beam-of-light exit arrive in a later pass.)

@onready var player: Node2D = $Player

## World-Y below which the player is considered to have fallen off the level and
## is returned to spawn. Set generously below the lowest platform.
@export var fall_limit: float = 7000.0

var _spawn := Vector2.ZERO


func _ready() -> void:
	if player:
		_spawn = player.global_position


func _process(_delta: float) -> void:
	if player and is_instance_valid(player) and player.global_position.y > fall_limit:
		player.global_position = _spawn
		player.velocity = Vector2.ZERO
