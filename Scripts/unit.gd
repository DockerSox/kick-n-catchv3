extends Area2D

@export var team: String = "A"
@export var role: String = "field"
@export var unit_color: Color = Color.WHITE
@export var is_human_controlled: bool = false

var is_aiming: bool = false
var assigned_target: Node2D = null
var bounds_rect: Rect2 = Rect2()
var constrained: bool = false
var is_defending: bool = false
var human_defending: bool = false
var stop_distance: float = 20.0
var forbidden_rects: Array = []

enum AttackRole { NONE, RUNNER, DRAGGER, PREPPER }
var attack_role: AttackRole = AttackRole.NONE
var attack_target: Vector2 = Vector2.ZERO
var runner_timer: float = 0.0
var runner_reached: bool = false
var runner_reached_timer: float = 0.0

const RUNNER_TIMEOUT: float = 3.0
const RUNNER_REACHED_DELAY: float = 0.4
const RUNNER_REACH_DIST: float = 40.0
const ATTACK_MOVE_SPEED: float = 160.0

var defend_up: String = ""
var defend_down: String = ""
var defend_left: String = ""
var defend_right: String = ""

const MOVE_SPEED: float = 150.0
const DEFEND_SPEED: float = 180.0

@onready var color_rect: ColorRect = $ColorRect
@onready var name_label: Label = $NameLabel
@onready var border: ColorRect = $Border

func _ready() -> void:
	color_rect.color = unit_color
	name_label.text = role.substr(0, 2).to_upper()
	border.visible = false

func _physics_process(delta: float) -> void:
	if role == "goalie":
		return
	if is_aiming:
		return
	if is_defending:
		if human_defending:
			_handle_human_defend(delta)
		elif assigned_target != null:
			_move_toward_target(delta)
		return
	if attack_role != AttackRole.NONE:
		_handle_attack_movement(delta)

func set_human_defender_highlight(value: bool) -> void:
	border.visible = value

func _handle_attack_movement(delta: float) -> void:
	match attack_role:
		AttackRole.RUNNER:
			_handle_runner(delta)
		AttackRole.DRAGGER:
			_move_toward_attack_target(delta)
		AttackRole.PREPPER:
			_move_toward_attack_target(delta)

func _handle_runner(delta: float) -> void:
	var dist: float = position.distance_to(attack_target)
	if not runner_reached:
		_move_toward_attack_target(delta)
		runner_timer += delta
		if dist < RUNNER_REACH_DIST:
			runner_reached = true
			runner_reached_timer = 0.0
		elif runner_timer >= RUNNER_TIMEOUT:
			runner_reached = true
			runner_reached_timer = RUNNER_REACHED_DELAY
	else:
		# If crosshair has moved significantly, reset runner state
		if dist > RUNNER_REACH_DIST * 3.0:
			runner_reached = false
			runner_timer = 0.0
			return
		runner_reached_timer += delta
		if runner_reached_timer >= RUNNER_REACHED_DELAY:
			var pitch: Node = get_parent().get_parent()
			if pitch.has_method("on_runner_rotation_needed"):
				pitch.on_runner_rotation_needed()
			runner_reached = false
			runner_timer = 0.0

func _move_toward_attack_target(delta: float) -> void:
	if attack_target == Vector2.ZERO:
		return
	var dist: float = position.distance_to(attack_target)
	if dist < 15.0:
		return
	var dir: Vector2 = (attack_target - position).normalized()
	var new_pos: Vector2 = position + dir * ATTACK_MOVE_SPEED * delta
	new_pos = _avoid_forbidden(new_pos)
	position = new_pos

func _move_toward_target(delta: float) -> void:
	if assigned_target == null:
		return
	var dist: float = position.distance_to(assigned_target.position)
	if dist < stop_distance:
		return
	var dir: Vector2 = (assigned_target.position - position).normalized()
	var new_pos: Vector2 = position + dir * MOVE_SPEED * delta
	if constrained:
		new_pos = new_pos.clamp(bounds_rect.position, bounds_rect.end)
	new_pos = _avoid_forbidden(new_pos)
	position = new_pos

func _handle_human_defend(delta: float) -> void:
	var move: Vector2 = Vector2.ZERO
	if defend_up != "" and Input.is_action_pressed(defend_up):
		move.y -= 1
	if defend_down != "" and Input.is_action_pressed(defend_down):
		move.y += 1
	if defend_left != "" and Input.is_action_pressed(defend_left):
		move.x -= 1
	if defend_right != "" and Input.is_action_pressed(defend_right):
		move.x += 1
	if move.length() > 0:
		move = move.normalized()
	var new_pos: Vector2 = position + move * DEFEND_SPEED * delta
	if constrained:
		new_pos = new_pos.clamp(bounds_rect.position, bounds_rect.end)
	new_pos = _avoid_forbidden(new_pos)
	position = new_pos

func _avoid_forbidden(new_pos: Vector2) -> Vector2:
	for rect in forbidden_rects:
		if rect.has_point(new_pos):
			# Slide along the nearest edge instead of cancelling
			var current_in_rect: bool = rect.has_point(position)
			if current_in_rect:
				return position  # already inside, don't move further
			
			# Find which axis to slide on
			var from_left: bool = position.x < rect.position.x
			var from_right: bool = position.x > rect.end.x
			var from_top: bool = position.y < rect.position.y
			var from_bottom: bool = position.y > rect.end.y

			if from_left or from_right:
				# Approaching horizontally — allow vertical sliding
				return Vector2(position.x, new_pos.y)
			elif from_top or from_bottom:
				# Approaching vertically — allow horizontal sliding
				return Vector2(new_pos.x, position.y)
			else:
				return position
	return new_pos

func set_as_aiming(value: bool) -> void:
	is_aiming = value
	is_defending = false
	human_defending = false
	attack_role = AttackRole.NONE
	if value:
		color_rect.color = unit_color.lightened(0.3)
	else:
		color_rect.color = unit_color

func set_as_defender(target: Node2D, is_human: bool, up: String = "", down: String = "", left: String = "", right: String = "", stop_dist: float = 20.0) -> void:
	is_defending = true
	attack_role = AttackRole.NONE
	assigned_target = target
	human_defending = is_human
	defend_up = up
	defend_down = down
	defend_left = left
	defend_right = right
	stop_distance = stop_dist

func set_attack_role(new_role: AttackRole, target: Vector2) -> void:
	attack_role = new_role
	attack_target = target
	is_defending = false
	runner_reached = false
	runner_timer = 0.0
	runner_reached_timer = 0.0
