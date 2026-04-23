# The Amuns

> *"The gods did not ascend. They concealed themselves."*

Elite alien architects who seeded Earth thousands of years ago and withdrew. They return now because humanity has corrupted their design.

---

## Lore / Origins

The Amuns were mistaken for gods by early humanity — in truth they were architects.

Long before recorded history they governed Earth in silence. When their work was complete they constructed pyramids and temples: not monuments, but **anchors** — structures that stabilized a hidden dimensional corridor and gateway network only The Amuns could access.

Finding no further value in a world of primitive humanity and untapped potential, they withdrew. But they did not abandon Earth. They exist in a **veil state**, a partial dimensional shift, always watching, waiting for the moment Earth would once again serve a purpose.

Few in number yet unmatched in advancement, The Amuns are an elite civilization of disciplined warriors and masterful technology. Their throneworld lies within Orion — a dominion once mythologized by ancient humans as the realm of the gods.

Among their commanders was **Ra**, a war-leader whose warship presence in the skies became legend — believed to be a god of the sun.

When humans prematurely activated the Vine network, they did not just wake the plants. They broke the Amun control frequencies. The Amuns return not out of conquest, but necessity:
- The terraform project is compromised.
- Earth is evolving outside intended parameters.
- Humanity tampered with sacred architecture.

Their options: reassert control, recalibrate the Vines, or purge the planet.

---

## Strengths & Identity

*(to be filled in)*

---

## Economy

The Amuns use a **spawner-linked enhancement plus flying gatherer** economy.

- Build a **Purifier** directly above a ResourceSpawner
- Purifier increases vine capacity for the linked spawner field
- Build a **Syphon** as the local resource drop-off
- Syphon auto-deploys a flying **Syphon Drone** to gather and return cargo

| Stat | Value |
|---|---|
| Harvest model | Drone gather + return |
| Field modifier | Purifier increases linked vine capacity |
| Depletion | Depletes and destroys ResourceVines |

---

## Tech Tree — Tier 1 Build Order

```
HQ
└── Syphon
    ├── Purifier + Syphon economy line
    ├── Barracks             →  Naucratis
    └── Nemet               →  Mni
```

---

## Buildings

| Building | Cost | Build time | Notes |
|---|---|---|---|
| HQ | — | — | Starting structure |
| Bekhenet | 2500 | 25 s | Starting structure; on-field trickle construction producer |
| Syphon | 1200 | 10 s | Resource drop-off that auto-spawns a Syphon Drone |
| Purifier | 1500 | 15 s | Must be placed above a ResourceSpawner; boosts linked vine capacity |
| Kislagh | 4 | 6 s | Produces infantry |
| Nemet | 2000 | 20 s | Produces air units |
| Naucratis | 2000 | 20 s | Produces vehicles |
| Mni | 1500 | 15 s | Produces ships |

---

## Units

### Infantry

#### Soldier

| Stat | Value |
|---|---|
| HP | 500 |
| Cost | 2 |
| Build time | 3 s |

**Weapon — Laser Rifle**

| Stat | Value |
|---|---|
| Damage type | Laser |
| Damage | 10 |
| Range | 4.0 |
| Attack speed | 0.55 |

### Support Units

#### Syphon Drone

- spawned automatically by Syphon
- gathers resources and returns them to the Syphon
- not a normal production-grid unit
