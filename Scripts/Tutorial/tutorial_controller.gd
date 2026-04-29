extends Node2D
# TutorialController — orchestrates the tutorial as a sequence of steps.
#
# Lifecycle safety: every awaitable polling loop checks `_is_alive()` after
# each await frame. If the node has been freed (e.g. user clicked Main Menu
# during a step), the loop exits gracefully instead of crashing.
 
# ---------------------------------------------------------------------------
# Pitch / world constants
# ---------------------------------------------------------------------------
const PITCH_W: float = 2400.0
const PITCH_H: float = 900.0
 
const INTRO_BALL_POS: Vector2 = Vector2(1200.0, 450.0)
const INTRO_HOLDER_POS: Vector2 = Vector2(1200.0, 450.0)
const INTRO_TEAMMATE_POS: Vector2 = Vector2(900.0, 450.0)
const INTRO_CROSSHAIR_POS: Vector2 = Vector2(1000.0, 450.0)
const TEAM_A_COLOR: Color = Color(0.41568628, 0.050980393, 0.6784314, 1)
const PINK_COLOR: Color = Color(0.8, 0.26666668, 0.8, 1)
 
# Camera
const INTRO_ZOOM_START: Vector2 = Vector2(80.0, 80.0)
const INTRO_ZOOM_FINAL: Vector2 = Vector2(1.2, 1.2)
const INTRO_ZOOM_DURATION: float = 2.0
const INTRO_LABEL_REVEAL_FRACTION: float = 0.35
const CAMERA_FOLLOW_SPEED: float = 3.0
const CAMERA_BALL_FOLLOW_SPEED: float = 5.0
 
const CAMERA_BOUND_LEFT: float = -1500.0
const CAMERA_BOUND_RIGHT: float = 3900.0
const CAMERA_BOUND_TOP: float = 0.0
const CAMERA_BOUND_BOTTOM: float = 900.0
 
const TUTORIAL_INPUT_ID: String = "joy0"
 
const GLYPH_START: String = "[Start]"
const GLYPH_LSTICK: String = "[L-Stick]"
const GLYPH_A: String = "[A]"
 
const CASCADE_SPAWN_OFFSCREEN_X: float = -200.0
const CASCADE_RANGE3_OFFSET: float = -350.0
const CASCADE_RANGE2_OFFSET: float = -250.0
const CASCADE_RANGE1_OFFSET: float = -150.0
const SCRIPTED_WALK_SPEED: float = 350.0
 
const STEP4_KICK_PROMPT_TIMEOUT: float = 2.5
const STEP3_LINGER_AFTER_MOVE: float = 1.0
const STEP3_4_FLASH_INTERVAL: float = 1.5

const TUTORIAL_CONTEST_SCENE: PackedScene = preload("res://Scenes/Tutorial/tutorial_contest.tscn")

# Formation positions (from pitch.gd POSITIONS_A / POSITIONS_B)
const FORMATION_POSITIONS_A: Dictionary = {
	"centre":  Vector2(1250.0, 450.0),
	"goalie":  Vector2(100.0,  450.0),
	"winger":  Vector2(1200.0, 150.0),
	"defence": Vector2(1850.0, 450.0),
	"attack":  Vector2(650.0,  450.0),
}
const FORMATION_POSITIONS_B: Dictionary = {
	"centre":  Vector2(1150.0, 450.0),
	"goalie":  Vector2(2300.0, 450.0),
	"winger":  Vector2(1200.0, 750.0),
	"defence": Vector2(550.0,  450.0),
	"attack":  Vector2(1750.0, 450.0),
}

# Step 10 — goalie kick setup
const STEP10_AIMER_POSITION: Vector2 = Vector2(450.0, 450.0)  # zone-3 from goalie

# Step 8 — goal square + goalie pre-spawn (introduced here so they're already
# visible by the time step 11 labels them)
const GOAL_SQUARE_SIZE: Vector2 = Vector2(200.0, 300.0)

# Step 12 goalie kick
const STEP12_GOALIE_OFFSET_FROM_CROSSHAIR_X: float = -300.0

const STEP11_CAMERA_ZOOM: Vector2 = Vector2(0.6, 0.6)  # zoom out for full pitch
const STEP11_CAMERA_CENTRE: Vector2 = Vector2(1200.0, 450.0)  # pitch centre

# Step 13 formation reveal
const PITCH_TEXTURE_WITH_MARKINGS: Texture2D = preload("res://Assets/without goals.png")
const PITCH_W_SINGLE_TILE: Vector2 = Vector2(2400.0, 900.0)
const PITCH_CENTRE: Vector2 = Vector2(1200.0, 450.0)
const STEP13_CAMERA_ZOOM: Vector2 = Vector2(0.5, 0.5)

# Goal square colours (Team A purple, Team B pink, alpha 0.4)
const GOAL_SQUARE_COLOR_A: Color = Color(0.416, 0.051, 0.678, 0.196)  # #6A0DAD
const GOAL_SQUARE_COLOR_B: Color = Color(0.8, 0.26666668, 0.8, 0.196)  # #CC44CC pink

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var camera: Camera2D = $Camera2D
@onready var pitch_background: ColorRect = $PitchBackground
@onready var pitch_lines: Sprite2D = $PitchLines
@onready var units_a: Node2D = $UnitsA
@onready var units_b: Node2D = $UnitsB
@onready var pitch_ball: Node2D = $PitchBall
@onready var crosshair: Node2D = $TutorialCrosshair
@onready var ui: CanvasLayer = $TutorialUI
@onready var white_overlay: ColorRect = $UIRoot/WhiteOverlay
@onready var pause_menu: Control = $UIRoot/PauseMenu
 
var camera_target: Vector2 = Vector2.ZERO
var camera_follow_active: bool = false
var camera_follow_speed: float = CAMERA_FOLLOW_SPEED
 
# Step 7 — clamp player unit inside crosshair circle
var _clamp_player_to_crosshair: bool = false
var _player_unit_to_clamp: Node2D = null

# Custom unit movement (chunk 5e) — bypasses unit.gd's hardcoded pitch bounds.
# When _tutorial_unit_movement_active is true, _process reads input and
# moves _tutorial_movement_unit each frame at TUTORIAL_UNIT_MOVE_SPEED.
const TUTORIAL_UNIT_MOVE_SPEED: float = 135.0  # matches unit.gd ATTACK_MOVE_SPEED
var _tutorial_unit_movement_active: bool = false
var _tutorial_movement_unit: Node2D = null
var _tutorial_movement_actions: Dictionary = {}
 
var _saved_state: Dictionary = {}
 
const UNIT_SCENE: PackedScene = preload("res://Scenes/unit.tscn")
 
# Carried from step 8 to step 9.
var _step9_player_unit: Node2D = null
var _step9_ai_unit: Node2D = null

# Carried from step 13 to step 14.
var _step14_player_unit: Node2D = null
var _step14_ai_unit: Node2D = null

# Set during step 8's kick: where the contest crosshair was. Used by step 11/12
# to position the goalie relative to it (300px left).
var _step8_crosshair_kick_pos: Vector2 = Vector2.ZERO
var _tutorial_goalie: Node2D = null
var _tutorial_goal_square: ColorRect = null

# When true, camera position is set EXACTLY to camera_target each frame,
# bypassing the lerp. Used for step 15's outro where we want the camera
# locked tightly to the ball.
var camera_snap_mode: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_snapshot_game_state()
	_setup_pause_menu()
	_setup_initial_visual_state()
	_run_tutorial()
 
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("Pause"):
		_on_pause_pressed()
 
func _process(delta: float) -> void:
	if camera_follow_active:
		if camera_snap_mode:
			# Snap mode: camera is exactly at camera_target, no lerp, no clamp.
			# Used for step 15 where we want the camera locked tightly to the
			# ball regardless of pitch bounds.
			camera.position = camera_target
		else:
			camera.position = camera.position.lerp(camera_target, camera_follow_speed * delta)
			var vp_size: Vector2 = get_viewport_rect().size
			var half_w: float = (vp_size.x / 2.0) / camera.zoom.x
			var half_h: float = (vp_size.y / 2.0) / camera.zoom.y
			camera.position.x = clamp(camera.position.x,
				CAMERA_BOUND_LEFT + half_w, CAMERA_BOUND_RIGHT - half_w)
			camera.position.y = clamp(camera.position.y,
				CAMERA_BOUND_TOP + half_h, CAMERA_BOUND_BOTTOM - half_h)

	# Custom unit movement (bypasses unit.gd's hardcoded pitch bounds).
	if _tutorial_unit_movement_active and _tutorial_movement_unit != null \
			and is_instance_valid(_tutorial_movement_unit):
		var move: Vector2 = Vector2.ZERO
		if _tutorial_movement_actions.has("up") \
				and Input.is_action_pressed(_tutorial_movement_actions["up"]):
			move.y -= 1
		if _tutorial_movement_actions.has("down") \
				and Input.is_action_pressed(_tutorial_movement_actions["down"]):
			move.y += 1
		if _tutorial_movement_actions.has("left") \
				and Input.is_action_pressed(_tutorial_movement_actions["left"]):
			move.x -= 1
		if _tutorial_movement_actions.has("right") \
				and Input.is_action_pressed(_tutorial_movement_actions["right"]):
			move.x += 1
		if move.length() > 0:
			move = move.normalized()
			_tutorial_movement_unit.position += move * TUTORIAL_UNIT_MOVE_SPEED * delta

	# Crosshair clamp (must run AFTER tutorial movement so it constrains the
	# updated position).
	if _clamp_player_to_crosshair and _player_unit_to_clamp != null:
		var offset: Vector2 = _player_unit_to_clamp.position - crosshair.position
		var max_radius: float = crosshair.CROSSHAIR_RADIUS - 5.0
		if offset.length() > max_radius:
			offset = offset.normalized() * max_radius
			_player_unit_to_clamp.position = crosshair.position + offset

	# Step 15 AI per-frame work.
	if _step15_ai_active and not _step15_kick_in_progress:
		_step15_check_role_rotation(delta)

# ---------------------------------------------------------------------------
# Lifecycle-safe await primitives
# ---------------------------------------------------------------------------
 
# Returns true if this controller is still alive and in the scene tree.
# All polling loops must check this after their await.
func _is_alive() -> bool:
	return is_instance_valid(self) and is_inside_tree()
 
