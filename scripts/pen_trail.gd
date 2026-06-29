extends Line2D

const MAX_POINTS := 300
const MIN_DIST := 6.0

func _ready() -> void:
	width = 2.5
	default_color = Color(0.2, 0.5, 0.9, 0.6)
	top_level = true

func add_trail_point(world_pos: Vector2) -> void:
	if get_point_count() > 0:
		var last := get_point_position(get_point_count() - 1)
		if world_pos.distance_to(last) < MIN_DIST:
			return
	add_point(world_pos)
	if get_point_count() > MAX_POINTS:
		remove_point(0)

func clear_trail() -> void:
	clear_points()
