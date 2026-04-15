extends Node2D

@onready var anim: AnimationPlayer = $AnimationPlayer

const PEAK_BY_ZONE: Dictionary = {
	1: 40.0,
	2: 100.0,
	3: 180.0
}

var _flying: bool = false
var _start: Vector2 = Vector2.ZERO
var _end: Vector2 = Vector2.ZERO
var _duration: float = 1.0
var _elapsed: float = 0.0
var _peak: float = 40.0

func _ready() -> void:
	visible = false

func attach_to_unit(unit: Node2D, crosshair_pos: Vector2) -> void:
	_flying = false
	visible = true
	var dir_x: float = sign(crosshair_pos.x - unit.position.x)
	if dir_x == 0.0:
		dir_x = 1.0
	position = unit.position + Vector2(dir_x * 18.0, 0.0)

func launch(from: Vector2, to: Vector2, duration: float, zone: int) -> void:
	_flying = true
	_start = from
	_end = to
	_duration = duration
	_elapsed = 0.0
	_peak = PEAK_BY_ZONE.get(zone, 40.0)
	visible = true

func land() -> void:
	_flying = false
	visible = false

func _process(delta: float) -> void:
	if not _flying:
		return
	_elapsed += delta
	var t: float = clamp(_elapsed / _duration, 0.0, 1.0)
	var x: float = lerp(_start.x, _end.x, t)
	var base_y: float = lerp(_start.y, _end.y, t)
	var arc_y: float = base_y - _peak * 4.0 * t * (1.0 - t)
	position = Vector2(x, arc_y)
	if t >= 1.0:
		land()
