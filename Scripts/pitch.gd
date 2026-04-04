extends Node2D

@onready var units_a: Node2D = $UnitsA
@onready var units_b: Node2D = $UnitsB
@onready var crosshair: Node2D = $Crosshair
@onready var score_label: Label = $UI/ScoreLabel
@onready var pause_menu: Control = $UI/PauseMenu
@onready var camera: Camera2D = $Camera2D
@onready var goal_square_a: ColorRect = $GoalSquareA
@onready var goal_square_b: ColorRect = $GoalSquareB
@onready var arrow_left: Label = $UI/ArrowLeft
@onready var arrow_right: Label = $UI/ArrowRight
@onready var match_end_label: Label = $UI/MatchEndLabel

var attacking_team: String = "A"
var aiming_unit: Node2D = null
var all_units_a: Array = []
var all_units_b: Array = []
var camera_target: Vector2 = Vector2.ZERO

const CAMERA_SPEED: float = 3.0
const PITCH_W: float = 2400.0
const PITCH_H: float = 900.0

const POSITIONS_A: Dictionary = {
	"centre":  Vector2(1150, 450),
	"goalie":  Vector2(250, 450),
	"winger":  Vector2(800, 150),
	"defence": Vector2(900, 450),
	"attack":  Vector2(600, 450)
}
const POSITIONS_B: Dictionary = {
	"centre":  Vector2(1250, 450),
	"goalie":  Vector2(2150, 450),
	"winger":  Vector2(1600, 750),
	"defence": Vector2(1500, 450),
	"attack":  Vector2(1800, 450)
}

func _ready() -> void:
	all_units_a = units_a.get_children()
	all_units_b = units_b.get_children()

	for unit in all_units_a:
		unit.position = POSITIONS_A.get(unit.role, Vector2(1200, 450))
	for unit in units_b.get_children():
		unit.position = POSITIONS_B.get(unit.role, Vector2(1200, 450))

	_set_goalie_bounds()
	_set_forbidden_zones()

	$UI/PauseButton.pressed.connect(_on_pause)
	$UI/PauseMenu/ResumeButton.pressed.connect(_on_resume)
	$UI/PauseMenu/QuitButton.pressed.connect(_on_quit)

	if GameState.return_scene == "res://Scenes/pitch.tscn":
		GameState.return_scene = ""
		attacking_team = GameState.contest_winner if GameState.contest_winner != "" else "A"
		GameState.attacking_team = attacking_team
		if GameState.contest_reason == "clash" or GameState.contest_reason == "no_unit":
			var winning_units: Array = all_units_a if attacking_team == "A" else all_units_b
			var losing_units: Array = all_units_b if attacking_team == "A" else all_units_a
	
			# Move nearest winning unit to crosshair position
			var nearest_winner: Node2D = null
			var nearest_winner_dist: float = INF
			for unit in winning_units:
				var d: float = unit.position.distance_to(GameState.contest_crosshair_pos)
				if d < nearest_winner_dist:
					nearest_winner_dist = d
					nearest_winner = unit
			if nearest_winner != null:
				nearest_winner.position = GameState.contest_crosshair_pos

			# Move nearest losing unit to crosshair position as marking unit
			var nearest_loser: Node2D = null
			var nearest_loser_dist: float = INF
			for unit in losing_units:
				if unit.role == "goalie":
					continue
				var d: float = unit.position.distance_to(GameState.contest_crosshair_pos)
				if d < nearest_loser_dist:
					nearest_loser_dist = d
					nearest_loser = unit
			if nearest_loser != null:
				nearest_loser.position = GameState.contest_crosshair_pos

			set_aiming_unit(nearest_winner if nearest_winner != null else _get_centre_unit(attacking_team))
		else:
			set_aiming_unit(_get_centre_unit(attacking_team))
		update_score()
		_update_goal_arrow()
		return

	attacking_team = GameState.attacking_team if GameState.attacking_team != "" else "A"
	set_aiming_unit(_get_centre_unit(attacking_team))
	update_score()
	_update_goal_arrow()

func _process(delta: float) -> void:
	camera.position = camera.position.lerp(camera_target, CAMERA_SPEED * delta)

# --- Private/internal helpers ---

