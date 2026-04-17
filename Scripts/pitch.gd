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
@onready var pitch_ball: Node2D = $PitchBall

var attacking_team: String = "A"
var aiming_unit: Node2D = null
var all_units_a: Array = []
var all_units_b: Array = []
var camera_target: Vector2 = Vector2.ZERO
var kick_in_progress: bool = false
var runner: Node2D = null
var dragger: Node2D = null
var prepper: Node2D = null
var rotation_cooldown: float = 0.0
var attack_update_timer: float = 0.0
var marker_defender: Node2D = null
var timeout_rotation_cooldown: float = 0.0
var last_resolve_pos: Vector2 = Vector2(1200.0, 450.0)
var player_unit_map: Dictionary = {}
var off_screen_arrows: Array = []

@export var MARK_DELAY: float = 1.0

const TIMEOUT_ROTATION_COOLDOWN_TIME: float = 3.0
const ROTATION_COOLDOWN_TIME: float = 2.0
const ATTACK_UPDATE_INTERVAL: float = 0.5
const CAMERA_SPEED: float = 3.0
const PITCH_W: float = 2400.0
const PITCH_H: float = 900.0
const POSITIONS_A: Dictionary = {
	"centre":  Vector2(1250, 450),
	"goalie":  Vector2(100, 450),
	"winger":  Vector2(1200, 150),
	"defence": Vector2(1850, 450),
	"attack":  Vector2(650, 450),
}
const POSITIONS_B: Dictionary = {
	"centre":  Vector2(1150, 450),
	"goalie":  Vector2(2300, 450),
	"winger":  Vector2(1200, 750),
	"defence": Vector2(550, 450),
	"attack":  Vector2(1750, 450),
}

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	all_units_a = units_a.get_children()
	all_units_b = units_b.get_children()

	if GameState.return_scene != "res://Scenes/pitch.tscn" or GameState.contest_reason == "kickoff":
		for unit in all_units_a:
			unit.position = POSITIONS_A.get(unit.role, Vector2(1200, 450))
		for unit in all_units_b:
			unit.position = POSITIONS_B.get(unit.role, Vector2(1200, 450))
	else:
		for unit in all_units_a + all_units_b:
			if GameState.saved_unit_positions.has(unit.name):
				unit.position = GameState.saved_unit_positions[unit.name]

	_set_goalie_bounds()
	_set_forbidden_zones()
	_create_off_screen_arrows()

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

		_assign_units_to_players_kickoff()

		if GameState.contest_reason == "clash" or GameState.contest_reason == "no_unit":
			var winning_units: Array = all_units_a if attacking_team == "A" else all_units_b
			var nearest: Node2D = _nearest_unit_to(winning_units, GameState.contest_crosshair_pos, true)
			if nearest == null:
				nearest = _get_centre_unit(attacking_team)
			nearest.position = _safe_resolve_position(GameState.contest_crosshair_pos)

			var winning_players: Array = GameState.get_players_on_team(attacking_team)
			if winning_players.size() > 0:
				var best_p = winning_players[0]
				if winning_players.size() > 1:
					var best_dist: float = INF
					for p in winning_players:
						var u: Node2D = player_unit_map.get(p["input_id"], null)
						if u == null:
							continue
						var d: float = u.position.distance_to(GameState.contest_crosshair_pos)
						if d < best_dist:
							best_dist = d
							best_p = p
				best_p["unit_role"] = nearest.role
				player_unit_map[best_p["input_id"]] = nearest

			var losing_units: Array = all_units_b if attacking_team == "A" else all_units_a
			var nearest_loser: Node2D = _nearest_unit_to(losing_units, GameState.contest_crosshair_pos, true)
			if nearest_loser != null:
				nearest_loser.position = _safe_resolve_position(GameState.contest_crosshair_pos)

			last_resolve_pos = GameState.contest_crosshair_pos
			set_aiming_unit(nearest)
		else:
			var kickoff_centre: Node2D = _get_centre_unit(attacking_team)
			var kickoff_aimer: Node2D = _get_human_unit_for_aiming(attacking_team, kickoff_centre.position)
			if kickoff_aimer == null:
				kickoff_aimer = kickoff_centre
			set_aiming_unit(kickoff_aimer)

		update_score()
		_update_goal_arrow()
		pitch_ball.attach_to_unit(aiming_unit, crosshair.position)
		return

	attacking_team = GameState.attacking_team if GameState.attacking_team != "" else "A"
	_assign_units_to_players_kickoff()
	var centre_unit: Node2D = _get_centre_unit(attacking_team)
	var start_aimer: Node2D = _get_human_unit_for_aiming(attacking_team, centre_unit.position)
	if start_aimer == null:
		start_aimer = centre_unit
	set_aiming_unit(start_aimer)
	update_score()
	_update_goal_arrow()

