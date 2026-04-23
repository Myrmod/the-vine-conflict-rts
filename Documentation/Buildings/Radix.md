# Radix Buildings

## Heart
- main Radix structure
- produces Seedlings
- produces structures and defences from the structure tab
- uses the shared global ProductionQueue HUD feature (available to all factions)
- current implemented stats: 8 credits, 10 s build time

## Brood Nest
- Tier 1 infantry structure
- cost: 600 credits
- build_time: 6 s
- placed as a ghost first
- construction begins only after a Seedling reaches the site and is consumed

## Thorn Forge
- Tier 1 vehicle structure
- cost: 2000 credits
- build_time: 20 s
- uses the same Seedling-started construction flow as other Radix Tier 1 structures

## Sky Bloom
- Tier 1 air structure
- cost: 2000 credits
- build_time: 20 s
- uses the same Seedling-started construction flow as other Radix Tier 1 structures

## Construction rules
- current implemented Radix production buildings require a Seedling to start
- placement creates the site first, then a Seedling finishes the start action
- canceling before completion preserves or restores the Seedling instead of deleting it permanently