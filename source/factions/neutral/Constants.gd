class_name NeutralConstants

const SOUND_ROCKET_START = preload("res://assets/sound_effects/rocket1_start.mp3")
const SOUND_ROCKET_END = preload("res://assets/sound_effects/rocket1_end.mp3")

const STRUCTURES = {
	# Vines (resource nodes)
	# Naming: Vine_COLLISION_VARIATION — COLLISION = tile count
	"res://source/factions/neutral/structures/ResourceNode/ForestVine_2_1.tscn":
	{
		"unit_name": "Forest Vine",
		"description": "Dense overgrowth. Slows movement and reduces vision. Vehicles cannot pass.",
		"tile_count": 2,
		"resources_per_tile": 500,
		"restock_rate": 1,
		"restock_interval": 10,
		"footprint": Vector2i(2, 1),
		"hp": 10,
		"hp_max": 10,
		"armor":
		{
			Enums.DamageTypes.CANNON: 0.0,
			Enums.DamageTypes.CORROSIVE: 0.0,
			Enums.DamageTypes.CRUSH: 0.0,
			Enums.DamageTypes.EXPLOSIVE: 0.0,
			Enums.DamageTypes.FIRE: 0.0,
			Enums.DamageTypes.LASER: 0.0,
			Enums.DamageTypes.MELEE: 0.0,
			Enums.DamageTypes.PLASMA: 0.0,
			Enums.DamageTypes.PRISM: 0.0,
			Enums.DamageTypes.RIFLE: 0.0,
			Enums.DamageTypes.ROCKET: 0.0,
			Enums.DamageTypes.TESLA: 0.0,
		},
	},
}

const DEFENCES = {}

const INFANTRY = {}

const VEHICLES = {}

const AIR = {}

const NAVY = {}
