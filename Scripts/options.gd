extends Control
# Options menu — adjustable settings, accessed from the title screen.
#
# Adding a new option:
#   1. Add the control (CheckButton, OptionButton, HSlider etc.) to options.tscn
#   2. In _ready, connect its signal to a handler and initialise its value
#      from Settings.<field>.
#   3. In Settings.gd, add the corresponding field + setter (mirroring
#      tutorial_on_launch / set_tutorial_on_launch).

func _ready() -> void:
	# Tutorial toggle — reflects current Settings value.
	$TutorialOnLaunchToggle.button_pressed = Settings.tutorial_on_launch
	$TutorialOnLaunchToggle.toggled.connect(_on_tutorial_on_launch_toggled)

	# Back button.
	$BackButton.pressed.connect(_on_back)
	$BackButton.grab_focus()

func _input(event: InputEvent) -> void:
	# Cancel/B/Esc returns to title.
	if event.is_action_pressed("ui_cancel"):
		_on_back()

func _on_tutorial_on_launch_toggled(pressed: bool) -> void:
	Settings.set_tutorial_on_launch(pressed)

func _on_back() -> void:
	GameState.go_to_scene("res://Scenes/title.tscn")
