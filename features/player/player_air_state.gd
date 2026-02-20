class_name PlayerAirState
extends PlayerState

@export var max_air_speed := 5.0
@export var air_acceleration := 10.0
@export var air_deceleration := 5.0

var _jump_direction := Vector3.ZERO
var _jump_start_position := Vector3.ZERO


func on_enter(_previous_state: PlayerState) -> void:
	_jump_direction = Vector3(player.velocity.x, 0, player.velocity.z).normalized()
	_jump_start_position = player.transform.origin


func on_exit(_next_state: PlayerState) -> void:
	_jump_direction = Vector3.ZERO
	_jump_start_position = Vector3.ZERO


func process_physics(delta: float) -> void:
	# Check if the player has landed
	if player.is_on_floor():
		player.move_and_slide()
		state.to_ground()
		return

	# Apply gravity
	player.velocity += player.get_gravity() * delta

	# Handle air control
	var input_direction := get_input_direction()
	_apply_air_control(input_direction, delta)

	# Apply movement
	player.move_and_slide()

	print("Distance %s" % get_jump_distance())

	# Check if can enter climbing state
	state.to_climb_up()


func get_jump_distance() -> float:
	var displacement := player.transform.origin - _jump_start_position
	displacement.y = 0

	return displacement.length()


func _apply_air_control(input_direction: Vector3, delta: float) -> void:
	var decelerate_x := false
	var decelerate_z := false

	if input_direction:
		player.velocity.x = move_toward(
			player.velocity.x,
			input_direction.x * max_air_speed,
			air_acceleration * delta,
		)

		player.velocity.z = move_toward(
			player.velocity.z,
			input_direction.z * max_air_speed,
			air_acceleration * delta,
		)

		# Slow down the player if they are trying to change direction in the air against their initial jump direction
		if _jump_direction != Vector3.ZERO:
			if sign(player.velocity.x) != sign(_jump_direction.x):
				decelerate_x = true

			if sign(player.velocity.z) != sign(_jump_direction.z):
				decelerate_z = true

		# Fully prevent reversing direction in the air
		# if _jump_direction != Vector3.ZERO:
		# 	var horizontal_vel := Vector3(player.velocity.x, 0, player.velocity.z)
		# 	if horizontal_vel.dot(_jump_direction) < 0.0:
		# 		# Remove the component that reversed past the jump direction
		# 		var reversed_amount := horizontal_vel.dot(_jump_direction)
		# 		player.velocity.x -= _jump_direction.x * reversed_amount
		# 		player.velocity.z -= _jump_direction.z * reversed_amount
	else:
		decelerate_x = true
		decelerate_z = true

	if decelerate_x:
		player.velocity.x = move_toward(player.velocity.x, 0, air_deceleration * delta)

	if decelerate_z:
		player.velocity.z = move_toward(player.velocity.z, 0, air_deceleration * delta)
