extends BaseTool

var _cel: Cel3D
var _can_start_timer := true
var _hovering: Cel3DObject = null
var _dragging := false
var _has_been_dragged := false
var _prev_mouse_pos := Vector2.ZERO
var _object_names := {
	Cel3DObject.Type.BOX: "Box",
	Cel3DObject.Type.SPHERE: "Sphere",
	Cel3DObject.Type.CAPSULE: "Capsule",
	Cel3DObject.Type.CYLINDER: "Cylinder",
	Cel3DObject.Type.PRISM: "Prism",
	Cel3DObject.Type.TORUS: "Torus",
	Cel3DObject.Type.PLANE: "Plane",
	Cel3DObject.Type.TEXT: "Text",
	Cel3DObject.Type.DIR_LIGHT: "Directional light",
	Cel3DObject.Type.SPOT_LIGHT: "Spotlight",
	Cel3DObject.Type.OMNI_LIGHT: "Point light",
	Cel3DObject.Type.IMPORTED: "Custom model",
}

onready var object_option_button := $"%ObjectOptionButton" as OptionButton
onready var new_object_menu_button := $"%NewObjectMenuButton" as MenuButton
onready var remove_object_button := $"%RemoveObject" as Button
onready var cel_options := $"%CelOptions" as Container
onready var object_options := $"%ObjectOptions" as Container
onready var mesh_options := $"%MeshOptions" as VBoxContainer
onready var light_options := $"%LightOptions" as VBoxContainer
onready var undo_redo_timer := $UndoRedoTimer as Timer
onready var load_model_dialog := $LoadModelDialog as FileDialog

onready var cel_properties := {
	"camera:projection": $"%ProjectionOptionButton",
	"camera:rotation_degrees": $"%CameraRotation",
	"camera:fov": $"%CameraFOV",
	"camera:size": $"%CameraSize",
	"viewport:world:environment:ambient_light_color": $"%AmbientColorPickerButton",
	"viewport:world:environment:ambient_light_energy": $"%AmbientEnergy",
}

onready var object_properties := {
	"visible": $"%VisibleCheckBox",
	"translation": $"%ObjectPosition",
	"rotation_degrees": $"%ObjectRotation",
	"scale": $"%ObjectScale",
	"node3d_type:mesh:size": $"%MeshSize",
	"node3d_type:mesh:sizev2": $"%MeshSizeV2",
	"node3d_type:mesh:left_to_right": $"%MeshLeftToRight",
	"node3d_type:mesh:radius": $"%MeshRadius",
	"node3d_type:mesh:height": $"%MeshHeight",
	"node3d_type:mesh:radial_segments": $"%MeshRadialSegments",
	"node3d_type:mesh:rings": $"%MeshRings",
	"node3d_type:mesh:is_hemisphere": $"%MeshIsHemisphere",
	"node3d_type:mesh:mid_height": $"%MeshMidHeight",
	"node3d_type:mesh:top_radius": $"%MeshTopRadius",
	"node3d_type:mesh:bottom_radius": $"%MeshBottomRadius",
	"node3d_type:mesh:text": $"%MeshText",
	"node3d_type:mesh:pixel_size": $"%MeshPixelSize",
	"node3d_type:mesh:curve_step": $"%MeshCurveStep",
	"node3d_type:mesh:horizontal_alignment": $"%MeshHorizontalAlignment",
	"node3d_type:light_color": $"%LightColor",
	"node3d_type:light_energy": $"%LightEnergy",
	"node3d_type:light_negative": $"%LightNegative",
	"node3d_type:shadow_enabled": $"%ShadowEnabled",
	"node3d_type:shadow_color": $"%ShadowColor",
	"node3d_type:omni_range": $"%OmniRange",
	"node3d_type:spot_range": $"%SpotRange",
	"node3d_type:spot_angle": $"%SpotAngle",
}


