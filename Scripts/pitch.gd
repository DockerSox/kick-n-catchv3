extends Node2D

# --- Node references ---
@onready var units_a: Node2D = $UnitsA
@onready var units_b: Node2D = $UnitsB
@onready var crosshair: Node2D = $Crosshair
@onready var score_label: Label = $UI/ScoreLabel
@onready var pause_menu: Control = $UI/PauseMenu
@onready var camera: Camera2D = $Camera2D
@onready var goal_square_a: ColorRect = $GoalSquareA
@onready var goal_square_b: ColorRect = $GoalSquareB

# --- Game state ---
var attacking_team: String = "A"
var aiming_unit: Node2D = null
var all_units_a: Array = []
var all_units_b: Array = []

# Pitch dimensions
const PITCH_W: float = 2400.0
const PITCH_H: float = 900.0

# Team A attacks left goal square, starts on right half
# Team B attacks right goal square, starts on left half
const POSITIONS_A: Dictionary = {
	"centre":  Vector2(1200, 450),
	"goalie":  Vector2(250, 450),
	"winger":  Vector2(800, 150),
	"defence":     Vector2(900, 450),
	"attack":     Vector2(600, 450)
}
const POSITIONS_B: Dictionary = {
	"centre":  Vector2(1200, 450),
	"goalie":  Vector2(2150, 450),
	"winger":  Vector2(1600, 750),
	"defence":     Vector2(1500, 450),
	"attack":     Vector2(1800, 450)
}

func _ready() -> void:
	# Collect unit arrays
	all_units_a = units_a.get_children()
	all_units_b = units_b.get_children()

	# Position all units
	for unit in all_units_a:
		unit.position = POSITIONS_A.get(unit.role, Vector2(1200, 450))
	for unit in units_b.get_children():
		unit.position = POSITIONS_B.get(unit.role, Vector2(1200, 450))

	# Set goalie constraints
	_set_goalie_bounds()

	# Connect pause button
	$UI/PauseButton.pressed.connect(_on_pause)
	$UI/PauseMenu/ResumeButton.pressed.connect(_on_resume)
	$UI/PauseMenu/QuitButton.pressed.connect(_on_quit)

	# Determine attacking team from GameState
	attacking_team = GameState.attacking_team if GameState.attacking_team != "" else "A"

# Handle returning from a Contest Game
	if GameState.return_scene == "res://Scenes/pitch.tscn":
		GameState.return_scene = ""
		attacking_team = GameState.contest_winner if GameState.contest_winner != "" else "A"
		GameState.attacking_team = attacking_team
		GameState.return_scene = ""
		if GameState.contest_reason == "clash" or GameState.contest_reason == "no_unit":
			attacking_team = GameState.contest_winner
			GameState.attacking_team = GameState.contest_winner
			# Find nearest unit to contest position on winning team
			var winning_units: Array = all_units_a if attacking_team == "A" else all_units_b
			var nearest: Node2D = null
			var nearest_dist: float = INF
			for unit in winning_units:
				var d: float = unit.position.distance_to(GameState.contest_crosshair_pos)
				if d < nearest_dist:
					nearest_dist = d
					nearest = unit
			if nearest != null:
				nearest.position = GameState.contest_crosshair_pos
			_set_aiming_unit(nearest if nearest != null else _get_centre_unit(attacking_team))
			_update_score()
			return
	
	
	# Start the game
	_set_aiming_unit(_get_centre_unit(attacking_team))
	_update_score()

func _set_goalie_bounds() -> void:
	for unit in all_units_a + all_units_b:
		if unit.role == "goalie":
			var sq: ColorRect = goal_square_a if unit.team == "A" else goal_square_b
			unit.constrained = true
			unit.bounds_rect = Rect2(sq.position, sq.size)

func _get_centre_unit(team: String) -> Node2D:
	var arr: Array = all_units_a if team == "A" else all_units_b
	for unit in arr:
		if unit.role == "centre":
			return unit
	return arr[0]

func _set_aiming_unit(unit: Node2D) -> void:
	# Clear previous aiming unit
	if aiming_unit != null:
		aiming_unit.set_as_aiming(false)
	aiming_unit = unit
	aiming_unit.set_as_aiming(true)
	# Move camera toward aiming unit
	camera.position = aiming_unit.position
	# Activate crosshair at aiming unit's position
	crosshair.position = aiming_unit.position
	crosshair.activate(aiming_unit)

func _update_score() -> void:
	score_label.text = str(GameState.score_a) + " - " + str(GameState.score_b)

func _on_pause() -> void:
	get_tree().paused = true
	pause_menu.visible = true

func _on_resume() -> void:
	get_tree().paused = false
	pause_menu.visible = false

func _on_quit() -> void:
	get_tree().paused = false
	GameState.go_to_scene("res://Scenes/title.tscn")

# Called by Crosshair when a kick resolves
func on_kick_resolved(winning_team: String, resolve_position: Vector2) -> void:
	attacking_team = winning_team
	GameState.attacking_team = winning_team

	# Check if resolved position is inside a goal square
	var goal_a_rect: Rect2 = Rect2(goal_square_a.position, goal_square_a.size)
	var goal_b_rect: Rect2 = Rect2(goal_square_b.position, goal_square_b.size)

	if winning_team == "A" and goal_a_rect.has_point(resolve_position):
		_score_goal("A")
		return
	elif winning_team == "B" and goal_b_rect.has_point(resolve_position):
		_score_goal("B")
		return

	# Find the new aiming unit — nearest on winning team to resolve_position
	var winning_units: Array = all_units_a if winning_team == "A" else all_units_b
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for unit in winning_units:
		var d: float = unit.position.distance_to(resolve_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = unit
	_set_aiming_unit(nearest)

func _score_goal(team: String) -> void:
	if team == "A":
		GameState.score_a += 1
	else:
		GameState.score_b += 1
	_update_score()

	if GameState.score_a >= 2 or GameState.score_b >= 2:
		_end_match()
	else:
		# Reset positions and restart
		await get_tree().create_timer(1.5).timeout
		_reset_positions()

func _reset_positions() -> void:
	for unit in all_units_a:
		unit.position = POSITIONS_A.get(unit.role, Vector2(800, 1200))
	for unit in all_units_b:
		unit.position = POSITIONS_B.get(unit.role, Vector2(800, 1200))
	# Contest game to decide who attacks after reset
	GameState.return_scene = "res://Scenes/pitch.tscn"
	GameState.contest_reason = "kickoff"
	GameState.go_to_scene("res://Scenes/main.tscn")

func _end_match() -> void:
	var _winner: String = "Team A Wins!" if GameState.score_a >= 2 else "Team B Wins!"
	# For now just go back to title after delay
	await get_tree().create_timer(3.0).timeout
	GameState.reset_score()
	GameState.go_to_scene("res://Scenes/title.tscn")
