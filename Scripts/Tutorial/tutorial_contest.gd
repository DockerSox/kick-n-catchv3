extends Node2D
# TutorialContest — scripted sandbagged contest minigame.
#
# 4-label sub-flow: each substep's text appears in one of four corner-margin
# labels and persists until the contest ends. As new substeps advance, older
# substep labels dim to 50% alpha (current substep stays at 100%).
#
# Layout (margins around the centred contest viewport):
#   LeftTopText      = 1a "USE THE LEFT THUMBSTICK TO AIM"
#   LeftBottomText   = 1b "PRESS A TO JUMP"
#   RightTopText     = 1c "THE BALL LAUNCHES UP THEN FALLS DOWN"
#   RightBottomText  = 1d "THE FIRST UNIT TO TOUCH THE BALL WINS"
#
# When called with suppress_text=true (second contest), skips all sub-steps
# and instructional text. Just plays the contest directly.
 
signal contest_finished(winner: String)
 
const TEAM_A_COLOR: Color = Color(0.41568628, 0.050980393, 0.6784314, 1)
const TEAM_B_COLOR: Color = Color(0.8, 0.26666668, 0.8, 1)
 
const SCRIPTED_BALL_VY: float = -400.0
const AI_LAUNCH_DELAY_BASE: float = 0.8
const AI_BAD_ANGLE: float = 30.0
 
# Sub-flow tuning
const PAUSE_BALL_NEAR_TOP_Y: float = 80.0
const SUBSTEP_1A_ADVANCE_DELAY: float = 2.0
const SUBSTEP_1C_ADVANCE_DELAY: float = 2.0
const SUBSTEP_1D_PAUSE_BEFORE_RESUME: float = 2.0
 
# Alpha values
const ALPHA_CURRENT: float = 1.0
const ALPHA_DIMMED: float = 0.5
 
# Sub-flow text
const TEXT_1A: String = "USE THE LEFT THUMBSTICK\nTO AIM"
const TEXT_1B: String = "PRESS A TO JUMP"
const TEXT_1C: String = "THE BALL LAUNCHES UP\nTHEN FALLS DOWN"
const TEXT_1D: String = "THE FIRST UNIT TO\nTOUCH THE BALL WINS"
 
@onready var ball: Area2D = $SubViewportContainer/SubViewport/Ball
@onready var paddle_left: Area2D = $SubViewportContainer/SubViewport/ContestUnitA
@onready var paddle_right: Area2D = $SubViewportContainer/SubViewport/ContestUnitB
@onready var win_label: Label = $SubViewportContainer/SubViewport/UI/WinLabel
 
# 4-label sub-flow text labels (added in scene editor, see chunk 7c notes)
@onready var label_1a: Label = $LeftTopText
@onready var label_1b: Label = $LeftBottomText
@onready var label_1c: Label = $RightTopText
@onready var label_1d: Label = $RightBottomText

var _player_team: String = "A"
var _player_input_id: String = "joy0"
var _sandbag_strength: float = 1.0
var _suppress_text: bool = false
var _game_over: bool = false
var _ai_launch_armed: bool = false
var _ball_paused_at_top: bool = false
var _saved_ball_velocity: Vector2 = Vector2.ZERO
 
func _ready() -> void:
	add_to_group("tutorial_contest")
	win_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_label.visible = false
 
	# Configure the 4 new sub-flow labels with consistent styling. We use
	# LabelSettings (same as tutorial_ui.gd) to bypass scene-level theme overrides.
	for lbl in [label_1a, label_1b, label_1c, label_1d]:
		if lbl != null:
			var settings: LabelSettings = LabelSettings.new()
			settings.font_size = 36
			settings.font_color = Color(1, 1, 1, 1)
			settings.line_spacing = -8.0
			lbl.label_settings = settings
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			lbl.visible = false
			lbl.modulate.a = ALPHA_CURRENT
 
	ball.paddle_hit.connect(_on_paddle_hit)
	ball.hit_bottom.connect(_on_ball_hit_bottom)
 
# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func start_scripted_contest(player_input_id: String, player_team: String,
		sandbag_strength: float = 1.0, suppress_text: bool = false) -> void:
	_player_input_id = player_input_id
	_player_team = player_team
	_sandbag_strength = sandbag_strength
	_suppress_text = suppress_text
	_game_over = false
 
	$SubViewportContainer/SubViewport.handle_input_locally = false
 
	if _suppress_text:
		await _start_round_silent()
	else:
		await _start_round_with_subflow()
 
# ---------------------------------------------------------------------------
# Tutorial sub-flow (first contest only)
# ---------------------------------------------------------------------------
func _start_round_with_subflow() -> void:
	_setup_round()
 
	paddle_left.activate()
	paddle_right.activate()
 
	# Reset all sub-flow labels.
	for lbl in [label_1a, label_1b, label_1c, label_1d]:
		if lbl != null:
			lbl.visible = false
			lbl.modulate.a = ALPHA_CURRENT
 
	# 1a: "USE THE LEFT THUMBSTICK TO AIM" - wait for player to rotate, then 1s.
	_show_substep_label(label_1a, TEXT_1A)
	var player_paddle: Area2D = _get_player_paddle()
	var starting_angle: float = player_paddle.aim_angle_deg
	while is_instance_valid(player_paddle) and not _game_over \
			and abs(player_paddle.aim_angle_deg - starting_angle) < 0.5:
		await get_tree().process_frame
	if _game_over: return
	await get_tree().create_timer(SUBSTEP_1A_ADVANCE_DELAY, false).timeout
	if _game_over: return
 
	# 1b: "PRESS A TO JUMP" - wait for player to launch + paddle returns.
	_dim_label(label_1a)
	_show_substep_label(label_1b, TEXT_1B)
	var paddle_left_start: bool = false  # has paddle clearly left start position?
	while is_instance_valid(player_paddle) and not _game_over:
		# Detect "left start": position.y is meaningfully above start (paddle is in flight).
		if player_paddle.position.y < player_paddle.start_position.y - 30.0:
			paddle_left_start = true
		# Detect "returned": position.y back at or near start AFTER having left.
		if paddle_left_start \
				and player_paddle.position.y >= player_paddle.start_position.y - 1.0:
			paddle_left.activate()
			paddle_right.activate()
			break
		await get_tree().process_frame
	if _game_over: return
 
	# 1c: "THE BALL LAUNCHES UP THEN FALLS DOWN" - text appears, brief pause,
	# THEN launch ball.
	_dim_label(label_1b)
	_show_substep_label(label_1c, TEXT_1C)
	# Brief pause so player reads the text before the ball moves.
	await get_tree().create_timer(1.0, false).timeout
	if _game_over: return
	_ball_paused_at_top = false
	_launch_scripted_ball()
	# Wait for ball to peak (start falling: velocity.y > 0), then pause it.
	# This way the player sees the up-arc AND the start of the down-arc
	# before the freeze.
	var ball_has_peaked: bool = false
	while is_instance_valid(ball) and not _game_over:
		if ball.active and ball.velocity.y > 0.0:
			ball_has_peaked = true
		# Pause when ball is on the way DOWN and nearing the top region.
		if ball_has_peaked and ball.position.y <= PAUSE_BALL_NEAR_TOP_Y * 1.5:
			_saved_ball_velocity = ball.velocity
			ball.velocity = Vector2.ZERO
			ball.active = false
			_ball_paused_at_top = true
			break
		await get_tree().process_frame
	if _game_over: return
	await get_tree().create_timer(SUBSTEP_1C_ADVANCE_DELAY, false).timeout
	if _game_over: return
 
	# 1d: "THE FIRST UNIT TO TOUCH THE BALL WINS" - 1s pause.
	_dim_label(label_1c)
	_show_substep_label(label_1d, TEXT_1D)
	await get_tree().create_timer(SUBSTEP_1D_PAUSE_BEFORE_RESUME, false).timeout
	if _game_over: return

	# Show "GO!" in centre of contest viewport, brief flash that fades to
	# semi-transparent and persists.
	# Find tutorial UI to call show_persistent_centre_text.
	var tut_ui = get_tree().get_first_node_in_group("tutorial_ui")
	if tut_ui != null and tut_ui.has_method("show_persistent_centre_text"):
		tut_ui.show_persistent_centre_text("GO!", Color(1, 1, 1, 1), 0.2, 0.15, 80)

	# Resume ball physics.
	ball.velocity = _saved_ball_velocity
	ball.active = true
	_ball_paused_at_top = false
 
	# All four labels remain visible. 1a/1b/1c at 50%, 1d at 100%.
	# Arm sandbag AI.
	_ai_launch_armed = true
	_ai_launch_loop_after_pause()
 
