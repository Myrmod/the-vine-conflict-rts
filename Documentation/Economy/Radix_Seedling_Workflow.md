# Radix Seedling Workflow

## Purpose
Single source of truth for the implemented Radix Seedling construction and creep workflow.

## Core Roles
- Heart:
  - produces Seedlings
  - owns the relevant Radix production queue entries for Seedling-started structures
- Seedling:
  - unarmed builder and spreader unit
  - executes creep spread actions
  - starts Radix structure construction actions

## Lifecycle Rules
- a Seedling begins as a normal controllable unit after Heart production
- a Seedling may be assigned to:
  - creep spread
  - Seedling-started structure construction
- a Seedling is consumed only when the assigned action completes successfully

## Structure Start Flow
- the player places the target Radix structure first
- the placed site is tracked in the HUD queue as a construction target
- a Seedling travels to the site and begins the start action
- once the start action completes, the Seedling is consumed and the structure continues from its started state

## Cancel and Refund Behavior
- if the player cancels before the Seedling is consumed, the original Seedling remains alive
- if the player cancels a started Seedling-built structure after the Seedling has already been consumed, the game restores an equivalent Seedling
- canceling construction also follows the current structure refund rules for spent resources

## Success Outcome
- creep spread or structure start completes
- the Seedling is removed as part of the successful action resolution

## Design Notes
- this is an intentional Radix faction identity mechanic
- Seedlings are not standard combat infantry and should be documented as support/build units first
