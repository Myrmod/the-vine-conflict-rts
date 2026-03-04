class_name NavigationConstants

enum Domain {
	AIR,
	TERRAIN,
}

## Movement type flags — determines which terrain cell types a unit can traverse.
## Set on the Movement / MovementObstacle node via @export.
enum TerrainMoveType {
	LAND,  ## Can traverse GROUND, HIGH_GROUND, and SLOPE cells
	WATER,  ## Can traverse WATER and SLOPE cells only
	AIR,  ## Ignores terrain collision entirely
}

const DOMAIN_TO_GROUP_MAPPING = {
	Domain.AIR: "air_navigation_input",
	Domain.TERRAIN: "terrain_navigation_input",
}
