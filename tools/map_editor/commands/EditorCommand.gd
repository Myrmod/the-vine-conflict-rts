class_name EditorCommand

extends RefCounted

## Base class for undoable editor commands

var description: String = "Command"


func execute():
	"""Execute the command. Override in subclasses."""
	push_error("EditorCommand.execute() must be overridden")


func undo():
	"""Undo the command. Override in subclasses."""
	push_error("EditorCommand.undo() must be overridden")


func get_description() -> String:
	return description