func _ready() -> void:
	Global.connect("cel_changed", self, "_cel_changed")
	_cel_changed()
	var new_object_popup := new_object_menu_button.get_popup()
	for object in _object_names:
		if object == Cel3DObject.Type.TORUS:  # Remove when Godot 3.6 or 4.0 is used
			continue
		new_object_popup.add_item(_object_names[object], object)
	new_object_popup.connect("id_pressed", self, "_new_object_popup_id_pressed")
	for prop in cel_properties:
		var node: Control = cel_properties[prop]
		if node is ValueSliderV3:
			node.connect("value_changed", self, "_cel_property_vector3_changed", [prop])
		elif node is Range:
			node.connect("value_changed", self, "_cel_property_value_changed", [prop])
		elif node is OptionButton:
			node.connect("item_selected", self, "_cel_property_item_selected", [prop])
		elif node is ColorPickerButton:
			node.connect("color_changed", self, "_cel_property_color_changed", [prop])
	for prop in object_properties:
		var node: Control = object_properties[prop]
		if node is ValueSliderV3:
			node.connect("value_changed", self, "_object_property_vector3_changed", [prop])
		elif node is ValueSliderV2:
			var property_path: String = prop
			if property_path.ends_with("v2"):
				property_path = property_path.replace("v2", "")
			node.connect("value_changed", self, "_object_property_vector2_changed", [property_path])
		elif node is Range:
			node.connect("value_changed", self, "_object_property_value_changed", [prop])
		elif node is OptionButton:
			node.connect("item_selected", self, "_object_property_item_selected", [prop])
		elif node is ColorPickerButton:
			node.connect("color_changed", self, "_object_property_color_changed", [prop])
		elif node is CheckBox:
			node.connect("toggled", self, "_object_property_toggled", [prop])
		elif node is LineEdit:
			node.connect("text_changed", self, "_object_property_text_changed", [prop])


func draw_start(position: Vector2) -> void:
	var project: Project = Global.current_project
	if not project.get_current_cel() is Cel3D:
		return
	if not project.layers[project.current_layer].can_layer_get_drawn():
		return
	var found_cel := false
	for frame_layer in project.selected_cels:
		if _cel == project.frames[frame_layer[0]].cels[frame_layer[1]]:
			found_cel = true
	if not found_cel:
		return

	if is_instance_valid(_cel.selected):
		# Needs canvas.current_pixel, because draw_start()'s position is floored
		_cel.selected.applying_gizmos = Global.canvas.gizmos_3d.get_hovering_gizmo(
			Global.canvas.current_pixel
		)
	if is_instance_valid(_hovering):
		_cel.selected = _hovering
		_dragging = true
		_prev_mouse_pos = position
	else:  # We're not hovering
		if is_instance_valid(_cel.selected):
			# If we're not clicking on a gizmo, unselect
			if _cel.selected.applying_gizmos == Cel3DObject.Gizmos.NONE:
				_cel.selected = null
			else:
				_dragging = true
				_prev_mouse_pos = position


func draw_move(position: Vector2) -> void:
	if not Global.current_project.get_current_cel() is Cel3D:
		return
	var camera: Camera = _cel.camera
	if _dragging:
		_has_been_dragged = true
		var proj_mouse_pos := camera.project_position(position, camera.translation.z)
		var proj_prev_mouse_pos := camera.project_position(_prev_mouse_pos, camera.translation.z)
		_cel.selected.change_transform(proj_mouse_pos, proj_prev_mouse_pos)
		_prev_mouse_pos = position


func draw_end(_position: Vector2) -> void:
	if not Global.current_project.get_current_cel() is Cel3D:
		return
	_dragging = false
	if is_instance_valid(_cel.selected) and _has_been_dragged:
		_cel.selected.applying_gizmos = Cel3DObject.Gizmos.NONE
		_object_property_changed(_cel.selected)
	_has_been_dragged = false


func cursor_move(position: Vector2) -> void:
	.cursor_move(position)
	if not Global.current_project.get_current_cel() is Cel3D:
		return
	# Hover logic
	var camera: Camera = _cel.camera
	var ray_from := camera.project_ray_origin(position)
	var ray_to := ray_from + camera.project_ray_normal(position) * 20
	var space_state := camera.get_world().direct_space_state
	var selection := space_state.intersect_ray(ray_from, ray_to)
	if selection.empty():
		if is_instance_valid(_hovering):
			_hovering.unhover()
			_hovering = null
	else:
		if is_instance_valid(_hovering):
			_hovering.unhover()
		_hovering = selection["collider"].get_parent()
		_hovering.hover()


func _on_ObjectOptionButton_item_selected(index: int) -> void:
	if not _cel is Cel3D:
		return
	var id := object_option_button.get_item_id(index) - 1
	var object := _cel.get_object_from_id(id)
	if not is_instance_valid(object):
		_cel.selected = null
		return
	_cel.selected = object


func _cel_changed() -> void:
	if not Global.current_project.get_current_cel() is Cel3D:
		get_child(0).visible = false  # Just to ensure that the content of the tool is hidden
		return
	get_child(0).visible = true
	_cel = Global.current_project.get_current_cel()
	_cel.selected = null
	if not _cel.is_connected("scene_property_changed", self, "_set_cel_node_values"):
		_cel.connect("scene_property_changed", self, "_set_cel_node_values")
		_cel.connect("objects_changed", self, "_fill_object_option_button")
		_cel.connect("selected_object", self, "_selected_object")
	cel_options.visible = true
	object_options.visible = false
	_set_cel_node_values()
	_fill_object_option_button()


