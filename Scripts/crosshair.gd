extends Node2D

# Single circle radius — roughly unit height
const CROSSHAIR_RADIUS: float = 50.0

# Maximum distance crosshair can move from aiming unit
const RADIUS_INNER: float = 150.0
const RADIUS_MIDDLE: float = 300.0
const RADIUS_OUTER: float = 450.0

const MOVE_SPEED: float = 300.0

const COUNTDOWN_TIME: Dictionary = {
	1: 1.5,
	2: 2.5,
	3: 4.0
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

@onready var countdown_label: Label = $CountdownLabel
@onready var collision_shape: CollisionShape2D = $CollisionArea/CollisionShape2D
@onready var circle: Line2D = $Circle
@onready var line_h: Line2D = $CrosshairLines/LineH
@onready var line_v: Line2D = $CrosshairLines/LineV
@onready var collision_area: Area2D = $CollisionArea

func _ready() -> void:
	_draw_circle_line(circle, CROSSHAIR_RADIUS)
	_draw_crosshair_lines()
	# Set collision shape radius to match visual
	var shape := CircleShape2D.new()
	shape.radius = CROSSHAIR_RADIUS
	collision_shape.shape = shape
	countdown_label.visible = false
	visible = false

func activate(unit: Node2D) -> void:
	aim_action_left = ""
	aim_action_right = ""
	aim_action_up = ""
	aim_action_down = ""
	kick_action = ""

	aiming_unit = unit
	pitch = get_parent()
	position = unit.position
	visible = true
	active = true
	countdown_active = false
	countdown_label.visible = false

	var team: String = unit.team
	var is_human: bool = (team == "A" and GameState.team_a_player == 1) or \
						 (team == "B" and GameState.team_b_player == 1)
	if is_human:
		var prefix: String = "p1_aim" if team == "A" else "p2_aim"
		aim_action_left = prefix + "_left"
		aim_action_right = prefix + "_right"
		aim_action_up = prefix + "_up"
		aim_action_down = prefix + "_down"
		kick_action = "p1_kick" if team == "A" else "p2_kick"

func _physics_process(delta: float) -> void:
	if not active:
		return
	if countdown_active:
		_handle_countdown(delta)
		return
	_handle_movement(delta)
	_update_zone()
	_update_countdown_label()
	if kick_action != "" and Input.is_action_just_pressed(kick_action):
		_start_countdown()

func _handle_movement(delta: float) -> void:
	var move: Vector2 = Vector2.ZERO
	if aim_action_left != "" and Input.is_action_pressed(aim_action_left):
		move.x -= 1
	if aim_action_right != "" and Input.is_action_pressed(aim_action_right):
		move.x += 1
	if aim_action_up != "" and Input.is_action_pressed(aim_action_up):
		move.y -= 1
	if aim_action_down != "" and Input.is_action_pressed(aim_action_down):
		move.y += 1

	if move.length() > 0:
		move = move.normalized()

	var new_pos: Vector2 = position + move * MOVE_SPEED * delta

	# Clamp to outer radius from aiming unit
	var offset: Vector2 = new_pos - aiming_unit.position
	if offset.length() > RADIUS_OUTER:
		offset = offset.normalized() * RADIUS_OUTER
		new_pos = aiming_unit.position + offset

	# Clamp to pitch bounds
	new_pos.x = clamp(new_pos.x, 50.0, 2350.0)
	new_pos.y = clamp(new_pos.y, 50.0, 850.0)

	position = new_pos

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

func _handle_countdown(delta: float) -> void:
	countdown_remaining -= delta
	var display: int = int(ceil(countdown_remaining / \
		(COUNTDOWN_TIME[current_zone] / float(current_zone))))
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

	var attacking: String = aiming_unit.team

	if units_a_inside.size() > 0 and units_b_inside.size() == 0:
		pitch.on_kick_resolved("A", position)
	elif units_b_inside.size() > 0 and units_a_inside.size() == 0:
		pitch.on_kick_resolved("B", position)
	elif units_a_inside.size() > 0 and units_b_inside.size() > 0:
		_trigger_contest(position)
	else:
		_no_unit_resolution(attacking, position)

func _trigger_contest(pos: Vector2) -> void:
	GameState.return_scene = "res://Scenes/pitch.tscn"
	GameState.contest_reason = "clash"
	GameState.contest_crosshair_pos = pos
	GameState.go_to_scene("res://Scenes/main.tscn")

func _no_unit_resolution(attacking_team: String, pos: Vector2) -> void:
	var all_units: Array = get_parent().all_units_a if attacking_team == "A" \
		else get_parent().all_units_b
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for unit in all_units:
		var d: float = unit.position.distance_to(pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest = unit
	if nearest != null:
		nearest.position = pos
	pitch.on_kick_resolved(attacking_team, pos)

func _draw_circle_line(line: Line2D, radius: float) -> void:
	var points: PackedVector2Array = []
	var steps: int = 64
	for i in range(steps + 1):
		var angle: float = (float(i) / float(steps)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	line.points = points

func _draw_crosshair_lines() -> void:
	var size: float = 15.0
	line_h.points = [Vector2(-size, 0), Vector2(size, 0)]
	line_v.points = [Vector2(0, -size), Vector2(0, size)]
