extends Node
# Boot — runs once at game launch, routes to tutorial or title based on
# Settings.tutorial_on_launch.
#
# This scene is the project's main_scene. It does no rendering or input —
# it just calls go_to_scene() and exits.
 
func _ready() -> void:
	# Defer one frame so autoloads are fully ready.
	await get_tree().process_frame
	if Settings.tutorial_on_launch:
		GameState.go_to_scene("res://Scenes/Tutorial/tutorial.tscn")
	else:
		GameState.go_to_scene("res://Scenes/title.tscn")
 
