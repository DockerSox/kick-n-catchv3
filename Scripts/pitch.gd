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
@onready var defender_arrow: Label = $UI/DefenderArrow
@onready var goal_label: Label = $UI/GoalLabel

var human_defender: Node2D = null
var attacking_team: String = "A"
var aiming_unit: Node2D = null
var all_units_a: Array = []
var all_units_b: Array = []
var camera_target: Vector2 = Vector2.ZERO

var runner: Node2D = null
var dragger: Node2D = null
var prepper: Node2D = null
var rotation_cooldown: float = 0.0

const ROTATION_COOLDOWN_TIME: float = 2.0
var attack_update_timer: float = 0.0
const ATTACK_UPDATE_INTERVAL: float = 0.5
const CAMERA_SPEED: float = 3.0
const PITCH_W: float = 2400.0
const PITCH_H: float = 900.0

const POSITIONS_A: Dictionary = {
	"centre":  Vector2(1150, 450),
	"goalie":  Vector2(100, 450),    # centre of left goal square
	"winger":  Vector2(800, 150),
	"defence": Vector2(900, 450),
	"attack":  Vector2(600, 450)
}
const POSITIONS_B: Dictionary = {
	"centre":  Vector2(1250, 450),
	"goalie":  Vector2(2300, 450),   # centre of right goal square
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

	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	for child in pause_menu.get_children():
		child.process_mode = Node.PROCESS_MODE_ALWAYS
	$UI.process_mode = Node.PROCESS_MODE_ALWAYS

	if GameState.return_scene == "res://Scenes/pitch.tscn":
		GameState.return_scene = ""
		attacking_team = GameState.contest_winner if GameState.contest_winner != "" else "A"
		GameState.attacking_team = attacking_team
		if GameState.contest_reason == "clash" or GameState.contest_reason == "no_unit":
			var winning_units: Array = all_units_a if attacking_team == "A" else all_units_b
			var losing_units: Array = all_units_b if attacking_team == "A" else all_units_a

			var nearest_winner: Node2D = null
			var nearest_winner_dist: float = INF
			for unit in winning_units:
				if unit.role == "goalie":
					continue
				var d: float = unit.position.distance_to(GameState.contest_crosshair_pos)
				if d < nearest_winner_dist:
					nearest_winner_dist = d
					nearest_winner = unit
			if nearest_winner != null:
				nearest_winner.position = _safe_resolve_position(GameState.contest_crosshair_pos)

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
				nearest_loser.position = _safe_resolve_position(GameState.contest_crosshair_pos)

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
	_check_role_rotation()
	_update_defender_arrow()

# --- Private/internal helpers ---

func _get_goal_rect(sq: ColorRect) -> Rect2:
	return Rect2(
		Vector2(sq.offset_left, sq.offset_top),
		Vector2(sq.offset_right - sq.offset_left, sq.offset_bottom - sq.offset_top)
	)

func _safe_resolve_position(pos: Vector2) -> Vector2:
	var goal_a_rect: Rect2 = _get_goal_rect(goal_square_a)
	var goal_b_rect: Rect2 = _get_goal_rect(goal_square_b)
	for rect in [goal_a_rect, goal_b_rect]:
		if rect.has_point(pos):
			var dist_left: float = abs(pos.x - rect.position.x)
			var dist_right: float = abs(pos.x - rect.end.x)
			var dist_top: float = abs(pos.y - rect.position.y)
			var dist_bottom: float = abs(pos.y - rect.end.y)
			var min_dist: float = min(min(dist_left, dist_right), min(dist_top, dist_bottom))
			if min_dist == dist_left:
				return Vector2(rect.position.x - 20.0, pos.y)
			elif min_dist == dist_right:
				return Vector2(rect.end.x + 20.0, pos.y)
			elif min_dist == dist_top:
				return Vector2(pos.x, rect.position.y - 20.0)
			else:
				return Vector2(pos.x, rect.end.y + 20.0)
	return pos

func _set_goalie_bounds() -> void:
	for unit in all_units_a + all_units_b:
		if unit.role == "goalie":
			var sq: ColorRect = goal_square_a if unit.team == "A" else goal_square_b
			var rect: Rect2 = _get_goal_rect(sq)
			unit.position = rect.position + rect.size / 2.0
			unit.constrained = true
			unit.bounds_rect = rect
			unit.is_defending = false
			unit.assigned_target = null

func _set_forbidden_zones() -> void:
	var goal_a_rect: Rect2 = _get_goal_rect(goal_square_a)
	var goal_b_rect: Rect2 = _get_goal_rect(goal_square_b)
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
	human_defender = null
	var defending_units: Array = all_units_b if attacking_team == "A" else all_units_a
	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b

	for child in get_children():
		if child.name.ends_with("_target"):
			child.queue_free()

	for unit in defending_units:
		unit.is_defending = false
		unit.human_defending = false
		unit.assigned_target = null
		unit.set_human_defender_highlight(false)

	for unit in attacking_units:
		if unit != aiming_unit:
			unit.is_defending = false
			unit.assigned_target = null
			unit.attack_role = unit.AttackRole.NONE

	var targetable_attackers: Array = attacking_units.filter(
		func(u): return u.role != "goalie"
	)

	var is_human_defending: bool = (attacking_team == "A" and GameState.team_b_player == 1) or \
								   (attacking_team == "B" and GameState.team_a_player == 1)

	var marker_defender: Node2D = null
	var marker_dist: float = INF
	for defender in defending_units:
		if defender.role == "goalie":
			continue
		var d: float = defender.position.distance_to(aiming_unit.position)
		if d < marker_dist:
			marker_dist = d
			marker_defender = defender

	if marker_defender != null:
		var defending_direction: float = -1.0 if attacking_team == "A" else 1.0
		marker_defender.position = aiming_unit.position + Vector2(defending_direction * 35.0, 0.0)
		marker_defender.set_as_defender(aiming_unit, false, "", "", "", "", 40.0)

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
			var dist: float = defender.position.distance_to(attacker.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = attacker
		if nearest == null:
			continue
		unassigned_attackers.erase(nearest)

		var give_human: bool = is_human_defending and not human_assigned
		if give_human:
			human_assigned = true
			human_defender = defender
			var prefix: String = "p2_aim" if attacking_team == "A" else "p1_aim"
			defender.set_as_defender(nearest, true,
				prefix + "_up", prefix + "_down",
				prefix + "_left", prefix + "_right")
			defender.set_human_defender_highlight(true)
		else:
			defender.set_as_defender(nearest, false)
			defender.set_human_defender_highlight(false)

func _assign_attack_roles() -> void:
	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b
	var eligible: Array = attacking_units.filter(
		func(u): return u != aiming_unit and u.role != "goalie"
	)
	if eligible.size() < 3:
		return

	var goalie: Node2D = null
	for u in attacking_units:
		if u.role == "goalie":
			goalie = u
			break

	var ch_pos: Vector2 = crosshair.position
	eligible.sort_custom(func(a, b):
		return a.position.distance_to(ch_pos) < b.position.distance_to(ch_pos)
	)
	runner = eligible[0]

	var remaining: Array = [eligible[1], eligible[2]]
	if goalie != null:
		remaining.sort_custom(func(a, b):
			return a.position.distance_to(goalie.position) < b.position.distance_to(goalie.position)
		)
	dragger = remaining[0]
	prepper = remaining[1]

	_update_attack_targets()

func _update_attack_targets() -> void:
	if runner == null or dragger == null or prepper == null:
		return

	var ch_pos: Vector2 = crosshair.position
	var goalie: Node2D = null
	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b
	for u in attacking_units:
		if u.role == "goalie":
			goalie = u
			break

	runner.set_attack_role(runner.AttackRole.RUNNER, ch_pos)

	var in_defensive_half: bool
	if attacking_team == "A":
		in_defensive_half = aiming_unit.position.x > 1200.0
	else:
		in_defensive_half = aiming_unit.position.x < 1200.0

	var dragger_target: Vector2
	if goalie != null:
		if in_defensive_half:
			dragger_target = (prepper.position + goalie.position) / 2.0
		else:
			var top_point: Vector2 = Vector2(goalie.position.x, 0.0)
			dragger_target = (goalie.position + top_point) / 2.0
	else:
		dragger_target = dragger.position
	dragger.set_attack_role(dragger.AttackRole.DRAGGER, dragger_target)

	var prepper_target: Vector2
	if goalie != null:
		if in_defensive_half:
			var is_prepper_defensive: bool
			if attacking_team == "A":
				is_prepper_defensive = prepper.position.x > aiming_unit.position.x
			else:
				is_prepper_defensive = prepper.position.x < aiming_unit.position.x
			if is_prepper_defensive:
				prepper_target = goalie.position
			else:
				var defending_units: Array = all_units_b if attacking_team == "A" else all_units_a
				var nearest_def: Node2D = null
				var nearest_def_dist: float = INF
				for u in defending_units:
					var d: float = prepper.position.distance_to(u.position)
					if d < nearest_def_dist:
						nearest_def_dist = d
						nearest_def = u
				if nearest_def != null:
					var away_dir: Vector2 = (prepper.position - nearest_def.position).normalized()
					var target: Vector2 = prepper.position + away_dir * 200.0
					var offset: Vector2 = target - aiming_unit.position
					if offset.length() > crosshair.RADIUS_OUTER:
						offset = offset.normalized() * crosshair.RADIUS_OUTER
						target = aiming_unit.position + offset
					if attacking_team == "A":
						target.x = min(target.x, aiming_unit.position.x)
					else:
						target.x = max(target.x, aiming_unit.position.x)
					prepper_target = target
				else:
					prepper_target = prepper.position
		else:
			prepper_target = (goalie.position + Vector2(goalie.position.x, 900.0)) / 2.0
	else:
		prepper_target = prepper.position
	prepper.set_attack_role(prepper.AttackRole.PREPPER, prepper_target)

func _check_role_rotation() -> void:
	if runner == null or prepper == null:
		return

	if rotation_cooldown > 0.0:
		rotation_cooldown -= get_process_delta_time()

	var ch_pos: Vector2 = crosshair.position
	var runner_dist: float = runner.position.distance_to(ch_pos)
	var prepper_dist: float = prepper.position.distance_to(ch_pos)
	if prepper_dist < runner_dist and rotation_cooldown <= 0.0:
		on_runner_rotation_needed()
		return

	attack_update_timer += get_process_delta_time()
	if attack_update_timer >= ATTACK_UPDATE_INTERVAL:
		attack_update_timer = 0.0
		_update_attack_targets()

func on_runner_rotation_needed() -> void:
	rotation_cooldown = ROTATION_COOLDOWN_TIME
	var old_runner: Node2D = runner
	var old_dragger: Node2D = dragger
	var old_prepper: Node2D = prepper
	runner = old_prepper
	dragger = old_runner
	prepper = old_dragger
	if dragger != null:
		var away_dir: Vector2 = (dragger.position - crosshair.position).normalized()
		if away_dir == Vector2.ZERO:
			away_dir = Vector2(1.0, 0.0)
		dragger.position += away_dir * 30.0
	_update_attack_targets()

func _assign_post_kick_attack_roles(kick_pos: Vector2) -> void:
	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b
	var eligible: Array = attacking_units.filter(
		func(u): return u != aiming_unit and u.role != "goalie"
	)
	if eligible.size() < 1:
		return

	eligible.sort_custom(func(a, b):
		return a.position.distance_to(kick_pos) < b.position.distance_to(kick_pos)
	)

	var receiver: Node2D = eligible[0]
	receiver.set_attack_role(receiver.AttackRole.RUNNER, kick_pos)

	for i in range(1, eligible.size()):
		var unit: Node2D = eligible[i]
		var away_dir: Vector2 = (unit.position - kick_pos).normalized()
		if away_dir == Vector2.ZERO:
			away_dir = Vector2(1, 0)
		var away_pos: Vector2 = unit.position + away_dir * 300.0
		away_pos.x = clamp(away_pos.x, 50.0, PITCH_W - 50.0)
		away_pos.y = clamp(away_pos.y, 50.0, PITCH_H - 50.0)
		unit.set_attack_role(unit.AttackRole.DRAGGER, away_pos)

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
	# Determine which player scored
	var goal_text: String
	if team == "A":
		GameState.score_a += 1
		goal_text = "P1 GOAL!" if GameState.team_a_player == 1 else "TEAM A GOAL!"
	else:
		GameState.score_b += 1
		goal_text = "P2 GOAL!" if GameState.team_b_player == 1 else "TEAM B GOAL!"

	# Show goal text with brief freeze
	goal_label.text = goal_text
	goal_label.add_theme_color_override("font_color",
		aiming_unit.unit_color if aiming_unit != null else Color.WHITE)
	goal_label.visible = true
	get_tree().paused = true
	goal_label.process_mode = Node.PROCESS_MODE_ALWAYS

	await goal_label.get_tree().create_timer(1.5).timeout

	get_tree().paused = false
	goal_label.visible = false
	update_score()

	if GameState.score_a >= 2 or GameState.score_b >= 2:
		_end_match()
	else:
		await get_tree().create_timer(0.5).timeout
		_reset_positions()

func _reset_positions() -> void:
	for unit in all_units_a:
		unit.position = POSITIONS_A.get(unit.role, Vector2(1200, 450))
	for unit in all_units_b:
		unit.position = POSITIONS_B.get(unit.role, Vector2(1200, 450))
	_set_goalie_bounds()
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
	rotation_cooldown = 0.0
	if aiming_unit != null:
		aiming_unit.set_as_aiming(false)
	aiming_unit = unit
	aiming_unit.set_as_aiming(true)

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
	_assign_attack_roles()

func update_score() -> void:
	score_label.text = str(GameState.score_a) + " - " + str(GameState.score_b)

func on_kick_resolved(winning_team: String, resolve_position: Vector2, is_goal: bool = false) -> void:
	attacking_team = winning_team
	GameState.attacking_team = winning_team

	var safe_pos: Vector2 = _safe_resolve_position(resolve_position)

	if is_goal:
		_score_goal(winning_team)
		return

	var winning_units: Array = all_units_a if winning_team == "A" else all_units_b
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for unit in winning_units:
		if unit.role == "goalie":
			continue
		var d: float = unit.position.distance_to(safe_pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest = unit
	set_aiming_unit(nearest)

func on_kick_launched(kick_pos: Vector2) -> void:
	# All defenders move toward the kick position
	var defending_units: Array = all_units_b if attacking_team == "A" else all_units_a
	for unit in defending_units:
		if unit.role == "goalie":
			continue
		unit.set_attack_role(unit.AttackRole.RUNNER, kick_pos)

	# Find nearest attacking unit to crosshair and make them runner
	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b
	var eligible: Array = attacking_units.filter(
		func(u): return u != aiming_unit and u.role != "goalie"
	)

	if eligible.size() > 0:
		eligible.sort_custom(func(a, b):
			return a.position.distance_to(kick_pos) < b.position.distance_to(kick_pos)
		)
		var nearest: Node2D = eligible[0]
		# Override to runner without triggering rotation
		nearest.attack_role = nearest.AttackRole.RUNNER
		nearest.attack_target = kick_pos
		nearest.runner_reached = false
		nearest.runner_timer = 0.0

		# Others move away from kick position
		for i in range(1, eligible.size()):
			var unit: Node2D = eligible[i]
			var away_dir: Vector2 = (unit.position - kick_pos).normalized()
			if away_dir == Vector2.ZERO:
				away_dir = Vector2(1, 0)
			var away_pos: Vector2 = unit.position + away_dir * 300.0
			away_pos.x = clamp(away_pos.x, 50.0, PITCH_W - 50.0)
			away_pos.y = clamp(away_pos.y, 50.0, PITCH_H - 50.0)
			unit.attack_role = unit.AttackRole.DRAGGER
			unit.attack_target = away_pos

func _update_defender_arrow() -> void:
	if human_defender == null:
		defender_arrow.visible = false
		return

	# Convert unit world position to screen position
	var screen_pos: Vector2 = get_viewport().get_camera_2d().get_screen_center_position()
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_size: Vector2 = viewport_size / 2.0

	# Get unit position relative to camera centre
	var unit_screen_x: float = (human_defender.position.x - screen_pos.x) * camera.zoom.x + half_size.x
	var unit_screen_y: float = (human_defender.position.y - screen_pos.y) * camera.zoom.y + half_size.y

	var on_screen: bool = unit_screen_x >= 0 and unit_screen_x <= viewport_size.x and \
						  unit_screen_y >= 0 and unit_screen_y <= viewport_size.y

	if on_screen:
		defender_arrow.visible = false
		return

	# Show arrow on the appropriate side
	defender_arrow.visible = true
	defender_arrow.add_theme_color_override("font_color", human_defender.unit_color)

	# Clamp y to viewport bounds with padding
	var arrow_y: float = clamp(unit_screen_y, 30.0, viewport_size.y - 30.0)

	if unit_screen_x < 0:
		# Off left side
		defender_arrow.text = "◀"
		defender_arrow.position = Vector2(10.0, arrow_y - 20.0)
	else:
		# Off right side
		defender_arrow.text = "▶"
		defender_arrow.position = Vector2(viewport_size.x - 40.0, arrow_y - 20.0)
