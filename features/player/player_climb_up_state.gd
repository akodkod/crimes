class_name PlayerClimbUpState
extends PlayerState

var climb_up_from_ground_min_height := 0.3
var climb_up_from_ground_max_height := 2.0
var climb_up_from_air_max_height := 1.5 # height of the body

# Climb up won't active if jump was too short
var climb_up_from_air_jump_distance_threshold := 3.0

var climb_up_forward_ray_length := 0.7
var climb_up_step_forward_length := 0.25

var _climb_up_target_point := Vector3.ZERO


func can_enter() -> bool:
	if has_climbing_target():
		return true

	# Check jump distance and if it's less than threshold
	# skip climb up to avoid accidentally triggering it when trying to jump while standing in front of an obstacle
	if state.is_air() and state.air.get_jump_distance() < climb_up_from_air_jump_distance_threshold:
		return false

	var forward_ray_collision := _climb_up_cast_forward_ray()

	if not forward_ray_collision:
		return false

	if not forward_ray_collision.has("position") or forward_ray_collision.position is not Vector3:
		push_warning("Forward ray collision does not have a valid position")
		return false

	var collision_point: Vector3 = forward_ray_collision.position
	_climb_up_target_point = _climb_up_find_target_point(collision_point)

	return _climb_up_target_point != Vector3.ZERO


func on_enter(previous_state: PlayerState) -> void:
	var is_from_air := previous_state is PlayerAirState
	var forward_tween_duration := 0.4 if is_from_air else 0.2

	# Do not apply two step climb up if we are already in the air
	if not is_from_air:
		var rise_tween := create_tween()
		rise_tween.tween_property(player, "transform:origin:y", _climb_up_target_point.y + 0.05, 0.3)
		rise_tween.set_ease(Tween.EASE_OUT)
		await rise_tween.finished

	# Set the target point slightly forward to ensure we end up on top of the obstacle, not just rising up in place
	var forward_offset := transform.basis.x * climb_up_step_forward_length
	var climb_up_target_point_with_offset := _climb_up_target_point + forward_offset

	var forward_tween := create_tween()
	forward_tween.tween_property(player, "transform:origin", climb_up_target_point_with_offset, forward_tween_duration)
	forward_tween.set_ease(Tween.EASE_IN)
	forward_tween.set_trans(Tween.TRANS_QUAD)
	await forward_tween.finished

	_exit_climb_up_state()


func process_frame(_delta: float) -> void:
	if not has_climbing_target():
		_exit_climb_up_state()


func _climb_up_cast_forward_ray() -> Dictionary:
	var from_offset: Vector3

	# No offset for air, but for ground we need to start the ray a bit above the ground to avoid hitting small obstacles
	if state.is_air():
		from_offset = Vector3(0, 0, 0)
	else:
		from_offset = Vector3(0, climb_up_from_ground_min_height - 0.001, 0)

	var from := transform.origin + from_offset
	var to := from + (transform.basis.x * climb_up_forward_ray_length)

	var query := PhysicsRayQueryParameters3D.create(from, to, Data.CLIMBABLE_MASK)
	var world_3d := player.get_world_3d()
	var collision := world_3d.direct_space_state.intersect_ray(query)

	Debugger.draw_ray_and_collision(query, collision, 3)

	return collision


func _climb_up_find_target_point(forward_ray_collision_point: Vector3) -> Vector3:
	var from_offset: Vector3

	# Calculate offset based on we're on the ground or in the air
	if state.is_air():
		from_offset = Vector3(0, climb_up_from_air_max_height + 0.2, 0)
	else:
		from_offset = Vector3(0, climb_up_from_ground_max_height - climb_up_from_ground_min_height + 0.2, 0)

	var from := forward_ray_collision_point + from_offset
	var to := forward_ray_collision_point

	var query := PhysicsRayQueryParameters3D.create(from, to, Data.CLIMBABLE_MASK)
	var world_3d := player.get_world_3d()
	var collision := world_3d.direct_space_state.intersect_ray(query)

	Debugger.draw_ray_and_collision(query, collision, 3)

	if not collision:
		Debugger.log("No collision detected in height check", Debugger.Area.CHARACTER_MOVEMENT)
		return Vector3.ZERO

	var collision_point: Vector3 = collision.position
	var height := snappedf(collision_point.y - transform.origin.y, 0.01)

	if state.is_air() and height > climb_up_from_air_max_height:
		Debugger.log("Climb height from air too high: %s" % height, Debugger.Area.CHARACTER_MOVEMENT)
		return Vector3.ZERO

	if height < climb_up_from_ground_min_height or height > climb_up_from_ground_max_height:
		Debugger.log("Climb height from ground out of range: %s" % height, Debugger.Area.CHARACTER_MOVEMENT)
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
