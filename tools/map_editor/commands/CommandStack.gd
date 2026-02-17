class_name CommandStack

extends RefCounted

## Manages undo/redo command history

signal history_changed

var _undo_stack: Array[EditorCommand] = []
var _redo_stack: Array[EditorCommand] = []
var _max_history: int = 100


func push_command(command: EditorCommand):
	"""Execute a command and add it to the undo stack"""
	command.execute()
	_undo_stack.append(command)
	_redo_stack.clear()  # Clear redo stack when new command is executed

	# Limit history size
	if _undo_stack.size() > _max_history:
		_undo_stack.pop_front()

	history_changed.emit()


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func undo():
	"""Undo the last command"""
	if not can_undo():
		return

	var command = _undo_stack.pop_back()
	command.undo()
	_redo_stack.append(command)
	history_changed.emit()


func redo():
	"""Redo the last undone command"""
	if not can_redo():
		return

	var command = _redo_stack.pop_back()
	command.execute()
	_undo_stack.append(command)
	history_changed.emit()


func clear():
	"""Clear all history"""
	_undo_stack.clear()
	_redo_stack.clear()
	history_changed.emit()


func get_undo_description() -> String:
	if can_undo():
		return _undo_stack.back().get_description()
	return ""


func get_redo_description() -> String:
	if can_redo():
		return _redo_stack.back().get_description()
	return ""
