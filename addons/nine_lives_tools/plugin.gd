@tool
extends EditorPlugin

var _group_menu: EditorContextMenuPlugin
var _create_at_cursor: RefCounted


func _enter_tree() -> void:
	_group_menu = preload("group_at_center_menu.gd").new()
	_group_menu.undo_redo = get_undo_redo()

	add_context_menu_plugin(
		EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE,
		_group_menu,
	)

	_create_at_cursor = preload("create_at_cursor.gd").new()
	_create_at_cursor.undo_redo = get_undo_redo()

	# Receive _forward_3d_gui_input regardless of what is selected.
	set_input_event_forwarding_always_enabled()


func _exit_tree() -> void:
	remove_context_menu_plugin(_group_menu)
	_group_menu = null
	_create_at_cursor = null


# Only handle Node3D so we don't interfere with resource inspectors (Sky, etc.).
func _handles(object: Object) -> bool:
	return object is Node3D


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	return _create_at_cursor.handle_3d_input(camera, event)