# Awaits a single process frame. Returns true if still alive after the await,
# false if the node was freed (caller should return early).
func _safe_await_frame() -> bool:
	await get_tree().process_frame
	return _is_alive()
 
# Awaits a SceneTreeTimer. Returns true if still alive after.
func _safe_await_timer(seconds: float) -> bool:
	# create_timer(time, process_always=false) makes it respect tree pause.
	await get_tree().create_timer(seconds, false).timeout
	return _is_alive()
 
# ---------------------------------------------------------------------------
# Pause menu
# ---------------------------------------------------------------------------
func _setup_pause_menu() -> void:
	if pause_menu == null:
		return
	pause_menu.visible = false
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	for child in pause_menu.get_children():
		child.process_mode = Node.PROCESS_MODE_ALWAYS
	var resume_btn: Button = pause_menu.get_node_or_null("ResumeButton")
	var options_btn: Button = pause_menu.get_node_or_null("OptionsButton")
	var main_menu_btn: Button = pause_menu.get_node_or_null("MainMenuButton")
	var quit_btn: Button = pause_menu.get_node_or_null("QuitButton")
	if resume_btn != null:
		resume_btn.pressed.connect(_on_resume)
	if options_btn != null:
		options_btn.pressed.connect(_on_options)
	if main_menu_btn != null:
		main_menu_btn.pressed.connect(_on_main_menu)
	if quit_btn != null:
		quit_btn.pressed.connect(_on_quit)
 
func _on_pause_pressed() -> void:
	if pause_menu == null:
		return
	if pause_menu.visible:
		_on_resume()
	else:
		get_tree().paused = true
		pause_menu.visible = true
		var resume_btn: Button = pause_menu.get_node_or_null("ResumeButton")
		if resume_btn != null:
			resume_btn.grab_focus()
 
func _on_resume() -> void:
	get_tree().paused = false
	if pause_menu != null:
		pause_menu.visible = false
 
func _on_options() -> void:
	pass
 
func _on_main_menu() -> void:
	get_tree().paused = false
	_exit_to_title()
 
func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()
 
# ---------------------------------------------------------------------------
# State save / restore
# ---------------------------------------------------------------------------
func _snapshot_game_state() -> void:
	_saved_state = {
		"players": GameState.players.duplicate(true),
		"score_a": GameState.score_a,
		"score_b": GameState.score_b,
		"attacking_team": GameState.attacking_team,
		"contest_winner": GameState.contest_winner,
		"return_scene": GameState.return_scene,
		"contest_reason": GameState.contest_reason,
		"contest_crosshair_pos": GameState.contest_crosshair_pos,
		"saved_unit_positions": GameState.saved_unit_positions.duplicate(true),
		"contest_player_index": GameState.contest_player_index,
	}
	GameState.players = [{"input_id": TUTORIAL_INPUT_ID, "team": "A", "unit_role": "centre"}]
	GameState.score_a = 0
	GameState.score_b = 0
	GameState.attacking_team = "A"
	GameState.contest_winner = ""
	GameState.return_scene = ""
	GameState.contest_reason = ""
	GameState.contest_crosshair_pos = Vector2.ZERO
	GameState.saved_unit_positions = {}
	GameState.contest_player_index = -1
 
func _restore_game_state() -> void:
	if _saved_state.is_empty():
		return
	GameState.players = _saved_state["players"]
	GameState.score_a = _saved_state["score_a"]
	GameState.score_b = _saved_state["score_b"]
	GameState.attacking_team = _saved_state["attacking_team"]
	GameState.contest_winner = _saved_state["contest_winner"]
	GameState.return_scene = _saved_state["return_scene"]
	GameState.contest_reason = _saved_state["contest_reason"]
	GameState.contest_crosshair_pos = _saved_state["contest_crosshair_pos"]
	GameState.saved_unit_positions = _saved_state["saved_unit_positions"]
	GameState.contest_player_index = _saved_state["contest_player_index"]
 
func _exit_to_title() -> void:
	# Tutorial has been seen at least once — don't auto-route to it on next launch.
	Settings.set_tutorial_on_launch(false)
	_restore_game_state()
	GameState.go_to_scene("res://Scenes/title.tscn")
 
# ---------------------------------------------------------------------------
# Initial visual setup
# ---------------------------------------------------------------------------
func _setup_initial_visual_state() -> void:
	var holder: Node2D = units_a.get_node_or_null("Holder")
	var teammate: Node2D = units_a.get_node_or_null("Teammate")
	if holder != null:
		holder.position = INTRO_HOLDER_POS
		holder.set_player_label("")
	if teammate != null:
		teammate.position = INTRO_TEAMMATE_POS
		teammate.set_player_label("")
 
	if holder != null and teammate != null:
		pitch_ball.attach_to_unit(holder, teammate.position)
 
	camera.position = pitch_ball.position
	camera.zoom = INTRO_ZOOM_START
	camera.make_current()
 
	white_overlay.visible = false
	pitch_background.visible = true
	pitch_lines.visible = true
 
	if holder != null:
		crosshair.set_idle_visual(holder, INTRO_CROSSHAIR_POS)
 
# ---------------------------------------------------------------------------
# Step runner
# ---------------------------------------------------------------------------
func _run_tutorial() -> void:
	await _step_01_cinematic_intro()
	if not _is_alive(): return
	_step_02_pause_prompt()
	if not _is_alive(): return
	await _step_03_crosshair_movement()
	if not _is_alive(): return
	await _step_04_first_kick()
	if not _is_alive(): return
	await _step_05_cascade()
	if not _is_alive(): return
	await _step_06_opponent_intro()
	if not _is_alive(): return
	await _step_07_defending()
	if not _is_alive(): return
	await _step_08_multi_unit_hint()
	if not _is_alive(): return
	await _step_09_first_contest()
	if not _is_alive(): return
	await _step_11_goalie_intro()
	if not _is_alive(): return
	await _step_12_goalie_kick()
	if not _is_alive(): return
	await _step_13_formation_reveal()
	if not _is_alive(): return
	await _step_14_restart_contest()
	if not _is_alive(): return
	await _step_15_tactical_demo()