func _new_object_popup_id_pressed(id: int) -> void:
	if id == Cel3DObject.Type.IMPORTED:
		load_model_dialog.popup_centered()
		Global.dialog_open(true)
	else:
		_add_object(id)


func _add_object(type: int, file_path := "") -> void:
	var dict := {"type": type, "file_path": file_path}
	var new_objects := _cel.object_properties.duplicate()
	new_objects[_cel.current_object_id] = dict
	var undo_redo: UndoRedo = Global.current_project.undo_redo
	undo_redo.create_action("Add 3D object")
	undo_redo.add_do_property(_cel, "object_properties", new_objects)
	undo_redo.add_undo_property(_cel, "object_properties", _cel.object_properties)
	undo_redo.add_do_method(_cel, "_add_object_node", _cel.current_object_id)
	undo_redo.add_undo_method(_cel, "_remove_object_node", _cel.current_object_id)
	undo_redo.add_do_method(Global, "undo_or_redo", false)
	undo_redo.add_undo_method(Global, "undo_or_redo", true)
	undo_redo.commit_action()
	_cel.current_object_id += 1


func _on_RemoveObject_pressed() -> void:
	if is_instance_valid(_cel.selected):
		var new_objects := _cel.object_properties.duplicate()
		new_objects.erase(_cel.selected.id)
		var undo_redo: UndoRedo = Global.current_project.undo_redo
		undo_redo.create_action("Remove 3D object")
		undo_redo.add_do_property(_cel, "object_properties", new_objects)
		undo_redo.add_undo_property(_cel, "object_properties", _cel.object_properties)
		undo_redo.add_do_method(_cel, "_remove_object_node", _cel.selected.id)
		undo_redo.add_undo_method(_cel, "_add_object_node", _cel.selected.id)
		undo_redo.add_do_method(Global, "undo_or_redo", false)
		undo_redo.add_undo_method(Global, "undo_or_redo", true)
		undo_redo.commit_action()
		_cel.selected = null


func _object_property_changed(object: Cel3DObject) -> void:
	var undo_redo: UndoRedo = Global.current_project.undo_redo
	var new_properties := _cel.object_properties.duplicate()
	new_properties[object.id] = object.serialize()
	undo_redo.create_action("Change object transform")
	undo_redo.add_do_property(_cel, "object_properties", new_properties)
	undo_redo.add_undo_property(_cel, "object_properties", _cel.object_properties)
	undo_redo.add_do_method(_cel, "_update_objects_transform", object.id)
	undo_redo.add_undo_method(_cel, "_update_objects_transform", object.id)
	undo_redo.add_do_method(Global, "undo_or_redo", false)
	undo_redo.add_undo_method(Global, "undo_or_redo", true)
	undo_redo.commit_action()


func _selected_object(object: Cel3DObject) -> void:
	if is_instance_valid(object):
		cel_options.visible = false
		object_options.visible = true
		remove_object_button.disabled = false
		for prop in object_properties:  # Hide irrelevant nodes
			var node: Control = object_properties[prop]
			var property_path: String = prop
			if property_path.ends_with("v2"):
				property_path = property_path.replace("v2", "")
			var property = object.get_indexed(property_path)
			var property_exists: bool = property != null
			# Differentiate between the mesh size of a box/prism (Vector3) and a plane (Vector2)
			if node is ValueSliderV3 and typeof(property) != TYPE_VECTOR3:
				property_exists = false
			elif node is ValueSliderV2 and typeof(property) != TYPE_VECTOR2:
				property_exists = false
			if node.get_index() > 0:
				_get_previous_node(node).visible = property_exists
			node.visible = property_exists
		mesh_options.visible = object.node3d_type is MeshInstance
		light_options.visible = object.node3d_type is Light
		_set_object_node_values()
		if not object.is_connected("property_changed", self, "_set_object_node_values"):
			object.connect("property_changed", self, "_set_object_node_values")
		object_option_button.select(object_option_button.get_item_index(object.id + 1))
	else:
		cel_options.visible = true
		object_options.visible = false
		remove_object_button.disabled = true
		object_option_button.select(0)


func _set_cel_node_values() -> void:
	if _cel.camera.projection == Camera.PROJECTION_PERSPECTIVE:
		_get_previous_node(cel_properties["camera:fov"]).visible = true
		_get_previous_node(cel_properties["camera:size"]).visible = false
		cel_properties["camera:fov"].visible = true
		cel_properties["camera:size"].visible = false
	else:
		_get_previous_node(cel_properties["camera:size"]).visible = true
		_get_previous_node(cel_properties["camera:fov"]).visible = false
		cel_properties["camera:size"].visible = true
		cel_properties["camera:fov"].visible = false
	_can_start_timer = false
	_set_node_values(_cel, cel_properties)
	_can_start_timer = true


