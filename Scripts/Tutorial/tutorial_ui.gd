extends CanvasLayer
# TutorialUI — text overlays, button glyphs, and big centre-screen moments.
#
# Linger semantics (chunk 5e):
#   - show_instruction()                     — text fades in.
#   - hide_instruction(linger_seconds=1.0)   — wait `linger_seconds` AFTER
#     this call before fading out. Lets the text "breathe" after the player
#     has resolved the prompt.
#   - hide_instruction_immediate()           — fade now, no linger. Use only
#     when a step explicitly needs an instant transition.
#
# Additionally a hard minimum from show is enforced (MIN_INSTRUCTION_DURATION),
# so even a fast-acting player can't flash a prompt by in <0.5s.
 
@onready var instructional_text: Label = $InstructionalText
@onready var glyph_label: Label = $GlyphLabel
@onready var moment_text: Label = $MomentText
 
const FADE_DURATION: float = 0.25
const MIN_INSTRUCTION_DURATION: float = 0.5     # hard minimum from show
const DEFAULT_LINGER: float = 1.0               # default pause after hide()
 
var _instruction_shown_at: float = -1.0
var _pending_hide: bool = false
 
func _ready() -> void:
	instructional_text.visible = false
	glyph_label.visible = false
	moment_text.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in get_children():
		child.process_mode = Node.PROCESS_MODE_ALWAYS
 
# ---------------------------------------------------------------------------
# Instructional text + glyph
# ---------------------------------------------------------------------------
func show_instruction(text: String, glyph: String = "") -> void:
	_pending_hide = false
	_instruction_shown_at = Time.get_ticks_msec() / 1000.0
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
 
# Hide the instruction with a linger. Default behaviour: wait DEFAULT_LINGER
# seconds, then fade. Pass 0.0 for instant fade, or larger values for more
# breathing room.
func hide_instruction(linger_seconds: float = DEFAULT_LINGER) -> void:
	if _pending_hide:
		return
	_pending_hide = true
 
	# Linger first (this is the "stay visible after the player acted" pause).
	if linger_seconds > 0.0:
		await get_tree().create_timer(linger_seconds).timeout
 
	# Hard minimum: text must have been visible for MIN_INSTRUCTION_DURATION
	# from show. Catches edge cases where show + hide happen near-simultaneously.
	var elapsed: float = (Time.get_ticks_msec() / 1000.0) - _instruction_shown_at
	var remaining: float = MIN_INSTRUCTION_DURATION - elapsed
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
 
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
 
# Convenience for instant fade.
func hide_instruction_immediate() -> void:
	await hide_instruction(0.0)
 
# ---------------------------------------------------------------------------
# Big centre-screen moment text
# ---------------------------------------------------------------------------
func show_moment(text: String, color: Color = Color.WHITE, duration: float = 1.5) -> void:
	moment_text.text = text
	moment_text.add_theme_color_override("font_color", color)
	moment_text.modulate.a = 0.0
	moment_text.scale = Vector2(0.7, 0.7)
	moment_text.visible = true
	var t_in: Tween = create_tween()
	t_in.tween_property(moment_text, "modulate:a", 1.0, FADE_DURATION)
	t_in.parallel().tween_property(moment_text, "scale", Vector2(1.0, 1.0), FADE_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t_in.finished
	await get_tree().create_timer(duration).timeout
	var t_out: Tween = create_tween()
	t_out.tween_property(moment_text, "modulate:a", 0.0, FADE_DURATION)
	await t_out.finished
	moment_text.visible = false
 
