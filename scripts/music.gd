extends AudioStreamPlayer

# Autoloaded singleton: plays looping background music that persists across scene
# changes. Loops seamlessly via the stream's own loop flag (no gap from the old
# finished→replay approach, which couldn't loop an MP3 gaplessly).

func _ready() -> void:
	var bgm := preload("res://assets/sounds/bgm.mp3")
	if bgm is AudioStreamMP3:
		bgm.loop = true
		bgm.loop_offset = 0.0
	stream = bgm
	bus = "Music"
	play()
