extends Node2D
# TutorialCrosshair — tutorial-only crosshair.
#
# Lifecycle paths:
#   set_idle_visual(unit, position) — visible but inert. No input, no kicking.
#                                      Used during the cinematic intro.
#   activate(unit, input_id)        — bind input, become interactive. Position
#                                      retained from current value (does NOT
#                                      snap to unit.position).
#   activate_and_position(unit, input_id) — same as activate but DOES snap to
#                                      unit.position. Used for fresh aimers.
#   deactivate()                    — stop accepting input, hide.
#   force_kick()                    — programmatic kick trigger (no input).
#
# Signals:
#   kick_launched(target_pos, zone, duration)
#   kick_resolved(target_pos, zone)
#   movement_started
 
signal kick_launched(target_pos: Vector2, zone: int, duration: float)
signal kick_resolved(target_pos: Vector2, zone: int)
signal movement_started
 
const RADIUS_INNER: float = 200.0
const RADIUS_MIDDLE: float = 300.0
const RADIUS_OUTER: float = 400.0
const MOVE_SPEED: float = 350.0
const CROSSHAIR_RADIUS: float = 50.0
const COUNTDOWN_TIME: Dictionary = {
	1: 0.7,
	2: 1.4,
	3: 2.1
}
 
var active: bool = false
var aiming_unit: Node2D = null
var current_zone: int = 1
var countdown_active: bool = false
var countdown_remaining: float = 0.0
var has_moved: bool = false
 
var movement_locked: bool = false
var kick_locked: bool = false
var required_target_unit: Node2D = null
 
# Zone-flash settings (used only by step 5).
var zone_flash_enabled: bool = false
var _last_zone_for_flash: int = -1
 
var aim_action_left: String = ""
var aim_action_right: String = ""
var aim_action_up: String = ""
var aim_action_down: String = ""
var kick_action: String = ""
 
@onready var countdown_label: Label = $CountdownLabel
@onready var circle: Line2D = $Circle
@onready var line_h: Line2D = $CrosshairLines/LineH
@onready var line_v: Line2D = $CrosshairLines/LineV
 
func _ready() -> void:
	_draw_circle(circle, CROSSHAIR_RADIUS)
	_draw_crosshair_lines()
	countdown_label.visible = false
	visible = false
 
# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
 
# Show the crosshair without making it interactive. Used during the cinematic
# intro so the crosshair is visible but the player can't move/kick.
func set_idle_visual(unit: Node2D, world_position: Vector2) -> void:
	aiming_unit = unit
	position = world_position
	visible = true
	active = false
	countdown_active = false
	countdown_label.visible = false
	has_moved = false
	movement_locked = false
	kick_locked = true
	required_target_unit = null
	zone_flash_enabled = false
	_clear_input_bindings()
	var aiming_color: Color = unit.unit_color
	circle.default_color = aiming_color
	line_h.default_color = aiming_color
	line_v.default_color = aiming_color
	line_h.visible = true
	line_v.visible = true
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	_update_zone()
	_update_countdown_label()
 
# Make the crosshair interactive for the given input. Does NOT snap position
# to the unit — retains current crosshair position.
func activate(unit: Node2D, input_id: String) -> void:
	aiming_unit = unit
	visible = true
	active = true
	countdown_active = false
	countdown_label.visible = false
	has_moved = false
	movement_locked = false
	kick_locked = false
	required_target_unit = null
	_last_zone_for_flash = -1
	_bind_input(input_id)
	var aiming_color: Color = unit.unit_color
	circle.default_color = aiming_color
	line_h.default_color = aiming_color
	line_v.default_color = aiming_color
	line_h.visible = true
	line_v.visible = true
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	_update_zone()
	_update_countdown_label()
 
# Same as activate() but ALSO snaps position to the unit.
func activate_and_position(unit: Node2D, input_id: String) -> void:
	position = unit.position
	activate(unit, input_id)
 
