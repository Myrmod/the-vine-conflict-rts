# Harvesting Mechanics

## Shared Rules
- base resource per vine tile starts at 500
- Amuns and Legion use gather, carry, and return loops
- Radix Seedlings are part of the construction economy, not a direct harvester unit
- if a cargo-based gatherer dies while carrying resources, the carried load is lost

## Amuns
- economy identity: flying gather logistics plus spawner-linked field enhancement
- Syphon:
  - acts as the Amuns resource drop-off structure
  - auto-spawns a Syphon Drone on completion
  - drone gathers resources and returns to the Syphon
- Purifier:
  - can only be placed above a ResourceSpawner
  - links to that spawner and increases capacity for vines associated with it
  - newly spawned vines from the linked spawner inherit the added capacity bonus

## Legion
- economy identity: classic refinery loop
- Refinery:
  - deploys a Harvester vehicle
  - serves as a valid drop-off structure
- Harvester:
  - gathers from the nearest field
  - delivers to the nearest valid drop-off structure
  - Legion command centers are not drop-off structures

## Remnants
- economy identity: destructive front-line conversion
- gather units:
  - infantry: Incinerator
  - vehicle: Flame Tank
- mechanic:
  - units destroy vines as part of gathering
  - no refinery return loop
  - when a vine is depleted, gatherers continue to the next available resource tile automatically
  - retargeting is issued through the deterministic command path (CommandBus -> Match command execution)
  - if a target vine is removed before execution, command execution selects the next valid resource target

## Radix
- economy identity: Seedling-driven territorial growth and construction
- Heart produces Seedlings
- Seedlings are consumed only when creep spread or Seedling-started construction completes successfully
- canceling before completion preserves the Seedling, and canceling an already started Seedling-built structure restores one
- detailed behavior spec: [Radix Seedling Workflow](Radix_Seedling_Workflow.md)



