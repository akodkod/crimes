class_name Player
extends Character

@export var camera: Camera3D

@export var max_speed := 5.0
@export var acceleration := 20.0
@export var deceleration := 15.0
@export var jump_velocity := 4.5
@export var rotation_speed := 0.0

var climb_up_min_height := 0.3
var climb_up_max_height := 2.0
var climb_up_forward_ray_length := 0.7
var climb_up_step_forward_length := 0.25

var _climb_up_target_point := Vector3.ZERO


func _get_validation_conditions() -> Array[ValidationCondition]:
	return [
		ValidationCondition.simple(
			camera != null,
			"Camera node must be assigned",
		),
	]


func _process(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	if _is_climbing():
		return

	# Add the gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if _should_climb_up():
			_climb_up()
		else:
			_jump()

	# Get the input direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# Calculate direction based on camera orientation
	var camera_forward := camera.transform.basis.z
	var camera_right := camera.transform.basis.x
	var direction := (camera_forward * input_dir.y + camera_right * input_dir.x).normalized()

	if direction:
		velocity.x = move_toward(velocity.x, direction.x * max_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * max_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0, deceleration * delta)

	# Rotate the player to face the movement direction based on the camera orientation
	if direction:
		var target_rotation := atan2(direction.x, direction.z) - PI / 2

		if rotation_speed > 0:
			rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)
		else:
			rotation.y = target_rotation

	# DebugDraw3D.draw_arrow(
	# 	transform.origin + Vector3(0, 0.75, 0),
	# 	transform.origin + velocity / 2.0 + Vector3(0, 0.75, 0),
	# 	Color.BLUE_VIOLET,
	# 	0.1,
	# )

	move_and_slide()


func _is_climbing() -> bool:
	return _climb_up_target_point != Vector3.ZERO


func _jump() -> void:
	# velocity.y = jump_velocity
	pass


func _should_climb_up() -> bool:
	# If we already have a target point, we automatically climb up to it
	if _climb_up_target_point != Vector3.ZERO:
		return true

	var forward_ray_collision := _climb_up_cast_forward_ray()

	if not forward_ray_collision.has("position") or forward_ray_collision.position is not Vector3:
		return false

	var collision_point: Vector3 = forward_ray_collision.position
	_climb_up_target_point = _climb_up_find_target_point(collision_point)

	print("_should_climb_up: ", _climb_up_target_point)

	return _climb_up_target_point != Vector3.ZERO


func _climb_up_cast_forward_ray() -> Dictionary:
	var from := transform.origin + Vector3(0, climb_up_min_height - 0.001, 0)
	var to := from + (transform.basis.x * climb_up_forward_ray_length)

	var query := PhysicsRayQueryParameters3D.create(from, to, Data.CLIMBABLE_MASK)
	var collision := get_world_3d().direct_space_state.intersect_ray(query)

	Debugger.draw_ray_and_collision(query, collision, 3)

	return collision


func _climb_up_find_target_point(forward_ray_collision_point: Vector3) -> Vector3:
	var from := forward_ray_collision_point + Vector3(0, climb_up_max_height - climb_up_min_height + 0.2, 0)
	var to := forward_ray_collision_point

	var query := PhysicsRayQueryParameters3D.create(from, to, Data.CLIMBABLE_MASK)
	var collision := get_world_3d().direct_space_state.intersect_ray(query)

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


func _climb_up() -> void:
	var rise_tween := create_tween()
	rise_tween.tween_property(self, "transform:origin:y", _climb_up_target_point.y + 0.05, 0.3)
	rise_tween.set_ease(Tween.EASE_OUT)
	await rise_tween.finished

	# Set the target point slightly forward to ensure we end up on top of the obstacle, not just rising up in place
	var forward_offset := transform.basis.x * climb_up_step_forward_length
	var climb_up_target_point_with_offset := _climb_up_target_point + forward_offset

	var forward_tween := create_tween()
	forward_tween.tween_property(self, "transform:origin", climb_up_target_point_with_offset, 0.2)
	forward_tween.set_ease(Tween.EASE_IN)
	forward_tween.set_trans(Tween.TRANS_QUAD)
	await forward_tween.finished

	_climb_up_target_point = Vector3.ZERO


func _on_climb_up_finished() -> void:
	_climb_up_target_point = Vector3.ZERO
