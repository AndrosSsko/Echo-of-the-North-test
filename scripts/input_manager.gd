extends Node

# Emitted when the user switches between Keyboard/Mouse and Controller
signal input_device_changed(is_gamepad: bool)

const ACTION_TAKEDOWN: String = "takedown"
const ACTION_THROW_BOLA: String = "throw_bola"
const ACTION_THROW_PEBBLE: String = "throw_pebble"
const ACTION_INTERACT: String = "interact"

var is_gamepad: bool = false

func _input(event: InputEvent) -> void:
	# Detect if the event type changed to update the UI prompt style
	var event_is_gamepad: bool = (event is InputEventJoypadButton or event is InputEventJoypadMotion)
	
	if event_is_gamepad != is_gamepad:
		is_gamepad = event_is_gamepad
		input_device_changed.emit(is_gamepad)

# Returns a clean string representing the key or button for a specific action
func get_action_button_text(action_name: String) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action_name)
	
	# Fallback if the action isn't defined
	if events.is_empty():
		return "[?]"
		
	# Find the first event that matches the currently active device
	for event in events:
		if is_gamepad and event is InputEventJoypadButton:
			return _format_gamepad_button(event)
		elif not is_gamepad and event is InputEventKey:
			return _format_keyboard_key(event)
			
	return "[?]"

# Internal helper to clean up controller button strings
func _format_gamepad_button(event: InputEventJoypadButton) -> String:
	var button_name: String = event.as_text()
	# Strip "Joypad Button" prefix for a cleaner UI look (e.g., "Button 0" -> "0")
	button_name = button_name.replace("Joypad Button ", "")
	# Handle parentheses that appear in some OS configurations
	if "(" in button_name:
		button_name = button_name.split("(")[0].strip_edges()
	return "[" + button_name.to_upper() + "]"

# Internal helper to clean up keyboard key strings
func _format_keyboard_key(event: InputEventKey) -> String:
	var key_name: String = OS.get_keycode_string(event.physical_keycode)
	if key_name == "Space": key_name = "Spacebar"
	return "[" + key_name + "]"