func _ai_launch_loop_after_pause() -> void:
	await get_tree().create_timer(AI_LAUNCH_DELAY_BASE * _sandbag_strength, false).timeout
	if _game_over or not _ai_launch_armed:
		return
	var ai_paddle: Area2D = _get_ai_paddle()
	if is_instance_valid(ai_paddle) and ai_paddle.state == ai_paddle.State.AIMING:
		ai_paddle.aim_angle_deg = AI_BAD_ANGLE
		ai_paddle._launch()
 
# Show a label with the given text at full opacity.
func _show_substep_label(lbl: Label, text: String) -> void:
	if lbl == null:
		return
	lbl.text = text
	lbl.modulate.a = 0.0
	lbl.visible = true
	var t: Tween = create_tween()
	t.tween_property(lbl, "modulate:a", ALPHA_CURRENT, 0.25)
 
# Dim a label to ALPHA_DIMMED.
func _dim_label(lbl: Label) -> void:
	if lbl == null:
		return
	var t: Tween = create_tween()
	t.tween_property(lbl, "modulate:a", ALPHA_DIMMED, 0.25)
 
# Reset all labels to dimmed (for retry).
func _dim_all_labels() -> void:
	for lbl in [label_1a, label_1b, label_1c, label_1d]:
		if lbl != null and lbl.visible:
			var t: Tween = create_tween()
			t.tween_property(lbl, "modulate:a", ALPHA_DIMMED, 0.25)
 
# Hide all sub-flow labels.
func _hide_all_labels() -> void:
	for lbl in [label_1a, label_1b, label_1c, label_1d]:
		if lbl != null:
			lbl.visible = false
 
# ---------------------------------------------------------------------------
# Silent round (second contest, or retries)
# ---------------------------------------------------------------------------
func _start_round_silent() -> void:
	_setup_round()
	await get_tree().create_timer(1.0, false).timeout
	# Keep labels at their current state (dimmed) for retries; for true silent
	# (suppress_text=true), they'd already be hidden.
	_launch_scripted_ball()
	paddle_left.activate()
	paddle_right.activate()
	_ai_launch_armed = true
	_ai_launch_loop()
 
func _ai_launch_loop() -> void:
	while _ai_launch_armed and is_instance_valid(ball) and not _game_over:
		if ball.active and ball.velocity.y > 0:
			break
		await get_tree().process_frame
	if _game_over or not _ai_launch_armed:
		return
	await get_tree().create_timer(AI_LAUNCH_DELAY_BASE * _sandbag_strength, false).timeout
	if _game_over or not _ai_launch_armed:
		return
	var ai_paddle: Area2D = _get_ai_paddle()
	if is_instance_valid(ai_paddle) and ai_paddle.state == ai_paddle.State.AIMING:
		ai_paddle.aim_angle_deg = AI_BAD_ANGLE
		ai_paddle._launch()
 
