extends Control

const MAX_PLAYERS: int = 8
const MAX_PER_TEAM: int = 4
const COUNTDOWN_DURATION: float = 3.0

class PlayerSlot:
	var input_id: String = ""
	var player_num: int = 0
	var team: String = ""
	var confirmed: bool = false
	var icon: Control = null

var slots: Array = []
var counting_down: bool = false
var countdown_timer: float = -1.0
var _axis_moved: Dictionary = {}

@onready var left_column: Control = $LeftColumn
@onready var right_column: Control = $RightColumn
@onready var centre_column: Control = $CentreColumn
@onready var start_label: Label = $StartLabel

func _ready() -> void:
	start_label.visible = false

func _process(delta: float) -> void:
	_poll_all_inputs()
	if counting_down:
		countdown_timer -= delta
		var secs: int = ceili(countdown_timer)
		start_label.text = "Starting in " + str(max(secs, 1)) + "..."
		if countdown_timer <= 0.0:
			_launch_game()

# ---------------------------------------------------------------------------
# Input polling
# ---------------------------------------------------------------------------

func _poll_all_inputs() -> void:
	_poll_kb0()
	_poll_kb1()
	for i in range(8):
		_poll_gamepad(i)
	# Check if any unjoined input interrupts the countdown
	if counting_down:
		_check_unjoined_interrupt()

func _poll_kb0() -> void:
	var id: String = "kb0"
	if not _is_joined(id):
		if Input.is_action_just_pressed("kb0_join") or \
		   Input.is_action_just_pressed("kb0_confirm") or \
		   Input.is_action_just_pressed("kb0_secondary"):
			_on_join(id)
		return

	if counting_down:
		if Input.is_action_just_pressed("kb0_secondary"):
			_on_secondary_during_countdown(id)
		return

	if Input.is_action_just_pressed("kb0_left"):
		_on_move(id, "A")
	elif Input.is_action_just_pressed("kb0_right"):
		_on_move(id, "B")

	if Input.is_action_just_pressed("kb0_confirm"):
		_on_confirm(id)
	elif Input.is_action_just_pressed("kb0_secondary"):
		_on_secondary(id)

func _poll_kb1() -> void:
	var id: String = "kb1"
	if not _is_joined(id):
		if Input.is_action_just_pressed("kb1_join") or \
		   Input.is_action_just_pressed("kb1_confirm") or \
		   Input.is_action_just_pressed("kb1_secondary"):
			_on_join(id)
		return

	if counting_down:
		if Input.is_action_just_pressed("kb1_secondary"):
			_on_secondary_during_countdown(id)
		return

	if Input.is_action_just_pressed("kb1_left"):
		_on_move(id, "A")
	elif Input.is_action_just_pressed("kb1_right"):
		_on_move(id, "B")

	if Input.is_action_just_pressed("kb1_confirm"):
		_on_confirm(id)
	elif Input.is_action_just_pressed("kb1_secondary"):
		_on_secondary(id)

func _poll_gamepad(device: int) -> void:
	if not Input.is_joy_known(device):
		return
	var id: String = "joy" + str(device)

	if not _is_joined(id):
		if Input.is_action_just_pressed("joy_join_" + str(device)):
			_on_join(id)
		return

	if counting_down:
		if Input.is_action_just_pressed("joy_secondary_" + str(device)):
			_on_secondary_during_countdown(id)
		return

	var axis_val: float = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var moved: bool = _axis_moved.get(id, false)
	if abs(axis_val) < 0.5:
		_axis_moved[id] = false
	elif not moved:
		_axis_moved[id] = true
		if axis_val < 0:
			_on_move(id, "A")
		else:
			_on_move(id, "B")

	if Input.is_action_just_pressed("joy_confirm_" + str(device)):
		_on_confirm(id)
	elif Input.is_action_just_pressed("joy_secondary_" + str(device)):
		_on_secondary(id)

# ---------------------------------------------------------------------------
# Countdown interrupt from unjoined inputs
# ---------------------------------------------------------------------------

func _check_unjoined_interrupt() -> void:
	if not _is_joined("kb0") and _any_kb0_just_pressed():
		_stop_countdown()
		return
	if not _is_joined("kb1") and _any_kb1_just_pressed():
		_stop_countdown()
		return
	for device in range(8):
		if not Input.is_joy_known(device):
			continue
		var joy_id: String = "joy" + str(device)
		if not _is_joined(joy_id) and Input.is_action_just_pressed("joy_join_" + str(device)):
			_stop_countdown()
			return

func _any_kb0_just_pressed() -> bool:
	return Input.is_action_just_pressed("kb0_join") or \
		   Input.is_action_just_pressed("kb0_confirm") or \
		   Input.is_action_just_pressed("kb0_secondary")

func _any_kb1_just_pressed() -> bool:
	return Input.is_action_just_pressed("kb1_join") or \
		   Input.is_action_just_pressed("kb1_confirm") or \
		   Input.is_action_just_pressed("kb1_secondary")

# ---------------------------------------------------------------------------
# Lobby actions
# ---------------------------------------------------------------------------

