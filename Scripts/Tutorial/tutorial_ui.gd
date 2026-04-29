extends CanvasLayer
# TutorialUI — text overlays and big centre-screen moments.
 
@onready var instructional_text: Label = $InstructionalText
@onready var glyph_label: Label = $GlyphLabel
@onready var log_text: Label = $LogText
@onready var moment_text: Label = $MomentText
 
const FADE_DURATION: float = 0.25
const MIN_INSTRUCTION_DURATION: float = 0.5
const DEFAULT_LINGER: float = 1.0
 
var _instruction_shown_at: float = -1.0
var _pending_hide: bool = false
 
# Current "big" text content tracked separately so we can demote it cleanly.
var _current_text: String = ""
 
func _ready() -> void:
	add_to_group("tutorial_ui")
	instructional_text.visible = false
	glyph_label.visible = false
	# Force correct sizes from script so scene-level overrides don't interfere.
	var vp_width: float = 1280.0
	# InstructionalText: top centre, large font.
	var inst_settings: LabelSettings = LabelSettings.new()
	inst_settings.font_size = 48
	inst_settings.font_color = Color(1, 1, 1, 0.8)
	inst_settings.line_spacing = -15.0
	instructional_text.label_settings = inst_settings
	instructional_text.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	instructional_text.position = Vector2(0, -20)
	instructional_text.size = Vector2(vp_width, 160)
	instructional_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructional_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	instructional_text.autowrap_mode = TextServer.AUTOWRAP_WORD

	if log_text != null:
		var log_settings: LabelSettings = LabelSettings.new()
		log_settings.font_size = 28
		log_settings.font_color = Color(1, 1, 1, 0.6)
		log_text.label_settings = log_settings
		log_text.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		log_text.position = Vector2(0, 100)
		log_text.size = Vector2(vp_width, 60)
		log_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		log_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		log_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	moment_text.visible = false
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for child in get_children():
		child.process_mode = Node.PROCESS_MODE_PAUSABLE
 
# ---------------------------------------------------------------------------
# Instructional text + glyph + log
# ---------------------------------------------------------------------------
func show_instruction(text: String, glyph: String = "", font_size_override: int = 0) -> void:
	# Cancel any in-flight hide.
	_pending_hide = false
	# If there's a currently-visible instruction, demote it to the log first.
	if _current_text != "" and instructional_text.visible:
		_promote_to_log(_current_text)
 
	_pending_hide = false
	_instruction_shown_at = Time.get_ticks_msec() / 1000.0
	_current_text = text

	if font_size_override > 0:
		instructional_text.add_theme_font_size_override("font_size", font_size_override)
	else:
		instructional_text.remove_theme_font_size_override("font_size")
 
	instructional_text.text = text
	instructional_text.modulate.a = 0.0
	instructional_text.visible = true
	var t1: Tween = create_tween()
	t1.tween_property(instructional_text, "modulate:a", 1.0, FADE_DURATION)
 
	if glyph != "":
		glyph_label.text = glyph
		glyph_label.modulate.a = 0.0
		glyph_label.visible = true
		var t2: Tween = create_tween()
		t2.tween_property(glyph_label, "modulate:a", 1.0, FADE_DURATION)
	else:
		glyph_label.visible = false
 
func hide_instruction(_linger_seconds: float = DEFAULT_LINGER) -> void:
	# No-op (chunk 7c policy): current text persists until a NEW show_instruction
	# replaces it. The previous behaviour of demote-and-fade is gone — kept
	# the function signature for compatibility with existing call sites, but
	# does nothing.
	# For an explicit clear (e.g. before the contest popup), use force_hide_now().
	pass

func force_hide_now() -> void:
	if _current_text != "":
		_promote_to_log(_current_text)
		_current_text = ""
	if instructional_text.visible:
		var t1: Tween = create_tween()
		t1.tween_property(instructional_text, "modulate:a", 0.0, FADE_DURATION)
		t1.tween_callback(func(): instructional_text.visible = false)
	if glyph_label.visible:
		var t2: Tween = create_tween()
		t2.tween_property(glyph_label, "modulate:a", 0.0, FADE_DURATION)
		t2.tween_callback(func(): glyph_label.visible = false)
	_instruction_shown_at = -1.0
	_pending_hide = false

func hide_instruction_immediate() -> void:
	# No-op: hide_instruction is a no-op now (text persists until replaced).
	pass
 
# Replaces the log slot with the given text.
func _promote_to_log(text: String) -> void:
	if log_text == null:
		return
	log_text.text = text
	if not log_text.visible:
		log_text.modulate.a = 0.0
		log_text.visible = true
		var t: Tween = create_tween()
		t.tween_property(log_text, "modulate:a", 1.0, FADE_DURATION)
 
# Clear the log explicitly (e.g. between major step transitions).
func clear_log() -> void:
	if log_text == null or not log_text.visible:
		return
	var t: Tween = create_tween()
	t.tween_property(log_text, "modulate:a", 0.0, FADE_DURATION)
	t.tween_callback(func():
		if log_text != null:
			log_text.visible = false)
 
