# ADR 0005 — Persistent infected agents, mechanical portals and localized trauma

Status: accepted, 2026-11-14.

## Decision
Extend fixed, nonrespawning infected entities to a versioned FSM over heard/seen stimuli and bounded memory, graph-grounded movement and search, persistent acoustic-sensitive doors, obstacles, falls and grapple contact. Reuse the existing Anatomy module for infected tissue wounds and circulating blood; do not introduce HP or destroy and respawn IDs. Keep NPC and user observations at the Perception boundary. Continue to run each simulation decision in deterministic steps up to 10 seconds; store the RNG state and prior stimulus sequence to make save/replay reproducible.

## Motivation
The previous `distance_m` and `alert_s` model could approach sound but never lose a route meaningfully, physically interact with doors, fall or struggle. UI-only prompts would simulate danger without causal consequences. A full NavMesh rigid-body/cloth solution is invalid in the seven-node text world and too costly for the target tablet.

## Consequences
- Contact changes local tissues and bleeding; grapple has physical persistence and escape conditions.
- Portals block player and infected movement; mechanical impacts accumulate, bracing consumes real wood, and door sounds use the same acoustic system.
- Lost traces initiate time-bounded searches and terminate without imaginary tracking.
- New v3 save migration preserves existing v1/v2 infected IDs and actor state. Corrupt barriers and false IDs reject before replacing world state.
- Same-node obstacles are explicit detour costs, **not** mesh-based navigation. Use true geometric doors/occlusion only once room geometry exists.
- Default doors start open for compatible first-night saves; material strengths are design assumptions, not tested engineering values.

## Verification
`tests/test_infected_navigation.gd`, `test_infected_behavior.gd`, `test_infected_gameplay.gd`, `test_infected_anatomy.gd`, former world/physiology/sensory/transaction regressions, Godot 4.6.3 CI. See `docs/16_INFECTED_BEHAVIOR.md`.
