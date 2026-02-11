@tool
extends EditorContextMenuPlugin

var undo_redo: EditorUndoRedoManager


func _popup_menu(_paths: PackedStringArray) -> void:
	var sel := EditorInterface.get_selection()
	var nodes := sel.get_selected_nodes()
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return

	var node3d_count := 0
	for node: Node in nodes:
		if node is Node3D and node != scene_root:
			node3d_count += 1

	if node3d_count < 1:
		return

	var icon := EditorInterface.get_editor_theme().get_icon(&"Groups", &"EditorIcons")
	add_context_menu_item("Group at Center", _on_group_at_center, icon)


## Called from shortcut / command palette – grabs the current selection.
func group_selected_nodes() -> void:
	var sel := EditorInterface.get_selection()
	_on_group_at_center(sel.get_selected_nodes())


func _on_group_at_center(nodes: Array) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return

	var picked: Array[Node3D] = []
	for node: Variant in nodes:
		if node is Node3D and node != scene_root:
			picked.append(node)

	if picked.is_empty():
		push_warning("Select at least one Node3D (not the scene root)")
		return

	var global_aabb := _compute_selection_global_aabb(picked)
	if global_aabb == null:
		push_warning("Could not compute bounds (no visual/collision shapes found)")
		return

	var center: Vector3 = global_aabb.position + global_aabb.size * 0.5
	var common_parent := _find_common_parent(picked)
	if common_parent == null:
		push_warning("Selected nodes must share a common parent")
		return

	# Sort by child index ascending so undo restores the original order.
	var pairs: Array[Dictionary] = []

	for node: Node3D in picked:
		pairs.append({ "node": node, "index": node.get_index() })

	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.index < b.index)

	var sorted_picked: Array[Node3D] = []
	var sorted_indices: Array[int] = []
	for pair: Dictionary in pairs:
		sorted_picked.append(pair.node)
		sorted_indices.append(pair.index)

	var group := Node3D.new()
	group.name = "Group"

	undo_redo.create_action("Group at Center")
	undo_redo.add_do_method(self, "_do_group", group, sorted_picked, common_parent, scene_root, center)
	undo_redo.add_do_reference(group)
	undo_redo.add_undo_method(self, "_undo_group", group, sorted_picked, common_parent, scene_root, sorted_indices)
	undo_redo.commit_action()


func _do_group(
		group: Node3D,
		nodes: Array[Node3D],
		parent: Node,
		scene_root: Node,
		center: Vector3,
) -> void:
	parent.add_child(group)
	group.owner = scene_root
	group.global_transform = Transform3D(Basis.IDENTITY, center)

	for node: Node3D in nodes:
		node.reparent(group, true)
		_set_owner_recursive(node, scene_root)

	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(group)


func _undo_group(
		group: Node3D,
		nodes: Array[Node3D],
		parent: Node,
		scene_root: Node,
		original_indices: Array[int],
) -> void:
	for i: int in range(nodes.size()):
		nodes[i].reparent(parent, true)
		_set_owner_recursive(nodes[i], scene_root)
		parent.move_child(nodes[i], original_indices[i])

	parent.remove_child(group)

	var sel := EditorInterface.get_selection()
	sel.clear()

	for node in nodes:
		sel.add_node(node)


func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	node.owner = new_owner

	for child in node.get_children():
		_set_owner_recursive(child, new_owner)


func _compute_selection_global_aabb(nodes: Array[Node3D]) -> Variant:
	var have_any := false
	var acc := AABB()

	for node: Node3D in nodes:
		var contributors: Array[Node3D] = [node]

		for child: Node in node.get_children():
			if child is Node3D:
				contributors.append_array(_collect_node3d_descendants(child))

		for contributor: Node3D in contributors:
			var aabb_local_opt: Variant = _get_local_bounds_aabb(contributor)
			if aabb_local_opt == null:
				continue

			var aabb_local: AABB = aabb_local_opt
			var aabb_global: AABB = contributor.global_transform * aabb_local

			if not have_any:
				acc = aabb_global
				have_any = true
			else:
				acc = acc.merge(aabb_global)

	return acc if have_any else null


func _collect_node3d_descendants(root: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	out.append(root)

	for child: Node in root.get_children():
		if child is Node3D:
			out.append_array(_collect_node3d_descendants(child))

	return out


func _get_local_bounds_aabb(node: Node3D) -> Variant:
	# VisualInstance3D covers MeshInstance3D, CSGShape3D, MultiMeshInstance3D, etc.
	if node is VisualInstance3D:
		return (node as VisualInstance3D).get_aabb()

	if node is CollisionShape3D:
		var collision_shape := node as CollisionShape3D

		if collision_shape.shape == null:
			return null

		return _shape3d_local_aabb(collision_shape.shape)

	return null


func _shape3d_local_aabb(shape: Shape3D) -> Variant:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)

	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius

		return AABB(
			Vector3(-r, -r, -r),
			Vector3(2.0 * r, 2.0 * r, 2.0 * r),
		)

	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var r := capsule.radius
		var half_y := capsule.height * 0.5

		return AABB(
			Vector3(-r, -half_y, -r),
			Vector3(2.0 * r, 2.0 * half_y, 2.0 * r),
		)

	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var r := cylinder.radius
		var half_y := cylinder.height * 0.5

		return AABB(
			Vector3(-r, -half_y, -r),
			Vector3(2.0 * r, 2.0 * half_y, 2.0 * r),
		)

	if shape is ConvexPolygonShape3D:
		var points := (shape as ConvexPolygonShape3D).points

		if points.is_empty():
			return null

		var aabb := AABB(points[0], Vector3.ZERO)

		for point: Vector3 in points:
			aabb = aabb.expand(point)

		return aabb

	return null


func _find_common_parent(nodes: Array[Node3D]) -> Node:
	if nodes.is_empty():
		return null

	var parent := nodes[0].get_parent()

	for i: int in range(1, nodes.size()):
		if nodes[i].get_parent() != parent:
			return null

	return parent
