extends Control

var p1_joined: bool = false
var p2_joined: bool = false
var p1_position: String = "centre"
var p2_position: String = "centre"
var p1_confirmed: bool = false
var p2_confirmed: bool = false
var p1_using_keyboard: bool = false
var p2_using_keyboard: bool = false

var p1_axis_moved: bool = false
var p2_axis_moved: bool = false

@onready var p1_icon: Control = $P1Icon
@onready var p2_icon: Control = $P2Icon
@onready var start_label: Label = $StartLabel
@onready var left_column: Control = $LeftColumn
@onready var centre_column: Control = $CentreColumn
@onready var right_column: Control = $RightColumn

# References to child labels within icons
@onready var p1_controller_icon: Label = $P1Icon/ControllerIcon
@onready var p1_ready_label: Label = $P1Icon/ReadyLabel
@onready var p2_controller_icon: Label = $P2Icon/ControllerIcon
@onready var p2_ready_label: Label = $P2Icon/ReadyLabel

func _ready() -> void:
	p1_icon.visible = false
	p2_icon.visible = false
	start_label.visible = false
	# Ensure ready labels exist and are hidden
	p1_ready_label.visible = false
	p2_ready_label.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.device == 0 and event.pressed:
		p1_using_keyboard = false
		_update_p1_icon()
		_handle_p1_button(event.button_index)
	if event is InputEventJoypadMotion and event.device == 0:
		_handle_p1_axis(event)

	if event is InputEventJoypadButton and event.device == 1 and event.pressed:
		p2_using_keyboard = false
		_update_p2_icon()
		_handle_p2_button(event.button_index)
	if event is InputEventJoypadMotion and event.device == 1:
		_handle_p2_axis(event)

	if event is InputEventKey and event.pressed:
		_handle_keyboard(event)

func _handle_p1_button(button: int) -> void:
	if button == JOY_BUTTON_A:
		if not p1_joined:
			p1_joined = true
			_move_icon(p1_icon, centre_column, -80.0)
			p1_icon.visible = true
			return
		if p1_position == "centre":
			return
		if not p1_confirmed:
			p1_confirmed = true
			p1_ready_label.visible = true
			_update_start_label()
			_check_start()
		return
	if button == JOY_BUTTON_B:
		if p1_confirmed:
			p1_confirmed = false
			p1_ready_label.visible = false
			_update_start_label()
		elif p1_position != "centre":
			p1_position = "centre"
			_move_icon(p1_icon, centre_column, -80.0)
			_update_start_label()

func _handle_p1_axis(event: InputEventJoypadMotion) -> void:
	if not p1_joined:
		return
	if abs(event.axis_value) < 0.5:
		p1_axis_moved = false
		return
	if p1_axis_moved:
		return
	if event.axis == JOY_AXIS_LEFT_X:
		p1_axis_moved = true
		if event.axis_value < -0.5 and p1_position != "left":
			p1_confirmed = false
			p1_ready_label.visible = false
			p1_position = "left"
			_move_icon(p1_icon, left_column, -80.0)
			_update_start_label()
		elif event.axis_value > 0.5 and p1_position != "right":
			p1_confirmed = false
			p1_ready_label.visible = false
			p1_position = "right"
			_move_icon(p1_icon, right_column, -80.0)
			_update_start_label()

func _handle_p2_button(button: int) -> void:
	if button == JOY_BUTTON_A:
		if not p2_joined:
			p2_joined = true
			_move_icon(p2_icon, centre_column, 80.0)
			p2_icon.visible = true
			return
		if p2_position == "centre":
			return
		if not p2_confirmed:
			p2_confirmed = true
			p2_ready_label.visible = true
			_update_start_label()
			_check_start()
		return
	if button == JOY_BUTTON_B:
		if p2_confirmed:
			p2_confirmed = false
			p2_ready_label.visible = false
			_update_start_label()
		elif p2_position != "centre":
			p2_position = "centre"
			_move_icon(p2_icon, centre_column, 80.0)
			_update_start_label()

