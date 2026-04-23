# The Legion

> *"This is not salvation. This is an invasion."*

The organized military faction of humanity. Power-hungry in the literal sense — they run on an established power grid and represent the remnant state apparatus that still believes humanity can fight back and reclaim the planet.

---

## Lore / Origins — The Human Conflict

*Full shared backstory: [Human_conflict/Origins.md](../Human_conflict/Origins.md)*

### The Ash War (2030)

By the late 2020s the world was mid-transition to renewable energy. Fossil fuel investment had been slashed but green infrastructure was not scaled quickly enough. In 2029, a naval confrontation in the South China Sea destroyed a major tanker, triggering panic across global markets. Energy prices surged, blackouts spread, supply chains failed.

A missile strike near an early-warning radar was misinterpreted as a nuclear decapitation strike. A "limited de-escalatory response" was launched. Retaliatory launches followed within minutes. By 2030 the interconnected global grid was shattered — not erased, but dismantled, leaving behind isolated power hubs, irradiated wastelands, and fractured nations built around whatever energy survived.

### The Vines Discovery (2069)

Approximately 40 years after the Ash War, scientists across the globe were hunting for a reliable energy source. Africa was less damaged, so solar farms rose in the Sahara. GPR technology discovered a dormant vine-like organism deep beneath an ancient Egyptian anchor site.

One scientist warned that the organism was living and should not be stimulated with artificial energy. He was shut down, locked up. Desperate governments overrode the warning and applied high energy to the dormant vines.

### The Awakening

Energy pulses spiked in Egypt. Within hours dormant spores activated regionally. Within weeks, continental eruptions. Within a month, global overgrowth. Infrastructure was swallowed, farms demolished, millions dead or mutated.

**Humanity divided:**

The **elites and governments** (proto-Legion) believed the vines were a miracle — clean energy, economic regrowth, cities revived. They suppressed early disaster reports; if the vines vanished, the planet goes dark again.

The **common people** saw the horrors: millions dead and mutated, governments suppressing truth, refugee camps forming, strange mutated forms attacking them. They sided with the locked-up scientist: *"This is not salvation. This is an invasion."*

The Legion represents the organized, power-centric military that emerged from what remained of state authority — fighting to control both humanity and the Vine network.

---

## Strengths & Identity

- **Conventional military** — standard RTS power-plant economy
- Strong air capability once airfield is established
- Power grid creates upgrade and buff potential
- Higher building costs than Remnants — more capable but more fragile early on

---

## Economy

The Legion uses **conventional refineries** with harvesters that cut Vines.

- Harvester gathers, carries, and returns resources to the Refinery.
- Legion harvesting depletes and destroys ResourceVines.
- If a Harvester is destroyed while carrying resources, the carried load is lost.

| Stat | Value |
|---|---|
| Capacity | 250 |
| Harvester speed | 2.0 |
| Harvest rate | 100 res/s |
| Delivery rate | 100 res/s |

---

## Tech Tree — Tier 1 Build Order

```
HQ
└── Power Plant
    ├── Barracks   →  Factory  →  T2 structure
    └── Refinery   →  Factory  →  Airfield
                              →  Naval Yard
```

> Airfield requires Factory; Factory requires either Barracks or Refinery.

---

## Buildings

| Building | Cost | Build time | Power | Notes |
|---|---|---|---|---|
| HQ | — | — | — | Starting structure |
| Power Plant | 800 | 8 s | — | Provides 200 power |
| Refinery | 2000 | 20 s | 50 | Provides a Harvester that must return cargo to deliver |
| Barracks | 600 | 6 s | 25 | Produces infantry |
| Airfield | 2000 | 20 s | 50 | Produces air units |
| Factory | 2000 | 20 s | 50 | Produces tanks |
| Naval Yard | 1500 | 15 s | 50 | Produces ships |

---

## Units

### Infantry

#### Basic Infantry

| Stat | Value |
|---|---|
| HP | 100 |
| Movement speed | 1.0 |
| Cost | 200 |
| Armor vs Rifle | 0% |
| Armor vs Explosive | 0% |
| Armor vs Melee | 0% |

**Weapon — Rifle**

| Stat | Value |
|---|---|
| Damage type | Rifle |
| Damage | 10 |
| AoE | 0 |
| Range | 3.0 |
| Attack speed | 1.0 |

**Abilities**
- Can deploy (prevents crushing by vehicles)
