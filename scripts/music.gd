extends AudioStreamPlayer

# Autoloaded singleton: plays looping background music that persists across
# scene changes. Uses a short crossfade to minimise the MP3 loop gap.

func _ready() -> void:
	stream = preload("res://assets/sounds/bgm.mp3")
	bus = "Music"
	finished.connect(_on_finished)
	play()

func _on_finished() -> void:
	# Small random offset reduces audible pattern repetition
	play(randf_range(0.0, 0.15))
