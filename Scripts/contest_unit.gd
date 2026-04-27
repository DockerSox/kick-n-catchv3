extends Area2D

# Add "CONTEST!" text to this event

@export var move_left_action: String = ""
@export var move_right_action: String = ""
@export var launch_action: String = ""
@export var paddle_color: Color = Color.WHITE

enum State { WAITING, AIMING, LAUNCHED }
var state: State = State.WAITING

var aim_angle_deg: float = 90.0
const AIM_SPEED: float = 60.0
const AIM_MIN: float = 20.0
const AIM_MAX: float = 160.0

var velocity: Vector2 = Vector2.ZERO
const LAUNCH_SPEED: float = 450.0
const GRAVITY: float = 400.0
const HALF_HEIGHT: float = 60.0

var start_position: Vector2 = Vector2.ZERO

# Set to true for AI-controlled paddles. Main sets ball_ref before activating.
var is_ai: bool = false
var ball_ref: Node2D = null

@onready var arrow: Line2D = $Arrow
@onready var arrow_left: Line2D = $ArrowLeft
@onready var arrow_right: Line2D = $ArrowRight
@onready var color_rect: ColorRect = $ColorRect

func _ready() -> void:
	color_rect.color = paddle_color
	_update_arrow()

func set_paddle_color(new_color: Color) -> void:
	paddle_color = new_color
	color_rect.color = new_color

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
	if is_ai:
		# Launch the moment the ball starts falling (velocity.y > 0)
		if ball_ref != null and ball_ref.active and ball_ref.velocity.y > 0:
			_launch()
	else:
		if move_left_action != "" and Input.is_action_pressed(move_left_action):
			aim_angle_deg += AIM_SPEED * delta
		if move_right_action != "" and Input.is_action_pressed(move_right_action):
			aim_angle_deg -= AIM_SPEED * delta
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

func _handle_movement(delta: float) -> void:
	velocity.y += GRAVITY * delta
	position += velocity * delta

	var floor_y: float = 700.0
	if position.y >= floor_y - HALF_HEIGHT:
		position.y = floor_y - HALF_HEIGHT
		velocity.y = 0.0
		velocity.x = 0.0

	var half_width: float = 15.0
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

	arrow.points = [Vector2.ZERO, tip]

	var head_len: float = 14.0
	var head_angle: float = deg_to_rad(30.0)

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

func set_player_label(text: String) -> void:
	var lbl: Label = get_node_or_null("PlayerLabel")
	if lbl == null:
		lbl = Label.new()
		lbl.name = "PlayerLabel"
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.position = Vector2(-20.0, -30.0)
		lbl.size = Vector2(70.0, 20.0)
		add_child(lbl)
	lbl.text = text
	lbl.visible = text != ""