# ---------------------------------------------------------------------------
# Process
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	camera.position = camera.position.lerp(camera_target, CAMERA_SPEED * delta)
	if not kick_in_progress:
		_check_role_rotation(delta)
	if Input.is_action_just_pressed("Pause"):
		_on_pause()
	_update_off_screen_arrows()
	if not kick_in_progress and aiming_unit != null:
		pitch_ball.attach_to_unit(aiming_unit, crosshair.position)

# ---------------------------------------------------------------------------
# Private helpers — setup
# ---------------------------------------------------------------------------

func _get_goal_rect(sq: ColorRect) -> Rect2:
	return Rect2(sq.position, sq.size)

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
	var unit_half: Vector2 = Vector2(15.0, 25.0)
	var expanded_a: Rect2 = goal_a_rect.grow_individual(unit_half.x, unit_half.y, unit_half.x, unit_half.y)
	var expanded_b: Rect2 = goal_b_rect.grow_individual(unit_half.x, unit_half.y, unit_half.x, unit_half.y)
	for unit in all_units_a + all_units_b:
		if unit.role != "goalie":
			unit.forbidden_rects = [expanded_a, expanded_b]

func _create_off_screen_arrows() -> void:
	defender_arrow.visible = false
	off_screen_arrows = []
	for i in range(8):
		var lbl := Label.new()
		lbl.visible = false
		lbl.add_theme_font_size_override("font_size", 36)
		$UI.add_child(lbl)
		off_screen_arrows.append(lbl)

# ---------------------------------------------------------------------------
# Private helpers — player / unit mapping
# ---------------------------------------------------------------------------

func _refresh_player_labels() -> void:
	for unit in all_units_a + all_units_b:
		unit.set_player_label("")
	for p in GameState.players:
		var unit: Node2D = player_unit_map.get(p["input_id"], null)
		if unit == null:
			continue
		var player_num: int = _get_player_num_for_input(p["input_id"])
		unit.set_player_label("P" + str(player_num))

