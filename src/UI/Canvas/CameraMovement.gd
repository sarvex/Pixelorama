extends Camera2D

signal zoom_changed
signal rotation_changed

enum Cameras { MAIN, SECOND, SMALL }

const CAMERA_SPEED_RATE := 15.0

export(Cameras) var index := 0

var zoom_min := Vector2(0.005, 0.005)
var zoom_max := Vector2.ONE
var viewport_container: ViewportContainer
var transparent_checker: ColorRect
var mouse_pos := Vector2.ZERO
var drag := false
var rotation_slider: ValueSlider
var zoom_slider: ValueSlider
var should_tween := true


func _ready() -> void:
	set_process_input(false)
	if index == Cameras.MAIN:
		rotation_slider = Global.top_menu_container.get_node("%RotationSlider")
		rotation_slider.connect("value_changed", self, "_rotation_value_changed")
		zoom_slider = Global.top_menu_container.get_node("%ZoomSlider")
		zoom_slider.connect("value_changed", self, "_zoom_value_changed")
		set_zoom_max_value()
	connect("zoom_changed", self, "_zoom_changed")
	connect("rotation_changed", self, "_rotation_changed")
	rotating = true
	viewport_container = get_parent().get_parent()
	transparent_checker = get_parent().get_node("TransparentChecker")
	update_transparent_checker_offset()


func set_zoom_max_value() -> void:
	zoom_slider.max_value = 100.0 / zoom_min.x


func _rotation_value_changed(value: float) -> void:
	# Negative makes going up rotate clockwise
	var degrees := -value
	var difference := degrees - rotation_degrees
	var canvas_center: Vector2 = Global.current_project.size / 2
	offset = (offset - canvas_center).rotated(deg2rad(difference)) + canvas_center
	rotation_degrees = wrapf(degrees, -180, 180)
	emit_signal("rotation_changed")


func _zoom_value_changed(value: float) -> void:
	if value <= 0:
		value = 1
	var percent := 100.0 / value
	var new_zoom := Vector2(percent, percent)
	if zoom == new_zoom:
		return
	if Global.smooth_zoom and should_tween:
		var tween := create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
		tween.connect("step_finished", self, "_on_tween_step")
		tween.tween_property(self, "zoom", new_zoom, 0.05)
	else:
		zoom = new_zoom
		emit_signal("zoom_changed")


func update_transparent_checker_offset() -> void:
	var o := get_global_transform_with_canvas().get_origin()
	var s := get_global_transform_with_canvas().get_scale()
	o.y = get_viewport_rect().size.y - o.y
	transparent_checker.update_offset(o, s)


func _input(event: InputEvent) -> void:
	if !Global.can_draw:
		drag = false
		return
	mouse_pos = viewport_container.get_local_mouse_position()
	if event.is_action_pressed("pan"):
		drag = true
	elif event.is_action_released("pan"):
		drag = false
	elif event.is_action_pressed("zoom_in", false, true):  # Wheel Up Event
		zoom_camera(-1)
	elif event.is_action_pressed("zoom_out", false, true):  # Wheel Down Event
		zoom_camera(1)

	elif event is InputEventMagnifyGesture:  # Zoom Gesture on a laptop touchpad
		if event.factor < 1:
			zoom_camera(1)
		else:
			zoom_camera(-1)
	elif event is InputEventPanGesture and OS.get_name() != "Android":
		# Pan Gesture on a laptop touchpad
		offset = offset + event.delta.rotated(rotation) * zoom * 7
	elif event is InputEventMouseMotion:
		if drag:
			offset = offset - event.relative.rotated(rotation) * zoom
			update_transparent_checker_offset()
			_update_rulers()
	else:
		var velocity := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
		if velocity != Vector2.ZERO and !_has_selection_tool():
			offset += velocity.rotated(rotation) * zoom * CAMERA_SPEED_RATE
			_update_rulers()

	save_values_to_project()


func _has_selection_tool() -> bool:
	for slot in Tools._slots.values():
		if slot.tool_node is SelectionTool:
			return true
	return false


# Rotate Camera
func _rotate_camera_around_point(degrees: float, point: Vector2) -> void:
	offset = (offset - point).rotated(deg2rad(degrees)) + point
	rotation_degrees = wrapf(rotation_degrees + degrees, -180, 180)
	emit_signal("rotation_changed")


