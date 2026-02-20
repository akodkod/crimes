class_name PlayerLadderState
extends PlayerState

var _ladder: Ladder = null


func can_enter() -> bool:
	_ladder = player.get_ladder_candidate()

	if not _ladder:
		return false

	var player_position := player.global_transform.origin

	if state.is_air():
		return _ladder.can_mount_in_middle(player_position)

	if player.wants_to_climb_ladder_up():
		return _ladder.can_mount_from_bottom(player_position)

	if player.wants_to_climb_ladder_down():
		return _ladder.can_mount_from_top(player_position)

	return false
