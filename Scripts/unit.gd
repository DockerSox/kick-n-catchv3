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

var defend_up: String = ""
var defend_down: String = ""
var defend_left: String = ""
var defend_right: String = ""

const MOVE_SPEED: float = 150.0
const DEFEND_SPEED: float = 180.0

@onready var color_rect: ColorRect = $ColorRect
@onready var name_label: Label = $NameLabel

func _ready() -> void:
	color_rect.color = unit_color
	name_label.text = role.substr(0, 2).to_upper()

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
			return position
	return new_pos

func set_as_aiming(value: bool) -> void:
	is_aiming = value
	is_defending = false
	human_defending = false
	if value:
		color_rect.color = unit_color.lightened(0.3)
	else:
		color_rect.color = unit_color

func set_as_defender(target: Node2D, is_human: bool, up: String = "", down: String = "", left: String = "", right: String = "", stop_dist: float = 20.0) -> void:
	is_defending = true
	assigned_target = target
	human_defending = is_human
	defend_up = up
	defend_down = down
	defend_left = left
	defend_right = right
	stop_distance = stop_dist
