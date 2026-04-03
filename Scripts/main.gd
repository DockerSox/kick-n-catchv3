extends Node2D

@onready var ball: Area2D = $SubViewportContainer/SubViewport/Ball
@onready var paddle_left: Area2D = $SubViewportContainer/SubViewport/ContestUnitA
@onready var paddle_right: Area2D = $SubViewportContainer/SubViewport/ContestUnitB
@onready var win_label: Label = $SubViewportContainer/SubViewport/UI/WinLabel

@export var two_player: bool = true

func _ready() -> void:
	win_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ball.paddle_hit.connect(_on_paddle_hit)
	ball.hit_bottom.connect(_on_ball_hit_bottom)
	await _start_round()

func _start_round() -> void:
	var screen: Vector2 = Vector2(460, 700)

	ball.position = Vector2(screen.x / 2.0, screen.y / 3.0)
	ball.velocity = Vector2.ZERO
	ball.active = false

	paddle_left.start_position = Vector2(80, 640.0)
	paddle_left.position = paddle_left.start_position
	paddle_right.start_position = Vector2(380.0, 640.0)
	paddle_right.position = paddle_right.start_position
	paddle_right.is_cpu = not two_player

	await get_tree().create_timer(1.0).timeout
	ball.launch()
	paddle_left.activate()
	paddle_right.activate()

	if not two_player:
		var cpu_delay: float = randf_range(1.0, 3.0)
		await get_tree().create_timer(cpu_delay).timeout
		paddle_right.cpu_launch()

	$SubViewportContainer/SubViewport.handle_input_locally = false

func _on_ball_hit_bottom() -> void:
	var left_launched: bool = paddle_left.state == paddle_left.State.LAUNCHED
	var right_launched: bool = paddle_right.state == paddle_right.State.LAUNCHED
	if left_launched and right_launched:
		await _try_again()

func _try_again() -> void:
	win_label.text = "TRY AGAIN"
	win_label.visible = true
	await get_tree().create_timer(2.0).timeout
	win_label.visible = false
	await _start_round()

func _on_paddle_hit(area: Area2D) -> void:
	if area == paddle_left:
		_end_game("Player 1 Wins!")
	elif area == paddle_right:
		if two_player:
			_end_game("Player 2 Wins!")
		else:
			_end_game("CPU Wins!")

func _end_game(message: String) -> void:
	win_label.text = message
	win_label.visible = true
	# Store winner in GameState
	if message == "Player 1 Wins!":
		GameState.contest_winner = "A"
	elif message == "Player 2 Wins!" or message == "CPU Wins!":
		GameState.contest_winner = "B"
	# Wait 2 seconds then return to whatever scene called us
	await get_tree().create_timer(2.0).timeout
	if GameState.return_scene != "":
		GameState.go_to_scene(GameState.return_scene)
	else:
		get_tree().paused = true
