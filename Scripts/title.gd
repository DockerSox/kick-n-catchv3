extends Control
 
func _ready() -> void:
	$PlayButton.pressed.connect(_on_play)
	$TutorialButton.pressed.connect(_on_tutorial)
	$OptionsButton.pressed.connect(_on_options)
	$ExitButton.pressed.connect(_on_exit)
	$PlayButton.grab_focus()
 
func _on_play() -> void:
	GameState.go_to_scene("res://Scenes/team_select.tscn")
 
func _on_tutorial() -> void:
	GameState.go_to_scene("res://Scenes/Tutorial/tutorial.tscn")
 
func _on_options() -> void:
	# Options popup — we'll build this later
	pass
 
func _on_exit() -> void:
	get_tree().quit()
 
