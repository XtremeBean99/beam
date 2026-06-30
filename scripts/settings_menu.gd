extends Control

## Reusable volume + key rebinding settings panel. Reads and writes the
## Settings autoload. Emits `closed` when the player backs out.

signal closed

const REBINDABLE_ACTIONS := ["left", "right", "jump", "crouch", "punch", "shoot", "pause"]

@onready var _rows := {
	"Master": $Dim/Center/Panel/VBox/Master,
	"Music": $Dim/Center/Panel/VBox/Music,
	"SFX": $Dim/Center/Panel/VBox/SFX,
}

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

	_setup_rebind_buttons()
	$Dim/Center/Panel/VBox/Back.pressed.connect(_on_back)


func _setup_rebind_buttons() -> void:
	var section := $Dim/Center/Panel/VBox/RebindSection/VBox
	for action in REBINDABLE_ACTIONS:
		var btn: Button = section.get_node_or_null(action + "Button")
		if btn:
			_refresh_button_label(btn, action)
			btn.pressed.connect(_on_rebind_pressed.bind(action, btn))


func _refresh_button_label(btn: Button, action: String) -> void:
	var events := InputMap.action_get_events(action)
	if events.size() > 0:
		btn.text = events[0].as_text()
	else:
		btn.text = "(unbound)"


func open() -> void:
	show()
	# Refresh volume sliders
	for bus in _rows:
		var slider: HSlider = _rows[bus].get_node("Slider")
		slider.value = Settings.get_volume(bus)
	# Refresh key labels
	for action in REBINDABLE_ACTIONS:
		var btn: Button = $Dim/Center/Panel/VBox/RebindSection/VBox.get_node_or_null(action + "Button")
		if btn:
			_refresh_button_label(btn, action)
	($Dim/Center/Panel/VBox/Master/Slider as HSlider).grab_focus()


func _on_value_changed(value: float, bus: String) -> void:
	Settings.set_volume(bus, value)
	(_rows[bus].get_node("Value") as Label).text = "%d%%" % roundi(value * 100.0)


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
		# Cancel on mouse click outside
		_cancel_rebind()


func _apply_rebind(event: InputEventKey) -> void:
	var action := _rebinding_action
	# Remove old key events, add new one
	var events := InputMap.action_get_events(action)
	for e in events:
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)
	_refresh_button_label(_rebinding_button, action)
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
