# UnitCommandQueue: Per-unit order queue for shift-queued commands.
# Added as a child node to units that support queuing.
# Stores simplified command dicts: { "type": CommandType, "data": { ... } }
extends Node

signal queue_changed

var _queue: Array[Dictionary] = []


func enqueue(command_data: Dictionary) -> void:
	_queue.append(command_data)
	queue_changed.emit()


func dequeue() -> Dictionary:
	if _queue.is_empty():
		return {}
	var cmd = _queue.pop_front()
	queue_changed.emit()
	return cmd


func peek() -> Dictionary:
	if _queue.is_empty():
		return {}
	return _queue[0]


func clear() -> void:
	if not _queue.is_empty():
		_queue.clear()
		queue_changed.emit()


func size() -> int:
	return _queue.size()


func get_all() -> Array[Dictionary]:
	return _queue
