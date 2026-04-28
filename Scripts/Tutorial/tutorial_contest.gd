extends Node2D
# TutorialContest — scripted sandbagged contest minigame.
#
# Mirrors main.gd's scene structure exactly (same paths, same UI). The only
# differences:
#   - Ball is launched with a scripted velocity instead of randomised
#   - One paddle is sandbagged: launches late with a poor angle so player wins
#   - InstructionText (a direct child of root, OUTSIDE the SubViewport) shows
#     "USE THE LEFT THUMBSTICK TO AIM AND A TO JUMP" etc.
#   - On contest end, emits contest_finished signal instead of changing scenes.
 
signal contest_finished(winner: String)
 
const TEAM_A_COLOR: Color = Color(0.41568628, 0.050980393, 0.6784314, 1)
const TEAM_B_COLOR: Color = Color(0.8, 0.26666668, 0.8, 1)
 
# Ball trajectory tuning.
# Live ball.launch() makes the ball exit the top for ~0.2-0.8s. We want it to
# JUST barely peek above the viewport top (peak at y≈33), keeping the ball
# visible for almost all of its flight.
const SCRIPTED_BALL_VY: float = -400.0
 
# AI sandbag: how long after the ball starts falling before the AI launches.
const AI_LAUNCH_DELAY_BASE: float = 0.8
 
# AI bad angle: very oblique, won't reach a centred falling ball.
const AI_BAD_ANGLE: float = 30.0
 
@onready var ball: Area2D = $SubViewportContainer/SubViewport/Ball
@onready var paddle_left: Area2D = $SubViewportContainer/SubViewport/ContestUnitA
@onready var paddle_right: Area2D = $SubViewportContainer/SubViewport/ContestUnitB
@onready var win_label: Label = $SubViewportContainer/SubViewport/UI/WinLabel
@onready var instruction_text_right: Label = $RightInstructionText
@onready var instruction_text_left: Label = $LeftInstructionText
 
var _player_team: String = "A"
var _player_input_id: String = "joy0"
var _sandbag_strength: float = 1.0
var _game_over: bool = false
var _ai_launch_armed: bool = false
 
func _ready() -> void:
	win_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_label.visible = false
	if instruction_text_right != null:
		instruction_text_right.visible = false
	if instruction_text_left != null:
		instruction_text_left.visible = false

	ball.paddle_hit.connect(_on_paddle_hit)
	ball.hit_bottom.connect(_on_ball_hit_bottom)
 
# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func start_scripted_contest(player_input_id: String, player_team: String,
		sandbag_strength: float = 1.0) -> void:
	_player_input_id = player_input_id
	_player_team = player_team
	_sandbag_strength = sandbag_strength
	_game_over = false
 
	# Right side: explanation of the contest mechanic.
	instruction_text_right.text = "THE BALL LAUNCHES UP\nTHEN FALLS DOWN\n\n" \
		+ "THE FIRST UNIT\nTO TOUCH THE BALL\nWINS"
	instruction_text_right.visible = true

	# Left side: how-to-play prompt.
	instruction_text_left.text = "USE THE LEFT THUMBSTICK\nTO AIM\n\n" \
		+ "PRESS A TO JUMP"
	instruction_text_left.visible = true
 
	# Show "CONTEST!" using WinLabel (reusing as live game does for messages).
	win_label.text = "CONTEST!"
	win_label.visible = true
	await get_tree().create_timer(2.0).timeout
	win_label.visible = false
 
	# Make sure SubViewport accepts input.
	$SubViewportContainer/SubViewport.handle_input_locally = false
 
	await _start_round()
 
func _start_round() -> void:
	_game_over = false
	_ai_launch_armed = false
 
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
 
	# Activate paddles immediately so the player can aim, but DON'T launch
	# the ball until they've actually moved the thumbstick.
	paddle_left.activate()
	paddle_right.activate()

	# Determine which paddle is the player's so we can watch its aim_angle.
	var player_paddle: Area2D = paddle_left if _player_team == "A" else paddle_right
	var starting_angle: float = player_paddle.aim_angle_deg

	# Wait for the player to begin aiming.
	while is_instance_valid(player_paddle) \
			and abs(player_paddle.aim_angle_deg - starting_angle) < 0.5 \
			and not _game_over:
		await get_tree().process_frame
	if _game_over:
		return

	# Player has aimed. Launch the ball.
	_launch_scripted_ball()
	_ai_launch_armed = true
	_ai_launch_loop()
 
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
	# Disable contest_unit's built-in auto-AI; we manually trigger launch.
	paddle.is_ai = false
	paddle.ball_ref = null
	paddle.move_left_action = ""
	paddle.move_right_action = ""
	paddle.launch_action = ""
 
func _launch_scripted_ball() -> void:
	# Override ball.launch's randomisation. Set velocity directly.
	ball.velocity = Vector2(0.0, SCRIPTED_BALL_VY)
	ball.active = true
 
func _ai_launch_loop() -> void:
	# Wait for ball to start falling.
	while _ai_launch_armed and is_instance_valid(ball) and not _game_over:
		if ball.active and ball.velocity.y > 0:
			break
		await get_tree().process_frame
	if _game_over or not _ai_launch_armed:
		return
 
	# Sandbag delay.
	await get_tree().create_timer(AI_LAUNCH_DELAY_BASE * _sandbag_strength).timeout
	if _game_over or not _ai_launch_armed:
		return
 
	# Launch the AI paddle with a deliberately poor angle.
	var ai_paddle: Area2D = paddle_right if _player_team == "A" else paddle_left
	if is_instance_valid(ai_paddle) and ai_paddle.state == ai_paddle.State.AIMING:
		ai_paddle.aim_angle_deg = AI_BAD_ANGLE
		ai_paddle._launch()
 
# ---------------------------------------------------------------------------
# Outcome handlers (mirror main.gd structure)
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
	win_label.text = "TRY AGAIN"
	win_label.visible = true
	await get_tree().create_timer(2.0).timeout
	win_label.visible = false
	await _start_round()
 
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
 
	# Show winner message.
	var msg: String = "YOU WIN!" if winner == _player_team else "OPPONENT WINS"
	win_label.text = msg
	win_label.visible = true
	instruction_text_right.visible = false
	instruction_text_left.visible = false
 
	await get_tree().create_timer(2.0).timeout
	win_label.visible = false
	contest_finished.emit(winner)
 
