class_name Player
extends Character

@export var state: PlayerStateMachine
@export var camera: Camera3D
@export var ladder_detector: Area3D

var _ladder_candidate: Ladder = null


func _get_validation_conditions() -> Array[ValidationCondition]:
	return [
		ValidationCondition.simple(
			state != null,
			"State machine node must be assigned",
		),
		ValidationCondition.simple(
			camera != null,
			"Camera node must be assigned",
		),
		ValidationCondition.simple(
			ladder_detector != null,
			"Ladder detector node must be assigned",
		),
	]


func _ready() -> void:
	if ladder_detector:
		if not ladder_detector.area_entered.is_connected(_on_ladder_area_entered):
			ladder_detector.area_entered.connect(_on_ladder_area_entered)

		if not ladder_detector.area_exited.is_connected(_on_ladder_area_exited):
			ladder_detector.area_exited.connect(_on_ladder_area_exited)


func _on_ladder_area_entered(area: Area3D) -> void:
	if area.owner is not Ladder:
		push_error("Owner of ladder area is not a Ladder, but is a %s" % area.owner)
		return

	if _ladder_candidate:
		push_warning("Multiple ladder candidates detected. This may cause unexpected behavior.")
		return

	print("Ladder candidate entered: %s" % area.owner)
	_ladder_candidate = area.owner as Ladder


func _on_ladder_area_exited(area: Area3D) -> void:
	if area.owner is not Ladder:
		push_error("Owner of ladder area is not a Ladder, but is a %s" % area.owner)
		return

	print("Ladder candidate exited: %s" % area.owner)
	_ladder_candidate = null


func get_ladder_candidate() -> Ladder:
	return _ladder_candidate


func wants_to_jump() -> bool:
	return Input.is_action_just_pressed(Data.INPUT_JUMP)


func wants_to_climb_ladder_up() -> bool:
	return Input.is_action_pressed(Data.INPUT_MOVE_UP)


func wants_to_climb_ladder_down() -> bool:
	return Input.is_action_pressed(Data.INPUT_MOVE_DOWN)