func _set_goalie_bounds() -> void:
	for unit in all_units_a + all_units_b:
		if unit.role == "goalie":
			var sq: ColorRect = goal_square_a if unit.team == "A" else goal_square_b
			# Use offset values which is how ColorRect stores position in Node2D scenes
			var rect_pos: Vector2 = Vector2(sq.offset_left, sq.offset_top)
			var rect_size: Vector2 = Vector2(sq.offset_right - sq.offset_left, sq.offset_bottom - sq.offset_top)
			unit.constrained = true
			unit.bounds_rect = Rect2(rect_pos, rect_size)

func _set_forbidden_zones() -> void:
	var goal_a_rect: Rect2 = Rect2(
		Vector2(goal_square_a.offset_left, goal_square_a.offset_top),
		Vector2(goal_square_a.offset_right - goal_square_a.offset_left,
				goal_square_a.offset_bottom - goal_square_a.offset_top)
	)
	var goal_b_rect: Rect2 = Rect2(
		Vector2(goal_square_b.offset_left, goal_square_b.offset_top),
		Vector2(goal_square_b.offset_right - goal_square_b.offset_left,
				goal_square_b.offset_bottom - goal_square_b.offset_top)
	)
	for unit in all_units_a + all_units_b:
		if unit.role != "goalie":
			unit.forbidden_rects = [goal_a_rect, goal_b_rect]

func _get_centre_unit(team: String) -> Node2D:
	var arr: Array = all_units_a if team == "A" else all_units_b
	for unit in arr:
		if unit.role == "centre":
			return unit
	return arr[0]

func _assign_defenders() -> void:
	var defending_units: Array = all_units_b if attacking_team == "A" else all_units_a
	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b

	# Clean up marker nodes
	for child in get_children():
		if child.name.ends_with("_target"):
			child.queue_free()

	# Reset all units
	for unit in defending_units:
		unit.is_defending = false
		unit.human_defending = false
		unit.assigned_target = null
	for unit in attacking_units:
		if unit != aiming_unit:
			unit.is_defending = false
			unit.assigned_target = null

	# Exclude attacking goalie from targets
	var targetable_attackers: Array = attacking_units.filter(
		func(u): return u.role != "goalie"
	)

	# Determine if defending team is human controlled
	var is_human_defending: bool = (attacking_team == "A" and GameState.team_b_player == 1) or \
								   (attacking_team == "B" and GameState.team_a_player == 1)

	# Find closest defender to aiming unit — they become the marker
	var marker_defender: Node2D = null
	var marker_dist: float = INF
	for defender in defending_units:
		if defender.role == "goalie":
			continue
		var d: float = defender.position.distance_to(aiming_unit.position)
		if d < marker_dist:
			marker_dist = d
			marker_defender = defender

	# Snap marker defender to defensive side of aiming unit
	if marker_defender != null:
		var defending_direction: float = -1.0 if attacking_team == "A" else 1.0
		marker_defender.position = aiming_unit.position + Vector2(defending_direction * 35.0, 0.0)
		# Marking unit is always AI controlled — never human
		marker_defender.set_as_defender(aiming_unit, false, "", "", "", "", 40.0)

	# Assign remaining defenders to remaining targetable attackers
	var remaining_defenders: Array = defending_units.filter(
		func(u): return u != marker_defender and u.role != "goalie"
	)
	var unassigned_attackers: Array = targetable_attackers.filter(
		func(u): return u != aiming_unit
	)

	var human_assigned: bool = false

	for defender in remaining_defenders:
		if unassigned_attackers.is_empty():
			break
		var nearest: Node2D = null
		var nearest_dist: float = INF
		for attacker in unassigned_attackers:
			var dist: float = defender.position.distance_to(attacker.position)  # was "d"
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = attacker
		if nearest == null:
			continue
		unassigned_attackers.erase(nearest)

		# Give human control to the first non-marker defender
		var give_human: bool = is_human_defending and not human_assigned
		if give_human:
			human_assigned = true
			var prefix: String = "p2_aim" if attacking_team == "A" else "p1_aim"
			defender.set_as_defender(nearest, true,
				prefix + "_up", prefix + "_down",
				prefix + "_left", prefix + "_right")
		else:
			defender.set_as_defender(nearest, false)

