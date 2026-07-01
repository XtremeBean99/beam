extends Control

## Reusable volume + key-rebinding + display settings panel. Reads and writes the
## Settings autoload. Emits `closed` when the player backs out.

signal closed

# Single source of truth for which actions are rebindable lives in Settings.
@onready var _rebindable: Array = Settings.REBINDABLE_ACTIONS

@onready var _rows := {
	"Master": $Dim/Center/Panel/VBox/Master,
	"Music": $Dim/Center/Panel/VBox/Music,
	"SFX": $Dim/Center/Panel/VBox/SFX,
}
@onready var _fullscreen_check: CheckButton = $Dim/Center/Panel/VBox/Fullscreen/Check

var _rebinding_action := ""
var _rebinding_button: Button = null
var _rebinding_original := ""


func _ready() -> void:
	for bus in _rows:
		var row: Node = _rows[bus]
		var slider: HSlider = row.get_node("Slider")
		var value: Label = row.get_node("Value")
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = Settings.get_volume(bus)
		value.text = "%d%%" % roundi(slider.value * 100.0)
		slider.value_changed.connect(_on_value_changed.bind(bus))

	_fullscreen_check.button_pressed = Settings.fullscreen
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	_setup_rebind_buttons()
	$Dim/Center/Panel/VBox/Back.pressed.connect(_on_back)


func _setup_rebind_buttons() -> void:
	var section := $Dim/Center/Panel/VBox/RebindSection/VBox
	for action in _rebindable:
		var btn: Button = section.get_node_or_null(action + "Row/" + action + "Button")
		if btn:
			_refresh_button_label(btn, action)
			btn.pressed.connect(_on_rebind_pressed.bind(action, btn))


func _key_label_for(action: String) -> String:
	# Show the first keyboard binding (the rebind UI only manages keyboard keys).
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return e.as_text()
	return "(unbound)"


func _refresh_button_label(btn: Button, action: String) -> void:
	btn.text = _key_label_for(action)


func _refresh_all_labels() -> void:
	var section := $Dim/Center/Panel/VBox/RebindSection/VBox
	for action in _rebindable:
		var btn: Button = section.get_node_or_null(action + "Row/" + action + "Button")
		if btn:
			_refresh_button_label(btn, action)


func open() -> void:
	show()
	for bus in _rows:
		var slider: HSlider = _rows[bus].get_node("Slider")
		slider.value = Settings.get_volume(bus)
	_fullscreen_check.button_pressed = Settings.fullscreen
	_refresh_all_labels()
	($Dim/Center/Panel/VBox/Master/Slider as HSlider).grab_focus()


func _on_value_changed(value: float, bus: String) -> void:
	Settings.set_volume(bus, value)
	(_rows[bus].get_node("Value") as Label).text = "%d%%" % roundi(value * 100.0)


func _on_fullscreen_toggled(on: bool) -> void:
	Settings.set_fullscreen(on)


func _on_rebind_pressed(action: String, btn: Button) -> void:
	if _rebinding_action != "":
		return  # already waiting for a key
	_rebinding_action = action
	_rebinding_button = btn
	_rebinding_original = btn.text
	btn.text = "..."
	btn.release_focus()


func _input(event: InputEvent) -> void:
	if _rebinding_action == "":
		return
	if event is InputEventKey and event.pressed:
		# Ignore ui_accept keys (Enter, Space) — they'd re-trigger the button.
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			_cancel_rebind()
			return
		_apply_rebind(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_cancel_rebind()  # cancel on a click outside


func _key_code(e: InputEventKey) -> int:
	return e.physical_keycode if e.physical_keycode != 0 else e.keycode


func _apply_rebind(event: InputEventKey) -> void:
	var action := _rebinding_action
	var new_code := _key_code(event)

	# Conflict resolution: if this key is bound to another rebindable action, take
	# it away there so no two actions share a key (the key "moves" to this action).
	for other in _rebindable:
		if other == action:
			continue
		for e in InputMap.action_get_events(other):
			if e is InputEventKey and _key_code(e) == new_code:
				InputMap.action_erase_event(other, e)

	# Replace only the keyboard event(s) of this action, preserving any joypad/mouse
	# bindings instead of wiping every event as the old code did.
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)

	_refresh_all_labels()  # other actions may have lost this key
	Settings.save_keybindings()
	_finish_rebind()


func _cancel_rebind() -> void:
	if _rebinding_button:
		_rebinding_button.text = _rebinding_original
	_finish_rebind()


func _finish_rebind() -> void:
	_rebinding_action = ""
	_rebinding_button = null
	_rebinding_original = ""


func _on_back() -> void:
	if _rebinding_action != "":
		_cancel_rebind()
	hide()
	closed.emit()
