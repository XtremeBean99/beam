extends Node

## Autoloaded settings: persists audio volumes (Master / Music / SFX) and key
## bindings to a ConfigFile, applying them on startup and on change.

const PATH := "user://settings.cfg"
const BUSES := ["Master", "Music", "SFX"]
const REBINDABLE_ACTIONS := ["left", "right", "jump", "crouch", "shoot", "pause"]

var volumes := {"Master": 1.0, "Music": 0.9, "SFX": 0.9}
var fullscreen := true


func _ready() -> void:
	load_settings()
	load_keybindings()
	apply_all()
	apply_display()


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


func apply_display() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_display()
	save_settings()


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
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for b in BUSES:
		volumes[b] = float(cfg.get_value("audio", b, get_volume(b)))
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))


func save_keybindings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # preserve the [audio] section
	for action in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var codes: Array[int] = []
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				# The project's bindings are physical; fall back to logical only
				# if a physical code is somehow missing. Never persist 0 (none).
				var pc: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
				if pc != 0:
					codes.append(pc)
		cfg.set_value("keys", action, codes)
	cfg.save(PATH)


func load_keybindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for action in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var codes = cfg.get_value("keys", action, [])
		if codes == null:
			continue
		# Keep only valid (non-zero) codes; if none are valid, leave the project's
		# default binding for this action untouched (guards against old corrupt saves).
		var valid: Array = []
		for code in codes:
			if int(code) != 0:
				valid.append(int(code))
		if valid.is_empty():
			continue
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				InputMap.action_erase_event(action, e)
		for code in valid:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(code)
			InputMap.action_add_event(action, ev)