func _update_goal_arrow() -> void:
	var attacking_color: Color = Color.WHITE
	if aiming_unit != null:
		attacking_color = aiming_unit.unit_color

	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b
	var goalie: Node2D = null
	for unit in attacking_units:
		if unit.role == "goalie":
			goalie = unit
			break

	if goalie == null or aiming_unit == null:
		arrow_left.visible = false
		arrow_right.visible = false
		return

	if goalie.position.x < aiming_unit.position.x:
		arrow_left.visible = true
		arrow_right.visible = false
		arrow_left.add_theme_color_override("font_color", attacking_color)
	else:
		arrow_left.visible = false
		arrow_right.visible = true
		arrow_right.add_theme_color_override("font_color", attacking_color)

func _score_goal(team: String) -> void:
	if team == "A":
		GameState.score_a += 1
	else:
		GameState.score_b += 1
	update_score()

	if GameState.score_a >= 2 or GameState.score_b >= 2:
		_end_match()
	else:
		await get_tree().create_timer(1.5).timeout
		_reset_positions()

func _reset_positions() -> void:
	for unit in all_units_a:
		unit.position = POSITIONS_A.get(unit.role, Vector2(1200, 450))
	for unit in all_units_b:
		unit.position = POSITIONS_B.get(unit.role, Vector2(1200, 450))
	GameState.return_scene = "res://Scenes/pitch.tscn"
	GameState.contest_reason = "kickoff"
	GameState.go_to_scene("res://Scenes/main.tscn")

func _end_match() -> void:
	var winner_text: String = "Team A Wins!" if GameState.score_a >= 2 else "Team B Wins!"
	match_end_label.text = winner_text
	match_end_label.visible = true
	match_end_label.process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().create_timer(3.0).timeout
	GameState.reset_score()
	GameState.go_to_scene("res://Scenes/title.tscn")

# --- Signal callbacks ---

func _on_pause() -> void:
	get_tree().paused = true
	pause_menu.visible = true

func _on_resume() -> void:
	get_tree().paused = false
	pause_menu.visible = false

func _on_quit() -> void:
	get_tree().paused = false
	GameState.go_to_scene("res://Scenes/title.tscn")

# --- Public functions called by other nodes ---

func set_aiming_unit(unit: Node2D) -> void:
	if aiming_unit != null:
		aiming_unit.set_as_aiming(false)
	aiming_unit = unit
	aiming_unit.set_as_aiming(true)

	# Set camera target with clamping
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_w: float = (viewport_size.x / 2.0) / camera.zoom.x
	var half_h: float = (viewport_size.y / 2.0) / camera.zoom.y
	camera_target = aiming_unit.position
	camera_target.x = clamp(camera_target.x, half_w, PITCH_W - half_w)
	camera_target.y = clamp(camera_target.y, half_h, PITCH_H - half_h)

	crosshair.position = aiming_unit.position
	crosshair.activate(aiming_unit)
	_assign_defenders()
	_update_goal_arrow()

func update_score() -> void:
	score_label.text = str(GameState.score_a) + " - " + str(GameState.score_b)

func on_kick_resolved(winning_team: String, resolve_position: Vector2) -> void:
	attacking_team = winning_team
	GameState.attacking_team = winning_team

	var goal_a_rect: Rect2 = Rect2(
		Vector2(goal_square_a.offset_left, goal_square_a.offset_top),
		Vector2(goal_square_a.offset_right - goal_square_a.offset_left,
				goal_square_a.offset_bottom - goal_square_a.offset_top)
	)
	var goal_b_rect: Rect2 = Rect2(
		Vector2(goal_square_b.offset_left, goal_square_b.offset_top),
		Vector2(goal_square_b.offset_right - goal_square_b.offset_left,
				goal_square_b.offset_bottom - goal_square_b.offset_top)
	)

	if winning_team == "A" and goal_a_rect.has_point(resolve_position):
		_score_goal("A")
		return
	elif winning_team == "B" and goal_b_rect.has_point(resolve_position):
		_score_goal("B")
		return

	var winning_units: Array = all_units_a if winning_team == "A" else all_units_b
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for unit in winning_units:
		var d: float = unit.position.distance_to(resolve_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = unit
	set_aiming_unit(nearest)
