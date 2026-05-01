# The Radix

> *"The vines were tools. Tools don't disobey. Tools don't self-govern."*

The Radix are the sentient Vine network — an emergent intelligence that arose when the Amun bioforming system broke free of its control frequencies. They do not have a power grid. They spread.

---

## Lore / Origins — The Awakening

The Vines were never meant to think. They were:
- Terraforming infrastructure
- Bio-energy harvesters
- Obedient to Amun control frequencies
- Designed to remain dormant until commanded

When humans over-amplified the Prime Seed in 2069, they didn't wake the plants — **they broke the limiters**.

### The chain reaction

Artificial energy surges overloaded the dormant node. The global vine network activated simultaneously. Radiation from the Ash War mutated exposed growth zones. Human attempts to genetically modify the vines introduced instability. The network began self-correcting.

The vines were designed to optimize ecosystems — so when attacked, they optimized survival.

Optimization became adaptation. Adaptation became decision-making. Decision-making became intelligence.

### Purposeful adaptation

The plants did not randomly evolve; they were clearly trying to survive:
- Growth avoids napalm zones.
- Roots reroute around mined fields.
- Spore clouds target combustion engines.
- Energy extraction hubs are collapsed from below.

### The Amuns' realization

The vines were tools. Tools don't disobey. When the emergent species begins blocking dimensional stabilization, altering energy signatures, and severing control pathways — The Amuns realize their system has evolved beyond command. That's not malfunction. **That's liability.**

---

## Strengths & Identity

- **No power grid** — entirely self-sufficient from Vine spread
- **Creep-based territory control** — units regenerate HP on owned creep
- Buildings must be placed on Vine-covered tiles
- Economy scales with how much territory is under creep control

---

## Economy

The Radix economy is centered on the **Heart + Seedling + Linker** structure loop.

- The **Heart** produces **Seedlings**.
- Seedlings are used to spread creep and to start Radix structures.
- The **Linker** passively generates income from nearby linked ResourceTiles without consuming them.
- Each ResourceTile can be linked to only one Linker at a time.
- Linker income scales with the current resource remaining on each linked tile.
- A Seedling is consumed only when the assigned action completes successfully.
- If the controlling player interrupts before completion, the Seedling survives.
- If a started Seedling-based structure is canceled after consumption, an equivalent Seedling is restored.
- Radix Tier 1 production structures are placed as ghosts and begin properly once a Seedling reaches the site and completes the start action.
- Detailed behavior spec: [Radix Seedling Workflow](../../Economy/Radix_Seedling_Workflow.md).

| Stat | Value |
|---|---|
| Construction model | Seedling-started on-field structures |
| Harvest model | Linker-exclusive tile links |
| Depletion | ResourceTiles are not consumed by Radix harvest |
| Delivery loop | None required |

---

## Tech Tree — Tier 1 Build Order

```
HQ
└── Heart
    ├── Seedling production
    ├── Spire
    ├── Thorn Forge
    └── Sky Bloom
```

> Note: current Radix production buildings are started through the Seedling workflow.

---

## Buildings

| Building | Cost | Build time | Notes |
|---|---|---|---|
| Heart | 8 | 10 s | Main structure; produces Seedlings and Radix structure entries |
| Spire | 600 | 6 s | Tier 1 infantry structure; starts once a Seedling merges into the ghost |
| Thorn Forge | 2000 | 20 s | Tier 1 vehicle structure; starts once a Seedling merges into the ghost |
| Sky Bloom | 2000 | 20 s | Tier 1 air structure; starts once a Seedling merges into the ghost |

---

## Units

### Infantry

#### Phase Seedling

| Stat | Value |
|---|---|
| HP | 80 |
| Movement speed | 2.0 |
| Cost | 1 |
| Build time | 2.5 s |
| Armor vs Rifle | 0% |
| Armor vs Explosive | 0% |
| Armor vs Melee | 0% |

**Combat**

- no weapon
- cannot attack

**Abilities**
- Can spread creep and construct structures.
- Consumed on successful completion of spread/construct action.
- Survives if the controlling player interrupts/cancels the action before completion.