func _on_join(input_id: String) -> void:
	if slots.size() >= MAX_PLAYERS:
		return
	var slot := PlayerSlot.new()
	slot.input_id = input_id
	slot.player_num = slots.size() + 1
	slot.team = ""
	slot.confirmed = false
	slot.icon = _create_icon(slot.player_num, input_id)
	slots.append(slot)
	_place_icon_in_column(slot.icon, centre_column)

func _on_move(input_id: String, team: String) -> void:
	var slot: PlayerSlot = _get_slot(input_id)
	if slot == null or slot.confirmed:
		return
	if team == slot.team:
		return
	if _team_count(team) >= MAX_PER_TEAM:
		return
	slot.team = team
	var col: Control = left_column if team == "A" else right_column
	_place_icon_in_column(slot.icon, col)

func _on_confirm(input_id: String) -> void:
	var slot: PlayerSlot = _get_slot(input_id)
	if slot == null or slot.team == "" or slot.confirmed:
		return
	slot.confirmed = true
	_update_icon_ready(slot)
	_try_start_countdown()

func _on_secondary(input_id: String) -> void:
	var slot: PlayerSlot = _get_slot(input_id)
	if slot == null:
		return
	if slot.confirmed:
		slot.confirmed = false
		_update_icon_ready(slot)
		return
	if slot.team != "":
		slot.team = ""
		_place_icon_in_column(slot.icon, centre_column)
		return
	# Remove from lobby
	slot.icon.queue_free()
	slots.erase(slot)
	_renumber_slots()

func _on_secondary_during_countdown(input_id: String) -> void:
	var slot: PlayerSlot = _get_slot(input_id)
	if slot == null:
		return
	slot.confirmed = false
	_update_icon_ready(slot)
	_stop_countdown()

# ---------------------------------------------------------------------------
# Countdown
# ---------------------------------------------------------------------------

func _try_start_countdown() -> void:
	if counting_down or slots.is_empty():
		return
	for s in slots:
		if not s.confirmed:
			return
	counting_down = true
	countdown_timer = COUNTDOWN_DURATION
	start_label.visible = true

func _stop_countdown() -> void:
	counting_down = false
	countdown_timer = -1.0
	start_label.visible = false

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

func _launch_game() -> void:
	counting_down = false
	GameState.players = []
	for slot in slots:
		GameState.players.append({
			"input_id": slot.input_id,
			"team": slot.team,
			"unit_role": ""
		})
	GameState.reset_score()
	GameState.return_scene = "res://Scenes/pitch.tscn"
	GameState.contest_reason = "kickoff"
	GameState.go_to_scene("res://Scenes/main.tscn")

# ---------------------------------------------------------------------------
# Icon helpers
# ---------------------------------------------------------------------------

func _create_icon(player_num: int, input_id: String) -> Control:
	# Build icon entirely in code — do not use duplicate()
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(120, 110)

	var controller_icon := Label.new()
	controller_icon.text = "⌨" if (input_id == "kb0" or input_id == "kb1") else "🎮"
	controller_icon.add_theme_font_size_override("font_size", 36)
	controller_icon.add_theme_color_override("font_color", Color.WHITE)
	controller_icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	controller_icon.offset_top = 0
	controller_icon.offset_bottom = 48
	controller_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var player_label := Label.new()
	player_label.text = "P" + str(player_num)
	player_label.add_theme_font_size_override("font_size", 22)
	player_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	player_label.offset_top = 48
	player_label.offset_bottom = 78
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var ready_label := Label.new()
	ready_label.text = "READY"
	ready_label.add_theme_font_size_override("font_size", 18)
	ready_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ready_label.offset_top = 80
	ready_label.offset_bottom = 108
	ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_label.visible = false

	icon.add_child(controller_icon)  # index 0
	icon.add_child(player_label)     # index 1
	icon.add_child(ready_label)      # index 2

	add_child(icon)
	return icon

func _place_icon_in_column(icon: Control, column: Control) -> void:
	# Count icons already in this column, excluding the one being moved
	var count: int = 0
	for s in slots:
		if s.icon != null and s.icon != icon and s.icon.get_parent() == column:
			count += 1
	if icon.get_parent() != null:
		icon.get_parent().remove_child(icon)
	column.add_child(icon)
	# Position using column's global rect so layout_mode=0 columns work correctly
	var col_rect: Rect2 = column.get_rect()
	icon.position = Vector2(
		(col_rect.size.x - icon.size.x) / 2.0,
		130.0 + count * (icon.size.y + 8.0)
	)

func _update_icon_ready(slot: PlayerSlot) -> void:
	var ready_label: Label = slot.icon.get_child(2) as Label
	if ready_label:
		ready_label.visible = slot.confirmed

func _renumber_slots() -> void:
	for i in range(slots.size()):
		slots[i].player_num = i + 1
		var player_label: Label = slots[i].icon.get_child(1) as Label
		if player_label:
			player_label.text = "P" + str(i + 1)

# ---------------------------------------------------------------------------
# Slot helpers
# ---------------------------------------------------------------------------

func _get_slot(input_id: String) -> PlayerSlot:
	for s in slots:
		if s.input_id == input_id:
			return s
	return null

func _is_joined(input_id: String) -> bool:
	return _get_slot(input_id) != null

func _team_count(team: String) -> int:
	var count: int = 0
	for s in slots:
		if s.team == team:
			count += 1
	return count
