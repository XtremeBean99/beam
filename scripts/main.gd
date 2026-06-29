extends Node2D
@onready var score_label: Label = $HUD/ScorePanel/ScoreLabel

var score: int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_setup_level()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _setup_level() -> void:
	
	#Connect collectables
	var collectables = $LevelRoot.get_node_or_null("collectables")
	if collectables: 
		for collectable in collectables.get_children():
			collectable.collected.connect(increase_score)
	
	#Connect enemies
	var enemies = $LevelRoot.get_node_or_null("Enemies")
	if enemies: 
		for enemy in enemies.get_children():
			enemy.player_hit.connect(_on_player_hit)

# SIGNAL HANDLERS
func _on_player_hit(body):
	body.hurt()	 	
	print("HP -10")
	
# Score
func increase_score() -> void:
	score += 1
	score_label.text = "SCORE: %s" % score
	
	