func _assign_units_to_players_kickoff() -> void:
	# If players already have unit_role assignments, preserve them and just
	# rebuild the map — don't reshuffle.
	var roles_already_assigned: bool = false
	for p in GameState.players:
		if p["unit_role"] != "":
			roles_already_assigned = true
			break

	if roles_already_assigned:
		# Just rebuild the map from existing role strings
		player_unit_map = {}
		for p in GameState.players:
			if p["unit_role"] == "":
				continue
			var team_units: Array = all_units_a if p["team"] == "A" else all_units_b
			var unit: Node2D = _get_unit_by_role(team_units, p["unit_role"])
			if unit != null:
				player_unit_map[p["input_id"]] = unit
		# Ensure contest_player_index is set
		if GameState.contest_player_index < 0:
			for i in range(GameState.players.size()):
				var p = GameState.players[i]
				if p["team"] == attacking_team and p["unit_role"] == "centre":
					GameState.contest_player_index = i
					break
		return

	# Fresh assignment — shuffle roles and assign
	var field_roles: Array = ["centre", "winger", "defence", "attack"]
	var roles_a: Array = field_roles.duplicate()
	var roles_b: Array = field_roles.duplicate()
	roles_a.shuffle()
	roles_b.shuffle()

	var players_a: Array = GameState.get_players_on_team("A")
	var players_b: Array = GameState.get_players_on_team("B")

	if players_a.size() > 0:
		roles_a.erase("centre")
		roles_a.insert(0, "centre")
	if players_b.size() > 0:
		roles_b.erase("centre")
		roles_b.insert(0, "centre")

	player_unit_map = {}

	for i in range(players_a.size()):
		if i >= roles_a.size():
			break
		players_a[i]["unit_role"] = roles_a[i]
		var unit: Node2D = _get_unit_by_role(all_units_a, roles_a[i])
		if unit != null:
			player_unit_map[players_a[i]["input_id"]] = unit

	for i in range(players_b.size()):
		if i >= roles_b.size():
			break
		players_b[i]["unit_role"] = roles_b[i]
		var unit: Node2D = _get_unit_by_role(all_units_b, roles_b[i])
		if unit != null:
			player_unit_map[players_b[i]["input_id"]] = unit

	GameState.contest_player_index = -1
	for i in range(GameState.players.size()):
		var p = GameState.players[i]
		if p["team"] == attacking_team and p["unit_role"] == "centre":
			GameState.contest_player_index = i
			break

func _rebuild_player_unit_map() -> void:
	for p in GameState.players:
		if player_unit_map.has(p["input_id"]):
			continue
		if p["unit_role"] == "":
			continue
		var team_units: Array = all_units_a if p["team"] == "A" else all_units_b
		var unit: Node2D = _get_unit_by_role(team_units, p["unit_role"])
		if unit != null:
			player_unit_map[p["input_id"]] = unit

func _get_unit_by_role(units: Array, role_name: String) -> Node2D:
	for u in units:
		if u.role == role_name:
			return u
	return null

