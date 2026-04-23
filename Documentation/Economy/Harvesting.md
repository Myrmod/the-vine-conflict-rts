# Harvesting Mechanics (Resource Rework Draft)

## Shared Rules
- Base max resource per tile: 500.
- Amuns Prism modifier: tile max becomes 750 while Prism effect is active.
- Only Radix is non-depleting.
- Amuns, Legion, and Remnants destroy ResourceVines as resources are gathered.
- If a harvester dies while carrying resources, carried resources are lost.
- One tile can be affected by one unit at a time.

## Amuns
- Economy identity: field enhancement plus flying gather logistics.
- Prism:
  - Can only be built directly on top of a ResourceSpawner.
  - Only one Prism can exist per ResourceSpawner.
  - Increases resource amount (500 to 750 per tile) and ResourceTile growth speed.
  - Visual intent: field becomes more golden.
- Siphon:
  - Built next to the resource field.
  - Sends out flying, destructible Harvester Drones.
  - Drones return to the Siphon to deliver gathered resources.

## Legion
- Economy identity: classic refinery loop.
- Refinery provides a Harvester vehicle.
- Harvester gathers resources, then returns to the Refinery to deliver.

## Remnants
- Economy identity: destructive front-line conversion.
- Gather units:
  - Infantry: Incinerator.
  - Vehicle: Flame Tank.
- Production:
  - Incinerator is produced in the Barracks.
  - Flame Tank is produced in the Vehicle Bay.
- Mechanic:
  - Units burn spawned resources and gain value while destroying them.
  - Gather rate is destroyed resources per tick.
  - They do not return to a refinery and do not carry cargo.
  - Burn animation is the harvest action.

## Radix
- Economy identity: passive territorial scaling.
- Heart:
  - Produces Seedlings.
  - Seedlings are the required workforce for creep spread and structure construction.
- Seedling consumption rules:
  - A Seedling is consumed and destroyed when creep spread or structure construction successfully completes.
  - If the controlling player interrupts/cancels the action before completion, the Seedling is not destroyed.
- Detailed behavior spec: [Radix Seedling Workflow](Radix_Seedling_Workflow.md).
- Root Conduit:
  - Built next to a vine field.
  - Passively generates income without depleting resources.
  - Income scales with the number of ResourceTiles in radius.



