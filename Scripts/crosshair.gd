extends Node2D

@export var RADIUS_INNER: float = 200.0
@export var RADIUS_MIDDLE: float = 300.0
@export var RADIUS_OUTER: float = 400.0
@export var MOVE_SPEED: float = 350.0

const CROSSHAIR_RADIUS: float = 50.0
@export var COUNTDOWN_TIME: Dictionary = {
	1: 0.7,
	2: 1.4,
	3: 2.1
}

var active: bool = false
var aiming_unit: Node2D = null
var pitch: Node2D = null
var current_zone: int = 1
var countdown_active: bool = false
var countdown_remaining: float = 0.0
var aim_action_left: String = ""
var aim_action_right: String = ""
var aim_action_up: String = ""
var aim_action_down: String = ""
var kick_action: String = ""

var is_ai: bool = false
var ai_aim_timer: float = 0.0

@onready var countdown_label: Label = $CountdownLabel
@onready var collision_shape: CollisionShape2D = $CollisionArea/CollisionShape2D
@onready var circle: Line2D = $Circle
@onready var line_h: Line2D = $CrosshairLines/LineH
@onready var line_v: Line2D = $CrosshairLines/LineV
@onready var collision_area: Area2D = $CollisionArea

func _ready() -> void:
	_draw_circle(circle, CROSSHAIR_RADIUS)
	_draw_crosshair_lines()
	var shape := CircleShape2D.new()
	shape.radius = CROSSHAIR_RADIUS
	collision_shape.shape = shape
	countdown_label.visible = false
	visible = false

# Called when a human player controls the aiming unit.
func activate_with_input(unit: Node2D, input_id: String) -> void:
	is_ai = false
	ai_aim_timer = 0.0
	_setup(unit)
	match input_id:
		"kb0":
			aim_action_left  = "kb0_aim_left"
			aim_action_right = "kb0_aim_right"
			aim_action_up    = "kb0_aim_up"
			aim_action_down  = "kb0_aim_down"
			kick_action      = "kb0_kick"
		"kb1":
			aim_action_left  = "kb1_aim_left"
			aim_action_right = "kb1_aim_right"
			aim_action_up    = "kb1_aim_up"
			aim_action_down  = "kb1_aim_down"
			kick_action      = "kb1_kick"
		_:
			var n: String = input_id.substr(3)
			aim_action_left  = "joy_aim_left_"  + n
			aim_action_right = "joy_aim_right_" + n
			aim_action_up    = "joy_aim_up_"    + n
			aim_action_down  = "joy_aim_down_"  + n
			kick_action      = "joy_kick_"      + n

# Called when an AI team controls the aiming unit.
func activate_ai(unit: Node2D) -> void:
	is_ai = true
	ai_aim_timer = 0.0
	aim_action_left  = ""
	aim_action_right = ""
	aim_action_up    = ""
	aim_action_down  = ""
	kick_action      = ""
	_setup(unit)

# Called when no team controls this unit (should not occur in normal play).
func activate(unit: Node2D) -> void:
	is_ai = false
	ai_aim_timer = 0.0
	_setup(unit)
	aim_action_left  = ""
	aim_action_right = ""
	aim_action_up    = ""
	aim_action_down  = ""
	kick_action      = ""
	active = false
	visible = false

func _setup(unit: Node2D) -> void:
	aiming_unit = unit
	pitch = get_parent()
	position = unit.position
	visible = true
	active = true
	countdown_active = false
	countdown_label.visible = false

	var aiming_color: Color = unit.unit_color
	circle.default_color = aiming_color
	line_h.visible = true
	line_v.visible = true
	line_h.default_color = aiming_color
	line_v.default_color = aiming_color
	countdown_label.add_theme_color_override("font_color", Color.WHITE)

func _physics_process(delta: float) -> void:
	if not active:
		return
	if countdown_active:
		_handle_countdown(delta)
		return
	if is_ai:
		_handle_ai_movement(delta)
		_update_zone()
		_update_countdown_label()
		_check_ai_launch(delta)
	else:
		_handle_movement(delta)
		_update_zone()
		_update_countdown_label()
		if kick_action != "" and Input.is_action_just_pressed(kick_action):
			_start_countdown()

func _handle_movement(delta: float) -> void:
	var move: Vector2 = Vector2.ZERO
	if aim_action_left  != "" and Input.is_action_pressed(aim_action_left):
		move.x -= 1
	if aim_action_right != "" and Input.is_action_pressed(aim_action_right):
		move.x += 1
	if aim_action_up    != "" and Input.is_action_pressed(aim_action_up):
		move.y -= 1
	if aim_action_down  != "" and Input.is_action_pressed(aim_action_down):
		move.y += 1
	if move.length() > 0:
		move = move.normalized()
	var new_pos: Vector2 = position + move * MOVE_SPEED * delta
	var offset: Vector2 = new_pos - aiming_unit.position
	if offset.length() > RADIUS_OUTER:
		offset = offset.normalized() * RADIUS_OUTER
		new_pos = aiming_unit.position + offset
	new_pos.x = clamp(new_pos.x, 50.0, 2350.0)
	new_pos.y = clamp(new_pos.y, 50.0, 850.0)
	position = new_pos

