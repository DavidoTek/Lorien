extends ViewportContainer
class_name InfiniteCanvas

# -------------------------------------------------------------------------------------------------
class Info:
	var point_count: int
	var stroke_count: int
	var current_pressure: float
	var current_brush_position: Vector2

# -------------------------------------------------------------------------------------------------
onready var _viewport: Viewport = $Viewport
onready var _camera: Camera2D = $Viewport/Camera2D
onready var _cursor: Node2D = $Viewport/BrushCursor

var lines := []
var info := Info.new()
var _last_mouse_motion: InputEventMouseMotion
var _current_line: Line2D
var _current_pressures := []
var _current_brush_color := Config.DEFAULT_BRUSH_COLOR
var _current_brush_size := Config.DEFAULT_BRUSH_SIZE
var _is_enabled := false

# -------------------------------------------------------------------------------------------------
func _ready():
	_cursor.change_size(_current_brush_size)

# -------------------------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		info.current_pressure = event.pressure
		_last_mouse_motion = event
		_cursor.global_position = _camera.xform(event.global_position)
		
	if _is_enabled:
		if event is InputEventMouseButton:
			if event.button_index == BUTTON_LEFT:
				if event.pressed:
					start_new_line(_current_brush_color, _current_brush_size)
				else:
					end_line(true)
		

# -------------------------------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _is_enabled:
		var brush_position: Vector2
		
		if _last_mouse_motion != null:
			brush_position = _camera.xform(_last_mouse_motion.global_position)
			info.current_brush_position = brush_position
		
		if _current_line != null && _last_mouse_motion != null:
			if _last_mouse_motion.relative.length_squared() > 0.0:
				var pressure = _last_mouse_motion.pressure
				add_point(brush_position, pressure)
				_last_mouse_motion = null
		
		if Input.is_action_just_pressed("lorien_undo"):
			undo_last_line()

# -------------------------------------------------------------------------------------------------
func enable() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_camera.enable_intput()
	_cursor.show()
	_is_enabled = true
	
# -------------------------------------------------------------------------------------------------
func disable() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_camera.disable_intput()
	_cursor.hide()
	_is_enabled = false

# -------------------------------------------------------------------------------------------------
func start_new_line(brush_color: Color, brush_size: float = 6) -> void:
	_current_line = Line2D.new()
	_current_line.width_curve = Curve.new()
	#_current_line.antialiased = true
	_current_line.default_color = brush_color
	_current_line.width = brush_size
	_current_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_current_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_current_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_viewport.call_deferred("add_child", _current_line)

# -------------------------------------------------------------------------------------------------
func add_point(point: Vector2, pressure: float = 1.0) -> void:
	_current_pressures.append(pressure)
	_current_line.width_curve.clear_points()
	_current_line.add_point(point)
	
	var curve_step := 1.0 / _current_pressures.size()
	var i := 0
	for pressure in _current_pressures:
		_current_line.width_curve.add_point(Vector2(curve_step*i, pressure))
		i += 1

# -------------------------------------------------------------------------------------------------
func end_line(optimize: bool = false) -> void:
	if optimize:
		_optimize_stroke(_current_line)
	
	_current_pressures.clear()
	if _current_line != null:
		if _current_line.points.empty():
			_viewport.call_deferred("remove_child", _current_line)
		else:
			info.stroke_count += 1
			info.point_count += _current_line.points.size()
			lines.append(_current_line)
		_current_line = null

# -------------------------------------------------------------------------------------------------
func add_strokes(strokes: Array) -> void:
	for stroke in strokes:
		var line := Line2D.new()
		line.width_curve = Curve.new()
		line.width = stroke.size
		line.default_color = stroke.color
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.joint_mode = Line2D.LINE_JOINT_ROUND
	
		var p_idx := 0
		var curve_step: float = 1.0 / stroke.point_pressures.size()
		for point in stroke.points:
			line.add_point(point)
			var pressure: float = stroke.point_pressures[p_idx]
			line.width_curve.add_point(Vector2(curve_step*p_idx, pressure))
			p_idx += 1
		line.width_curve.bake()
		
		lines.append(line)
		_viewport.add_child(line)

		info.stroke_count += 1
		info.point_count += line.points.size()

# -------------------------------------------------------------------------------------------------
func undo_last_line() -> void:
	if _current_line == null && !lines.empty():
		var line = lines.pop_back()
		info.stroke_count -= 1
		info.point_count -= line.points.size()
		_viewport.remove_child(line)

# -------------------------------------------------------------------------------------------------
func set_brush_color(color: Color) -> void:
	_current_brush_color = color

# -------------------------------------------------------------------------------------------------
func set_brush_size(size: int) -> void:
	_current_brush_size = size
	_cursor.change_size(size)

# -------------------------------------------------------------------------------------------------
func get_camera_zoom() -> float:
	return _camera.zoom.x

# -------------------------------------------------------------------------------------------------
func clear() -> void:
	for l in lines:
		_viewport.remove_child(l)
	lines.clear()
	info.point_count = 0
	info.stroke_count = 0

# TODO: take the point inpuit speed into account. The higher the speed the higher the higher the discard distance can be
# -------------------------------------------------------------------------------------------------
func _optimize_stroke(line: Line2D, min_squared_distance_between_points: float = 4) -> void:
	if line.points.empty():
		return
	
	var total_filtered_points_count := 0
	var filtered_points := []
	filtered_points.append(line.points[0])
	for i in range(1, line.points.size()):
		var p: Vector2 = line.points[i]
		var last_valid_point: Vector2 = filtered_points[filtered_points.size()-1]
		if last_valid_point.distance_squared_to(p) >= min_squared_distance_between_points:
			filtered_points.append(p)
	print("Raw point count: %d, Filtered points: %d, Difference %d" % [line.points.size(), filtered_points.size(), line.points.size() - filtered_points.size()])
	
	line.points = filtered_points