extends Resource

class_name PlayerSettings

@export var color = Color.BLUE
@export var team = 0
@export var controller = Constants.PlayerType.SIMPLE_CLAIRVOYANT_AI
## -1 means random (assigned deterministically at match start), 0+ means a specific spawn point.
@export var spawn_index = -1
