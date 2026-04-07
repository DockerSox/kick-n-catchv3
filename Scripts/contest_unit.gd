extends Area2D

# --- Configuration (set from Main scene) ---
@export var is_cpu: bool = false
@export var move_left_action: String = ""    # e.g. "p1_left"
@export var move_right_action: String = ""
@export var launch_action: String = ""
@export var paddle_color: Color = Color.WHITE

# --- State ---
enum State { WAITING, AIMING, LAUNCHED }
var state: State = State.WAITING

var aim_angle_deg: float = 90.0   # degrees, 90 = straight up
const AIM_SPEED: float = 60.0     # degrees per second
const AIM_MIN: float = 20.0       # leftmost angle (almost horizontal right)
const AIM_MAX: float = 160.0      # rightmost angle

var velocity: Vector2 = Vector2.ZERO
const LAUNCH_SPEED: float = 450.0
const GRAVITY: float = 400.0
const HALF_HEIGHT: float = 60.0  # half of 120px height

# Arrow node reference
@onready var arrow: Line2D = $Arrow
@onready var arrow_left: Line2D = $ArrowLeft
@onready var arrow_right: Line2D = $ArrowRight

# Starting position — set by Main
var start_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	$ColorRect.color = paddle_color
	_update_arrow()

func activate() -> void:
	state = State.AIMING
	aim_angle_deg = 90.0
	position = start_position
	velocity = Vector2.ZERO
	_update_arrow()
	arrow.visible = true
	arrow_left.visible = true
	arrow_right.visible = true

func _physics_process(delta: float) -> void:
	match state:
		State.AIMING:
			_handle_aiming(delta)
		State.LAUNCHED:
			_handle_movement(delta)

func _handle_aiming(delta: float) -> void:
	if is_cpu:
		aim_angle_deg += randf_range(-1.0, 1.0) * AIM_SPEED * delta
		aim_angle_deg = clamp(aim_angle_deg, AIM_MIN, AIM_MAX)
	else:
		if move_left_action != "" and Input.is_action_pressed(move_left_action):
			aim_angle_deg += AIM_SPEED * delta   # was -= , now +=
		if move_right_action != "" and Input.is_action_pressed(move_right_action):
			aim_angle_deg -= AIM_SPEED * delta   # was += , now -=
		aim_angle_deg = clamp(aim_angle_deg, AIM_MIN, AIM_MAX)

		if launch_action != "" and Input.is_action_just_pressed(launch_action):
			_launch()

	_update_arrow()

func _launch() -> void:
	state = State.LAUNCHED
	arrow.visible = false
	arrow_left.visible = false
	arrow_right.visible = false
	var rad: float = deg_to_rad(aim_angle_deg)
	velocity = Vector2(cos(rad), -sin(rad)) * LAUNCH_SPEED

func cpu_launch() -> void:
	# Called by a timer in Main
	if state == State.AIMING:
		_launch()

func _handle_movement(delta: float) -> void:
	velocity.y += GRAVITY * delta
	position += velocity * delta

	# Floor clamp
	var floor_y: float = 700.0
	if position.y >= floor_y - HALF_HEIGHT:
		position.y = floor_y - HALF_HEIGHT
		velocity.y = 0.0
		velocity.x = 0.0

	# Side wall clamps
	var half_width: float = 15.0  # half of 30px wide paddle
	if position.x < half_width:
		position.x = half_width
		velocity.x = 0.0
	elif position.x > 460.0 - half_width:
		position.x = 460.0 - half_width
		velocity.x = 0.0

func _update_arrow() -> void:
	var rad: float = deg_to_rad(aim_angle_deg)
	var dir: Vector2 = Vector2(cos(rad), -sin(rad))
	var tip: Vector2 = dir * 60.0

	# Main shaft
	arrow.points = [Vector2.ZERO, tip]

	# Arrowhead — two lines branching back from the tip
	var head_len: float = 14.0
	var head_angle: float = deg_to_rad(30.0)

	# Rotate the direction backwards to form the two barbs
	var left_barb: Vector2 = tip + Vector2(
		dir.x * -cos(head_angle) - dir.y * -sin(head_angle),
		dir.x * -sin(head_angle) + dir.y * -cos(head_angle)
	) * head_len

	var right_barb: Vector2 = tip + Vector2(
		dir.x * -cos(-head_angle) - dir.y * -sin(-head_angle),
		dir.x * -sin(-head_angle) + dir.y * -cos(-head_angle)
	) * head_len

	$ArrowLeft.points = [tip, left_barb]
	$ArrowRight.points = [tip, right_barb]

# **Key concepts:**
# - `enum` defines named states — much cleaner than magic numbers.
# - `match` is GDScript's version of switch/case.
# - `@export` makes a variable visible and editable in the Godot Inspector, so you can configure each paddle differently without changing code.
# - `@onready` means "get this node reference when the scene is ready" — equivalent to grabbing it in `_ready()`.
# - `signal` declares a custom event other nodes can listen to.
