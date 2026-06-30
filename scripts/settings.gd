extends Node

## Autoloaded settings: persists audio volumes (Master / Music / SFX) to a
## ConfigFile and applies them to the audio buses on startup and on change.

const PATH := "user://settings.cfg"
const BUSES := ["Master", "Music", "SFX"]

var volumes := {"Master": 1.0, "Music": 0.9, "SFX": 0.9}


func _ready() -> void:
	load_settings()
	apply_all()


func get_volume(bus: String) -> float:
	return float(volumes.get(bus, 1.0))


func set_volume(bus: String, linear: float) -> void:
	linear = clampf(linear, 0.0, 1.0)
	volumes[bus] = linear
	_apply(bus, linear)
	save_settings()


func apply_all() -> void:
	for b in BUSES:
		_apply(b, get_volume(b))


func _apply(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for b in BUSES:
		cfg.set_value("audio", b, get_volume(b))
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for b in BUSES:
		volumes[b] = float(cfg.get_value("audio", b, get_volume(b)))
