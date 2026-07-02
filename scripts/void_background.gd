extends CanvasLayer

## Ambient void background, spawned automatically by ink_level for every level.
## Three code-built elements, all deliberately faint so terrain glow stays the
## hero: a vertical gradient wash, and two parallax layers of drifting ink
## motes and ghost brush strokes that wrap infinitely as the camera moves.
## No art assets required.

const TILE = 2400.0            # wrap period of each parallax layer, px
const FAR_FACTOR = 0.08        # how much the far layer follows the camera
const NEAR_FACTOR = 0.18       # near layer follows a little more
const TOP_COLOR = Color(0.075, 0.085, 0.115, 1.0)
const BOTTOM_COLOR = Color(0.035, 0.038, 0.052, 1.0)
const MOTE_COLOR = Color(0.55, 0.7, 0.95, 0.10)
const STROKE_COLOR = Color(0.5, 0.65, 0.9, 0.05)

var _far: Node2D = null
var _near: Node2D = null
var _drift: float = 0.0


func _ready() -> void:
	layer = -9   # above the flat VoidBG colour (-10), behind everything else

	# Gradient wash across the whole viewport.
	var grad: Gradient = Gradient.new()
	grad.set_color(0, TOP_COLOR)
	grad.set_color(1, BOTTOM_COLOR)
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var rect: TextureRect = TextureRect.new()
	rect.texture = tex
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(rect)

	_far = _build_layer(11731, 9, 5)    # seed, motes, strokes
	_near = _build_layer(52361, 6, 3)
	_near.modulate.a = 1.35             # near layer reads slightly stronger


## One parallax layer: a TILE-sized field of motes (soft dots) and ghost
## brush strokes (long faint arcs), duplicated 3x3 by drawing wrapped copies.
func _build_layer(seed_value: int, motes: int, strokes: int) -> Node2D:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var node: Node2D = Node2D.new()
	add_child(node)
	for i in range(motes):
		var pos: Vector2 = Vector2(rng.randf() * TILE, rng.randf() * TILE)
		var r: float = rng.randf_range(3.0, 9.0)
		_add_mote_copies(node, pos, r)
	for i in range(strokes):
		var origin: Vector2 = Vector2(rng.randf() * TILE, rng.randf() * TILE)
		var ang: float = rng.randf_range(-0.5, 0.5)
		var length: float = rng.randf_range(400.0, 900.0)
		var sag: float = rng.randf_range(30.0, 90.0)
		_add_stroke_copies(node, origin, ang, length, sag)
	return node


## Draw a mote at pos and at the 8 neighbouring tile offsets so wrapping the
## layer position by TILE never pops anything in or out at the edges.
func _add_mote_copies(node: Node2D, pos: Vector2, r: float) -> void:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var p: Vector2 = pos + Vector2(TILE * dx, TILE * dy)
			var dot: Line2D = Line2D.new()
			dot.points = PackedVector2Array([p, p + Vector2(0.1, 0)])
			dot.width = r * 2.0
			dot.default_color = MOTE_COLOR
			dot.begin_cap_mode = Line2D.LINE_CAP_ROUND
			dot.end_cap_mode = Line2D.LINE_CAP_ROUND
			node.add_child(dot)


func _add_stroke_copies(node: Node2D, origin: Vector2, ang: float, length: float, sag: float) -> void:
	var dir: Vector2 = Vector2(cos(ang), sin(ang))
	var perp: Vector2 = dir.orthogonal()
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var o: Vector2 = origin + Vector2(TILE * dx, TILE * dy)
			var pts: PackedVector2Array = PackedVector2Array()
			var steps: int = 14
			for s in range(steps + 1):
				var t: float = float(s) / float(steps)
				# gentle arc: line plus a sine sag, reads as a distant brush pull
				pts.append(o + dir * (length * t) + perp * (sin(t * PI) * sag))
			var line: Line2D = Line2D.new()
			line.points = pts
			line.width = 26.0
			line.default_color = STROKE_COLOR
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			node.add_child(line)


func _process(delta: float) -> void:
	_drift += delta * 6.0   # slow constant drift so the void feels alive even at rest
	var cam: Camera2D = get_viewport().get_camera_2d()
	var cam_pos: Vector2 = cam.get_screen_center_position() if cam != null else Vector2.ZERO
	_far.position = Vector2(
		wrapf(-cam_pos.x * FAR_FACTOR - _drift, -TILE, 0.0),
		wrapf(-cam_pos.y * FAR_FACTOR, -TILE, 0.0))
	_near.position = Vector2(
		wrapf(-cam_pos.x * NEAR_FACTOR - _drift * 1.6, -TILE, 0.0),
		wrapf(-cam_pos.y * NEAR_FACTOR, -TILE, 0.0))
