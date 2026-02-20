class_name PlayerStateMachine
extends Node

@export var initial_state: PlayerState
var current_state: PlayerState

var ground: PlayerGroundState
var air: PlayerAirState
var climb_up: PlayerClimbUpState


func _ready() -> void:
	if owner is not Player:
		push_error("PlayerStateMachine must be owned by a Player")
		return

	# Find child states
	var children := get_children()
	for child in children:
		if child is PlayerGroundState:
			ground = child
		elif child is PlayerAirState:
			air = child
		elif child is PlayerClimbUpState:
			climb_up = child

	# Set the initial state
	if initial_state:
		current_state = initial_state
		current_state.on_enter(null)


func _process(delta: float) -> void:
	var state := current_state

	if not state:
		return

	state.process_frame(delta)


func _physics_process(delta: float) -> void:
	var state := current_state

	if not state:
		print("No current state in PlayerStateMachine")
		return

	state.process_physics(delta)
	state.after_process_physics(delta)


func transition_to(new_state: PlayerState) -> bool:
	if new_state == current_state:
		return false

	if not new_state.can_enter():
		return false

	print("[Player] %s" % [new_state.name])

	# Exit the current state
	var previous_state := current_state
	current_state.on_exit(new_state)

	# Enter the new state
	current_state = new_state
	current_state.on_enter(previous_state)

	return true


func to_air() -> bool:
	return transition_to(air)


func to_ground() -> bool:
	return transition_to(ground)


func to_climb_up() -> bool:
	return transition_to(climb_up)


var player: Player:
	get:
		return owner
	set(value):
		push_error("PlayerStateMachine's player property is read-only")
