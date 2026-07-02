@tool
class_name SvgParser
extends RefCounted

## Parses SVG <path d="..."> elements into polyline arrays.
## Extracts data via regex directly — no XMLParser dependency.
## Path commands: M, L, H, V, C, S, Q, T, A, Z (absolute + relative).
## Transforms: matrix, translate, scale, rotate (composed left-to-right), applied
## in SVG space BEFORE the optional Y-flip so results match the source artwork.


## Parse an SVG file → [ { "pts": [[x,y], ...] }, ... ]
## NOTE: The SVG file must NOT have a .import file that remaps it to a texture.
## Godot's HTML5 export redirects FileAccess through the import remapping layer,
## silently serving binary .ctex data instead of the raw SVG XML when an import
## exists. Removing the .svg.import files ensures the raw SVG is read correctly
## on all platforms.
static func parse_file(path: String, flip_y: bool = true) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("SvgParser: file not found: %s" % path)
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("SvgParser: cannot open: %s" % path)
		return []
	var xml := f.get_as_text()
	f.close()
	if xml.is_empty():
		push_warning("SvgParser: empty file: %s" % path)
		return []
	# Sanity check: if the file was imported as a texture, get_as_text() returns
	# binary garbage that won't start with '<'. Catch that early.
	if not xml.strip_edges().begins_with("<"):
		push_warning("SvgParser: file does not look like XML (maybe imported as texture?): %s" % path)
		return []
	return parse_svg_string(xml, flip_y)


## Parse raw SVG string.
static func parse_svg_string(xml: String, flip_y: bool = true) -> Array:
	var strokes: Array = []

	# Extract viewBox height for Y-flipping.
	var svg_height: float = 0.0
	var vb_reg: RegEx = RegEx.new()
	vb_reg.compile("viewBox\\s*=\\s*\"[^\"]*\"")
	var vb_match := vb_reg.search(xml)
	if vb_match:
		var vb: String = _extract_quoted(vb_match.get_string())
		var parts: PackedStringArray = vb.split(" ", false)
		if parts.size() >= 4:
			svg_height = float(parts[3])

	# Match <path ... d="..." ... /> or <path ... d="..." > with optional transform.
	var path_reg: RegEx = RegEx.new()
	path_reg.compile("<path\\s([^>]*)\\bd\\s*=\\s*\"([^\"]*)\"([^>]*)/?>")
	for m in path_reg.search_all(xml):
		var d: String = m.get_string(2)
		if d.is_empty():
			continue
		var attrs: String = m.get_string(1) + " " + m.get_string(3)
		var xform: Array = _parse_transform(attrs)  # affine [a,b,c,d,e,f] or []
		# Parse in raw SVG space; transform, then flip.
		var subpaths: Array = _parse_d(d)
		for pts in subpaths:
			if pts.size() < 2:
				continue
			if not xform.is_empty():
				pts = _apply_matrix(pts, xform)
			if flip_y and svg_height > 0.0:
				pts = _flip_y(pts, svg_height)
			strokes.append({"pts": pts})

	return strokes


