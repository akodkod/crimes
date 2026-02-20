class_name PlayerStateMachine
extends Node

@export var initial_state: PlayerState
var current_state: PlayerState

var ground: PlayerGroundState
var air: PlayerAirState
var climb_up: PlayerClimbUpState
var ladder: PlayerLadderState


func _ready() -> void:
	if owner is not Player:
		push_error("PlayerStateMachine must be owned by a Player")
		return

	if not initial_state:
		push_error("PlayerStateMachine must have an initial state")
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
		elif child is PlayerLadderState:
			ladder = child

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
		return

	state.process_physics(delta)
	state.after_process_physics(delta)


func _try_enter(new_state: PlayerState) -> bool:
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


func try_enter_air() -> bool:
	return _try_enter(air)


func try_enter_ground() -> bool:
	return _try_enter(ground)


func try_enter_climb_up() -> bool:
	return _try_enter(climb_up)


func try_enter_ladder() -> bool:
	return _try_enter(ladder)


func is_air() -> bool:
	return current_state == air


func is_ground() -> bool:
	return current_state == ground


func is_climb_up() -> bool:
	return current_state == climb_up


func is_ladder() -> bool:
	return current_state == ladder


var player: Player:
	get:
		return owner
	set(value):
		push_error("PlayerStateMachine's player property is read-only")