func _handle_ai_movement(delta: float) -> void:
	# Find the goalie of the aiming unit's team
	var goalie_pos: Vector2 = aiming_unit.position
	if pitch != null:
		var team_units: Array = pitch.all_units_a if aiming_unit.team == "A" else pitch.all_units_b
		for u in team_units:
			if u.role == "goalie":
				goalie_pos = u.position
				break

	# Move crosshair toward goalie, clamped to RADIUS_OUTER
	var dir: Vector2 = (goalie_pos - aiming_unit.position)
	if dir.length() > RADIUS_OUTER:
		dir = dir.normalized() * RADIUS_OUTER
	var target: Vector2 = aiming_unit.position + dir
	target.x = clamp(target.x, 50.0, 2350.0)
	target.y = clamp(target.y, 50.0, 850.0)
	position = position.move_toward(target, MOVE_SPEED * delta)

func _check_ai_launch(delta: float) -> void:
	ai_aim_timer += delta
	if ai_aim_timer < 1.0:
		return

	# Launch when runner is the closest unit to the crosshair,
	# or immediately if there is no runner (fallback).
	if pitch == null:
		_start_countdown()
		return

	var runner: Node2D = pitch.runner
	if runner == null:
		_start_countdown()
		return

	# Find closest non-goalie unit to crosshair among all units
	var all_units: Array = pitch.all_units_a + pitch.all_units_b
	var closest: Node2D = null
	var closest_dist: float = INF
	for u in all_units:
		if u.role == "goalie":
			continue
		var d: float = u.position.distance_to(position)
		if d < closest_dist:
			closest_dist = d
			closest = u

	if closest == runner:
		_start_countdown()

func _update_zone() -> void:
	var dist: float = position.distance_to(aiming_unit.position)
	if dist <= RADIUS_INNER:
		current_zone = 1
	elif dist <= RADIUS_MIDDLE:
		current_zone = 2
	else:
		current_zone = 3

func _update_countdown_label() -> void:
	countdown_label.text = str(current_zone)
	countdown_label.visible = true

func _start_countdown() -> void:
	countdown_active = true
	countdown_remaining = COUNTDOWN_TIME[current_zone]
	circle.default_color = Color.WHITE
	line_h.visible = false
	line_v.visible = false
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	if pitch != null and pitch.has_method("on_kick_launched"):
		pitch.on_kick_launched(position)

func _handle_countdown(delta: float) -> void:
	countdown_remaining -= delta
	var total: float = COUNTDOWN_TIME[current_zone]
	var per_unit: float = total / float(current_zone)
	var display: int = int(ceil(countdown_remaining / per_unit))
	display = clamp(display, 0, current_zone)
	countdown_label.text = str(display)
	if countdown_remaining <= 0.0:
		_resolve_kick()

func _resolve_kick() -> void:
	active = false
	visible = false
	countdown_active = false

	var overlapping: Array = collision_area.get_overlapping_areas()
	var units_a_inside: Array = []
	var units_b_inside: Array = []

	for area in overlapping:
		if area.has_method("set_as_aiming"):
			if area.team == "A":
				units_a_inside.append(area)
			elif area.team == "B":
				units_b_inside.append(area)

	var a_goalie_only: bool = units_a_inside.size() == 1 and units_a_inside[0].role == "goalie"
	var b_goalie_only: bool = units_b_inside.size() == 1 and units_b_inside[0].role == "goalie"
	var a_has_goalie: bool = units_a_inside.any(func(u): return u.role == "goalie")
	var b_has_goalie: bool = units_b_inside.any(func(u): return u.role == "goalie")
	var units_a_no_goalie: Array = units_a_inside.filter(func(u): return u.role != "goalie")
	var units_b_no_goalie: Array = units_b_inside.filter(func(u): return u.role != "goalie")

	if a_goalie_only and units_b_inside.size() == 0:
		pitch.on_kick_resolved("A", position, true)
		return
	if b_goalie_only and units_a_inside.size() == 0:
		pitch.on_kick_resolved("B", position, true)
		return

	if units_a_no_goalie.size() > 0 and units_b_no_goalie.size() == 0:
		pitch.on_kick_resolved("A", position, false)
	elif units_b_no_goalie.size() > 0 and units_a_no_goalie.size() == 0:
		pitch.on_kick_resolved("B", position, false)
	elif units_a_no_goalie.size() > 0 and units_b_no_goalie.size() > 0:
		_trigger_contest(position)
	elif a_has_goalie and units_b_no_goalie.size() > 0:
		_trigger_contest(position)
	elif b_has_goalie and units_a_no_goalie.size() > 0:
		_trigger_contest(position)
	else:
		_no_unit_resolution(position)

func _trigger_contest(pos: Vector2) -> void:
	GameState.return_scene = "res://Scenes/pitch.tscn"
	GameState.contest_reason = "clash"
	GameState.contest_crosshair_pos = pos
	GameState.go_to_scene("res://Scenes/main.tscn")

func _no_unit_resolution(pos: Vector2) -> void:
	GameState.return_scene = "res://Scenes/pitch.tscn"
	GameState.contest_reason = "no_unit"
	GameState.contest_crosshair_pos = pos
	GameState.go_to_scene("res://Scenes/main.tscn")

func _draw_circle(line: Line2D, radius: float) -> void:
	var points: PackedVector2Array = []
	var steps: int = 64
	for i in range(steps + 1):
		var angle: float = (float(i) / float(steps)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	line.points = points

func _draw_crosshair_lines() -> void:
	line_h.points = [Vector2(-CROSSHAIR_RADIUS, 0), Vector2(CROSSHAIR_RADIUS, 0)]
	line_v.points = [Vector2(0, -CROSSHAIR_RADIUS), Vector2(0, CROSSHAIR_RADIUS)]
