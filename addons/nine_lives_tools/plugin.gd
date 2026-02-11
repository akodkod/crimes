@tool
extends EditorPlugin

const GROUP_SHORTCUT := "nine_lives_tools/group_at_center"
const COMMAND_KEY := "nine_lives_tools/group_at_center"

var _group_menu: EditorContextMenuPlugin
var _create_at_cursor: RefCounted
var _snap_to_ground: RefCounted
var _shortcut_listener: Node


func _enter_tree() -> void:
	_group_menu = preload("group_at_center_menu.gd").new()
	_group_menu.undo_redo = get_undo_redo()

	add_context_menu_plugin(
		EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE,
		_group_menu,
	)

	_create_at_cursor = preload("create_at_cursor.gd").new()
	_create_at_cursor.undo_redo = get_undo_redo()

	_snap_to_ground = preload("snap_to_ground.gd").new()
	_snap_to_ground.undo_redo = get_undo_redo()

	# Receive _forward_3d_gui_input regardless of what is selected.
	set_input_event_forwarding_always_enabled()

	# --- Configurable shortcut (Editor Settings → Shortcuts) ---
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_shortcut(GROUP_SHORTCUT):
		settings.add_shortcut(GROUP_SHORTCUT, Shortcut.new()) # no default key

	# --- Command palette (Cmd/Ctrl+Shift+P) ---
	EditorInterface.get_command_palette().add_command(
		"Group at Center", COMMAND_KEY, _group_menu.group_selected_nodes,
	)

	# --- Global shortcut listener (works from Scene Tree & 3D viewport) ---
	_shortcut_listener = _ShortcutListener.new()
	_shortcut_listener.shortcut_path = GROUP_SHORTCUT
	_shortcut_listener.callback = _group_menu.group_selected_nodes
	EditorInterface.get_base_control().add_child(_shortcut_listener)


func _exit_tree() -> void:
	remove_context_menu_plugin(_group_menu)

	# Clean up shortcut listener.
	if is_instance_valid(_shortcut_listener):
		_shortcut_listener.queue_free()
	_shortcut_listener = null

	# Clean up command palette entry.
	EditorInterface.get_command_palette().remove_command(COMMAND_KEY)

	# Clean up editor shortcut.
	EditorInterface.get_editor_settings().remove_shortcut(GROUP_SHORTCUT)

	_group_menu = null
	_create_at_cursor = null
	_snap_to_ground = null


# Only handle Node3D so we don't interfere with resource inspectors (Sky, etc.).
func _handles(object: Object) -> bool:
	return object is Node3D


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var result: int = _snap_to_ground.handle_3d_input(camera, event)
	if result == AFTER_GUI_INPUT_STOP:
		return result
	return _create_at_cursor.handle_3d_input(camera, event)


# ---------------------------------------------------------------------------
# Inner class: lightweight Node that listens for a configurable editor shortcut
# via _shortcut_input, which fires regardless of which dock has focus.
# ---------------------------------------------------------------------------
class _ShortcutListener extends Node:
	var shortcut_path: String
	var callback: Callable

	func _shortcut_input(event: InputEvent) -> void:
		if not event.is_pressed() or event.is_echo():
			return

		# Don't steal keys while the user is typing in a text field.
		var focused := get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return

		if EditorInterface.get_editor_settings().is_shortcut(shortcut_path, event):
			get_viewport().set_input_as_handled()
			callback.call()