func _handle_p2_axis(event: InputEventJoypadMotion) -> void:
	if not p2_joined:
		return
	if abs(event.axis_value) < 0.5:
		p2_axis_moved = false
		return
	if p2_axis_moved:
		return
	if event.axis == JOY_AXIS_LEFT_X:
		p2_axis_moved = true
		if event.axis_value < -0.5 and p2_position != "left":
			p2_confirmed = false
			p2_ready_label.visible = false
			p2_position = "left"
			_move_icon(p2_icon, left_column, 80.0)
			_update_start_label()
		elif event.axis_value > 0.5 and p2_position != "right":
			p2_confirmed = false
			p2_ready_label.visible = false
			p2_position = "right"
			_move_icon(p2_icon, right_column, 80.0)
			_update_start_label()

func _handle_keyboard(event: InputEventKey) -> void:
	match event.keycode:
		KEY_A:
			if not p1_joined:
				p1_joined = true
				p1_using_keyboard = true
				_move_icon(p1_icon, centre_column, -80.0)
				p1_icon.visible = true
				_update_p1_icon()
				return
			if p1_position != "left":
				p1_confirmed = false
				p1_ready_label.visible = false
				p1_position = "left"
				_move_icon(p1_icon, left_column, -80.0)
				_update_start_label()
		KEY_D:
			if p1_joined and p1_position != "right":
				p1_confirmed = false
				p1_ready_label.visible = false
				p1_position = "right"
				_move_icon(p1_icon, right_column, -80.0)
				_update_start_label()
		KEY_SPACE:
			if not p1_joined:
				p1_joined = true
				p1_using_keyboard = true
				_move_icon(p1_icon, centre_column, -80.0)
				p1_icon.visible = true
				_update_p1_icon()
				return
			if p1_position != "centre" and not p1_confirmed:
				p1_confirmed = true
				p1_ready_label.visible = true
				_update_start_label()
				_check_start()
		KEY_LEFT:
			if not p2_joined:
				p2_joined = true
				p2_using_keyboard = true
				_move_icon(p2_icon, centre_column, 80.0)
				p2_icon.visible = true
				_update_p2_icon()
				return
			if p2_position != "left":
				p2_confirmed = false
				p2_ready_label.visible = false
				p2_position = "left"
				_move_icon(p2_icon, left_column, 80.0)
				_update_start_label()
		KEY_RIGHT:
			if p2_joined and p2_position != "right":
				p2_confirmed = false
				p2_ready_label.visible = false
				p2_position = "right"
				_move_icon(p2_icon, right_column, 80.0)
				_update_start_label()
		KEY_ENTER, KEY_KP_ENTER:
			if not p2_joined:
				p2_joined = true
				p2_using_keyboard = true
				_move_icon(p2_icon, centre_column, 80.0)
				p2_icon.visible = true
				_update_p2_icon()
				return
			if p2_position != "centre" and not p2_confirmed:
				p2_confirmed = true
				p2_ready_label.visible = true
				_update_start_label()
				_check_start()

func _update_p1_icon() -> void:
	p1_controller_icon.text = "⌨" if p1_using_keyboard else "🎮"

func _update_p2_icon() -> void:
	p2_controller_icon.text = "⌨" if p2_using_keyboard else "🎮"

func _move_icon(icon: Control, column: Control, v_offset: float = 0.0) -> void:
	if icon.get_parent() != null:
		icon.get_parent().remove_child(icon)
	column.add_child(icon)
	icon.position = Vector2(
		(column.size.x - icon.size.x) / 2.0,
		column.size.y / 2.0 - icon.size.y / 2.0 + v_offset
	)

func _update_start_label() -> void:
	var p1_in_column: bool = p1_joined and p1_position != "centre"
	var p2_in_column: bool = p2_joined and p2_position != "centre"
	start_label.visible = p1_in_column or p2_in_column

func _check_start() -> void:
	var p1_ready: bool = p1_joined and p1_position != "centre" and p1_confirmed
	var p2_ready: bool = not p2_joined or (p2_position != "centre" and p2_confirmed)

	if not p1_ready:
		return
	if not p2_ready:
		return

	GameState.team_a_player = 1 if (p1_position == "left" or p2_position == "left") else 0
	GameState.team_b_player = 1 if (p1_position == "right" or p2_position == "right") else 0
	GameState.p1_team = "A" if p1_position == "left" else "B"
	GameState.p2_team = "A" if p2_position == "left" else "B" if p2_joined else ""

	GameState.reset_score()
	GameState.return_scene = "res://Scenes/pitch.tscn"
	GameState.contest_reason = "kickoff"
	GameState.go_to_scene("res://Scenes/main.tscn")
