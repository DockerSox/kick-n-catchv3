extends Node2D

@onready var ball: Area2D = $SubViewportContainer/SubViewport/Ball
@onready var paddle_left: Area2D = $SubViewportContainer/SubViewport/ContestUnitA
@onready var paddle_right: Area2D = $SubViewportContainer/SubViewport/ContestUnitB
@onready var win_label: Label = $SubViewportContainer/SubViewport/UI/WinLabel

@export var two_player: bool = true  # false = Player vs CPU

func _ready() -> void:
	var screen: Vector2 = Vector2(460, 700)
	ball.position = Vector2(screen.x / 2.0, screen.y / 3.0)

	paddle_left.start_position = Vector2(80, 700.0 - 60.0)
	paddle_left.position = paddle_left.start_position
	paddle_right.start_position = Vector2(460.0 - 80, 700.0 - 60.0)
	paddle_right.position = paddle_right.start_position

	paddle_right.is_cpu = not two_player

	# Connect to the ball's own signal instead of area_entered directly
	ball.paddle_hit.connect(_on_paddle_hit)

	await get_tree().create_timer(1.0).timeout
	ball.launch()
	paddle_left.activate()
	paddle_right.activate()

	if not two_player:
		var cpu_delay: float = randf_range(1.0, 3.0)
		await get_tree().create_timer(cpu_delay).timeout
		paddle_right.cpu_launch()

	$SubViewportContainer/SubViewport.handle_input_locally = false
	
	win_label.set_anchor_and_offset(SIDE_LEFT, 0, 0)
	win_label.set_anchor_and_offset(SIDE_RIGHT, 1, 0)
	win_label.set_anchor_and_offset(SIDE_TOP, 0, 0)
	win_label.set_anchor_and_offset(SIDE_BOTTOM, 1, 0)

func _on_paddle_hit(area: Area2D) -> void:
	print("hit detected: ", area.name)
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
	await get_tree().process_frame
	get_tree().paused = true
