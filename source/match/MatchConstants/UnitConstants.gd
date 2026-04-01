extends Node

const SOUND_ROCKET_START = preload("res://assets/sound_effects/rocket1_start.mp3")
const SOUND_ROCKET_END = preload("res://assets/sound_effects/rocket1_end.mp3")

const PRODUCTION_QUEUE_LIMIT = 5

const ADHERENCE_MARGIN_M = 0.3  # TODO: try lowering while fixing a 'push' problem
const NEW_RESOURCE_SEARCH_RADIUS_M = 30
const MOVING_UNIT_RADIUS_MAX_M = 1.0
const EMPTY_SPACE_RADIUS_SURROUNDING_STRUCTURE_M = MOVING_UNIT_RADIUS_MAX_M * 2.5
const STRUCTURE_CONSTRUCTING_SPEED = 0.3  # progress [0.0..1.0] per second

var DEFAULT_PROPERTIES := {}


func _ready() -> void:
	_fill_default_properties()


## Called by any code that needs DEFAULT_PROPERTIES before _ready() fires
## (e.g. static helpers, early autoload calls). Safe to call multiple times.
func ensure_ready() -> void:
	if not DEFAULT_PROPERTIES.is_empty():
		return
	_fill_default_properties()


func _fill_default_properties() -> void:
	for src: Dictionary in [
		AmunsConstants.STRUCTURES,
		AmunsConstants.DEFENCES,
		AmunsConstants.INFANTRY,
		AmunsConstants.VEHICLES,
		AmunsConstants.AIR,
		AmunsConstants.NAVY,
		LegionConstants.STRUCTURES,
		LegionConstants.DEFENCES,
		LegionConstants.INFANTRY,
		LegionConstants.VEHICLES,
		LegionConstants.AIR,
		LegionConstants.NAVY,
		RadixConstants.STRUCTURES,
		RadixConstants.DEFENCES,
		RadixConstants.INFANTRY,
		RadixConstants.VEHICLES,
		RadixConstants.AIR,
		RadixConstants.NAVY,
		RemnantConstants.STRUCTURES,
		RemnantConstants.DEFENCES,
		RemnantConstants.INFANTRY,
		RemnantConstants.VEHICLES,
		RemnantConstants.AIR,
		RemnantConstants.NAVY,
		NeutralConstants.STRUCTURES,
		NeutralConstants.DEFENCES,
		NeutralConstants.INFANTRY,
		NeutralConstants.VEHICLES,
		NeutralConstants.AIR,
		NeutralConstants.NAVY,
	]:
		DEFAULT_PROPERTIES.merge(src)