# ---------------------------------------------------------------------------
# Round setup (shared)
# ---------------------------------------------------------------------------
func _setup_round() -> void:
	_game_over = false
	_ai_launch_armed = false
	_ball_paused_at_top = false
 
	ball.position = Vector2(230.0, 233.0)
	ball.velocity = Vector2.ZERO
	ball.active = false
 
	paddle_left.start_position = Vector2(80.0, 640.0)
	paddle_left.position = paddle_left.start_position
	paddle_right.start_position = Vector2(380.0, 640.0)
	paddle_right.position = paddle_right.start_position
	paddle_left.set_paddle_color(TEAM_A_COLOR)
	paddle_right.set_paddle_color(TEAM_B_COLOR)
 
	if _player_team == "A":
		_setup_player_paddle(paddle_left, _player_input_id)
		_setup_sandbag_paddle(paddle_right)
		paddle_left.set_player_label("P1")
		paddle_right.set_player_label("")
	else:
		_setup_player_paddle(paddle_right, _player_input_id)
		_setup_sandbag_paddle(paddle_left)
		paddle_right.set_player_label("P1")
		paddle_left.set_player_label("")
 
func _setup_player_paddle(paddle: Area2D, input_id: String) -> void:
	paddle.is_ai = false
	paddle.ball_ref = null
	match input_id:
		"kb0":
			paddle.move_left_action = "kb0_left"
			paddle.move_right_action = "kb0_right"
			paddle.launch_action = "kb0_confirm"
		"kb1":
			paddle.move_left_action = "kb1_left"
			paddle.move_right_action = "kb1_right"
			paddle.launch_action = "kb1_confirm"
		_:
			var n: String = input_id.substr(3)
			paddle.move_left_action = "joy_aim_left_" + n
			paddle.move_right_action = "joy_aim_right_" + n
			paddle.launch_action = "joy_kick_" + n
 
func _setup_sandbag_paddle(paddle: Area2D) -> void:
	paddle.is_ai = false
	paddle.ball_ref = null
	paddle.move_left_action = ""
	paddle.move_right_action = ""
	paddle.launch_action = ""
 
func _launch_scripted_ball() -> void:
	ball.velocity = Vector2(0.0, SCRIPTED_BALL_VY)
	ball.active = true
 
func _get_player_paddle() -> Area2D:
	return paddle_left if _player_team == "A" else paddle_right
 
func _get_ai_paddle() -> Area2D:
	return paddle_right if _player_team == "A" else paddle_left
 
# ---------------------------------------------------------------------------
# Outcome handlers
# ---------------------------------------------------------------------------
func _on_paddle_hit(area: Area2D) -> void:
	if _game_over:
		return
	if area == paddle_left:
		_end_contest("A")
	elif area == paddle_right:
		_end_contest("B")
 
func _on_ball_hit_bottom() -> void:
	if _game_over:
		return
	await _try_again()
 
func _try_again() -> void:
	# Dim all sub-flow labels to indicate retry mode.
	_dim_all_labels()
	# Clear GO! if it's showing.
	var tut_ui = get_tree().get_first_node_in_group("tutorial_ui")
	if tut_ui != null and tut_ui.has_method("clear_persistent_centre_text"):
		tut_ui.clear_persistent_centre_text()
	win_label.text = "TRY AGAIN"
	win_label.visible = true
	await get_tree().create_timer(2.0, false).timeout
	if _game_over:
		return
	win_label.visible = false
	# Retry uses the silent flow (no sub-step transitions).
	await _start_round_silent()
 
func _end_contest(winner: String) -> void:
	if _game_over:
		return
	_game_over = true
	_ai_launch_armed = false
 
	paddle_left.state = paddle_left.State.WAITING
	paddle_right.state = paddle_right.State.WAITING
	paddle_left.velocity = Vector2.ZERO
	paddle_right.velocity = Vector2.ZERO
	ball.active = false
	ball.velocity = Vector2.ZERO
 
	var msg: String = "YOU WIN!" if winner == _player_team else "OPPONENT WINS"
	win_label.text = msg
	win_label.visible = true
	_hide_all_labels()
	# Clear the GO! text if it's still showing.
	var tut_ui = get_tree().get_first_node_in_group("tutorial_ui")
	if tut_ui != null and tut_ui.has_method("clear_persistent_centre_text"):
		tut_ui.clear_persistent_centre_text()
 
	await get_tree().create_timer(2.0, false).timeout
	win_label.visible = false
	contest_finished.emit(winner)
 
