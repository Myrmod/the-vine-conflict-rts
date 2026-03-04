extends PanelContainer

var player = null

@onready var _resource_label = find_child("ResourceLabel")
@onready var _resource_color_rect = find_child("ResourceColorRect")


func _ready():
	_resource_color_rect.color = Color.AQUAMARINE


func setup(a_player):
	assert(player == null, "player cannot be null")
	player = a_player
	_on_player_resource_changed()
	player.changed.connect(_on_player_resource_changed)


func _on_player_resource_changed():
	_resource_label.text = str(player.resource)
