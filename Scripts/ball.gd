extends Area2D

signal paddle_hit(paddle: Area2D)
signal hit_bottom

var velocity: Vector2 = Vector2.ZERO
var active: bool = false

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	#print("area entered: ", area.name, " active=", active)
	if active:
		paddle_hit.emit(area)

func launch() -> void:
	active = false
	velocity = Vector2.ZERO
	var screen: Vector2 = Vector2(460, 700)

	for _attempt in range(200):
		var angle_deg: float = randf_range(75.0, 105.0)
		var angle_rad: float = deg_to_rad(angle_deg)
		var speed: float = randf_range(450.0, 650.0)
		var vx: float = cos(angle_rad) * speed
		var vy: float = -sin(angle_rad) * speed

		var sim_x: float = screen.x / 2.0
		var sim_y: float = screen.y / 3.0
		var sim_vx: float = vx
		var sim_vy: float = vy
		var dt: float = 0.016
		var time_outside: float = 0.0
		var entered_top: bool = false
		var hit_wall: bool = false

		for _step in range(600):
			sim_vy += 400.0 * dt
			sim_y += sim_vy * dt
			sim_x += sim_vx * dt

			if sim_x < 20.0 or sim_x > screen.x - 20.0:
				hit_wall = true
				break

			if sim_y < 0.0:
				time_outside += dt
				entered_top = true
			elif entered_top:
				break

			if sim_y > screen.y and not entered_top:
				break

		if hit_wall or not entered_top:
			continue

		if time_outside >= 0.2 and time_outside <= 0.8:
			velocity = Vector2(vx, vy)
			active = true
			return

	velocity = Vector2(0.0, -600.0)
	active = true

func _physics_process(delta: float) -> void:
	if not active:
		return
	velocity.y += 400.0 * delta
	position += velocity * delta

	# Safety wall clamps
	if position.x < 20.0:
		position.x = 20.0
		velocity.x = abs(velocity.x)
	elif position.x > 440.0:
		position.x = 440.0
		velocity.x = -abs(velocity.x)

	# Floor detection — ball origin is centre, ball is 40px tall so half = 20
	if position.y >= 680.0:
		position.y = 680.0
		velocity = Vector2.ZERO
		active = false
		hit_bottom.emit()
