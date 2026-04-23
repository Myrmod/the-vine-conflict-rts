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

The Radix harvest energy through **stationary buildings** placed on the Vine network.

- The **Heart** produces **Seedlings**.
- Seedlings are used to spread creep and to construct Radix structures.
- A Seedling is consumed only when the assigned action completes successfully.
- If the controlling player interrupts the action before completion, the Seedling survives.
- Radix Tier 1 production structures are placed as ghosts and begin building only after a Seedling reaches them and merges into the site.
- Detailed behavior spec: [Radix Seedling Workflow](../../Economy/Radix_Seedling_Workflow.md).
- Build **Vine Spreaders** to expand territory
- Build **Root Conduits** near Vine fields for passive income

| Stat | Value |
|---|---|
| Harvest model | Passive generation |
| Depletion | Non-depleting |
| Scaling | Income scales with nearby ResourceTile count |
| Delivery loop | None required |

---

## Tech Tree — Tier 1 Build Order

```
HQ
└── Vine Spreader  (no power required)
    ├── Brood Nest  →  Thorn Forge  →  Sky Bloom
    │                           →  Naval Yard
    │                           →  T2 tech structure / upgrade building
    └── Root Conduit
```

> Note: all production buildings must be built on Vine-covered ground.

---

## Buildings

| Building | Cost | Build time | Notes |
|---|---|---|---|
| HQ | — | — | Starting structure |
| Heart | — | — | Main structure; produces Seedlings used for creep spread and construction |
| Vine Spreader | 500 | 5 s | Spreads Vines 5 tiles; required for all other buildings |
| Root Conduit | 1500 | 15 s | Passive income node; does not deplete ResourceVines; scales with nearby tile count |
| Brood Nest | 600 | 6 s | Tier 1 infantry structure; starts once a Seedling merges into the ghost |
| Thorn Forge | 2000 | 20 s | Tier 1 vehicle structure; starts once a Seedling merges into the ghost |
| Sky Bloom | 2000 | 20 s | Tier 1 air structure; starts once a Seedling merges into the ghost |
| Naval Yard | 1500 | 15 s | Produces ships |

---

## Units

### Infantry

#### Phase Seedling

| Stat | Value |
|---|---|
| HP | 50 |
| Movement speed | 2.0 |
| Cost | 100 |
| Armor vs Rifle | 0% |
| Armor vs Explosive | 0% |
| Armor vs Melee | 0% |

**Weapon — Melee**

| Stat | Value |
|---|---|
| Damage type | Melee |
| Damage | 10 |
| AoE | 0 |
| Range | 0 (melee) |
| Attack speed | 0.5 |

**Abilities**
- Can spread creep and construct structures.
- Consumed on successful completion of spread/construct action.
- Survives if the controlling player interrupts/cancels the action before completion.
