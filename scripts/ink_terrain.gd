@tool
extends Node2D
class_name InkTerrain

## Builds a hand-drawn level's terrain by reading a JSON file of strokes
## (extracted from a sketch like map2.png) and spawning one InkStroke per stroke,
## scaled from image space into world space.
##
## JSON shape: { "W": int, "H": int, "strokes": [ { "pts": [[x,y], ...] }, ... ] }

const InkStrokeScript = preload("res://scripts/ink_stroke.gd")

@export_file("*.json") var strokes_path: String = "res://assets/levels/map2_strokes.json":
	set(value):
		strokes_path = value
		_rebuild()

## Image-pixel -> world-unit scale.
@export var world_scale: float = 2.0:
	set(value):
		world_scale = value
		_rebuild()

## World-space offset applied after scaling.
@export var origin: Vector2 = Vector2.ZERO:
	set(value):
		origin = value
		_rebuild()

@export var thickness: float = 16.0:
	set(value):
		thickness = value
		_rebuild()

var _built: Array = []


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for n in _built:
		if is_instance_valid(n):
			n.queue_free()
	_built.clear()

	var data := _load_strokes()
	if data.is_empty():
		return
	for stroke in data.get("strokes", []):
		var raw: Array = stroke.get("pts", [])
		if raw.size() < 2:
			continue
		var pts := PackedVector2Array()
		for p in raw:
			pts.append(Vector2(float(p[0]), float(p[1])) * world_scale + origin)
		var ink := InkStrokeScript.new()
		ink.thickness = thickness
		ink.points = pts
		add_child(ink)
		_built.append(ink)


func _load_strokes() -> Dictionary:
	if not FileAccess.file_exists(strokes_path):
		push_warning("InkTerrain: strokes file not found: %s" % strokes_path)
		return {}
	var f := FileAccess.open(strokes_path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("InkTerrain: invalid strokes JSON")
		return {}
	return parsed