func deactivate() -> void:
	active = false
	visible = false
	countdown_active = false
 
func _bind_input(input_id: String) -> void:
	match input_id:
		"kb0":
			aim_action_left = "kb0_aim_left"
			aim_action_right = "kb0_aim_right"
			aim_action_up = "kb0_aim_up"
			aim_action_down = "kb0_aim_down"
			kick_action = "kb0_kick"
		"kb1":
			aim_action_left = "kb1_aim_left"
			aim_action_right = "kb1_aim_right"
			aim_action_up = "kb1_aim_up"
			aim_action_down = "kb1_aim_down"
			kick_action = "kb1_kick"
		_:
			var n: String = input_id.substr(3)
			aim_action_left = "joy_aim_left_" + n
			aim_action_right = "joy_aim_right_" + n
			aim_action_up = "joy_aim_up_" + n
			aim_action_down = "joy_aim_down_" + n
			kick_action = "joy_kick_" + n
 
func _clear_input_bindings() -> void:
	aim_action_left = ""
	aim_action_right = ""
	aim_action_up = ""
	aim_action_down = ""
	kick_action = ""
 
# ---------------------------------------------------------------------------
# Process
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not active:
		return
	if countdown_active:
		_handle_countdown(delta)
		return
	if not movement_locked:
		_handle_movement(delta)
		_update_zone()
		_update_countdown_label()
	if not kick_locked and kick_action != "" and Input.is_action_just_pressed(kick_action):
		_attempt_kick()
 
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
	if move.length() <= 0:
		return
	move = move.normalized()
	var new_pos: Vector2 = position + move * MOVE_SPEED * delta
	var offset: Vector2 = new_pos - aiming_unit.position
	if offset.length() > RADIUS_OUTER:
		offset = offset.normalized() * RADIUS_OUTER
	new_pos = aiming_unit.position + offset
	position = new_pos
	if not has_moved:
		has_moved = true
		movement_started.emit()
 
func _update_zone() -> void:
	if aiming_unit == null:
		return
	var dist: float = position.distance_to(aiming_unit.position)
	var new_zone: int = 1
	if dist <= RADIUS_INNER:
		new_zone = 1
	elif dist <= RADIUS_MIDDLE:
		new_zone = 2
	else:
		new_zone = 3
	if zone_flash_enabled and _last_zone_for_flash != -1 and new_zone != _last_zone_for_flash:
		flash_transition(0.05)
	_last_zone_for_flash = new_zone
	current_zone = new_zone
 
func _update_countdown_label() -> void:
	countdown_label.text = str(current_zone)
	countdown_label.visible = true
 
# ---------------------------------------------------------------------------
# Kick
# ---------------------------------------------------------------------------
func _attempt_kick() -> void:
	if required_target_unit != null:
		var target_radius: float = 60.0
		if position.distance_to(required_target_unit.position) > target_radius:
			return
	_start_countdown()
 
func force_kick() -> void:
	if not active or countdown_active:
		return
	_start_countdown()
 
func _start_countdown() -> void:
	countdown_active = true
	countdown_remaining = COUNTDOWN_TIME[current_zone]
	circle.default_color = Color.WHITE
	line_h.visible = false
	line_v.visible = false
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	kick_launched.emit(position, current_zone, countdown_remaining)
 
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
	kick_resolved.emit(position, current_zone)
 
# ---------------------------------------------------------------------------
# Visual flair
# ---------------------------------------------------------------------------
func flash_transition(duration: float = 0.05) -> void:
	if aiming_unit == null:
		return
	var original_color: Color = aiming_unit.unit_color
	circle.default_color = Color.WHITE
	line_h.default_color = Color.WHITE
	line_v.default_color = Color.WHITE
	var tween: Tween = create_tween()
	tween.tween_interval(duration)
	tween.tween_callback(func():
		if is_instance_valid(self):
			circle.default_color = original_color
			line_h.default_color = original_color
			line_v.default_color = original_color)
 
# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------
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
 