func _set_object_node_values() -> void:
	var object: Cel3DObject = _cel.selected
	if not is_instance_valid(object):
		return
	_can_start_timer = false
	_set_node_values(object, object_properties)
	_can_start_timer = true


func _set_node_values(to_edit: Object, properties: Dictionary) -> void:
	for prop in properties:
		var property_path: String = prop
		if property_path.ends_with("v2"):
			property_path = property_path.replace("v2", "")
		var value = to_edit.get_indexed(property_path)
		if value == null:
			continue
		if "scale" in prop:
			value *= 100
		var node: Control = properties[prop]
		if node is Range or node is ValueSliderV3 or node is ValueSliderV2:
			if typeof(node.value) != typeof(value) and typeof(value) != TYPE_INT:
				continue
			node.value = value
		elif node is OptionButton:
			node.selected = value
		elif node is ColorPickerButton:
			node.color = value
		elif node is CheckBox:
			node.pressed = value
		elif node is LineEdit:
			node.text = value


func _get_previous_node(node: Node) -> Node:
	return node.get_parent().get_child(node.get_index() - 1)


func _set_value_from_node(to_edit: Object, value, prop: String) -> void:
	if not is_instance_valid(to_edit):
		return
	if "mesh_" in prop:
		prop = prop.replace("mesh_", "")
		to_edit = to_edit.node3d_type.mesh
	if "scale" in prop:
		value /= 100
	to_edit.set_indexed(prop, value)


func _cel_property_vector3_changed(value: Vector3, prop: String) -> void:
	_set_value_from_node(_cel, value, prop)
	_value_handle_change()
	Global.canvas.gizmos_3d.update()


func _cel_property_value_changed(value: float, prop: String) -> void:
	_set_value_from_node(_cel, value, prop)
	_value_handle_change()
	Global.canvas.gizmos_3d.update()


func _cel_property_item_selected(value: int, prop: String) -> void:
	_set_value_from_node(_cel, value, prop)
	_value_handle_change()
	Global.canvas.gizmos_3d.update()


func _cel_property_color_changed(value: Color, prop: String) -> void:
	_set_value_from_node(_cel, value, prop)
	_value_handle_change()
	Global.canvas.gizmos_3d.update()


func _object_property_vector3_changed(value: Vector3, prop: String) -> void:
	_set_value_from_node(_cel.selected, value, prop)
	_value_handle_change()


func _object_property_vector2_changed(value: Vector2, prop: String) -> void:
	_set_value_from_node(_cel.selected, value, prop)
	_value_handle_change()


func _object_property_value_changed(value: float, prop: String) -> void:
	_set_value_from_node(_cel.selected, value, prop)
	_value_handle_change()


func _object_property_item_selected(value: int, prop: String) -> void:
	_set_value_from_node(_cel.selected, value, prop)
	_value_handle_change()


func _object_property_color_changed(value: Color, prop: String) -> void:
	_set_value_from_node(_cel.selected, value, prop)
	_value_handle_change()


func _object_property_toggled(value: bool, prop: String) -> void:
	_set_value_from_node(_cel.selected, value, prop)
	_value_handle_change()


func _object_property_text_changed(value: String, prop: String) -> void:
	_set_value_from_node(_cel.selected, value, prop)
	_value_handle_change()


func _value_handle_change() -> void:
	if _can_start_timer:
		undo_redo_timer.start()


func _fill_object_option_button() -> void:
	if not _cel is Cel3D:
		return
	object_option_button.clear()
	object_option_button.add_item("None", 0)
	for id in _cel.object_properties:
		var item_name: String = _object_names[_cel.object_properties[id]["type"]]
		object_option_button.add_item(item_name, id + 1)


func _on_UndoRedoTimer_timeout() -> void:
	if is_instance_valid(_cel.selected):
		_object_property_changed(_cel.selected)
	else:
		var undo_redo: UndoRedo = Global.current_project.undo_redo
		undo_redo.create_action("Change 3D layer properties")
		undo_redo.add_do_property(_cel, "scene_properties", _cel.serialize_scene_properties())
		undo_redo.add_undo_property(_cel, "scene_properties", _cel.scene_properties)
		undo_redo.add_do_method(_cel, "_scene_property_changed")
		undo_redo.add_undo_method(_cel, "_scene_property_changed")
		undo_redo.add_do_method(Global, "undo_or_redo", false)
		undo_redo.add_undo_method(Global, "undo_or_redo", true)
		undo_redo.commit_action()


func _on_LoadModelDialog_files_selected(paths: PoolStringArray) -> void:
	for path in paths:
		_add_object(Cel3DObject.Type.IMPORTED, path)


func _on_LoadModelDialog_popup_hide() -> void:
	Global.dialog_open(false)
