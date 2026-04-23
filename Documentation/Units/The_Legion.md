# The Legion Units

## Infantry

### Soldier

#### General
- role: light line infantry
- hp: 5
- max_hp: 5
- sight_range: 8.0
- cost: 2 credits
- build_time: 3.0 s

#### Weapon
- type: laser rifle
- damage: 1
- interval: 0.55 s
- range: 4.0

## Vehicles

### Harvester

#### General
- role: unarmed resource gatherer
- hp: 600
- max_hp: 600
- capacity: 500
- gather_rate: 250
- cost: 2 credits
- build_time: 3.0 s

#### Behavior
- deployed by the Refinery economy line
- gathers from the nearest resource field
- returns cargo to the nearest valid drop-off structure
- Legion command centers are not drop-off structures