func _rotation_changed() -> void:
	if index == Cameras.MAIN:
		# Negative to make going up in value clockwise, and match the spinbox which does the same
		var degrees := wrapf(-rotation_degrees, -180, 180)
		rotation_slider.value = degrees
		_update_rulers()


# Zoom Camera
func zoom_camera(dir: int) -> void:
	var viewport_size := viewport_container.rect_size
	if Global.smooth_zoom:
		var zoom_margin := zoom * dir / 5
		var new_zoom := zoom + zoom_margin
		if new_zoom > zoom_min && new_zoom < zoom_max:
			var new_offset := (
				offset
				+ (-0.5 * viewport_size + mouse_pos).rotated(rotation) * (zoom - new_zoom)
			)
			var tween := create_tween().set_parallel()
			tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
			tween.connect("step_finished", self, "_on_tween_step")
			tween.tween_property(self, "zoom", new_zoom, 0.05)
			tween.tween_property(self, "offset", new_offset, 0.05)
	else:
		var prev_zoom := zoom
		var zoom_margin := zoom * dir / 10
		if zoom + zoom_margin > zoom_min:
			zoom += zoom_margin
		if zoom > zoom_max:
			zoom = zoom_max
		offset = offset + (-0.5 * viewport_size + mouse_pos).rotated(rotation) * (prev_zoom - zoom)
		emit_signal("zoom_changed")


func _zoom_changed() -> void:
	update_transparent_checker_offset()
	if index == Cameras.MAIN:
		zoom_slider.value = round(100 / zoom.x)
		_update_rulers()
		for guide in Global.current_project.guides:
			guide.width = zoom.x * 2

	elif index == Cameras.SMALL:
		Global.preview_zoom_slider.value = -zoom.x


func _update_rulers() -> void:
	Global.horizontal_ruler.update()
	Global.vertical_ruler.update()


func _on_tween_step(_idx: int) -> void:
	should_tween = false
	emit_signal("zoom_changed")
	should_tween = true


func zoom_100() -> void:
	zoom = Vector2.ONE
	offset = Global.current_project.size / 2
	emit_signal("zoom_changed")


func fit_to_frame(size: Vector2) -> void:
	offset = size / 2

	# Adjust to the rotated size:
	if rotation != 0.0:
		# Calculating the rotated corners of the frame to find its rotated size
		var a := Vector2.ZERO  # Top left
		var b := Vector2(size.x, 0).rotated(rotation)  # Top right
		var c := Vector2(0, size.y).rotated(rotation)  # Bottom left
		var d := Vector2(size.x, size.y).rotated(rotation)  # Bottom right

		# Find how far apart each opposite point is on each axis, and take the longer one
		size.x = max(abs(a.x - d.x), abs(b.x - c.x))
		size.y = max(abs(a.y - d.y), abs(b.y - c.y))

	viewport_container = get_parent().get_parent()
	var h_ratio := viewport_container.rect_size.x / size.x
	var v_ratio := viewport_container.rect_size.y / size.y
	var ratio := min(h_ratio, v_ratio)
	if ratio == 0 or !viewport_container.visible:
		ratio = 0.1  # Set it to a non-zero value just in case
		# If the ratio is 0, it means that the viewport container is hidden
		# in that case, use the other viewport to get the ratio
		if index == Cameras.MAIN:
			h_ratio = Global.second_viewport.rect_size.x / size.x
			v_ratio = Global.second_viewport.rect_size.y / size.y
			ratio = min(h_ratio, v_ratio)
		elif index == Cameras.SECOND:
			h_ratio = Global.main_viewport.rect_size.x / size.x
			v_ratio = Global.main_viewport.rect_size.y / size.y
			ratio = min(h_ratio, v_ratio)

	ratio = clamp(ratio, 0.1, ratio)
	zoom = Vector2(1 / ratio, 1 / ratio)
	emit_signal("zoom_changed")


func save_values_to_project() -> void:
	Global.current_project.cameras_rotation[index] = rotation
	Global.current_project.cameras_zoom[index] = zoom
	Global.current_project.cameras_offset[index] = offset
	Global.current_project.cameras_zoom_max[index] = zoom_max
