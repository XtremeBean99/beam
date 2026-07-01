extends Area2D

## Static hazard. Touching the spikes kills the player outright (regardless of
## remaining health) via the player's die() path, which restarts the level.
## Drop instances into a level and position/scale them over the terrain.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	# Terrain shares the player's collision layer, so filter by group and only act
	# on a live player that still has the death path available.
	if body.is_in_group("player") and body.has_method("die") and body.alive:
		body.die()
