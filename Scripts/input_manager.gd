extends Node

# InputManager — registers all input actions at runtime so the Input Map
# does not need to be configured manually for gamepads 0-7.
#
# Action naming conventions:
#   kb0_*        WASD keyboard user
#   kb1_*        Arrow keys keyboard user
#   joy_*_N      Gamepad user N (0-7)
#
# Called once at startup before any scene loads.

func _ready() -> void:
	_clear_old_actions()
	_register_keyboard_user_0()
	_register_keyboard_user_1()
	for i in range(8):
		_register_gamepad_user(i)
	_register_global()

# ---------------------------------------------------------------------------

func _clear_old_actions() -> void:
	# Remove legacy p1_/p2_ actions if present
	var legacy: Array = [
		"p1_left","p1_right","p1_launch","p1_aim_up","p1_aim_down",
		"p1_aim_left","p1_aim_right","p1_kick",
		"p2_left","p2_right","p2_launch","p2_aim_up","p2_aim_down",
		"p2_aim_left","p2_aim_right","p2_kick",
	]
	for action in legacy:
		if InputMap.has_action(action):
			InputMap.erase_action(action)

func _add_key(action: String, keycode: Key, physical: bool = false) -> void:
	var ev := InputEventKey.new()
	if physical:
		ev.physical_keycode = keycode
	else:
		ev.keycode = keycode
	InputMap.action_add_event(action, ev)

func _add_joy_button(action: String, device: int, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _add_joy_axis(action: String, device: int, axis: JoyAxis, positive: bool) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = 1.0 if positive else -1.0
	InputMap.action_add_event(action, ev)

func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	else:
		InputMap.action_erase_events(action)

# ---------------------------------------------------------------------------
# Keyboard user 0: WASD
# ---------------------------------------------------------------------------

func _register_keyboard_user_0() -> void:
	# Join (A key)
	_ensure("kb0_join")
	_add_key("kb0_join", KEY_A)

	# Movement in lobby
	_ensure("kb0_left")
	_add_key("kb0_left", KEY_A)
	_ensure("kb0_right")
	_add_key("kb0_right", KEY_D)

	# Aim (used on pitch)
	_ensure("kb0_aim_left")
	_add_key("kb0_aim_left", KEY_A)
	_ensure("kb0_aim_right")
	_add_key("kb0_aim_right", KEY_D)
	_ensure("kb0_aim_up")
	_add_key("kb0_aim_up", KEY_W)
	_ensure("kb0_aim_down")
	_add_key("kb0_aim_down", KEY_S)

	# Confirm / kick
	_ensure("kb0_confirm")
	_add_key("kb0_confirm", KEY_SPACE)
	_ensure("kb0_kick")
	_add_key("kb0_kick", KEY_SPACE)

	# Secondary action
	_ensure("kb0_secondary")
	_add_key("kb0_secondary", KEY_Q)

# ---------------------------------------------------------------------------
# Keyboard user 1: Arrow keys
# ---------------------------------------------------------------------------

func _register_keyboard_user_1() -> void:
	# Join (Left arrow)
	_ensure("kb1_join")
	_add_key("kb1_join", KEY_LEFT)

	# Movement in lobby
	_ensure("kb1_left")
	_add_key("kb1_left", KEY_LEFT)
	_ensure("kb1_right")
	_add_key("kb1_right", KEY_RIGHT)

	# Aim
	_ensure("kb1_aim_left")
	_add_key("kb1_aim_left", KEY_LEFT)
	_ensure("kb1_aim_right")
	_add_key("kb1_aim_right", KEY_RIGHT)
	_ensure("kb1_aim_up")
	_add_key("kb1_aim_up", KEY_UP)
	_ensure("kb1_aim_down")
	_add_key("kb1_aim_down", KEY_DOWN)

	# Confirm / kick
	_ensure("kb1_confirm")
	_add_key("kb1_confirm", KEY_ENTER)
	_add_key("kb1_confirm", KEY_KP_ENTER)
	_ensure("kb1_kick")
	_add_key("kb1_kick", KEY_ENTER)
	_add_key("kb1_kick", KEY_KP_ENTER)

	# Secondary action — physical Left Shift
	_ensure("kb1_secondary")
	_add_key("kb1_secondary", KEY_SHIFT, true)

# ---------------------------------------------------------------------------
# Gamepad user N
# ---------------------------------------------------------------------------

func _register_gamepad_user(n: int) -> void:
	var s: String = str(n)

	_ensure("joy_join_" + s)
	_add_joy_button("joy_join_" + s, n, JOY_BUTTON_A)

	_ensure("joy_aim_left_" + s)
	_add_joy_axis("joy_aim_left_" + s, n, JOY_AXIS_LEFT_X, false)
	_ensure("joy_aim_right_" + s)
	_add_joy_axis("joy_aim_right_" + s, n, JOY_AXIS_LEFT_X, true)
	_ensure("joy_aim_up_" + s)
	_add_joy_axis("joy_aim_up_" + s, n, JOY_AXIS_LEFT_Y, false)
	_ensure("joy_aim_down_" + s)
	_add_joy_axis("joy_aim_down_" + s, n, JOY_AXIS_LEFT_Y, true)

	_ensure("joy_confirm_" + s)
	_add_joy_button("joy_confirm_" + s, n, JOY_BUTTON_A)
	_ensure("joy_kick_" + s)
	_add_joy_button("joy_kick_" + s, n, JOY_BUTTON_A)

	# Secondary: LB (button 4) AND B button (button 1) both work as cancel
	_ensure("joy_secondary_" + s)
	_add_joy_button("joy_secondary_" + s, n, JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("joy_secondary_" + s, n, JOY_BUTTON_B)

# ---------------------------------------------------------------------------
# Global
# ---------------------------------------------------------------------------

func _register_global() -> void:
	_ensure("Pause")
	_add_key("Pause", KEY_ESCAPE)
	for i in range(8):
		_add_joy_button("Pause", i, JOY_BUTTON_BACK)
		_add_joy_button("Pause", i, JOY_BUTTON_START)