## Parse a single SVG `d` attribute string → array of polylines (raw SVG space).
static func _parse_d(d: String) -> Array:
	var subpaths: Array = []
	var current_subpath: Array = []
	var pen: Vector2 = Vector2.ZERO
	var sub_start: Vector2 = Vector2.ZERO
	var tokens: Array = _tokenize(d)

	var i: int = 0
	var cmd: String = ""
	var prev_cmd: String = ""

	while i < tokens.size():
		if tokens[i] is String and tokens[i].length() == 1 and tokens[i].unicode_at(0) > 64:
			cmd = tokens[i]; i += 1
		else:
			cmd = prev_cmd
		prev_cmd = cmd

		match cmd:
			"M", "m":
				var pt := _read_point(tokens, i, pen, cmd == "m"); i += 2
				pen = pt; sub_start = pt
				if not current_subpath.is_empty():
					subpaths.append(current_subpath)
				current_subpath = [[pen.x, pen.y]]
				prev_cmd = "L" if cmd == "M" else "l"

			"L", "l":
				while i + 1 < tokens.size() and not _is_command(tokens[i]):
					var pt := _read_point(tokens, i, pen, cmd == "l"); i += 2
					pen = pt
					current_subpath.append([pen.x, pen.y])

			"H", "h":
				while i < tokens.size() and not _is_command(tokens[i]):
					var x := float(tokens[i]); i += 1
					if cmd == "h": x += pen.x
					pen = Vector2(x, pen.y)
					current_subpath.append([pen.x, pen.y])

			"V", "v":
				while i < tokens.size() and not _is_command(tokens[i]):
					var y := float(tokens[i]); i += 1
					if cmd == "v": y += pen.y
					pen = Vector2(pen.x, y)
					current_subpath.append([pen.x, pen.y])

			"C", "c":
				while i + 5 < tokens.size() and not _is_command(tokens[i]):
					var c1 := _read_point(tokens, i, pen, cmd == "c"); i += 2
					var c2 := _read_point(tokens, i, pen, cmd == "c"); i += 2
					var end := _read_point(tokens, i, pen, cmd == "c"); i += 2
					_sample_cubic(pen, c1, c2, end, current_subpath)
					pen = end

			"S", "s":
				while i + 3 < tokens.size() and not _is_command(tokens[i]):
					var c2 := _read_point(tokens, i, pen, cmd == "s"); i += 2
					var end := _read_point(tokens, i, pen, cmd == "s"); i += 2
					_sample_cubic(pen, pen, c2, end, current_subpath)
					pen = end

			"Q", "q":
				while i + 3 < tokens.size() and not _is_command(tokens[i]):
					var ctrl := _read_point(tokens, i, pen, cmd == "q"); i += 2
					var end := _read_point(tokens, i, pen, cmd == "q"); i += 2
					_sample_quadratic(pen, ctrl, end, current_subpath)
					pen = end

			"T", "t":
				while i + 1 < tokens.size() and not _is_command(tokens[i]):
					var end := _read_point(tokens, i, pen, cmd == "t"); i += 2
					_sample_quadratic(pen, pen, end, current_subpath)
					pen = end

			"A", "a":
				# rx ry x-axis-rotation large-arc-flag sweep-flag x y
				while i + 6 < tokens.size() and not _is_command(tokens[i]):
					var rx := float(tokens[i]); i += 1
					var ry := float(tokens[i]); i += 1
					var xrot := float(tokens[i]); i += 1
					var large := float(tokens[i]) != 0.0; i += 1
					var sweep := float(tokens[i]) != 0.0; i += 1
					var end := _read_point(tokens, i, pen, cmd == "a"); i += 2
					_sample_arc(pen, rx, ry, xrot, large, sweep, end, current_subpath)
					pen = end

			"Z", "z":
				if current_subpath.size() > 0:
					pen = sub_start
					current_subpath.append([pen.x, pen.y])
				subpaths.append(current_subpath)
				current_subpath = []
			_:
				break

	if not current_subpath.is_empty():
		subpaths.append(current_subpath)
	return subpaths


# ----- Curve sampling -----------------------------------------------------

static func _sample_cubic(p0: Vector2, c1: Vector2, c2: Vector2, p3: Vector2, out_path: Array) -> void:
	var dist := p0.distance_to(c1) + c1.distance_to(c2) + c2.distance_to(p3)
	var steps := maxi(2, ceili(dist / 3.0))
	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		var u := 1.0 - t
		var pt := p0 * (u*u*u) + c1 * (3*u*u*t) + c2 * (3*u*t*t) + p3 * (t*t*t)
		out_path.append([pt.x, pt.y])


static func _sample_quadratic(p0: Vector2, ctrl: Vector2, p2: Vector2, out_path: Array) -> void:
	var dist := p0.distance_to(ctrl) + ctrl.distance_to(p2)
	var steps := maxi(2, ceili(dist / 3.0))
	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		var u := 1.0 - t
		var pt := p0 * (u*u) + ctrl * (2*u*t) + p2 * (t*t)
		out_path.append([pt.x, pt.y])


