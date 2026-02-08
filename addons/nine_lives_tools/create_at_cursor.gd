@tool
extends RefCounted

var undo_redo: EditorUndoRedoManager

var _last_mouse_position: Vector2
var _last_camera: Camera3D
var _create_position: Vector3
var _add_as_child: bool


## Called from the plugin's _forward_3d_gui_input. Returns an AfterGUIInput value.
func handle_3d_input(camera: Camera3D, event: InputEvent) -> int:
	# Track mouse position continuously so we always have the latest cursor data.
	if event is InputEventMouseMotion:
		_last_mouse_position = event.position
		_last_camera = camera
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Detect Hyperkey (Cmd+Option+Shift+Control) shortcuts:
	#   +A  → add to scene root
	#   +C  → add as child of current selection
	if event is InputEventKey and event.pressed and not event.echo:
		var is_hyperkey: bool = (
			event.ctrl_pressed
			and event.alt_pressed
			and event.shift_pressed
			and event.meta_pressed
		)
		if is_hyperkey and event.keycode in [KEY_A, KEY_C]:
			_add_as_child = event.keycode == KEY_C
			_create_position = _raycast_from_mouse(camera)

			var title: String = (
				"Create Child Node at Cursor" if _add_as_child
				else "Create Node at Cursor"
			)
			EditorInterface.popup_create_dialog(
				_on_node_type_selected,
				&"Node3D",
				"",
				title,
			)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS

# ---------------------------------------------------------------------------
# Raycasting (follows the move_here addon pattern)
# ---------------------------------------------------------------------------


func _raycast_from_mouse(camera: Camera3D) -> Vector3:
	var origin: Vector3 = camera.project_ray_origin(_last_mouse_position)
	var direction: Vector3 = camera.project_ray_normal(_last_mouse_position)
	var end: Vector3 = origin + direction * 10000.0

	# Try physics raycast first.
	var world: World3D = camera.get_world_3d()
	if world and world.direct_space_state:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
		var result: Dictionary = world.direct_space_state.intersect_ray(query)
		if not result.is_empty():
			return result.position

	# Fallback: intersect with the ground plane (Y = 0).
	var plane := Plane(Vector3.UP, 0)
	var intersection: Variant = plane.intersects_ray(origin, direction)
	if intersection:
		return intersection

	# Last resort: a point along the ray.
	return origin + direction * 10.0

# ---------------------------------------------------------------------------
# Node creation callback
# ---------------------------------------------------------------------------


func _on_node_type_selected(type_name: String) -> void:
	if type_name.is_empty():
		return # User cancelled.

	# Instantiate the chosen type.
	var node: Node
	if type_name.begins_with("res://"):
		var script: Script = load(type_name)
		node = script.new()
	else:
		node = ClassDB.instantiate(type_name)

	if node == null:
		push_error("Nine Lives Tools: Could not instantiate '%s'." % type_name)
		return

	# Give the node a clean default name (ClassDB.instantiate produces "@Type@123").
	if not type_name.begins_with("res://"):
		node.name = type_name

	# Determine parent node.
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		push_error("Nine Lives Tools: No scene is currently open.")
		node.free()
		return

	var parent: Node = scene_root
	if _add_as_child:
		var selected: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
		if not selected.is_empty() and selected[0] is Node3D:
			parent = selected[0]

	# Auto-suffix to avoid duplicate names among siblings.
	node.name = _unique_name(parent, node.name)

	# Wrap in undo/redo.  We pass the world-space hit position and convert
	# to local inside _do_create_node so we can also apply a bottom-offset.
	undo_redo.create_action("Create Node at Cursor")
	undo_redo.add_do_method(self, &"_do_create_node", node, parent, _create_position, scene_root)
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_method(self, &"_undo_create_node", node)
	undo_redo.commit_action()


func _do_create_node(
		node: Node,
		parent: Node,
		hit_position: Vector3,
		scene_root: Node,
) -> void:
	parent.add_child(node)
	node.owner = scene_root
	if node is Node3D:
		var node3d := node as Node3D
		# Place the node so the bottom of its bounding box sits on the surface.
		node3d.global_position = hit_position
		node3d.global_position += Vector3(0.0, _get_bottom_offset(node3d), 0.0)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)


## Returns how far to shift the node upward so its AABB bottom sits on the hit point.
func _get_bottom_offset(node: Node3D) -> float:
	# CSG shapes: AABB isn't available right after instantiation (mesh not built
	# yet), so compute the offset directly from their known properties.
	if node is CSGBox3D:
		return (node as CSGBox3D).size.y / 2.0
	if node is CSGCylinder3D:
		return (node as CSGCylinder3D).height / 2.0
	if node is CSGSphere3D:
		return (node as CSGSphere3D).radius
	if node is CSGTorus3D:
		var torus := node as CSGTorus3D
		return (torus.outer_radius - torus.inner_radius) / 2.0
	if node is CSGMesh3D:
		var csg_mesh := node as CSGMesh3D
		if csg_mesh.mesh:
			var aabb: AABB = csg_mesh.mesh.get_aabb()
			if aabb.size != Vector3.ZERO:
				return -aabb.position.y

	# MeshInstance3D: read AABB from the mesh resource directly.
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var aabb: AABB = mi.mesh.get_aabb()
			if aabb.size != Vector3.ZERO:
				return -aabb.position.y

	# Generic VisualInstance3D fallback.
	if node is VisualInstance3D:
		var aabb: AABB = (node as VisualInstance3D).get_aabb()
		if aabb.size != Vector3.ZERO:
			return -aabb.position.y

	return 0.0


func _undo_create_node(node: Node) -> void:
	if node.get_parent():
		node.get_parent().remove_child(node)


## Returns a unique name among the parent's children (e.g. CSGBox3D, CSGBox3D2, CSGBox3D3…).
func _unique_name(parent: Node, base_name: String) -> String:
	var existing: Dictionary = { }

	for child: Node in parent.get_children():
		existing[child.name] = true

	if not existing.has(base_name):
		return base_name

	var idx: int = 2
	while existing.has(base_name + str(idx)):
		idx += 1

	return base_name + str(idx)
