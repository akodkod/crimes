class_name Player
extends Character

@export var camera: Camera3D

@onready var state: PlayerStateMachine = $PlayerStateMachine


func _get_validation_conditions() -> Array[ValidationCondition]:
	return [
		ValidationCondition.simple(
			camera != null,
			"Camera node must be assigned",
		),
	]


func wants_to_jump() -> bool:
	return Input.is_action_just_pressed(Data.INPUT_JUMP)
