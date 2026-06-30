extends Node

## Autoloaded settings: persists audio volumes (Master / Music / SFX) and key
## bindings to a ConfigFile, applying them on startup and on change.

const PATH := "user://settings.cfg"
const BUSES := ["Master", "Music", "SFX"]
const REBINDABLE_ACTIONS := ["left", "right", "jump", "crouch", "punch", "shoot", "pause"]

var volumes := {"Master": 1.0, "Music": 0.9, "SFX": 0.9}


func _ready() -> void:
	load_settings()
	load_keybindings()
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
	cfg.load(PATH)  # preserve existing key bindings
	for b in BUSES:
		cfg.set_value("audio", b, get_volume(b))
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for b in BUSES:
		volumes[b] = float(cfg.get_value("audio", b, get_volume(b)))


func save_keybindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		# Preserve existing audio settings
		pass
	for action in REBINDABLE_ACTIONS:
		var events := InputMap.action_get_events(action)
		var codes: Array[int] = []
		for e in events:
			if e is InputEventKey:
				codes.append(e.keycode)
		cfg.set_value("keys", action, codes)
	cfg.save(PATH)


func load_keybindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for action in REBINDABLE_ACTIONS:
		var codes = cfg.get_value("keys", action, [])
		if codes == null or codes.is_empty():
			continue
		# Remove current key events for this action
		var current := InputMap.action_get_events(action)
		for e in current:
			if e is InputEventKey:
				InputMap.action_erase_event(action, e)
		# Add saved key events
		for code in codes:
			var ev := InputEventKey.new()
			ev.keycode = int(code)
			InputMap.action_add_event(action, ev)
