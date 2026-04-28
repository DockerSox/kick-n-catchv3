extends Control
# Temporary placeholder. Replaced by the real tutorial in chunk 3.
# Lets us verify the boot flow works without the full tutorial scene existing yet.
 
func _ready() -> void:
	$Label.text = "TUTORIAL PLACEHOLDER\n\nPress Esc to return to title"
 
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("Pause"):
		GameState.go_to_scene("res://Scenes/title.tscn")
 
