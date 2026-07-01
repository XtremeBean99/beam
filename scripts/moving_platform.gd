extends AnimatableBody2D

## Floating platform that slides at a constant speed between two endpoint markers,
## ping-ponging forever. Endpoints default to the child Marker2D nodes "PointA" and
## "PointB" — drag them in the editor to set the range. Their positions are captured
## once at _ready, so the markers travelling along with the platform afterwards does
## not matter. Motion is forced horizontal (it rides at PointA's height), so the
## markers only need their X positions set; a marker's Y is ignored.
##
## Because it's an AnimatableBody2D moved from _physics_process, Godot applies its
## motion to any CharacterBody2D resting on it, so the player rides along.

@export var point_a_path: NodePath = ^"PointA"
@export var point_b_path: NodePath = ^"PointB"
## Constant travel speed in pixels per second.
@export var speed: float = 120.0

var _a: Vector2 = Vector2.ZERO
var _b: Vector2 = Vector2.ZERO
var _dist: float = 0.0
var _dir: float = 1.0
var _t: float = 0.0   # fraction from A (0) to B (1)


func _ready() -> void:
	var na := get_node_or_null(point_a_path)
	var nb := get_node_or_null(point_b_path)
	if na is Node2D and nb is Node2D:
		_a = (na as Node2D).global_position
		_b = (nb as Node2D).global_position
	else:
		# No markers wired — stay put at the authored position.
		_a = global_position
		_b = global_position
	_b.y = _a.y            # force horizontal: ride at PointA's height
	_dist = _a.distance_to(_b)
	global_position = _a


func _physics_process(delta: float) -> void:
	if _dist < 0.001 or speed <= 0.0:
		return
	# Convert the constant pixel speed into a per-second fraction of the span so the
	# platform crosses at a steady rate regardless of how far apart the markers are.
	_t += _dir * (speed / _dist) * delta
	if _t >= 1.0:
		_t = 1.0
		_dir = -1.0
	elif _t <= 0.0:
		_t = 0.0
		_dir = 1.0
	global_position = _a.lerp(_b, _t)