# ---------------------------------------------------------------------------
# Big centre-screen moment text (NICE KICK!, GOAL!, etc.)
#
# Now positions above a target world position with a brief white flash.
# Falls back to centre-screen if no anchor provided.
# ---------------------------------------------------------------------------
func show_moment(text: String, color: Color = Color.WHITE, duration: float = 1.5,
		_anchor_world_pos: Vector2 = Vector2.INF) -> void:
	moment_text.text = text
	moment_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	moment_text.offset_left = 0.0
	moment_text.offset_top = 0.0
	moment_text.offset_right = 0.0
	moment_text.offset_bottom = 0.0
	moment_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moment_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	moment_text.add_theme_font_size_override("font_size", 100)
	moment_text.pivot_offset = moment_text.size / 2.0

	moment_text.modulate = Color(1, 1, 1, 1)
	moment_text.scale = Vector2(0.3, 0.3)
	moment_text.visible = true

	await get_tree().process_frame
	moment_text.pivot_offset = moment_text.size / 2.0

	var t_punch: Tween = create_tween()
	t_punch.tween_property(moment_text, "scale", Vector2(1.2, 1.2), 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t_punch.finished

	var t_settle: Tween = create_tween()
	t_settle.set_parallel(true)
	t_settle.tween_property(moment_text, "scale", Vector2(1.0, 1.0), 0.1)
	t_settle.tween_property(moment_text, "modulate", color, 0.2)
	await t_settle.finished

	await get_tree().create_timer(duration, false).timeout

	var t_out: Tween = create_tween()
	t_out.tween_property(moment_text, "modulate:a", 0.0, FADE_DURATION)
	await t_out.finished
	moment_text.visible = false

# A second moment-text label that persists at low alpha until cleared. Used
# for "CONTEST!" announcements and "GO!" in the contest. The first 0.2s shows
# at full opacity, then the text fades to persistent_alpha and stays visible.
@onready var _persistent_centre_text: Label = null

func show_persistent_centre_text(text: String, color: Color = Color.WHITE,
		full_visible_duration: float = 0.2, persistent_alpha: float = 0.3,
		font_size: int = 0) -> void:
	# Lazily create the label if not yet created.
	if _persistent_centre_text == null:
		var topmost_layer: CanvasLayer = CanvasLayer.new()
		topmost_layer.name = "PersistentCentreLayer"
		topmost_layer.layer = 100
		get_tree().root.add_child(topmost_layer)
		_persistent_centre_text = Label.new()
		_persistent_centre_text.name = "PersistentCentreText"
		_persistent_centre_text.set_anchors_preset(Control.PRESET_FULL_RECT)
		_persistent_centre_text.offset_left = 0.0
		_persistent_centre_text.offset_top = 0.0
		_persistent_centre_text.offset_right = 0.0
		_persistent_centre_text.offset_bottom = 0.0
		_persistent_centre_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_persistent_centre_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var ls: LabelSettings = LabelSettings.new()
		ls.font_size = 80
		ls.font_color = Color(1, 1, 1, 1)
		_persistent_centre_text.label_settings = ls
		topmost_layer.add_child(_persistent_centre_text)
	# Update font colour for this call.
	# Update font colour and (optionally) size for this call.
	_persistent_centre_text.label_settings.font_color = color
	if font_size > 0:
		_persistent_centre_text.label_settings.font_size = font_size
	_persistent_centre_text.text = text
	_persistent_centre_text.modulate = Color(1, 1, 1, 0)
	_persistent_centre_text.scale = Vector2(0.5, 0.5)
	_persistent_centre_text.visible = true

	# Punch-in.
	var t_in: Tween = create_tween()
	t_in.set_parallel(true)
	t_in.tween_property(_persistent_centre_text, "modulate:a", 1.0, 0.1)
	t_in.tween_property(_persistent_centre_text, "scale", Vector2(1.15, 1.15), 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t_in.finished

	# Settle.
	var t_settle: Tween = create_tween()
	t_settle.tween_property(_persistent_centre_text, "scale", Vector2(1.0, 1.0), 0.05)
	await t_settle.finished

	# Hold at full alpha for the rest of the visible duration.
	var hold_remaining: float = full_visible_duration - 0.15
	if hold_remaining > 0.0:
		await get_tree().create_timer(hold_remaining, false).timeout

	# Fade to persistent_alpha and stay.
	var t_fade: Tween = create_tween()
	t_fade.tween_property(_persistent_centre_text, "modulate:a", persistent_alpha, 0.3)

# Clear the persistent centre text immediately.
func clear_persistent_centre_text() -> void:
	if _persistent_centre_text == null or not _persistent_centre_text.visible:
		return
	var t: Tween = create_tween()
	t.tween_property(_persistent_centre_text, "modulate:a", 0.0, 0.2)
	t.tween_callback(func():
		if _persistent_centre_text != null:
			_persistent_centre_text.visible = false)
 
# Set the log text directly, without going through show_instruction. Used for
# prompts that should appear as a persistent reference but never as a primary
# instruction (e.g. "PRESS START TO PAUSE" — informational, no required action).
func set_log(text: String) -> void:
	if log_text == null:
		return
	if text == "":
		clear_log()
		return
	log_text.text = text
	if not log_text.visible:
		log_text.modulate.a = 0.0
		log_text.visible = true
		var t: Tween = create_tween()
		t.tween_property(log_text, "modulate:a", 1.0, FADE_DURATION)

# Adds a semi-transparent black backing behind the instructional + log text.
# Called from step 13 onwards when pitch markings would otherwise obscure text.
var _text_bg: ColorRect = null
func enable_text_backing() -> void:
	if _text_bg != null:
		return
	_text_bg = ColorRect.new()
	_text_bg.color = Color(0, 0, 0, 0.4)
	_text_bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_text_bg.position = Vector2(0, 0)
	_text_bg.size = Vector2(1280, 200)
	_text_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text_bg)
	move_child(_text_bg, 0)  # render behind labels

func _exit_tree() -> void:
	if _persistent_centre_text != null and is_instance_valid(_persistent_centre_text):
		var layer: Node = _persistent_centre_text.get_parent()
		if layer != null and is_instance_valid(layer):
			layer.queue_free()
		_persistent_centre_text = null
