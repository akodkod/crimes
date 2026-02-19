class_name PlayerClimbUpState
extends PlayerState

var climb_up_min_height := 0.3
var climb_up_max_height := 2.0
var climb_up_forward_ray_length := 0.7
var climb_up_step_forward_length := 0.25

var _climb_up_target_point := Vector3.ZERO


func can_enter() -> bool:
	if has_climbing_target():
		return true

	var forward_ray_collision := _climb_up_cast_forward_ray()

	if not forward_ray_collision:
		return false

	if not forward_ray_collision.has("position") or forward_ray_collision.position is not Vector3:
		push_warning("Forward ray collision does not have a valid position")
		return false

	var collision_point: Vector3 = forward_ray_collision.position
	_climb_up_target_point = _climb_up_find_target_point(collision_point)

	return _climb_up_target_point != Vector3.ZERO


func on_enter(_previous_state: PlayerState) -> void:
	var rise_tween := create_tween()
	rise_tween.tween_property(player, "transform:origin:y", _climb_up_target_point.y + 0.05, 0.3)
	rise_tween.set_ease(Tween.EASE_OUT)
	await rise_tween.finished

	# Set the target point slightly forward to ensure we end up on top of the obstacle, not just rising up in place
	var forward_offset := transform.basis.x * climb_up_step_forward_length
	var climb_up_target_point_with_offset := _climb_up_target_point + forward_offset

	var forward_tween := create_tween()
	forward_tween.tween_property(player, "transform:origin", climb_up_target_point_with_offset, 0.2)
	forward_tween.set_ease(Tween.EASE_IN)
	forward_tween.set_trans(Tween.TRANS_QUAD)
	await forward_tween.finished

	_exit_climb_up_state()


func process_frame(_delta: float) -> void:
	if not has_climbing_target():
		_exit_climb_up_state()


func _climb_up_cast_forward_ray() -> Dictionary:
	var from := transform.origin + Vector3(0, climb_up_min_height - 0.001, 0)
	var to := from + (transform.basis.x * climb_up_forward_ray_length)

	var query := PhysicsRayQueryParameters3D.create(from, to, Data.CLIMBABLE_MASK)
	var world_3d := player.get_world_3d()
	var collision := world_3d.direct_space_state.intersect_ray(query)

	Debugger.draw_ray_and_collision(query, collision, 3)

	return collision


func _climb_up_find_target_point(forward_ray_collision_point: Vector3) -> Vector3:
	var from := forward_ray_collision_point + Vector3(0, climb_up_max_height - climb_up_min_height + 0.2, 0)
	var to := forward_ray_collision_point

	var query := PhysicsRayQueryParameters3D.create(from, to, Data.CLIMBABLE_MASK)
	var world_3d := player.get_world_3d()
	var collision := world_3d.direct_space_state.intersect_ray(query)

	Debugger.draw_ray_and_collision(query, collision, 3)

	if not collision:
		print("No collision detected in height check.")
		return Vector3.ZERO

	var collision_point: Vector3 = collision.position
	var height := snappedf(collision_point.y - transform.origin.y, 0.01)

	if height < climb_up_min_height or height > climb_up_max_height:
		print("Climb height out of range: ", height)
		return Vector3.ZERO

	return collision_point


func has_climbing_target() -> bool:
	return _climb_up_target_point != Vector3.ZERO


func _exit_climb_up_state() -> void:
	_climb_up_target_point = Vector3.ZERO

	if player.is_on_floor():
		state.to_ground()
	else:
		state.to_air()