## Flatten an elliptical arc (endpoint parameterization) into line points, per the
## W3C SVG implementation notes.
static func _sample_arc(p0: Vector2, rx: float, ry: float, x_rot_deg: float, large_arc: bool, sweep: bool, p1: Vector2, out_path: Array) -> void:
	if is_zero_approx(rx) or is_zero_approx(ry) or p0.is_equal_approx(p1):
		out_path.append([p1.x, p1.y])
		return
	rx = absf(rx)
	ry = absf(ry)
	var phi := deg_to_rad(x_rot_deg)
	var cosp := cos(phi)
	var sinp := sin(phi)

	# Step 1: midpoint-frame coordinates.
	var dx := (p0.x - p1.x) * 0.5
	var dy := (p0.y - p1.y) * 0.5
	var x1p := cosp * dx + sinp * dy
	var y1p := -sinp * dx + cosp * dy

	# Correct out-of-range radii.
	var lam := (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
	if lam > 1.0:
		var s := sqrt(lam)
		rx *= s
		ry *= s

	# Step 2: center in the midpoint frame.
	var sgn := -1.0 if large_arc == sweep else 1.0
	var num := rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
	var den := rx * rx * y1p * y1p + ry * ry * x1p * x1p
	var co := 0.0
	if den > 0.0:
		co = sgn * sqrt(maxf(0.0, num / den))
	var cxp := co * (rx * y1p / ry)
	var cyp := co * (-ry * x1p / rx)

	# Step 3: center in the original frame.
	var cx := cosp * cxp - sinp * cyp + (p0.x + p1.x) * 0.5
	var cy := sinp * cxp + cosp * cyp + (p0.y + p1.y) * 0.5

	# Step 4: start angle and sweep angle.
	var v0 := Vector2((x1p - cxp) / rx, (y1p - cyp) / ry)
	var v1 := Vector2((-x1p - cxp) / rx, (-y1p - cyp) / ry)
	var theta1 := _angle_between(Vector2(1, 0), v0)
	var dtheta := _angle_between(v0, v1)
	if not sweep and dtheta > 0.0:
		dtheta -= TAU
	elif sweep and dtheta < 0.0:
		dtheta += TAU

	var steps := maxi(2, ceili(absf(dtheta) / (PI / 16.0)))
	for k in range(1, steps + 1):
		var t := theta1 + dtheta * float(k) / float(steps)
		var x := cosp * rx * cos(t) - sinp * ry * sin(t) + cx
		var y := sinp * rx * cos(t) + cosp * ry * sin(t) + cy
		out_path.append([x, y])


static func _angle_between(u: Vector2, v: Vector2) -> float:
	var lng := u.length() * v.length()
	if lng == 0.0:
		return 0.0
	var a := acos(clampf(u.dot(v) / lng, -1.0, 1.0))
	if u.x * v.y - u.y * v.x < 0.0:
		a = -a
	return a


# ----- Transforms ---------------------------------------------------------

## Parse a `transform="..."` attribute into a composed affine [a,b,c,d,e,f].
## Returns [] if no recognized transform is found.
static func _parse_transform(attrs: String) -> Array:
	var t_reg := RegEx.new()
	t_reg.compile("transform\\s*=\\s*\"([^\"]*)\"")
	var t_match := t_reg.search(attrs)
	if t_match == null:
		return []
	var body: String = t_match.get_string(1)

	var fn_reg := RegEx.new()
	fn_reg.compile("([a-zA-Z]+)\\s*\\(([^)]*)\\)")
	var result: Array = []  # identity until first transform
	for fm in fn_reg.search_all(body):
		var fn_name: String = fm.get_string(1)
		var args := _parse_numbers(fm.get_string(2))
		var m := _transform_to_matrix(fn_name, args)
		if m.is_empty():
			continue
		# First transform seeds the matrix directly; later ones compose onto it.
		# (Was `[m]`, which wrapped the 6-element matrix in a nested array and made
		# _apply_matrix index out of bounds — aborting the whole parse.)
		result = m if result.is_empty() else _multiply(result, m)
	return result


static func _transform_to_matrix(fn_name: String, a: Array) -> Array:
	match fn_name:
		"matrix":
			if a.size() >= 6:
				return [a[0], a[1], a[2], a[3], a[4], a[5]]
		"translate":
			var tx: float = a[0] if a.size() >= 1 else 0.0
			var ty: float = a[1] if a.size() >= 2 else 0.0
			return [1.0, 0.0, 0.0, 1.0, tx, ty]
		"scale":
			var sx: float = a[0] if a.size() >= 1 else 1.0
			var sy: float = a[1] if a.size() >= 2 else sx
			return [sx, 0.0, 0.0, sy, 0.0, 0.0]
		"rotate":
			var ang: float = deg_to_rad(a[0]) if a.size() >= 1 else 0.0
			var c := cos(ang)
			var s := sin(ang)
			var rot := [c, s, -s, c, 0.0, 0.0]
			if a.size() >= 3:
				# rotate(angle, cx, cy) = translate(c) · rotate · translate(-c)
				var to := [1.0, 0.0, 0.0, 1.0, a[1], a[2]]
				var from := [1.0, 0.0, 0.0, 1.0, -a[1], -a[2]]
				return _multiply(_multiply(to, rot), from)
			return rot
	return []


## Compose two affine matrices: result applies m1 then m2 to a point as m1·m2.
static func _multiply(m1: Array, m2: Array) -> Array:
	return [
		m1[0] * m2[0] + m1[2] * m2[1],
		m1[1] * m2[0] + m1[3] * m2[1],
		m1[0] * m2[2] + m1[2] * m2[3],
		m1[1] * m2[2] + m1[3] * m2[3],
		m1[0] * m2[4] + m1[2] * m2[5] + m1[4],
		m1[1] * m2[4] + m1[3] * m2[5] + m1[5],
	]


static func _apply_matrix(pts: Array, m: Array) -> Array:
	var result: Array = []
	for p in pts:
		var x: float = p[0]
		var y: float = p[1]
		result.append([
			m[0] * x + m[2] * y + m[4],
			m[1] * x + m[3] * y + m[5],
		])
	return result


static func _flip_y(pts: Array, height: float) -> Array:
	var result: Array = []
	for p in pts:
		result.append([p[0], height - p[1]])
	return result


# ----- Helpers ------------------------------------------------------------

static func _parse_numbers(s: String) -> Array:
	var out: Array = []
	for tok in _tokenize(s):
		if not (tok is String):
			out.append(float(tok))
	return out


static func _extract_quoted(s: String) -> String:
	var start := s.find("\"")
	var end := s.find("\"", start + 1)
	if start != -1 and end != -1:
		return s.substr(start + 1, end - start - 1)
	return ""


static func _read_point(tokens: Array, i: int, pen: Vector2, relative: bool) -> Vector2:
	var x := float(tokens[i])
	var y := float(tokens[i + 1])
	if relative:
		return pen + Vector2(x, y)
	return Vector2(x, y)


static func _is_command(token) -> bool:
	return token is String and token.length() == 1 and token.unicode_at(0) > 64


static func _tokenize(d: String) -> Array:
	var tokens: Array = []
	var i := 0
	while i < d.length():
		var ch := d[i]
		if ch == " " or ch == "\t" or ch == "\n" or ch == "\r" or ch == ",":
			pass
		elif (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z"):
			tokens.append(ch)
		elif ch == "-" or ch == "." or (ch >= "0" and ch <= "9"):
			var start := i
			var dot_seen := ch == "."
			i += 1
			while i < d.length():
				var nch := d[i]
				if nch == "-":
					if i > start + 1 and (d[i - 1] == "e" or d[i - 1] == "E"):
						i += 1; continue
					break
				elif (nch >= "0" and nch <= "9") or nch == "e" or nch == "E":
					i += 1
				elif nch == ".":
					if dot_seen: break
					dot_seen = true; i += 1
				else:
					break
			tokens.append(d.substr(start, i - start).to_float())
			continue
		i += 1
	return tokens
