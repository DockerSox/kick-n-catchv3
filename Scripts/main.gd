extends Node2D

@onready var ball: Area2D = $SubViewportContainer/SubViewport/Ball
@onready var paddle_left: Area2D = $SubViewportContainer/SubViewport/ContestUnitA
@onready var paddle_right: Area2D = $SubViewportContainer/SubViewport/ContestUnitB

@onready var win_label: Label = $SubViewportContainer/SubViewport/UI/WinLabel

var game_over: bool = false

func _ready() -> void:
	win_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ball.paddle_hit.connect(_on_paddle_hit)
	ball.hit_bottom.connect(_on_ball_hit_bottom)
	await _start_round()

func _start_round() -> void:
	game_over = false
	ball.position = Vector2(230.0, 233.0)
	ball.velocity = Vector2.ZERO
	ball.active = false

	paddle_left.start_position = Vector2(80, 640.0)
	paddle_left.position = paddle_left.start_position
	paddle_right.start_position = Vector2(380.0, 640.0)
	paddle_right.position = paddle_right.start_position

	# Left paddle is always Team A, right paddle is always Team B.
	var players_a: Array = GameState.get_players_on_team("A")
	var players_b: Array = GameState.get_players_on_team("B")

	# Find which player controls their team's contest paddle.
	# contest_player_index holds the attacking team's relevant player.
	var left_input_id: String = ""
	var right_input_id: String = ""

	if GameState.contest_player_index >= 0 and \
	   GameState.contest_player_index < GameState.players.size():
		var cp = GameState.players[GameState.contest_player_index]
		if cp["team"] == "A":
			left_input_id = cp["input_id"]
		elif cp["team"] == "B":
			right_input_id = cp["input_id"]

	# Fallback: first player on each team if not already set
	if left_input_id == "" and players_a.size() > 0:
		left_input_id = players_a[0]["input_id"]
	if right_input_id == "" and players_b.size() > 0:
		right_input_id = players_b[0]["input_id"]

	_setup_paddle(paddle_left, left_input_id)
	_setup_paddle(paddle_right, right_input_id)

	paddle_left.set_paddle_color(_get_team_color("A"))
	paddle_right.set_paddle_color(_get_team_color("B"))

	var left_label: String = ""
	if left_input_id != "":
		var n: int = _get_player_num_for_input(left_input_id)
		if n > 0:
			left_label = "P" + str(n)
	paddle_left.set_player_label(left_label)

	var right_label: String = ""
	if right_input_id != "":
		var n: int = _get_player_num_for_input(right_input_id)
		if n > 0:
			right_label = "P" + str(n)
	paddle_right.set_player_label(right_label)

	await get_tree().create_timer(1.0).timeout
	ball.launch()
	paddle_left.activate()
	paddle_right.activate()

	$SubViewportContainer/SubViewport.handle_input_locally = false

func _get_player_num_for_input(input_id: String) -> int:
	for i in range(GameState.players.size()):
		if GameState.players[i]["input_id"] == input_id:
			return i + 1
	return 0

func _setup_paddle(paddle: Area2D, input_id: String) -> void:
	if input_id == "":
		# AI-controlled paddle
		paddle.is_ai = true
		paddle.ball_ref = ball
		paddle.move_left_action = ""
		paddle.move_right_action = ""
		paddle.launch_action = ""
		return

	paddle.is_ai = false
	paddle.ball_ref = null
	match input_id:
		"kb0":
			paddle.move_left_action  = "kb0_left"
			paddle.move_right_action = "kb0_right"
			paddle.launch_action     = "kb0_confirm"
		"kb1":
			paddle.move_left_action  = "kb1_left"
			paddle.move_right_action = "kb1_right"
			paddle.launch_action     = "kb1_confirm"
		_:
			var n: String = input_id.substr(3)
			paddle.move_left_action  = "joy_aim_left_"  + n
			paddle.move_right_action = "joy_aim_right_" + n
			paddle.launch_action     = "joy_kick_"      + n

func _get_team_color(team: String) -> Color:
	if team == "A":
		return Color(0.42, 0.05, 0.68, 1)
	return Color(0.8, 0.27, 0.8, 1)

func _on_ball_hit_bottom() -> void:
	if game_over:
		return
	await _try_again()

func _try_again() -> void:
	win_label.text = "TRY AGAIN"
	win_label.visible = true
	await get_tree().create_timer(2.0).timeout
	win_label.visible = false
	await _start_round()

func _on_paddle_hit(area: Area2D) -> void:
	if game_over:
		return
	if area == paddle_left:
		_end_game("A")
	elif area == paddle_right:
		_end_game("B")

func _end_game(winner: String) -> void:
	if game_over:
		return
	game_over = true

	paddle_left.state = paddle_left.State.WAITING
	paddle_right.state = paddle_right.State.WAITING
	paddle_left.velocity = Vector2.ZERO
	paddle_right.velocity = Vector2.ZERO
	ball.active = false
	ball.velocity = Vector2.ZERO

	var message: String = "Team A Wins!" if winner == "A" else "Team B Wins!"
	win_label.text = message
	win_label.visible = true
	GameState.contest_winner = winner

	if GameState.return_scene != "":
		await get_tree().create_timer(2.0).timeout
		GameState.go_to_scene(GameState.return_scene)
	else:
		get_tree().paused = true
