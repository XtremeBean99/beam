extends AudioStreamPlayer

# Autoloaded singleton: plays looping background music that persists across
# scene changes (title screen -> gameplay).

func _ready() -> void:
	stream = preload("res://assets/sounds/bgm.mp3")
	bus = "Master"
	# bgm.mp3 is imported with loop=false, so restart it manually when it ends.
	finished.connect(play)
	play()
