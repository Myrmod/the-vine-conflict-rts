# The Remnants

> *"They clearly see that they never mattered."*

The Remnants are the survivors and outcasts of the Ash War and the Awakening — the common people who were never consulted, never protected, and never believed. They fight with cheaper technology, faster infantry, and a pragmatic will to survive.

---

## Lore / Origins

*Full shared human backstory: [Human_conflict/Origins.md](../Human_conflict/Origins.md)*

The Remnants emerged from the **common people** who witnessed the horrors of the Vine awakening first-hand — millions dead, cities swallowed, governments suppressing the truth to protect their energy supply. They sided with the scientist who was imprisoned for warning against activating the Vines, because they were never consulted and they clearly saw that they never mattered to those in power.

Where the Legion represents organized state power, the Remnants represent those who survived outside it: refugees, militia, former soldiers who deserted, and communities that built their own tech from whatever remained.

*(Further faction-specific lore to be filled in)*

---

## Strengths & Identity

- **Cheaper and faster** than the Legion — lower build costs and faster infantry
- Destructive harvest doctrine — converts resources by burning ResourceVines
- Factory-forward tech tree — production unlocks early
- Less raw power: lower HP infantry, smaller power plant output

---

## Economy

The Remnants do not use a refinery return loop. They harvest by **burning** resources in place.

- Gather units are the **Incinerator** (infantry) and **Flame Tank** (vehicle).
- Burn animation is the harvest action.
- Gather rate is measured by destroyed resources per tick.
- Units do not carry cargo and do not return to a refinery.
- Remnants harvesting depletes and destroys ResourceVines.

| Stat | Value |
|---|---|
| Harvest model | Burn in place |
| Carry capacity | None |
| Delivery loop | None |
| Depletion | Depletes and destroys ResourceVines |

---

## Tech Tree — Tier 1 Build Order

```
HQ
└── Power Plant
    ├── Barracks   ─┐
    └── Factory  ──┘           →  T2 structure
                               →  Naval Yard
                               →  Airfield
```

> Factory is accessible earlier than in other factions — unlocked directly from Power Plant.

---

## Buildings

| Building | Cost | Build time | Power | Notes |
|---|---|---|---|---|
| HQ | — | — | — | Starting structure |
| Power Plant | 600 | 6 s | — | Provides 150 power |
| Barracks | 600 | 6 s | 25 | Produces infantry |
| Airfield | 2000 | 20 s | 50 | Produces air units |
| Factory | 2000 | 20 s | 50 | Produces tanks |
| Naval Yard | 1500 | 15 s | 50 | Produces ships |

> Economy unit production: Barracks produces Incinerator squads, Factory produces Flame Tanks.

---

## Units

### Infantry

#### Basic Infantry

| Stat | Value |
|---|---|
| HP | 80 |
| Movement speed | 1.25 |
| Cost | 150 |
| Armor vs Rifle | 0% |
| Armor vs Explosive | 0% |
| Armor vs Melee | 0% |

**Weapon — Rifle**

| Stat | Value |
|---|---|
| Damage type | Rifle |
| Damage | 6×5 (burst) |
| AoE | 0 |
| Range | 2.5 |
| Attack speed | 2.0 |

**Abilities**
- **Sprint** — gain +0.25 m/s for 10 seconds
