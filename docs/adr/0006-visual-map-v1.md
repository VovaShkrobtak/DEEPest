# ADR 0006 — Visual Map 1.0: read-only schematics

Status: accepted (initial UI slice)

## Context
DEEPest currently has a seven-node world graph, and the physical home is one
simulation location called shelter. No within-room coordinates, tiles, walls,
furniture collision, line-of-sight mesh or positional sound sources exist.
Rendering invented exact infected/NPC positions would violate the perception
boundary and undermine zombie behaviour.

## Decision
Add a small, optional, offline 2D schematic to the "Мир" tab, driven solely by
the public Observer snapshot. "Дом" shows an **illustrative** floor plan;
the rooms and furniture are not authoritative world geometry. "Двор" shows
existing route connections and their authored distances, but its node placement
is layout-only and is not geography or a navigation/physics coordinate system.

Only a route that exists in the observer's published connections is clickable.
The interaction routes through the existing published action catalogue and
Kernel.command; no UI-side movement, event, or world mutation takes place.
Actor locations, identities not seen, inferred sound directions and invisible
infected are never placed on this diagram. Observed people, sounds and danger
remain text-only, without invented coordinates.

## Consequences
- Simulation, save version and all environmental/acoustic systems unchanged.
- Android 10 / desktop use Godot Control drawing; no new textures, GPU shaders,
  polling or per-frame world traversal.
- A proper spatial home requires a separate data-model, physical geometry,
  portal/navigation/perception integration and migration; Visual Map 1.0 does
  not claim to deliver those capabilities.
- UI at 200% font scale and on physical SM-T515 remains to be verified.
- See tests/test_visual_map.gd for route hitboxes, isolation and private-state
  non-disclosure regression checks.
