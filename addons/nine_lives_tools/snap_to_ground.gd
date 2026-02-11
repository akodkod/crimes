@tool
extends RefCounted

var undo_redo: EditorUndoRedoManager


## Called from the plugin's _forward_3d_gui_input. Returns an AfterGUIInput value.
func handle_3d_input(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		var is_hyperkey: bool = (
			event.ctrl_pressed
			and event.alt_pressed
			and event.shift_pressed
			and event.meta_pressed
		)
		if is_hyperkey and event.keycode == KEY_G:
			_snap_selection_to_ground(camera)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------


func _snap_selection_to_ground(camera: Camera3D) -> void:
	var selected: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	if selected.is_empty():
		return

	var world: World3D = camera.get_world_3d()
	if world == null or world.direct_space_state == null:
		return

	# Collect snap data: { node, old_pos, new_pos } for each successful hit.
	var snap_data: Array[Dictionary] = []

	for node: Node in selected:
		if not node is Node3D:
			continue
		var node3d := node as Node3D
		var result: Variant = _raycast_down(node3d, world)
		if result == null:
			continue

		var hit_pos: Vector3 = result
		var old_pos: Vector3 = node3d.global_position
		var new_pos: Vector3 = Vector3(old_pos.x, hit_pos.y + _get_bottom_offset(node3d), old_pos.z)

		snap_data.append({
			"node": node3d,
			"old_pos": old_pos,
			"new_pos": new_pos,
		})

	if snap_data.is_empty():
		return

	undo_redo.create_action("Snap to Ground")
	for entry: Dictionary in snap_data:
		undo_redo.add_do_method(self, &"_set_position", entry.node, entry.new_pos)
		undo_redo.add_undo_method(self, &"_set_position", entry.node, entry.old_pos)
	undo_redo.commit_action()


# ---------------------------------------------------------------------------
# Raycasting
# ---------------------------------------------------------------------------


## Casts a ray straight down from the node's origin. Returns the hit position
## (Vector3) or null if nothing was hit. Excludes collision objects that belong
## to the node itself so it doesn't collide with its own body.
func _raycast_down(node: Node3D, world: World3D) -> Variant:
	var origin: Vector3 = node.global_position
	var end: Vector3 = origin + Vector3.DOWN * 10000.0

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = _collect_collision_rids(node)

	var result: Dictionary = world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null

	return result.position


## Recursively collects the RIDs of every CollisionObject3D inside a subtree
## so the raycast can exclude the node's own colliders.
func _collect_collision_rids(node: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if node is CollisionObject3D:
		rids.append((node as CollisionObject3D).get_rid())
	for child: Node in node.get_children():
		rids.append_array(_collect_collision_rids(child))
	return rids


# ---------------------------------------------------------------------------
# AABB bottom offset
# ---------------------------------------------------------------------------


## Returns how far to shift the node upward so the bottom of its visual
## bounding box sits on the hit point.  For compound nodes (a Node3D parent
## with mesh/CSG children) it merges the children's AABBs.
func _get_bottom_offset(node: Node3D) -> float:
	# --- CSG primitives (AABB not available right after instantiation) ---
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

	# --- MeshInstance3D ---
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var aabb: AABB = mi.mesh.get_aabb()
			if aabb.size != Vector3.ZERO:
				return -aabb.position.y

	# --- Generic VisualInstance3D ---
	if node is VisualInstance3D:
		var aabb: AABB = (node as VisualInstance3D).get_aabb()
		if aabb.size != Vector3.ZERO:
			return -aabb.position.y

	# --- Compound node: merge children AABBs ---
	var merged: AABB = _compute_children_local_aabb(node)
	if merged.size != Vector3.ZERO:
		return -merged.position.y

	return 0.0


## Recursively merges the local AABBs of all VisualInstance3D descendants,
## transforming each child's AABB into the root node's local space.
func _compute_children_local_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var found := false

	for child: Node in root.get_children():
		if child is VisualInstance3D:
			var vi := child as VisualInstance3D
			var child_aabb: AABB = vi.get_aabb()
			if child_aabb.size == Vector3.ZERO:
				continue
			# Transform child AABB into root's local space.
			var child_to_root: Transform3D = root.global_transform.affine_inverse() * vi.global_transform
			var transformed: AABB = child_to_root * child_aabb
			if not found:
				merged = transformed
				found = true
			else:
				merged = merged.merge(transformed)

		if child is Node3D:
			var sub: AABB = _compute_children_local_aabb(child as Node3D)
			if sub.size != Vector3.ZERO:
				if not found:
					merged = sub
					found = true
				else:
					merged = merged.merge(sub)

	return merged


# ---------------------------------------------------------------------------
# Undo / Redo helpers
# ---------------------------------------------------------------------------


func _set_position(node: Node3D, pos: Vector3) -> void:
	node.global_position = pos
