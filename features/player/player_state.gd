@abstract
class_name PlayerState
extends Node

func _ready() -> void:
	if owner is not Player:
		push_error("PlayerState must be owned by a Player")
		return

	set_process(false)
	set_physics_process(false)


func can_enter() -> bool:
	return true


func on_enter(_previous_state: PlayerState) -> void:
	pass


func on_exit(_next_state: PlayerState) -> void:
	pass


func process_frame(_delta: float) -> void:
	pass


func process_physics(_delta: float) -> void:
	pass


func after_process_physics(_delta: float) -> void:
	pass


func get_input_direction() -> Vector3:
	# Get the input direction
	var input_direction := Input.get_vector(
		Data.INPUT_MOVE_LEFT,
		Data.INPUT_MOVE_RIGHT,
		Data.INPUT_MOVE_FORWARD,
		Data.INPUT_MOVE_BACKWARD,
	)

	# Calculate direction based on camera orientation
	var camera := player.camera
	var camera_forward := camera.transform.basis.z
	var camera_right := camera.transform.basis.x
	var direction := (camera_forward * input_direction.y + camera_right * input_direction.x).normalized()

	return direction


var player: Player:
	get:
		return owner
	set(value):
		push_error("PlayerState.player property is read-only")

var state: PlayerStateMachine:
	get:
		return player.state
	set(value):
		push_error("PlayerState.state property is read-only")

var transform: Transform3D:
	get:
		return player.transform
	set(value):
		push_error("PlayerState.transform property is read-only")
