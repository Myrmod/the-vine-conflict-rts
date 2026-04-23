# Radix Seedling Workflow (Design Spec Draft)

## Purpose
Define a single source of truth for how Radix Seedlings are produced, used, consumed, and preserved when actions are canceled.

## Core Roles
- Heart:
  - Main Radix structure.
  - Produces Seedlings.
- Seedling:
  - Builder/spreader unit.
  - Executes creep spread actions.
  - Executes structure construction actions.

## Lifecycle Rules
- A Seedling starts alive after being produced by Heart.
- A Seedling can be assigned to either:
  - Creep spread action.
  - Structure construction action.
- A Seedling is consumed and destroyed only when the assigned action successfully completes.
- If the controlling player interrupts or cancels the action before completion, the Seedling is not consumed and remains alive.

## Success and Cancel Outcomes
- Success outcome:
  - Action result is applied (creep spread completed or structure completed).
  - Seedling is destroyed.
- Player-interrupt/cancel outcome:
  - Partial progress handling follows system-specific rules.
  - Seedling survives and can receive new orders.

## Ownership and Control
- Seedlings follow owner-issued commands only.
- Consumption check is tied to the completion event of the owned action.

## Design Notes
- This behavior is intentional faction identity for Radix and should not be mirrored to other factions by default.
- If future balancing requires exceptions (for example partial-cost penalties), add those as explicit extensions to this spec rather than changing the core consumption rule.
