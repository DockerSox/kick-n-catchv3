extends Area2D

@export var team: String = "A"        # "A" or "B"
@export var role: String = "field"    # "field", "goalie", "winger", "def", "att"
@export var unit_color: Color = Color.WHITE
@export var is_human_controlled: bool = false

var is_aiming: bool = false
var assigned_target: Node2D = null    # for defenders: their assigned attacker

# Movement bounds for goalies
var bounds_rect: Rect2 = Rect2()
var constrained: bool = false

const MOVE_SPEED: float = 120.0

@onready var color_rect: ColorRect = $ColorRect
@onready var name_label: Label = $NameLabel

func _ready() -> void:
	color_rect.color = unit_color
	name_label.text = role.substr(0, 2).to_upper()

func _physics_process(delta: float) -> void:
	if is_aiming:
		return  # aiming unit is controlled via crosshair, not direct movement
	if assigned_target != null:
		_move_toward_target(delta)

func _move_toward_target(delta: float) -> void:
	var dir: Vector2 = (assigned_target.position - position).normalized()
	var new_pos: Vector2 = position + dir * MOVE_SPEED * delta
	if constrained:
		new_pos = new_pos.clamp(bounds_rect.position, bounds_rect.end)
	position = new_pos

func set_as_aiming(value: bool) -> void:
	is_aiming = value
	# Visual indicator — brighten when aiming
	if value:
		color_rect.color = unit_color.lightened(0.3)
	else:
		color_rect.color = unit_color