# ---------------------------------------------------------------------------
# STEP 1 — Cinematic intro
# ---------------------------------------------------------------------------
func _step_01_cinematic_intro() -> void:
	if not await _safe_await_timer(0.4): return
 
	var framing_centre: Vector2 = (INTRO_HOLDER_POS + INTRO_TEAMMATE_POS) / 2.0
	var zoom_duration: float = INTRO_ZOOM_DURATION
	var label_delay: float = zoom_duration * INTRO_LABEL_REVEAL_FRACTION
 
	var tween: Tween = create_tween()
	tween.tween_method(_set_zoom_log, 0.0, 1.0, zoom_duration)\
		.set_trans(Tween.TRANS_LINEAR)
	tween.parallel().tween_property(camera, "position", framing_centre, zoom_duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_callback(_reveal_holder_label).set_delay(label_delay)
	await tween.finished
	if not _is_alive(): return
 
	await _safe_await_timer(0.5)
 
func _set_zoom_log(t: float) -> void:
	if not _is_alive(): return
	var z_start: float = INTRO_ZOOM_START.x
	var z_end: float = INTRO_ZOOM_FINAL.x
	var log_start: float = log(z_start)
	var log_end: float = log(z_end)
	var z: float = exp(lerp(log_start, log_end, t))
	camera.zoom = Vector2(z, z)
 
func _reveal_holder_label() -> void:
	if not _is_alive(): return
	var holder: Node2D = units_a.get_node_or_null("Holder")
	if holder != null:
		holder.set_player_label("P1")
 
# ---------------------------------------------------------------------------
# STEP 2 — Pause prompt
# ---------------------------------------------------------------------------
func _step_02_pause_prompt() -> void:
	# Set "PRESS START TO PAUSE" directly as a log entry. It's informational,
	# no required action. No timer, no time-lock — step 3 begins immediately.
	ui.set_log("PRESS START TO PAUSE AND ADJUST SETTINGS")
 
# ---------------------------------------------------------------------------
# STEP 3 — Crosshair movement
#
# Flow:
#   - Show "USE THE LEFT THUMBSTICK..." text.
#   - Allow crosshair movement, kick is locked.
#   - On first crosshair movement: linger 1s with text still visible, then
#     fade text. (No idle-flash here — that's step 4's job.)
# ---------------------------------------------------------------------------
func _step_03_crosshair_movement() -> void:
	var holder: Node2D = units_a.get_node_or_null("Holder")
	var teammate: Node2D = units_a.get_node_or_null("Teammate")
	if holder == null or teammate == null:
		return

	crosshair.activate(holder, TUTORIAL_INPUT_ID)
	crosshair.kick_locked = true

	ui.show_instruction("USE THE LEFT THUMBSTICK TO MOVE THE CROSSHAIR", GLYPH_LSTICK)

	while _is_alive() and not crosshair.has_moved:
		await get_tree().process_frame
	if not _is_alive(): return

	# Unlock the kick AS SOON AS the player has started moving — they
	# shouldn't have to wait through the text linger to act.
	crosshair.required_target_unit = teammate
	crosshair.kick_locked = false

	# Begin the text fade non-blocking, in parallel with step 4 logic.
	ui.hide_instruction()
	# No await here — step 4 starts immediately.
 
# ---------------------------------------------------------------------------
# STEP 4 — First kick
#
# Flow:
#   - Allow kick (kick_locked = false), but require crosshair on teammate.
#   - Watch the crosshair for 2.5s.
#   - If crosshair lands on teammate at any point: show "PRESS A TO KICK..."
#     immediately. Stop watching.
#   - If 2.5s pass without crosshair landing on teammate: force-show the
#     prompt AND start flashing the teammate. Flash continues until
#     crosshair is on teammate.
#   - Once kick is launched: text persists through countdown, then ball
#     flight, then fades after resolution.
# ---------------------------------------------------------------------------
func _step_04_first_kick() -> void:
	var holder: Node2D = units_a.get_node_or_null("Holder")
	var teammate: Node2D = units_a.get_node_or_null("Teammate")
	if holder == null or teammate == null:
		return
 
	# Watch for crosshair-on-teammate or timeout, whichever comes first.
	var elapsed: float = 0.0
	var prompt_shown: bool = false
	var flash_active: bool = false
 
	while _is_alive() and not prompt_shown:
		var on_teammate: bool = crosshair.position.distance_to(teammate.position) <= 60.0
		if on_teammate:
			ui.show_instruction("PRESS A TO KICK THE BALL TO YOUR TEAMMATE", GLYPH_A)
			prompt_shown = true
			break
		if elapsed >= STEP4_KICK_PROMPT_TIMEOUT and not flash_active:
			# Player has been moving without finding teammate. Force-show and start flashing.
			ui.show_instruction("PRESS A TO KICK THE BALL TO YOUR TEAMMATE", GLYPH_A)
			prompt_shown = true
			flash_active = true
			_start_attention_flash(teammate, func():
				return _is_alive() and \
					crosshair.position.distance_to(teammate.position) > 60.0)
			break
		elapsed += get_process_delta_time()
		await get_tree().process_frame
	if not _is_alive(): return
 
	# Wait for the kick. Text remains visible throughout.
	var kick_data: Array = await crosshair.kick_launched
	if not _is_alive(): return
	var target_pos: Vector2 = kick_data[0]
	var zone: int = kick_data[1]
	var duration: float = kick_data[2]
 
	pitch_ball.launch(holder.position, target_pos, duration, zone)
	camera_target = pitch_ball.position
	camera_follow_active = true
	camera_follow_speed = CAMERA_BALL_FOLLOW_SPEED
 
	ui.show_moment("NICE KICK!", TEAM_A_COLOR.lightened(0.4), 0.8, holder.position)
 
	# Track ball + countdown in a single polling loop. Exits when both done.
	# This avoids the kick_resolved signal race.
	while _is_alive() and (pitch_ball._flying or crosshair.countdown_active):
		if pitch_ball._flying:
			camera_target = pitch_ball.position
		await get_tree().process_frame
	if not _is_alive(): return
 
	# Now fade the kick prompt.
	await ui.hide_instruction()
	if not _is_alive(): return
 
	pitch_ball.attach_to_unit(teammate, teammate.position + Vector2(-100, 0))
	camera_target = teammate.position
	camera_follow_speed = CAMERA_FOLLOW_SPEED

	# Re-bind crosshair to the new aimer (teammate) IMMEDIATELY so the player
	# can move the crosshair while NICE CATCH plays (rather than waiting).
	holder.set_player_label("")
	teammate.set_player_label("P1")
	crosshair.activate_and_position(teammate, TUTORIAL_INPUT_ID)

	await ui.show_moment("NICE CATCH!", TEAM_A_COLOR.lightened(0.4), 1.0, teammate.position)
	if not _is_alive(): return
 
	await _safe_await_timer(0.4)
 
# Schedules a periodic flash on `unit` while `still_flashing` returns true.
# First flash is immediate. Subsequent flashes every STEP3_4_FLASH_INTERVAL.
func _start_attention_flash(unit: Node2D, still_flashing: Callable) -> void:
	if not _is_alive() or unit == null:
		return
	if not still_flashing.call():
		return
	_flash_unit(unit)
	_repeat_attention_flash(unit, still_flashing)
 
func _repeat_attention_flash(unit: Node2D, still_flashing: Callable) -> void:
	if not await _safe_await_timer(STEP3_4_FLASH_INTERVAL): return
	if still_flashing.call() and is_instance_valid(unit):
		_flash_unit(unit)
		_repeat_attention_flash(unit, still_flashing)
 
func _flash_unit(unit: Node2D, duration: float = 0.25) -> void:
	if unit == null:
		return
	var rect: ColorRect = unit.get_node_or_null("ColorRect")
	if rect == null:
		return
	var original: Color = rect.color
	rect.color = Color.WHITE
	var t: Tween = create_tween()
	t.tween_interval(duration)
	t.tween_callback(func():
		if is_instance_valid(rect):
			rect.color = original)
 
# ---------------------------------------------------------------------------
# STEP 5 — Cascade: zone-3 → zone-2 → zone-1 kicks with walk-ins
# ---------------------------------------------------------------------------
func _step_05_cascade() -> void:
	var teammate: Node2D = units_a.get_node_or_null("Teammate")
	var holder: Node2D = units_a.get_node_or_null("Holder")
	if teammate == null:
		return
 
	crosshair.activate_and_position(teammate, TUTORIAL_INPUT_ID)
	crosshair.flash_transition(0.08)
	crosshair.zone_flash_enabled = true
 
	if holder != null:
		var fade: Tween = create_tween()
		fade.tween_property(holder, "modulate:a", 0.0, 0.4)
		fade.tween_callback(func():
			if is_instance_valid(holder):
				holder.queue_free())

	ui.show_instruction("LONGER KICKS TAKE LONGER TO LAND", "")

	# Spawn AND walk the new unit in immediately. No await on the holder fade.
	var t_zone3: Node2D = _spawn_unit(units_a, "Teammate2",
		Vector2(teammate.position.x - 700.0, teammate.position.y), "A", TEAM_A_COLOR)
	var t_zone3_pos: Vector2 = teammate.position + Vector2(CASCADE_RANGE3_OFFSET, 0)
	await _walk_unit_to(t_zone3, t_zone3_pos)
	if not _is_alive(): return
 
	var t_zone2_pos: Vector2 = t_zone3_pos + Vector2(CASCADE_RANGE2_OFFSET, 0)
	var t_zone2: Node2D = _spawn_unit(units_a, "Teammate3",
		Vector2(t_zone2_pos.x - 800.0, t_zone2_pos.y), "A", TEAM_A_COLOR)
 
	await _cascade_kick(teammate, t_zone3, t_zone2, t_zone2_pos)
	if not _is_alive(): return
 
	var t_zone1_pos: Vector2 = t_zone2_pos + Vector2(CASCADE_RANGE1_OFFSET, 0)
	var t_zone1: Node2D = _spawn_unit(units_a, "Teammate4",
		Vector2(t_zone1_pos.x - 800.0, t_zone1_pos.y), "A", TEAM_A_COLOR)
 
	await _cascade_kick(t_zone3, t_zone2, t_zone1, t_zone1_pos)
	if not _is_alive(): return
 
	await _cascade_kick_final(t_zone2, t_zone1)
	if not _is_alive(): return
 
	crosshair.zone_flash_enabled = false

	# Spawn pink (for step 6) NOW so it can start walking in while step 5's
	# text lingers and fades. Step 6 will pick it up.
	var aimer_at_end: Node2D = _find_p1_unit()
	if aimer_at_end != null:
		# Spawn ~700 units left of the current aimer so it's always off-camera
		# regardless of how far the cascade has walked the action leftward.
		var pink_spawn_x: float = aimer_at_end.position.x - 700.0
		var pink_early: Node2D = _spawn_unit(units_b, "PinkOpponent",
			Vector2(pink_spawn_x, aimer_at_end.position.y),
			"B", PINK_COLOR)
		var pink_target: Vector2 = aimer_at_end.position + Vector2(-250.0, 0.0)
		# Walk in parallel; don't await.
		var walk_dist: float = pink_early.position.distance_to(pink_target)
		var walk_time: float = walk_dist / SCRIPTED_WALK_SPEED
		var walk_tween: Tween = create_tween()
		walk_tween.tween_property(pink_early, "position", pink_target, walk_time)

	await ui.hide_instruction()
	if not _is_alive(): return
	await _safe_await_timer(0.4)
 
func _cascade_kick(aimer: Node2D, target: Node2D,
		next_unit: Node2D, next_unit_target: Vector2) -> void:
	crosshair.required_target_unit = target
	crosshair.kick_locked = false
 
	var kick_data: Array = await crosshair.kick_launched
	if not _is_alive(): return
	var target_pos: Vector2 = kick_data[0]
	var zone: int = kick_data[1]
	var duration: float = kick_data[2]
 
	pitch_ball.launch(aimer.position, target_pos, duration, zone)
	camera_target = pitch_ball.position
	camera_follow_active = true
	camera_follow_speed = CAMERA_BALL_FOLLOW_SPEED
 
	var walk_distance: float = next_unit.position.distance_to(next_unit_target)
	var walk_speed: float = walk_distance / max(duration, 0.1)
 
	# Single polling loop: exits when both ball and countdown finish.
	while _is_alive() and (pitch_ball._flying or crosshair.countdown_active):
		if pitch_ball._flying:
			camera_target = pitch_ball.position
		if next_unit != null and is_instance_valid(next_unit) \
				and next_unit.position.distance_to(next_unit_target) > 1.0:
			var dir: Vector2 = (next_unit_target - next_unit.position).normalized()
			next_unit.position += dir * walk_speed * get_process_delta_time()
		await get_tree().process_frame
	if not _is_alive(): return
 
	if next_unit != null and is_instance_valid(next_unit):
		next_unit.position = next_unit_target
 
	pitch_ball.attach_to_unit(target, target.position + Vector2(-50, 0))
	camera_target = target.position
	camera_follow_speed = CAMERA_FOLLOW_SPEED
	aimer.set_player_label("")
	target.set_player_label("P1")
 
	var fade: Tween = create_tween()
	fade.tween_property(aimer, "modulate:a", 0.0, 0.4)
 
	crosshair.activate_and_position(target, TUTORIAL_INPUT_ID)
	crosshair.zone_flash_enabled = true
	crosshair.flash_transition(0.08)
 
	await fade.finished
	if not _is_alive(): return
	if is_instance_valid(aimer):
		aimer.queue_free()
 
func _cascade_kick_final(aimer: Node2D, target: Node2D) -> void:
	crosshair.required_target_unit = target
	crosshair.kick_locked = false
 
	var kick_data: Array = await crosshair.kick_launched
	if not _is_alive(): return
	var target_pos: Vector2 = kick_data[0]
	var zone: int = kick_data[1]
	var duration: float = kick_data[2]
 
	pitch_ball.launch(aimer.position, target_pos, duration, zone)
	camera_target = pitch_ball.position
	camera_follow_active = true
	camera_follow_speed = CAMERA_BALL_FOLLOW_SPEED
 
	while _is_alive() and (pitch_ball._flying or crosshair.countdown_active):
		if pitch_ball._flying:
			camera_target = pitch_ball.position
		await get_tree().process_frame
	if not _is_alive(): return
 
	pitch_ball.attach_to_unit(target, target.position + Vector2(-50, 0))
	camera_target = target.position
	camera_follow_speed = CAMERA_FOLLOW_SPEED
	aimer.set_player_label("")
	target.set_player_label("P1")
 
	var fade: Tween = create_tween()
	fade.tween_property(aimer, "modulate:a", 0.0, 0.4)
 
	crosshair.activate_and_position(target, TUTORIAL_INPUT_ID)
	crosshair.flash_transition(0.08)
 
	await fade.finished
	if not _is_alive(): return
	if is_instance_valid(aimer):
		aimer.queue_free()
 
# ---------------------------------------------------------------------------
# STEP 6 — Opponent introduction
# ---------------------------------------------------------------------------
func _step_06_opponent_intro() -> void:
	var aimer: Node2D = _find_p1_unit()
	if aimer == null:
		return
 
	crosshair.kick_locked = true

	# Pink was spawned at end of step 5 and is walking in. Find it.
	var pink: Node2D = units_b.get_node_or_null("PinkOpponent")
	if pink == null:
		# Fallback: spawn now if step 5 didn't (e.g. P1 not found).
		pink = _spawn_unit(units_b, "PinkOpponent",
			Vector2(aimer.position.x - 700.0, aimer.position.y),
			"B", PINK_COLOR)

	ui.show_instruction("THE PINK UNIT IS YOUR OPPONENT", "")

	# Wait for pink to reach its target if not already there.
	var pink_target: Vector2 = aimer.position + Vector2(-250.0, 0.0)
	while _is_alive() and is_instance_valid(pink) \
			and pink.position.distance_to(pink_target) > 5.0:
		await get_tree().process_frame
	if not _is_alive(): return

	# Show kick prompt immediately as pink arrives — no pause.
	ui.show_instruction("KICK TO THEM AND LET'S LEARN HOW TO DEFEND", GLYPH_A)
 
	crosshair.required_target_unit = pink
	crosshair.kick_locked = false
 
	var kick_data: Array = await crosshair.kick_launched
	if not _is_alive(): return
 
	var target_pos: Vector2 = kick_data[0]
	var zone: int = kick_data[1]
	var duration: float = kick_data[2]
 
	pitch_ball.launch(aimer.position, target_pos, duration, zone)
	camera_target = pitch_ball.position
	camera_follow_active = true
	camera_follow_speed = CAMERA_BALL_FOLLOW_SPEED
 
	while _is_alive() and (pitch_ball._flying or crosshair.countdown_active):
		if pitch_ball._flying:
			camera_target = pitch_ball.position
		await get_tree().process_frame
	if not _is_alive(): return
 
	await ui.hide_instruction()
	if not _is_alive(): return
 
	# Pink is now defending — aiming LEFT toward player. Ball goes on LEFT.
	pitch_ball.attach_to_unit(pink, pink.position + Vector2(-50, 0))
	camera_target = pink.position
	camera_follow_speed = CAMERA_FOLLOW_SPEED
 
	# P1 label STAYS on aimer — player still controls it in step 7.
 
	await _safe_await_timer(0.4)
 
# ---------------------------------------------------------------------------
# STEP 7 — Defending
# ---------------------------------------------------------------------------
func _step_07_defending() -> void:
	var pink: Node2D = units_b.get_node_or_null("PinkOpponent")
	var player_unit: Node2D = _find_p1_unit()
	if pink == null or player_unit == null:
		return
 
	var crosshair_target_pos: Vector2 = pink.position + Vector2(-250.0, 0.0)
 
	crosshair.set_idle_visual(pink, crosshair_target_pos)
	crosshair.circle.default_color = PINK_COLOR
	crosshair.line_h.default_color = PINK_COLOR
	crosshair.line_v.default_color = PINK_COLOR
 
	# Use the tutorial's custom movement handler (in _process), which bypasses
	# unit.gd's hardcoded pitch bounds.
	var actions: Dictionary = _get_move_actions_for_input(TUTORIAL_INPUT_ID)
	_tutorial_movement_unit = player_unit
	_tutorial_movement_actions = actions
	_tutorial_unit_movement_active = true
 
	ui.show_instruction("USE THE LEFT THUMBSTICK TO MOVE YOUR UNIT", GLYPH_LSTICK)
 
	var unit_start_pos: Vector2 = player_unit.position
	while _is_alive() and player_unit.position.distance_to(unit_start_pos) < 10.0:
		await get_tree().process_frame
	if not _is_alive(): return
 
	ui.show_instruction("MOVE INTO THE CROSSHAIR TO WIN THE BALL BACK", "")
 
	while _is_alive() and player_unit.position.distance_to(crosshair.position) > crosshair.CROSSHAIR_RADIUS:
		await get_tree().process_frame
	if not _is_alive(): return
 
	await ui.hide_instruction()
	if not _is_alive(): return
 
	_player_unit_to_clamp = player_unit
	_clamp_player_to_crosshair = true
 
	crosshair.active = true
	crosshair._update_zone()
	var zone: int = crosshair.current_zone
	var duration: float = crosshair.COUNTDOWN_TIME[zone]
 
	crosshair.force_kick()
	pitch_ball.launch(pink.position, crosshair.position, duration, zone)
	camera_target = pitch_ball.position
	camera_follow_active = true
	camera_follow_speed = CAMERA_BALL_FOLLOW_SPEED
 
	while _is_alive() and (pitch_ball._flying or crosshair.countdown_active):
		if pitch_ball._flying:
			camera_target = pitch_ball.position
		await get_tree().process_frame
	if not _is_alive(): return
 
	_clamp_player_to_crosshair = false
	_player_unit_to_clamp = null
	_tutorial_unit_movement_active = false
	_tutorial_movement_unit = null
	_tutorial_movement_actions = {}
 
	await ui.show_moment("NICE DEFENCE!", TEAM_A_COLOR.lightened(0.4), 1.0, player_unit.position)
	if not _is_alive(): return
 
	pitch_ball.attach_to_unit(player_unit, player_unit.position + Vector2(20, 0))
	camera_target = player_unit.position
	camera_follow_speed = CAMERA_FOLLOW_SPEED

	crosshair.activate_and_position(player_unit, TUTORIAL_INPUT_ID)

	# Pink walks offscreen-right and fades out (it's defeated, leaves the play).
	_walk_and_fade_unit_async(pink, pink.position + Vector2(800.0, 0.0), 0.6)

	await _safe_await_timer(0.4)
 
# ---------------------------------------------------------------------------
# STEP 8 — Multi-unit hint (storyboard Tutorial 5)
#
# Layout: two purple teammates mid-zone-3 from aimer, one slightly above one
# below. Pink unit slightly left of bottom purple. All three walk in together.
# Player can kick within ~200 units of any of the three. On kick, the nearest
# of the two new purples (NOT the aimer) and the pink converge on the
# crosshair, arriving before countdown reaches zero.
# ---------------------------------------------------------------------------
const STEP8_PURPLE_DISTANCE: float = 350.0
const STEP8_PURPLE_VERTICAL_OFFSET: float = 80.0
const STEP8_PINK_X_OFFSET: float = -100.0  # how far left of bottom-purple
const STEP8_TARGET_TOLERANCE: float = 200.0  # kick valid within this of any unit

func _step_08_multi_unit_hint() -> void:
	var aimer: Node2D = _find_p1_unit()
	if aimer == null:
		return

	# Compute target positions.
	var purple_top_target: Vector2 = aimer.position + Vector2(
		-STEP8_PURPLE_DISTANCE, -STEP8_PURPLE_VERTICAL_OFFSET)
	var purple_bottom_target: Vector2 = aimer.position + Vector2(
		-STEP8_PURPLE_DISTANCE, STEP8_PURPLE_VERTICAL_OFFSET)
	var pink_target: Vector2 = purple_bottom_target + Vector2(STEP8_PINK_X_OFFSET, 0.0)

	# Spawn all three offscreen-left.
	var entry_y: float = aimer.position.y
	var spawn_offscreen_x: float = aimer.position.x - 800.0
	var purple_top: Node2D = _spawn_unit(units_a, "Teammate5",
		Vector2(spawn_offscreen_x, entry_y - STEP8_PURPLE_VERTICAL_OFFSET),
		"A", TEAM_A_COLOR)
	var purple_bottom: Node2D = _spawn_unit(units_a, "Teammate6",
		Vector2(spawn_offscreen_x, entry_y + STEP8_PURPLE_VERTICAL_OFFSET),
		"A", TEAM_A_COLOR)
	var pink_step8: Node2D = _spawn_unit(units_b, "PinkBlocker",
		Vector2(spawn_offscreen_x - 100.0, entry_y + STEP8_PURPLE_VERTICAL_OFFSET),
		"B", PINK_COLOR)

	ui.show_instruction("SOMETIMES MANY UNITS CAN REACH THE CROSSHAIR", "")

	# Walk all three in together.
	var walk_top: Tween = create_tween()
	var walk_top_dist: float = purple_top.position.distance_to(purple_top_target)
	walk_top.tween_property(purple_top, "position", purple_top_target,
		walk_top_dist / SCRIPTED_WALK_SPEED)
	var walk_bot: Tween = create_tween()
	var walk_bot_dist: float = purple_bottom.position.distance_to(purple_bottom_target)
	walk_bot.tween_property(purple_bottom, "position", purple_bottom_target,
		walk_bot_dist / SCRIPTED_WALK_SPEED)
	var walk_pink: Tween = create_tween()
	var walk_pink_dist: float = pink_step8.position.distance_to(pink_target)
	walk_pink.tween_property(pink_step8, "position", pink_target,
		walk_pink_dist / SCRIPTED_WALK_SPEED)
	# Wait for the longest walk to complete.
	await walk_pink.finished
	if not _is_alive(): return

	# Set up the crosshair to allow a kick within tolerance of any of the
	# three units. We do NOT set required_target_unit; instead we wrap the
	# kick check ourselves. NOTE: we don't reset the crosshair position
	# (player may have moved it during the walk-in).
	crosshair.activate(aimer, TUTORIAL_INPUT_ID)  # don't reposition!
	crosshair.required_target_unit = null
	crosshair.kick_locked = true  # we manage kick gating ourselves

	# Custom kick gate: poll until the player presses the kick action AND
	# the crosshair is near one of the three units.
	var kick_input_action: String = "joy_kick_0"  # matches TUTORIAL_INPUT_ID = "joy0"
	var validation_units: Array = [purple_top, purple_bottom, pink_step8]
	while _is_alive():
		if Input.is_action_just_pressed(kick_input_action):
			var nearest_to_crosshair: Node2D = _nearest_unit_to_position(
				validation_units, crosshair.position)
			if nearest_to_crosshair != null \
					and crosshair.position.distance_to(nearest_to_crosshair.position) \
						<= STEP8_TARGET_TOLERANCE:
				# Valid kick. Trigger the countdown ourselves.
				crosshair.force_kick()
				break
		await get_tree().process_frame
	if not _is_alive(): return

	# Wait for kick_launched (it fires from inside force_kick, but force_kick
	# is sync so the signal already fired — we capture state directly).
	var target_pos: Vector2 = crosshair.position
	var zone: int = crosshair.current_zone
	var duration: float = crosshair.COUNTDOWN_TIME[zone]

	# Save the crosshair position so steps 11/12 can position the goalie
	# relative to it (300px left).
	_step8_crosshair_kick_pos = target_pos

	# Pre-spawn the goal square + goalie 300px left of the crosshair. They
	# appear during the kick's leftward camera pan as if always present.
	var goalie_pos: Vector2 = target_pos + Vector2(STEP12_GOALIE_OFFSET_FROM_CROSSHAIR_X, 0.0)
	_spawn_goal_square_and_goalie(goalie_pos)

	# Launch ball arc.
	pitch_ball.launch(aimer.position, target_pos, duration, zone)
	camera_target = pitch_ball.position
	camera_follow_active = true
	camera_follow_speed = CAMERA_BALL_FOLLOW_SPEED

	# During the arc: nearest of the two new purples + pink converge on the
	# crosshair. They must arrive before countdown reaches zero, so walk
	# slightly faster than required.
	var nearest_purple: Node2D = _nearest_unit_in_list(
		[purple_top, purple_bottom], target_pos)
	var convergence_arrival_time: float = duration * 0.85  # arrive 85% through

	# Set up converge tweens.
	var purple_offset: Vector2 = Vector2(20.0, 0.0)
	var pink_offset: Vector2 = Vector2(-20.0, 0.0)
	var converge_purple: Tween = create_tween()
	converge_purple.tween_property(nearest_purple, "position",
		target_pos + purple_offset, convergence_arrival_time)
	var converge_pink: Tween = create_tween()
	converge_pink.tween_property(pink_step8, "position",
		target_pos + pink_offset, convergence_arrival_time)

	# Track ball + countdown.
	while _is_alive() and (pitch_ball._flying or crosshair.countdown_active):
		if pitch_ball._flying:
			camera_target = pitch_ball.position
		await get_tree().process_frame
	if not _is_alive(): return

	# Hand off ball to the converged purple.
	pitch_ball.attach_to_unit(nearest_purple, nearest_purple.position + Vector2(-30, 0))
	camera_target = nearest_purple.position
	camera_follow_speed = CAMERA_FOLLOW_SPEED
	aimer.set_player_label("")
	nearest_purple.set_player_label("P1")

	await ui.hide_instruction()
	if not _is_alive(): return
	await _safe_await_timer(0.4)

	# Save references for step 9 (the contest needs the converged units).
	_step9_player_unit = nearest_purple
	_step9_ai_unit = pink_step8

	# Fade out the non-converged purple — it's no longer in play.
	var unconverged_purple: Node2D = purple_top if nearest_purple == purple_bottom else purple_bottom
	if is_instance_valid(unconverged_purple):
		var fade: Tween = create_tween()
		fade.tween_property(unconverged_purple, "modulate:a", 0.0, 0.6)
		fade.tween_callback(func():
			if is_instance_valid(unconverged_purple):
				unconverged_purple.queue_free())

# ---------------------------------------------------------------------------
# STEP 9 — Contest intro + first contest (player wins)
#
# Storyboard panels (Tutorial 5 panels 5+):
#   - "WHEN EACH TEAM HAS A UNIT AT THE TARGET, A CONTEST OCCURS" — text
#   - The two converged units (purple + pink at crosshair) trigger a contest.
#   - Contest popup opens. Sandbagged AI. Player wins.
#   - Returns to scene. Player's purple unit retains the ball.
# ---------------------------------------------------------------------------
func _step_09_first_contest() -> void:
	if _step9_player_unit == null or _step9_ai_unit == null:
		return
	if not is_instance_valid(_step9_player_unit) or not is_instance_valid(_step9_ai_unit):
		return

	# Show contest intro text. Don't move the camera — units are at crosshair.
	ui.show_instruction(
		"WHEN EACH TEAM HAS A UNIT AT THE TARGET, A CONTEST OCCURS\n(THEY ALSO OCCUR IF NO-ONE IS AT THE TARGET)",
		"", 28)
	if not await _safe_await_timer(2.5): return
	await ui.hide_instruction()
	if not _is_alive(): return

	# Instantiate the tutorial contest scene as a child of this controller.
	var contest: Node2D = TUTORIAL_CONTEST_SCENE.instantiate()
	# Add to a CanvasLayer so it renders above the world. Use UIRoot.
	var ui_root: CanvasLayer = $UIRoot
	ui_root.add_child(contest)
	# Move pause menu to the back of UIRoot's children so it renders ON TOP
	# of the contest popup. (Last child renders on top.)
	if pause_menu != null and pause_menu.get_parent() == ui_root:
		ui_root.move_child(pause_menu, ui_root.get_child_count() - 1)
	# Clear main current/log slots — contest has its own labels.
	ui.force_hide_now()
	ui.clear_log()

	# Connect signal. Use an Array as a mutable wrapper so the lambda's
	# write actually reaches outer scope.
	var winner_holder: Array = [""]
	contest.contest_finished.connect(func(w: String):
		winner_holder[0] = w)
	# Start the contest. AI is fully sandbagged — player wins.
	contest.start_scripted_contest(TUTORIAL_INPUT_ID, "A", 1.0)

	# Wait for contest_finished. We use a polling loop on a local var rather
	# than `await contest.contest_finished` to avoid the async signal race.
	while _is_alive() and winner_holder[0] == "":
		await get_tree().process_frame
	if not _is_alive(): return
	contest.queue_free()
	if not _is_alive(): return

	# After the contest, the player's purple unit "wins" the ball back.
	# Attach the pitch ball to it and clean up the AI unit.
	if is_instance_valid(_step9_player_unit):
		pitch_ball.attach_to_unit(_step9_player_unit,
			_step9_player_unit.position + Vector2(-30, 0))
		camera_target = _step9_player_unit.position
		camera_follow_speed = CAMERA_FOLLOW_SPEED

	# Pink leaves the field.
	if is_instance_valid(_step9_ai_unit):
		_walk_and_fade_unit_async(_step9_ai_unit,
			_step9_ai_unit.position + Vector2(800.0, 0.0), 0.6)

	await _safe_await_timer(0.4)
 
# ---------------------------------------------------------------------------
# STEP 10 — Just text. "CONTESTS ALSO OCCUR IF NO-ONE IS AT THE TARGET"
#
# After step 9's contest, the player retains the ball at the converged
# position. This step is purely instructional — no playable content.
# ---------------------------------------------------------------------------
func _step_10_no_one_contest_text() -> void:
	ui.show_instruction("CONTESTS ALSO OCCUR IF NO-ONE IS AT THE TARGET", "")
	if not await _safe_await_timer(3.0): return
	await ui.hide_instruction()
	if not _is_alive(): return
	await _safe_await_timer(0.4)

# ---------------------------------------------------------------------------
# STEP 11 — Goalie introduction. "EACH TEAM HAS A GOALIE AT ONE END OF
# THE PITCH"
#
# The goalie + goal square were pre-spawned during step 8's kick, so they
# should already be visible (camera should have framed them during the
# leftward pan). This step just labels them.
# ---------------------------------------------------------------------------
func _step_11_goalie_intro() -> void:
	# Pan the camera to frame both P1 and the goalie if needed (in case the
	# player has been moving the crosshair around).
	var p1: Node2D = _find_p1_unit()
	if p1 != null and _tutorial_goalie != null and is_instance_valid(_tutorial_goalie):
		var midpoint: Vector2 = (p1.position + _tutorial_goalie.position) / 2.0
		camera_target = midpoint
		camera_follow_active = true
		camera_follow_speed = CAMERA_FOLLOW_SPEED
		# Brief moment to let the camera settle.
		if not await _safe_await_timer(0.4): return

	ui.show_instruction("EACH TEAM HAS A GOALIE AT ONE END OF THE PITCH", "")
	if not await _safe_await_timer(3.0): return
	await ui.hide_instruction()
	if not _is_alive(): return
	await _safe_await_timer(0.3)

# ---------------------------------------------------------------------------
# STEP 12 — Goalie kick. "KICK TO YOUR GOALIE TO SCORE A GOAL"
#
# Player kicks at the goalie. Ball arcs. "GOAL!" big text on landing.
# ---------------------------------------------------------------------------
func _step_12_goalie_kick() -> void:
	var p1: Node2D = _find_p1_unit()
	if p1 == null or _tutorial_goalie == null or not is_instance_valid(_tutorial_goalie):
		return

	# Re-bind crosshair to P1 (in case it was deactivated).
	crosshair.activate_and_position(p1, TUTORIAL_INPUT_ID)
	crosshair.required_target_unit = _tutorial_goalie
	crosshair.kick_locked = false

	ui.show_instruction("KICK TO YOUR GOALIE TO SCORE A GOAL", GLYPH_A)

	var kick_data: Array = await crosshair.kick_launched
	if not _is_alive(): return
	var target_pos: Vector2 = kick_data[0]
	var zone: int = kick_data[1]
	var duration: float = kick_data[2]

	pitch_ball.launch(p1.position, target_pos, duration, zone)
	camera_target = pitch_ball.position
	camera_follow_active = true
	camera_follow_speed = CAMERA_BALL_FOLLOW_SPEED

	while _is_alive() and (pitch_ball._flying or crosshair.countdown_active):
		if pitch_ball._flying:
			camera_target = pitch_ball.position
		await get_tree().process_frame
	if not _is_alive(): return

	# Goalie catches the ball.
	pitch_ball.attach_to_unit(_tutorial_goalie,
		_tutorial_goalie.position + Vector2(20, 0))
	camera_target = _tutorial_goalie.position
	camera_follow_speed = CAMERA_FOLLOW_SPEED

	await ui.hide_instruction()
	if not _is_alive(): return

	await ui.show_moment("GOAL!", TEAM_A_COLOR.lightened(0.4), 1.5, _tutorial_goalie.position)
	if not _is_alive(): return

	await _safe_await_timer(0.4)

# ---------------------------------------------------------------------------
# STEP 13 — Formation reveal
#
# Hard cut from step 12's "GOAL!" view to the zoomed-out full-pitch formation:
# - Free all existing units (P1 + tutorial goalie + step-8 goal square)
# - Swap PitchLines texture to "without goal.png" (markings included), disable
#   region tiling so markings appear in correct positions
# - Spawn 10 new units in formation
# - Spawn both team A + team B goal squares at standard positions
# - Snap camera to pitch centre, zoom out
# - Show "TEAMS FORM UP LIKE THIS TO START GAMES & AFTER GOALS" text
# ---------------------------------------------------------------------------
func _step_13_formation_reveal() -> void:
	# Hide instructional UI immediately during the cut.
	# (No await here — instant transition.)
	# Free all existing units in both teams.
	for child in units_a.get_children():
		child.queue_free()
	for child in units_b.get_children():
		child.queue_free()

	# Free the step-8 goal square if it exists; we'll spawn fresh ones for
	# the formation view.
	if _tutorial_goal_square != null and is_instance_valid(_tutorial_goal_square):
		_tutorial_goal_square.queue_free()
		_tutorial_goal_square = null
	_tutorial_goalie = null

	# Wait one frame so queue_free's take effect.
	await get_tree().process_frame
	if not _is_alive(): return

	# Swap pitch texture to the markings version (single-tile, not regioned).
	pitch_lines.texture = PITCH_TEXTURE_WITH_MARKINGS
	pitch_lines.region_enabled = false
	pitch_lines.position = PITCH_CENTRE
	# Sprite2D's centred property defaults true; the texture displays centred
	# on its position. Since the texture is 2400x900 and centre is (1200, 450),
	# this fills exactly the pitch area.

	# Detach pitch ball from its previous holder (it'll re-attach to centre
	# unit below).
	# pitch_ball remains in scene; just reposition.

	# Snap camera to pitch centre + zoom out.
	camera_follow_active = false
	camera.position = PITCH_CENTRE
	camera.zoom = STEP13_CAMERA_ZOOM

	# Spawn the 10 formation units.
	var formation_a: Dictionary = {}
	for role in FORMATION_POSITIONS_A.keys():
		var pos: Vector2 = FORMATION_POSITIONS_A[role]
		var name_str: String = "TeamA_" + role.capitalize()
		var u: Node2D = _spawn_unit(units_a, name_str, pos, "A", TEAM_A_COLOR)
		u.role = role
		formation_a[role] = u

	var formation_b: Dictionary = {}
	for role in FORMATION_POSITIONS_B.keys():
		var pos: Vector2 = FORMATION_POSITIONS_B[role]
		var name_str: String = "TeamB_" + role.capitalize()
		var u: Node2D = _spawn_unit(units_b, name_str, pos, "B", PINK_COLOR)
		u.role = role
		formation_b[role] = u

	# Spawn both goal squares (A on left, B on right).
	var _goal_a_rect: ColorRect = _spawn_goal_square_at_position(
		FORMATION_POSITIONS_A["goalie"], GOAL_SQUARE_COLOR_A, "GoalSquareA_Formation")
	var _goal_b_rect: ColorRect = _spawn_goal_square_at_position(
		FORMATION_POSITIONS_B["goalie"], GOAL_SQUARE_COLOR_B, "GoalSquareB_Formation")

	# Player is the Team A centre — give them the P1 label and attach the ball.
	var player_unit: Node2D = formation_a["centre"]
	player_unit.set_player_label("P1")
	pitch_ball.attach_to_unit(player_unit, player_unit.position + Vector2(-30, 0))

	# Hide crosshair during reveal — it'll come back in step 14.
	crosshair.deactivate()

	# Pitch markings are now visible — add a backing behind text labels for readability.
	ui.enable_text_backing()

	# Hold a beat, then show the text.
	if not await _safe_await_timer(0.6): return

	ui.show_instruction("TEAMS FORM UP LIKE THIS TO START GAMES & AFTER GOALS", "", 36)
	if not await _safe_await_timer(3.5): return
	await ui.hide_instruction()
	if not _is_alive(): return

	# Save references for step 14 (need the centre units for the contest).
	_step14_player_unit = player_unit
	_step14_ai_unit = formation_b["centre"]

	await _safe_await_timer(0.3)

# ---------------------------------------------------------------------------
# STEP 14 — Restart contest
#
# Storyboard panels (Tutorial 8 panels 4-6):
#   - "AND PLAY RESTARTS WITH A" text
#   - Pause briefly
#   - "CONTEST!" text (or popup directly)
#   - Both centre units converge to centre circle
#   - Contest popup opens (sandbagged, player wins)
#   - Both units walk back to formation; player retains ball
# ---------------------------------------------------------------------------
func _step_14_restart_contest() -> void:
	if _step14_player_unit == null or _step14_ai_unit == null:
		return
	if not is_instance_valid(_step14_player_unit) \
			or not is_instance_valid(_step14_ai_unit):
		return

	ui.show_instruction("AND PLAY RESTARTS WITH A...", "")
	if not await _safe_await_timer(2.0): return

	# Camera zooms in to centre — units stay where they are.
	var zoom_tween: Tween = create_tween()
	zoom_tween.tween_property(camera, "zoom", Vector2(1.2, 1.2), 0.6)
	var pan_tween: Tween = create_tween()
	pan_tween.tween_property(camera, "position", PITCH_CENTRE, 0.6)
	await zoom_tween.finished
	if not _is_alive(): return

	# Open the contest popup. Pass suppress_text=true so no in-popup text shows.
	var contest: Node2D = TUTORIAL_CONTEST_SCENE.instantiate()
	var ui_root: CanvasLayer = $UIRoot
	ui_root.add_child(contest)

	# Move pause menu to back so it renders on top of contest.
	if pause_menu != null and pause_menu.get_parent() == ui_root:
		ui_root.move_child(pause_menu, ui_root.get_child_count() - 1)

	# Show CONTEST! sized to fit inside contest viewport, more transparent persistent state.
	ui.show_persistent_centre_text("CONTEST!", Color(1, 1, 1, 1), 0.4, 0.15, 60)

	ui.force_hide_now()
	ui.clear_log()

	var winner_holder: Array = [""]
	contest.contest_finished.connect(func(w: String):
		winner_holder[0] = w)
	contest.start_scripted_contest(TUTORIAL_INPUT_ID, "A", 1.0, true)  # suppress_text = true

	while _is_alive() and winner_holder[0] == "":
		await get_tree().process_frame
	if not _is_alive(): return
	contest.queue_free()
	if not _is_alive(): return
	ui.clear_persistent_centre_text()

	# After contest: player retains ball at centre. Other units do their
	# normal AI walk-back to formation positions; centre units stay still.
	if is_instance_valid(_step14_player_unit):
		pitch_ball.attach_to_unit(_step14_player_unit,
			_step14_player_unit.position + Vector2(-30, 0))
		camera_target = _step14_player_unit.position
		camera_follow_active = true
		camera_follow_speed = CAMERA_FOLLOW_SPEED

	# Brief pause to let the contest "YOU WIN" disappear cleanly.
	await _safe_await_timer(0.5)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _await_crosshair_over_unit(unit: Node2D, radius: float = 60.0) -> void:
	while _is_alive() and crosshair.position.distance_to(unit.position) > radius:
		await get_tree().process_frame
 
func _spawn_unit(parent: Node2D, unit_name: String, unit_position: Vector2,
		team: String, color: Color) -> Node2D:
	var unit: Node2D = UNIT_SCENE.instantiate()
	unit.name = unit_name
	parent.add_child(unit)
	unit.position = unit_position
	unit.team = team
	unit.role = "field"
	unit.unit_color = color
	var rect: ColorRect = unit.get_node_or_null("ColorRect")
	if rect != null:
		rect.color = color
	return unit
 
func _walk_unit_to(unit: Node2D, target: Vector2, speed: float = SCRIPTED_WALK_SPEED) -> void:
	while _is_alive() and is_instance_valid(unit) \
			and unit.position.distance_to(target) > 2.0:
		var dir: Vector2 = (target - unit.position).normalized()
		var step: float = speed * get_process_delta_time()
		if step >= unit.position.distance_to(target):
			unit.position = target
			break
		unit.position += dir * step
		await get_tree().process_frame
	if _is_alive() and is_instance_valid(unit):
		unit.position = target
 
func _get_move_actions_for_input(input_id: String) -> Dictionary:
	match input_id:
		"kb0":
			return {"up": "kb0_aim_up", "down": "kb0_aim_down",
					"left": "kb0_aim_left", "right": "kb0_aim_right"}
		"kb1":
			return {"up": "kb1_aim_up", "down": "kb1_aim_down",
					"left": "kb1_aim_left", "right": "kb1_aim_right"}
		_:
			var n: String = input_id.substr(3)
			return {"up": "joy_aim_up_" + n, "down": "joy_aim_down_" + n,
					"left": "joy_aim_left_" + n, "right": "joy_aim_right_" + n}
 
func _find_p1_unit() -> Node2D:
	for container in [units_a, units_b]:
		for child in container.get_children():
			var label: Label = child.get_node_or_null("NameLabel")
			if label != null and label.text == "P1":
				return child
	return null
 
# Walks a unit toward a destination, fading it as it goes. Non-blocking.
func _walk_and_fade_unit_async(unit: Node2D, destination: Vector2,
		fade_duration: float = 0.6) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	# Walk
	var walk_distance: float = unit.position.distance_to(destination)
	var walk_speed: float = SCRIPTED_WALK_SPEED
	var walk_time: float = walk_distance / walk_speed
	var walk_tween: Tween = create_tween()
	walk_tween.tween_property(unit, "position", destination, walk_time)
	# Fade (parallel)
	var fade_tween: Tween = create_tween()
	fade_tween.tween_property(unit, "modulate:a", 0.0, fade_duration)
	# Cleanup
	await fade_tween.finished
	if is_instance_valid(unit):
		unit.queue_free()

func _nearest_unit_in_list(units: Array, pos: Vector2) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for u in units:
		if not is_instance_valid(u):
			continue
		var d: float = u.position.distance_to(pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest = u
	return nearest

func _nearest_unit_to_position(units: Array, pos: Vector2) -> Node2D:
	return _nearest_unit_in_list(units, pos)

# Spawns the goal square (a translucent ColorRect) and a goalie unit at the
# given position. The goal square is added under PitchBackground so it sits
# between the pitch and the units. The goalie is a regular unit with role
# "goalie".
func _spawn_goal_square_and_goalie(goalie_pos: Vector2) -> void:
	# Goal square: ColorRect centred on goalie position.
	var rect: ColorRect = ColorRect.new()
	rect.name = "GoalSquareA"
	rect.color = GOAL_SQUARE_COLOR_A
	rect.size = GOAL_SQUARE_SIZE
	# Position the rect so its centre is at goalie_pos (ColorRects are
	# positioned by top-left corner).
	rect.position = goalie_pos - GOAL_SQUARE_SIZE / 2.0
	# Add as a sibling of PitchLines so it renders above the pitch but below
	# the units. Tutorial scene structure: root has PitchBackground, PitchLines,
	# UnitsA, etc. We add the goal square as a child of root, after PitchLines.
	add_child(rect)
	# Move it to be just after PitchLines in render order.
	var pitch_lines_idx: int = pitch_lines.get_index()
	move_child(rect, pitch_lines_idx + 1)
	_tutorial_goal_square = rect

	# Spawn the goalie.
	var goalie: Node2D = _spawn_unit(units_a, "TutorialGoalie",
		goalie_pos, "A", TEAM_A_COLOR)
	goalie.role = "goalie"
	_tutorial_goalie = goalie

# Spawns just a goal square (no goalie), useful for step 13 formation reveal.
func _spawn_goal_square_at_position(centre_pos: Vector2, color: Color,
		rect_name: String) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.name = rect_name
	rect.color = color
	rect.size = GOAL_SQUARE_SIZE
	rect.position = centre_pos - GOAL_SQUARE_SIZE / 2.0
	add_child(rect)
	# Render between PitchLines and the units.
	var pitch_lines_idx: int = pitch_lines.get_index()
	move_child(rect, pitch_lines_idx + 1)
	return rect

# ---------------------------------------------------------------------------
# STEP 15 — Tactical demo + cinematic outro
#
# Setup: from formation positions (after step 14's contest), Team A centre =
# P1 with ball. Step 15 enables full match-play AI on all non-P1 non-goalie
# units, lets the player observe their tactical behaviour, takes a single
# kick, then plays the cinematic outro.
#
# AI behaviour mirrored from pitch.gd:
#   - Marker defender: closest pink to P1, stands 35px to the LEFT of P1
#     (defending_direction * 35 for Team A attacking).
#   - Other pink defenders: assigned to specific purple attackers as targets.
#   - Purple attackers: runner (closest to crosshair), dragger, prepper roles.
#   - Role rotation: prepper becomes runner if closer to crosshair than runner.
#   - Mark delay on kick: marker defender pauses 1s before pursuing the ball.
#
# After kick resolves, cinematic outro: zoom in on player, fade to white,
# return to title.
# ---------------------------------------------------------------------------

# Step 15 AI state — mirrors pitch.gd's match-play state machine.
var _step15_aiming_unit: Node2D = null
var _step15_marker_defender: Node2D = null
var _step15_runner: Node2D = null
var _step15_dragger: Node2D = null
var _step15_prepper: Node2D = null
var _step15_ai_active: bool = false
var _step15_attack_update_timer: float = 0.0
var _step15_rotation_cooldown: float = 0.0
var _step15_timeout_rotation_cooldown: float = 0.0
var _step15_kick_in_progress: bool = false

# Public-facing kick state for unit.gd's runner-reach callback.
var kick_in_progress: bool = false

const STEP15_ATTACK_UPDATE_INTERVAL: float = 0.5
const STEP15_ROTATION_COOLDOWN_TIME: float = 2.0
const STEP15_TIMEOUT_ROTATION_COOLDOWN_TIME: float = 3.0
const STEP15_MARK_DELAY: float = 1.0
const STEP15_TEXT_DEFENDER_DELAY: float = 0.5
const STEP15_TEXT_TACTICS_DELAY: float = 2.5
const STEP15_TEXT_KICK_DELAY: float = 4.0

# Outro tuning
const STEP15_OUTRO_ZOOM_DURATION: float = 1.5
const STEP15_OUTRO_FADE_DURATION: float = 1.0

func _step_15_tactical_demo() -> void:
	# Find the centre units (already set up by step 14).
	var p1: Node2D = _step14_player_unit
	if p1 == null or not is_instance_valid(p1):
		return

	# Set P1 as the aiming unit for AI orchestration.
	_step15_aiming_unit = p1

	# Bind crosshair to P1.
	crosshair.activate_and_position(p1, TUTORIAL_INPUT_ID)
	crosshair.required_target_unit = null
	crosshair.kick_locked = false

	# Mark P1 as aiming (for visual pulse).
	p1.set_as_aiming(true)

	# Camera follows P1 with EXACT position lock (no lerp). This stays on
	# throughout step 15 so the outro zoom centres precisely on the ball.
	camera_target = p1.position
	camera_follow_active = true
	camera_snap_mode = true

	# Activate full match-play AI on all non-P1 non-goalie units.
	_step15_assign_defenders()
	_step15_assign_attack_roles()
	_step15_ai_active = true

	# Show first text after a short delay.
	if not await _safe_await_timer(STEP15_TEXT_DEFENDER_DELAY): return
	ui.show_instruction("ONE DEFENDER MUST STAND STILL IN FRONT OF THE KICKER", "")

	# Show second text shortly after.
	if not await _safe_await_timer(STEP15_TEXT_TACTICS_DELAY): return
	ui.show_instruction("UNITS WILL CHANGE TACTICS AS YOU MOVE YOUR CROSSHAIR", "")

	# Wait for kick OR timeout to show kick prompt.
	var kick_prompt_shown: bool = false
	var elapsed: float = 0.0
	# Connect to kick_launched signal once.
	var kick_holder: Array = [null]  # mutable wrapper for lambda capture
	var kick_signal_connection: Callable = func(tp: Vector2, z: int, dur: float):
		kick_holder[0] = [tp, z, dur]
	crosshair.kick_launched.connect(kick_signal_connection)

	while _is_alive() and kick_holder[0] == null:
		if elapsed >= STEP15_TEXT_KICK_DELAY and not kick_prompt_shown:
			ui.show_instruction("PRESS A TO KICK", GLYPH_A)
			kick_prompt_shown = true
		elapsed += get_process_delta_time()
		await get_tree().process_frame

	if not _is_alive(): return
	if crosshair.kick_launched.is_connected(kick_signal_connection):
		crosshair.kick_launched.disconnect(kick_signal_connection)

	var kick_data: Array = kick_holder[0]
	var target_pos: Vector2 = kick_data[0]
	var zone: int = kick_data[1]
	var duration: float = kick_data[2]

	# Kick launches: AI roles reassign (everyone runs to ball, marker has delay).
	_step15_kick_in_progress = true
	kick_in_progress = true
	_step15_on_kick_launched(target_pos)

	pitch_ball.launch(p1.position, target_pos, duration, zone)
	camera_target = pitch_ball.position
	camera_follow_active = true
	camera_follow_speed = CAMERA_BALL_FOLLOW_SPEED

	# Track ball + countdown.
	while _is_alive() and (pitch_ball._flying or crosshair.countdown_active):
		if pitch_ball._flying:
			camera_target = pitch_ball.position
		await get_tree().process_frame
	if not _is_alive(): return

	# Kick resolved — bring the ball back visible (pitch_ball.land() hid it).
	pitch_ball.visible = true

	# Camera is already locked to ball position via snap mode. Just pause.
	_step15_kick_in_progress = false
	kick_in_progress = false
	if not await _safe_await_timer(1.0): return

	# Transition to outro.
	await _step_15_outro()

func _step_15_outro() -> void:
	# Stop AI updates immediately — units freeze at current positions.
	_step15_ai_active = false

	# Force all units to stop moving by clearing their roles and defending state.
	for u in units_a.get_children() + units_b.get_children():
		if not is_instance_valid(u):
			continue
		u.attack_role = u.AttackRole.NONE
		u.is_defending = false
		u.assigned_target = null
		u.clear_human_attack()
		u.is_aiming = false  # stops aiming pulse on P1

	# Stop the ball arc and ensure it stays visible at its current position.
	# (pitch_ball.land() hides the ball — we don't want that for the outro.)
	pitch_ball._flying = false
	pitch_ball.visible = true

	# Stop the crosshair countdown if active.
	if crosshair.has_method("deactivate"):
		crosshair.deactivate()

	# Hide all text.
	ui.force_hide_now()
	ui.clear_log()

	# Determine focus point: where the ball ended up.
	var focus_pos: Vector2 = pitch_ball.position

	# Detach pitch_ball if attached, then freeze it (visually it stays put).
	# Already done effectively because _kick_in_progress was set false.

	# Disable camera follow so the zoom tween can drive position freely.
	# (Snap mode also turns off here; we want a smooth zoom, not snap.)
	camera_follow_active = false
	camera_snap_mode = false

	# Camera is already at ball position from snap mode. Tween the zoom in
	# while holding position locked to focus_pos.
	var zoom_tween: Tween = create_tween()
	zoom_tween.tween_property(camera, "zoom", INTRO_ZOOM_START,
		STEP15_OUTRO_ZOOM_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Hold camera at focus_pos throughout the zoom (defensive against drift).
	var pan_tween: Tween = create_tween()
	pan_tween.tween_property(camera, "position", focus_pos,
		STEP15_OUTRO_ZOOM_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await zoom_tween.finished
	if not _is_alive(): return

	# Fade to white.
	white_overlay.visible = true
	white_overlay.modulate.a = 0.0
	var fade: Tween = create_tween()
	fade.tween_property(white_overlay, "modulate:a", 1.0, STEP15_OUTRO_FADE_DURATION)
	await fade.finished
	if not _is_alive(): return

	# Brief hold then exit.
	if not await _safe_await_timer(0.4): return

	_exit_to_title()

# ---------------------------------------------------------------------------
# Step 15 AI orchestration — replicated from pitch.gd
# ---------------------------------------------------------------------------

func _step15_get_attacking_units() -> Array:
	# Team A is the attacker in the tutorial.
	return units_a.get_children()

func _step15_get_defending_units() -> Array:
	return units_b.get_children()

func _step15_get_goalie(team_units: Array) -> Node2D:
	for u in team_units:
		if u.role == "goalie":
			return u
	return null

# Mirrors pitch.gd's _assign_defenders for tutorial.
func _step15_assign_defenders() -> void:
	var defending_units: Array = _step15_get_defending_units()
	var attacking_units: Array = _step15_get_attacking_units()

	for unit in defending_units + attacking_units:
		if unit == _step15_aiming_unit:
			continue
		unit.is_defending = false
		unit.human_defending = false
		unit.assigned_target = null
		unit.clear_human_attack()
		unit.attack_role = unit.AttackRole.NONE

	# Marker defender = closest non-goalie pink unit.
	var defending_no_goalie: Array = defending_units.filter(
		func(u): return u.role != "goalie"
	)
	var marker: Node2D = null
	var marker_dist: float = INF
	for unit in defending_no_goalie:
		var d: float = unit.position.distance_to(_step15_aiming_unit.position)
		if d < marker_dist:
			marker_dist = d
			marker = unit

	if marker != null:
		# defending_direction: -1 for Team A attacking, +1 for Team B attacking.
		# Tutorial is always Team A attacking.
		var defending_direction: float = -1.0
		marker.position = _step15_aiming_unit.position + Vector2(defending_direction * 35.0, 0.0)
		marker.set_as_defender(_step15_aiming_unit, false, "", "", "", "", 40.0)
	_step15_marker_defender = marker

	# Other defenders: assigned to specific purple attackers.
	var remaining_defenders: Array = defending_units.filter(
		func(u): return u != marker and u.role != "goalie"
	)
	var targetable_attackers: Array = attacking_units.filter(
		func(u): return u.role != "goalie" and u != _step15_aiming_unit
	)
	for defender in remaining_defenders:
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

# Mirrors pitch.gd's _assign_attack_roles for tutorial.
func _step15_assign_attack_roles() -> void:
	var attacking_units: Array = _step15_get_attacking_units()
	var eligible: Array = attacking_units.filter(
		func(u): return u != _step15_aiming_unit and u.role != "goalie"
	)
	_step15_runner = null
	_step15_dragger = null
	_step15_prepper = null

	if eligible.size() == 0: return
	if eligible.size() == 1:
		_step15_runner = eligible[0]
		_step15_update_attack_targets()
		return
	if eligible.size() == 2:
		var ch_pos2: Vector2 = crosshair.position
		eligible.sort_custom(func(a, b):
			return a.position.distance_to(ch_pos2) < b.position.distance_to(ch_pos2))
		_step15_runner = eligible[0]
		_step15_dragger = eligible[1]
		_step15_update_attack_targets()
		return

	var goalie: Node2D = _step15_get_goalie(attacking_units)
	var ch_pos: Vector2 = crosshair.position
	eligible.sort_custom(func(a, b):
		return a.position.distance_to(ch_pos) < b.position.distance_to(ch_pos))
	_step15_runner = eligible[0]
	var remaining: Array = [eligible[1], eligible[2]]
	if goalie != null:
		remaining.sort_custom(func(a, b):
			return a.position.distance_to(goalie.position) < b.position.distance_to(goalie.position))
	_step15_dragger = remaining[0]
	_step15_prepper = remaining[1]
	_step15_update_attack_targets()

# Mirrors pitch.gd's _update_attack_targets.
func _step15_update_attack_targets() -> void:
	if _step15_runner == null: return
	var ch_pos: Vector2 = crosshair.position
	var attacking_units: Array = _step15_get_attacking_units()
	var goalie: Node2D = _step15_get_goalie(attacking_units)

	if _step15_runner.attack_role != _step15_runner.AttackRole.RUNNER:
		_step15_runner.set_attack_role(_step15_runner.AttackRole.RUNNER, _step15_clamp_to_pitch(ch_pos))
	else:
		_step15_runner.update_runner_target(_step15_clamp_to_pitch(ch_pos))

	if _step15_dragger == null: return

	var in_defensive_half: bool = _step15_aiming_unit.position.x > 1200.0  # Team A defensive half
	var dragger_target: Vector2
	if goalie != null:
		if in_defensive_half:
			var p_pos: Vector2 = _step15_prepper.position if _step15_prepper != null else _step15_dragger.position
			dragger_target = (p_pos + goalie.position) / 2.0
		else:
			dragger_target = (goalie.position + Vector2(250.0, 0.0)) / 2.0
	else:
		dragger_target = _step15_dragger.position
	_step15_dragger.set_attack_role(_step15_dragger.AttackRole.DRAGGER, _step15_clamp_to_pitch(dragger_target))

	if _step15_prepper == null: return

	var prepper_target: Vector2
	if goalie != null:
		if in_defensive_half:
			var is_prepper_defensive: bool = _step15_prepper.position.x > _step15_aiming_unit.position.x
			if is_prepper_defensive:
				prepper_target = goalie.position
			else:
				var defending_units: Array = _step15_get_defending_units()
				var nearest_def: Node2D = null
				var nearest_def_dist: float = INF
				for u in defending_units:
					var d: float = _step15_prepper.position.distance_to(u.position)
					if d < nearest_def_dist:
						nearest_def_dist = d
						nearest_def = u
				if nearest_def != null:
					var away_dir: Vector2 = (_step15_prepper.position - nearest_def.position).normalized()
					var target: Vector2 = _step15_prepper.position + away_dir * 200.0
					var offset: Vector2 = target - _step15_aiming_unit.position
					if offset.length() > crosshair.RADIUS_OUTER:
						offset = offset.normalized() * crosshair.RADIUS_OUTER
						target = _step15_aiming_unit.position + offset
					target.x = min(target.x, _step15_aiming_unit.position.x)
					prepper_target = target
				else:
					prepper_target = _step15_prepper.position
		else:
			prepper_target = Vector2(250.0, 750.0)
	else:
		prepper_target = _step15_prepper.position
	_step15_prepper.set_attack_role(_step15_prepper.AttackRole.PREPPER, _step15_clamp_to_pitch(prepper_target))

# Mirrors pitch.gd's _check_role_rotation.
func _step15_check_role_rotation(delta: float) -> void:
	if _step15_runner == null or _step15_prepper == null:
		return
	if _step15_rotation_cooldown > 0.0:
		_step15_rotation_cooldown -= delta
	if _step15_timeout_rotation_cooldown > 0.0:
		_step15_timeout_rotation_cooldown -= delta

	var ch_pos: Vector2 = crosshair.position
	var runner_dist: float = _step15_runner.position.distance_to(ch_pos)
	var prepper_dist: float = _step15_prepper.position.distance_to(ch_pos)

	if prepper_dist < runner_dist and _step15_rotation_cooldown <= 0.0 \
			and _step15_timeout_rotation_cooldown <= 0.0:
		_step15_on_runner_rotation_needed(false)
		return

	_step15_attack_update_timer += delta
	if _step15_attack_update_timer >= STEP15_ATTACK_UPDATE_INTERVAL:
		_step15_attack_update_timer = 0.0
		_step15_update_attack_targets()

func _step15_on_runner_rotation_needed(from_timeout: bool = false) -> void:
	if from_timeout and _step15_timeout_rotation_cooldown > 0.0:
		return
	if from_timeout:
		_step15_timeout_rotation_cooldown = STEP15_TIMEOUT_ROTATION_COOLDOWN_TIME
	_step15_rotation_cooldown = STEP15_ROTATION_COOLDOWN_TIME
	var old_runner: Node2D = _step15_runner
	var old_dragger: Node2D = _step15_dragger
	var old_prepper: Node2D = _step15_prepper
	_step15_runner = old_prepper
	_step15_dragger = old_runner
	_step15_prepper = old_dragger
	if _step15_dragger != null:
		var away_dir: Vector2 = (_step15_dragger.position - crosshair.position).normalized()
		if away_dir == Vector2.ZERO:
			away_dir = Vector2(1.0, 0.0)
		_step15_dragger.position += away_dir * 30.0
	_step15_update_attack_targets()

# Mirrors pitch.gd's on_kick_launched defender/attacker reassignment.
func _step15_on_kick_launched(kick_pos: Vector2) -> void:
	var defending_units: Array = _step15_get_defending_units()
	for unit in defending_units:
		if unit.role == "goalie": continue
		if unit == _step15_marker_defender:
			unit.start_mark_delay(STEP15_MARK_DELAY)
			unit.assigned_target = null
			unit.set_attack_role(unit.AttackRole.RUNNER, kick_pos)
			unit.mark_delay_timer = STEP15_MARK_DELAY
			continue
		unit.set_attack_role(unit.AttackRole.RUNNER, kick_pos)

	# Reassign purple attackers — closest to kick_pos becomes runner, rest spread away.
	var attacking_units: Array = _step15_get_attacking_units()
	var eligible: Array = attacking_units.filter(
		func(u): return u != _step15_aiming_unit and u.role != "goalie"
	)
	_step15_runner = null
	if eligible.size() > 0:
		eligible.sort_custom(func(a, b):
			return a.position.distance_to(kick_pos) < b.position.distance_to(kick_pos))
		_step15_runner = eligible[0]
		_step15_runner.set_attack_role(_step15_runner.AttackRole.RUNNER, kick_pos)
		for i in range(1, eligible.size()):
			var unit: Node2D = eligible[i]
			var away_dir: Vector2 = (unit.position - kick_pos).normalized()
			if away_dir == Vector2.ZERO:
				away_dir = Vector2(1, 0)
			var away_pos: Vector2 = unit.position + away_dir * 300.0
			away_pos.x = clamp(away_pos.x, 50.0, PITCH_W - 50.0)
			away_pos.y = clamp(away_pos.y, 50.0, PITCH_H - 50.0)
			unit.set_attack_role(unit.AttackRole.DRAGGER, away_pos)

func _step15_clamp_to_pitch(pos: Vector2) -> Vector2:
	return Vector2(
		clamp(pos.x, 10.0, PITCH_W - 10.0),
		clamp(pos.y, 10.0, PITCH_H - 10.0)
	)

# Called by unit.gd's runner logic when a runner has reached its target or
# timed out. Delegates to step 15's role rotation if step 15 is active.
func on_runner_rotation_needed(from_timeout: bool = false) -> void:
	if _step15_ai_active and not _step15_kick_in_progress:
		_step15_on_runner_rotation_needed(from_timeout)
