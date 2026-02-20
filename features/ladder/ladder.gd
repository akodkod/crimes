class_name Ladder
extends Node3D

func can_mount_from_top(world_position: Vector3) -> bool:
	return true


func can_mount_from_bottom(world_position: Vector3) -> bool:
	return true


func can_mount_in_middle(world_position: Vector3) -> bool:
	return true
