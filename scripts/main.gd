extends Node2D
@onready var score_label: Label = $HUD/ScorePanel/ScoreLabel

var score: int = 0

func _ready() -> void:
	_setup_level()

func _setup_level() -> void:
	# Connect collectables via group
	for collectable in get_tree().get_nodes_in_group("collectables"):
		if collectable.has_signal("collected"):
			collectable.collected.connect(increase_score)

	# Connect enemies via group
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_signal("player_hit"):
			enemy.player_hit.connect(_on_player_hit)

func _on_player_hit(body: Node2D) -> void:
	if body.has_method("hurt") and body.alive:
		body.hurt()

func increase_score() -> void:
	score += 1
	score_label.text = "SCORE: %s" % score
	
	