func _nearest_unit_to(units: Array, pos: Vector2, skip_goalie: bool) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for u in units:
		if skip_goalie and u.role == "goalie":
			continue
		var d: float = u.position.distance_to(pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest = u
	return nearest

func _get_human_unit_for_aiming(team: String, from_pos: Vector2 = Vector2(-1, -1)) -> Node2D:
	var ref_pos: Vector2 = from_pos if from_pos != Vector2(-1, -1) else Vector2(PITCH_W / 2.0, PITCH_H / 2.0)
	var best_unit: Node2D = null
	var best_dist: float = INF
	for p in GameState.players:
		if p["team"] != team:
			continue
		var unit: Node2D = player_unit_map.get(p["input_id"], null)
		if unit == null or unit.role == "goalie":
			continue
		var d: float = unit.position.distance_to(ref_pos)
		if d < best_dist:
			best_dist = d
			best_unit = unit
	return best_unit

func _is_unit_human_controlled(unit: Node2D) -> bool:
	for input_id in player_unit_map:
		if player_unit_map[input_id] == unit:
			return true
	return false

func _get_input_id_for_unit(unit: Node2D) -> String:
	for input_id in player_unit_map:
		if player_unit_map[input_id] == unit:
			return input_id
	return ""

func _get_player_index_for_unit(unit: Node2D) -> int:
	var input_id: String = _get_input_id_for_unit(unit)
	for i in range(GameState.players.size()):
		if GameState.players[i]["input_id"] == input_id:
			return i
	return -1

func _get_player_num_for_input(input_id: String) -> int:
	for i in range(GameState.players.size()):
		if GameState.players[i]["input_id"] == input_id:
			return i + 1
	return 0

func _get_move_actions(input_id: String) -> Dictionary:
	match input_id:
		"kb0":
			return {"up": "kb0_aim_up", "down": "kb0_aim_down", "left": "kb0_aim_left", "right": "kb0_aim_right"}
		"kb1":
			return {"up": "kb1_aim_up", "down": "kb1_aim_down", "left": "kb1_aim_left", "right": "kb1_aim_right"}
		_:
			var n: String = input_id.substr(3)
			return {
				"up":    "joy_aim_up_"    + n,
				"down":  "joy_aim_down_"  + n,
				"left":  "joy_aim_left_"  + n,
				"right": "joy_aim_right_" + n
			}

func _are_all_human_units_offscreen(team: String) -> bool:
	var vp_rect: Rect2 = _get_viewport_world_rect()
	for p in GameState.players:
		if p["team"] != team:
			continue
		var unit: Node2D = player_unit_map.get(p["input_id"], null)
		if unit == null or unit == aiming_unit:
			continue
		if vp_rect.has_point(unit.position):
			return false
	return true

func _get_viewport_world_rect() -> Rect2:
	var vp_size: Vector2 = get_viewport_rect().size
	var centre: Vector2 = camera.get_screen_center_position()
	var half: Vector2 = vp_size / (2.0 * camera.zoom)
	return Rect2(centre - half, half * 2.0)

func _get_centre_unit(team: String) -> Node2D:
	var arr: Array = all_units_a if team == "A" else all_units_b
	for unit in arr:
		if unit.role == "centre":
			return unit
	return arr[0]

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

# ---------------------------------------------------------------------------
# Private helpers — defenders & attack roles
# ---------------------------------------------------------------------------

func _assign_defenders() -> void:
	var defending_units: Array = all_units_b if attacking_team == "A" else all_units_a
	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b

	for unit in defending_units + attacking_units:
		if unit == aiming_unit:
			continue
		unit.is_defending = false
		unit.human_defending = false
		unit.assigned_target = null
		unit.set_human_defender_highlight(false)
		unit.clear_human_attack()
		unit.attack_role = unit.AttackRole.NONE

	marker_defender = null
	var defending_units_no_goalie: Array = defending_units.filter(
		func(u): return u.role != "goalie"
	)

	if GameState.contest_reason == "kickoff":
		# After kickoff or post-goal: defending centre unit is the marker.
		# If centre is human-controlled, fall back to nearest AI unit.
		for unit in defending_units:
			if unit.role == "centre":
				if not _is_unit_human_controlled(unit):
					marker_defender = unit
				break
		if marker_defender == null:
			var marker_dist: float = INF
			for unit in defending_units_no_goalie:
				if _is_unit_human_controlled(unit):
					continue
				var d: float = unit.position.distance_to(aiming_unit.position)
				if d < marker_dist:
					marker_dist = d
					marker_defender = unit
	else:
		# After clash, no_unit, or possession change:
		# nearest AI unit to last resolve position is the marker.
		var marker_dist: float = INF
		for unit in defending_units_no_goalie:
			if _is_unit_human_controlled(unit):
				continue
			var d: float = unit.position.distance_to(last_resolve_pos)
			if d < marker_dist:
				marker_dist = d
				marker_defender = unit

	if marker_defender != null:
		var defending_direction: float = -1.0 if attacking_team == "A" else 1.0
		marker_defender.position = aiming_unit.position + Vector2(defending_direction * 35.0, 0.0)
		marker_defender.set_as_defender(aiming_unit, false, "", "", "", "", 40.0)

	var remaining_ai_defenders: Array = defending_units.filter(
		func(u): return u != marker_defender and u.role != "goalie" and not _is_unit_human_controlled(u)
	)
	var targetable_attackers: Array = attacking_units.filter(
		func(u): return u.role != "goalie" and u != aiming_unit
	)
	for defender in remaining_ai_defenders:
		if targetable_attackers.is_empty():
			break
		var nearest: Node2D = null
		var nd: float = INF
		for attacker in targetable_attackers:
			var dist: float = defender.position.distance_to(attacker.position)
			if dist < nd:
				nd = dist
				nearest = attacker
		if nearest != null:
			targetable_attackers.erase(nearest)
			defender.set_as_defender(nearest, false)

	for p in GameState.players:
		if p["team"] == attacking_team:
			continue
		var unit: Node2D = player_unit_map.get(p["input_id"], null)
		if unit == null or unit.role == "goalie":
			continue
		var actions: Dictionary = _get_move_actions(p["input_id"])
		unit.set_as_defender(null, true,
			actions["up"], actions["down"],
			actions["left"], actions["right"], 0.0)

	_assign_attack_movement()
	_refresh_player_labels()

func _assign_attack_movement() -> void:
	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b
	var human_players_on_team: Array = GameState.get_players_on_team(attacking_team)

	var non_aiming_humans: Array = []
	for p in human_players_on_team:
		var unit: Node2D = player_unit_map.get(p["input_id"], null)
		if unit == null or unit == aiming_unit or unit.role == "goalie":
			continue
		non_aiming_humans.append({"player": p, "unit": unit})

	if non_aiming_humans.size() == 0:
		_assign_attack_roles()
		return

	if human_players_on_team.size() == 1:
		_assign_attack_roles()
		var hu = non_aiming_humans[0]
		var actions: Dictionary = _get_move_actions(hu["player"]["input_id"])
		hu["unit"].set_as_human_attacker(
			actions["up"], actions["down"], actions["left"], actions["right"])
		return

	for hu in non_aiming_humans:
		var actions: Dictionary = _get_move_actions(hu["player"]["input_id"])
		hu["unit"].set_as_human_attacker(
			actions["up"], actions["down"], actions["left"], actions["right"])

	var ai_units: Array = attacking_units.filter(
		func(u): return u != aiming_unit and u.role != "goalie" and not _is_unit_human_controlled(u)
	)
	if ai_units.is_empty():
		return

	runner = null
	dragger = null
	prepper = null

	if _are_all_human_units_offscreen(attacking_team):
		runner = ai_units[0]
		runner.set_attack_role(runner.AttackRole.RUNNER, _clamp_to_pitch(crosshair.position))
		for i in range(1, ai_units.size()):
			var u: Node2D = ai_units[i]
			u.set_attack_role(u.AttackRole.DRAGGER, _clamp_to_pitch(u.position))
	else:
		for u in ai_units:
			u.set_attack_role(u.AttackRole.DRAGGER, _clamp_to_pitch(u.position))

func _assign_attack_roles() -> void:
	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b
	var eligible: Array = attacking_units.filter(
		func(u): return u != aiming_unit and u.role != "goalie" and not _is_unit_human_controlled(u)
	)

	runner = null
	dragger = null
	prepper = null

	if eligible.size() == 0:
		return
	if eligible.size() == 1:
		runner = eligible[0]
		_update_attack_targets()
		return
	if eligible.size() == 2:
		var ch_pos2: Vector2 = crosshair.position
		eligible.sort_custom(func(a, b):
			return a.position.distance_to(ch_pos2) < b.position.distance_to(ch_pos2)
		)
		runner = eligible[0]
		dragger = eligible[1]
		_update_attack_targets()
		return

	var goalie: Node2D = null
	for u in attacking_units:
		if u.role == "goalie":
			goalie = u
			break

	var ch_pos3: Vector2 = crosshair.position
	eligible.sort_custom(func(a, b):
		return a.position.distance_to(ch_pos3) < b.position.distance_to(ch_pos3)
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
	if runner == null:
		return

	var ch_pos: Vector2 = crosshair.position
	var goalie: Node2D = null
	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b
	for u in attacking_units:
		if u.role == "goalie":
			goalie = u
			break

	if runner.attack_role != runner.AttackRole.RUNNER:
		runner.set_attack_role(runner.AttackRole.RUNNER, _clamp_to_pitch(ch_pos))
	else:
		runner.update_runner_target(_clamp_to_pitch(ch_pos))

	if dragger == null:
		return

	var in_defensive_half: bool
	if attacking_team == "A":
		in_defensive_half = aiming_unit.position.x > 1200.0
	else:
		in_defensive_half = aiming_unit.position.x < 1200.0

	var dragger_target: Vector2
	if goalie != null:
		if in_defensive_half:
			var p_pos: Vector2 = prepper.position if prepper != null else dragger.position
			dragger_target = (p_pos + goalie.position) / 2.0
		else:
			if attacking_team == "A":
				dragger_target = (goalie.position + Vector2(250.0, 0.0)) / 2.0
			else:
				dragger_target = (goalie.position + Vector2(2150.0, 0.0)) / 2.0
	else:
		dragger_target = dragger.position
	dragger.set_attack_role(dragger.AttackRole.DRAGGER, _clamp_to_pitch(dragger_target))

	if prepper == null:
		return

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
			if attacking_team == "A":
				prepper_target = Vector2(250.0, 750.0)
			else:
				prepper_target = Vector2(2150.0, 750.0)
	else:
		prepper_target = prepper.position
	prepper.set_attack_role(prepper.AttackRole.PREPPER, _clamp_to_pitch(prepper_target))

func _check_role_rotation(delta: float) -> void:
	if runner == null or prepper == null:
		return

	var human_count: int = GameState.get_players_on_team(attacking_team).size()
	if human_count > 1:
		return

	if rotation_cooldown > 0.0:
		rotation_cooldown -= delta
	if timeout_rotation_cooldown > 0.0:
		timeout_rotation_cooldown -= delta

	var ch_pos: Vector2 = crosshair.position
	var runner_dist: float = runner.position.distance_to(ch_pos)
	var prepper_dist: float = prepper.position.distance_to(ch_pos)

	if prepper_dist < runner_dist and rotation_cooldown <= 0.0 and timeout_rotation_cooldown <= 0.0:
		on_runner_rotation_needed(false)
		return

	attack_update_timer += delta
	if attack_update_timer >= ATTACK_UPDATE_INTERVAL:
		attack_update_timer = 0.0
		_update_attack_targets()

# ---------------------------------------------------------------------------
# Private helpers — scoring / goal arrows
# ---------------------------------------------------------------------------

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
	pitch_ball.land()
	if team == "A":
		GameState.score_a += 1
	else:
		GameState.score_b += 1

	var goal_text: String = "GOAL!"
	var goal_color: Color = aiming_unit.unit_color if aiming_unit != null else Color.WHITE
	goal_label.text = goal_text
	goal_label.add_theme_color_override("font_color", goal_color)
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
	# Clear unit_role assignments so fresh shuffle happens after goal
	for p in GameState.players:
		p["unit_role"] = ""
	GameState.contest_player_index = -1
	GameState.return_scene = "res://Scenes/pitch.tscn"
	GameState.contest_reason = "kickoff"
	GameState.go_to_scene("res://Scenes/main.tscn")

func _end_match() -> void:
	var winner_text: String = "Team A Wins!" if GameState.score_a >= 2 else "Team B Wins!"
	var winner_text_color: String = "#6a0dad" if GameState.score_a >= 2 else "#cc44cc"
	match_end_label.text = winner_text
	match_end_label.add_theme_color_override("font_color", Color(winner_text_color))
	match_end_label.visible = true
	match_end_label.process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().create_timer(3.0).timeout
	GameState.reset_score()
	GameState.go_to_scene("res://Scenes/title.tscn")

# ---------------------------------------------------------------------------
# Off-screen arrows
# ---------------------------------------------------------------------------

func _update_off_screen_arrows() -> void:
	for arrow in off_screen_arrows:
		arrow.visible = false

	var screen_centre: Vector2 = camera.get_screen_center_position()
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_size: Vector2 = viewport_size / 2.0
	var arrow_index: int = 0

	for p in GameState.players:
		if arrow_index >= off_screen_arrows.size():
			break
		var unit: Node2D = player_unit_map.get(p["input_id"], null)
		if unit == null or unit == aiming_unit:
			continue

		var unit_screen_x: float = (unit.position.x - screen_centre.x) * camera.zoom.x + half_size.x
		var unit_screen_y: float = (unit.position.y - screen_centre.y) * camera.zoom.y + half_size.y
		var on_screen: bool = unit_screen_x >= 0 and unit_screen_x <= viewport_size.x \
						   and unit_screen_y >= 0 and unit_screen_y <= viewport_size.y
		if on_screen:
			continue

		var arrow: Label = off_screen_arrows[arrow_index]
		arrow_index += 1
		arrow.visible = true
		arrow.add_theme_color_override("font_color", unit.unit_color)

		var player_label: String = "P" + str(_get_player_num_for_input(p["input_id"]))
		var off_left: bool  = unit_screen_x < 0
		var off_right: bool = unit_screen_x > viewport_size.x
		var off_top: bool   = unit_screen_y < 0
		var off_bottom: bool = unit_screen_y > viewport_size.y

		if off_left and not off_top and not off_bottom:
			arrow.text = "◀ " + player_label
			arrow.position = Vector2(10.0, clamp(unit_screen_y, 30.0, viewport_size.y - 30.0) - 20.0)
		elif off_right and not off_top and not off_bottom:
			arrow.text = player_label + " ▶"
			arrow.position = Vector2(viewport_size.x - 80.0, clamp(unit_screen_y, 30.0, viewport_size.y - 30.0) - 20.0)
		elif off_top:
			arrow.text = "▲ " + player_label
			arrow.position = Vector2(clamp(unit_screen_x, 30.0, viewport_size.x - 80.0), 10.0)
		elif off_bottom:
			arrow.text = "▼ " + player_label
			arrow.position = Vector2(clamp(unit_screen_x, 30.0, viewport_size.x - 80.0), viewport_size.y - 40.0)
		else:
			var x_dist: float = min(abs(unit_screen_x), abs(unit_screen_x - viewport_size.x))
			var y_dist: float = min(abs(unit_screen_y), abs(unit_screen_y - viewport_size.y))
			if x_dist < y_dist:
				if off_left:
					arrow.text = "◀ " + player_label
					arrow.position = Vector2(10.0, clamp(unit_screen_y, 30.0, viewport_size.y - 30.0) - 20.0)
				else:
					arrow.text = player_label + " ▶"
					arrow.position = Vector2(viewport_size.x - 80.0, clamp(unit_screen_y, 30.0, viewport_size.y - 30.0) - 20.0)
			else:
				if off_top:
					arrow.text = "▲ " + player_label
					arrow.position = Vector2(clamp(unit_screen_x, 30.0, viewport_size.x - 80.0), 10.0)
				else:
					arrow.text = "▼ " + player_label
					arrow.position = Vector2(clamp(unit_screen_x, 30.0, viewport_size.x - 80.0), viewport_size.y - 40.0)

# ---------------------------------------------------------------------------
# Pause callbacks
# ---------------------------------------------------------------------------

func _on_pause() -> void:
	get_tree().paused = true
	pause_menu.visible = true
	$UI/PauseMenu/ResumeButton.grab_focus()

func _on_resume() -> void:
	get_tree().paused = false
	pause_menu.visible = false

func _on_quit() -> void:
	get_tree().paused = false
	GameState.go_to_scene("res://Scenes/title.tscn")

# ---------------------------------------------------------------------------
# Public functions called by other nodes
# ---------------------------------------------------------------------------

func set_aiming_unit(unit: Node2D) -> void:
	kick_in_progress = false
	rotation_cooldown = 0.0
	timeout_rotation_cooldown = 0.0
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

	var input_id: String = _get_input_id_for_unit(unit)
	if input_id != "":
		crosshair.activate_with_input(unit, input_id)
	elif GameState.get_players_on_team(attacking_team).size() == 0:
		crosshair.activate_ai(unit)
	else:
		crosshair.activate(unit)

	_assign_defenders()
	_update_goal_arrow()

func update_score() -> void:
	score_label.text = str(GameState.score_a) + " - " + str(GameState.score_b)

func on_kick_resolved(winning_team: String, resolve_position: Vector2, is_goal: bool = false) -> void:
	kick_in_progress = false
	attacking_team = winning_team
	GameState.attacking_team = winning_team

	if is_goal:
		_score_goal(winning_team)
		return

	last_resolve_pos = resolve_position

	var winning_units: Array = all_units_a if winning_team == "A" else all_units_b
	var nearest: Node2D = _nearest_unit_to(winning_units, resolve_position, true)
	if nearest == null:
		nearest = _get_centre_unit(winning_team)
	
	nearest.position = _safe_resolve_position(resolve_position)

	var winning_players: Array = GameState.get_players_on_team(winning_team)

	if winning_players.size() == 1:
		var p = winning_players[0]
		p["unit_role"] = nearest.role
		player_unit_map[p["input_id"]] = nearest
		set_aiming_unit(nearest)
		return

	var new_aimer: Node2D = _get_human_unit_for_aiming(winning_team, resolve_position)
	if new_aimer == null:
		new_aimer = nearest
	set_aiming_unit(new_aimer)

func on_kick_launched(kick_pos: Vector2) -> void:
	pitch_ball.launch(aiming_unit.position, kick_pos, crosshair.COUNTDOWN_TIME[crosshair.current_zone], crosshair.current_zone)
	kick_in_progress = true

	GameState.contest_player_index = _get_player_index_for_unit(aiming_unit)

	var defending_units: Array = all_units_b if attacking_team == "A" else all_units_a
	for unit in defending_units:
		if unit.role == "goalie":
			continue
		if _is_unit_human_controlled(unit):
			continue
		if unit == marker_defender:
			unit.start_mark_delay(MARK_DELAY)
			unit.assigned_target = null
			unit.set_attack_role(unit.AttackRole.RUNNER, kick_pos)
			unit.mark_delay_timer = MARK_DELAY
			continue
		unit.set_attack_role(unit.AttackRole.RUNNER, kick_pos)

	var attacking_units: Array = all_units_a if attacking_team == "A" else all_units_b
	var eligible: Array = attacking_units.filter(
		func(u): return u != aiming_unit and u.role != "goalie" and not _is_unit_human_controlled(u)
	)

	runner = null
	if eligible.size() > 0:
		eligible.sort_custom(func(a, b):
			return a.position.distance_to(kick_pos) < b.position.distance_to(kick_pos)
		)
		runner = eligible[0]
		runner.set_attack_role(runner.AttackRole.RUNNER, kick_pos)
		for i in range(1, eligible.size()):
			var unit: Node2D = eligible[i]
			var away_dir: Vector2 = (unit.position - kick_pos).normalized()
			if away_dir == Vector2.ZERO:
				away_dir = Vector2(1, 0)
			var away_pos: Vector2 = unit.position + away_dir * 300.0
			away_pos.x = clamp(away_pos.x, 50.0, PITCH_W - 50.0)
			away_pos.y = clamp(away_pos.y, 50.0, PITCH_H - 50.0)
			unit.set_attack_role(unit.AttackRole.DRAGGER, away_pos)

func on_runner_rotation_needed(from_timeout: bool = false) -> void:
	if from_timeout and timeout_rotation_cooldown > 0.0:
		return
	if from_timeout:
		timeout_rotation_cooldown = TIMEOUT_ROTATION_COOLDOWN_TIME
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

func _clamp_to_pitch(pos: Vector2) -> Vector2:
	return Vector2(
		clamp(pos.x, 10.0, PITCH_W - 10.0),
		clamp(pos.y, 10.0, PITCH_H - 10.0)
	)
