class_name Player
extends Character

@export var camera: Camera3D

@export var max_speed: float = 5.0
@export var acceleration: float = 20.0
@export var deceleration: float = 15.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 10.0


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
	# Add the gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if _should_climb():
			_climb()
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
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

	DebugDraw3D.draw_arrow(
		transform.origin + Vector3(0, 0.75, 0),
		transform.origin + velocity / 2.0 + Vector3(0, 0.75, 0),
		Color.BLUE_VIOLET,
		0.1,
	)

	move_and_slide()


func _jump() -> void:
	pass


func _should_climb() -> bool:
	return false


func _climb() -> void:
	pass
