extends Control

func _ready() -> void:
	$StartButton.pressed.connect(_on_start)
	$BackButton.pressed.connect(_on_back)

func _on_start() -> void:
	GameState.team_a_player = 1 if $TeamAOption.selected == 0 else 0
	GameState.team_b_player = 1 if $TeamBOption.selected == 0 else 0
	GameState.reset_score()
	# First thing is a Contest Game to decide who attacks first
	GameState.go_to_scene("res://Scenes/main.tscn")

func _on_back() -> void:
	GameState.go_to_scene("res://Scenes/title.tscn")
