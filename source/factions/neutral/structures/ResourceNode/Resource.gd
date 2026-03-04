extends ResourceUnit

@export var resource = 500:
	set(value):
		resource = max(0, value)
		if resource == 0:
			# Unregister from EntityRegistry before freeing depleted resource
			EntityRegistry.unregister(self)
			queue_free()

var color: Color = Color.GREEN


func _ready():
	_type = Enums.OccupationType.RESOURCE
	super._ready()
