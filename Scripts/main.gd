extends Node2D

@onready var ball: Area2D = $SubViewportContainer/SubViewport/Ball
@onready var paddle_left: Area2D = $SubViewportContainer/SubViewport/ContestUnitA
@onready var paddle_right: Area2D = $SubViewportContainer/SubViewport/ContestUnitB
@onready var win_label: Label = $SubViewportContainer/SubViewport/UI/WinLabel

var game_over: bool = false

@export var two_player: bool = true

func _ready() -> void:
	win_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ball.paddle_hit.connect(_on_paddle_hit)
	ball.hit_bottom.connect(_on_ball_hit_bottom)
	await _start_round()

func _start_round() -> void:
	game_over = false
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
		_end_game("Player 1 Wins!", "A")
	elif area == paddle_right:
		if two_player:
			_end_game("Player 2 Wins!", "B")
		else:
			_end_game("CPU Wins!", "B")

func _end_game(message: String, winner: String) -> void:
	if game_over:
		return
	game_over = true
	paddle_left.state = paddle_left.State.WAITING
	paddle_right.state = paddle_right.State.WAITING
	paddle_left.velocity = Vector2.ZERO
	paddle_right.velocity = Vector2.ZERO
	ball.active = false
	ball.velocity = Vector2.ZERO
	win_label.text = message
	win_label.visible = true
	GameState.contest_winner = winner
	if GameState.return_scene != "":
		await get_tree().create_timer(2.0).timeout
		GameState.go_to_scene(GameState.return_scene)
		# Do NOT clear return_scene here — pitch.gd reads and clears it
	else:
		get_tree().paused = true
