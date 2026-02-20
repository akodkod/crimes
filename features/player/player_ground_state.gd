class_name PlayerGroundState
extends PlayerState

@export var max_speed := 5.0
@export var acceleration := 20.0
@export var deceleration := 15.0
@export var jump_velocity := 4.5
@export var rotation_speed := 0.0


func process_physics(delta: float) -> void:
	# Check if the player has left the ground (e.g., walked off a ledge)
	if not player.is_on_floor():
		state.try_enter_air()
		return

	# TODO: Start here
	# if player.wants_to_climb_ladder_up() or player.wants_to_climb_ladder_down():
		# if state.try_enter_ladder():
			# return

	# Check if the player wants to jump
	if player.wants_to_jump():
		# Try to climb up
		if state.try_enter_climb_up():
			return

		# Jump if climbing up is not possible
		player.velocity.y = jump_velocity

		state.try_enter_air()
		return

	# Handle player movement
	var input_direction := get_input_direction()
	_apply_velocity(input_direction, delta)
	_rotate_towards_movement(input_direction, delta)


func after_process_physics(_delta: float) -> void:
	player.move_and_slide()


func _apply_velocity(input_direction: Vector3, delta: float) -> void:
	if input_direction:
		player.velocity.x = move_toward(
			player.velocity.x,
			input_direction.x * max_speed,
			acceleration * delta,
		)

		player.velocity.z = move_toward(
			player.velocity.z,
			input_direction.z * max_speed,
			acceleration * delta,
		)
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, deceleration * delta)
		player.velocity.z = move_toward(player.velocity.z, 0, deceleration * delta)


func _rotate_towards_movement(input_direction: Vector3, delta: float) -> void:
	if not input_direction:
		return

	var target_rotation := atan2(input_direction.x, input_direction.z) - PI / 2

	if rotation_speed > 0:
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
	else:
		player.rotation.y = target_rotation
