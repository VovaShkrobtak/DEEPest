# ADR 0003 — Acoustic events and the sensory observation boundary
Status: accepted, 2026-11-14.

## Decision
Use a deterministic bounded `Acoustics` state owned by SimulationKernel rather than a global per-action zombie-alert flag. All world actions and actors can emit typed acoustic stimuli, with attenuation determined by graph distance, envelope loss, weather and the listener's sensitivity. Zombie target acquisition relies on audible stimuli, not direct player coordinates; the player reads the same acoustic state through `Perception` and `Observer`.

## Alternatives
A constant enemy hearing radius was simple but could not distinguish rain, enclosure, windows or bodily impairment. Full wave/impulse response in 3D was inappropriate because the project currently has only seven named locations, no room meshes and a weak Android hardware target.

## Consequences
Conserves reproducibility, remains UI-independent, scales with a small bounded event queue, and supports physically motivated stealth choices. State migration adds a sound clock and queue; invalid/future/forged sound events are rejected. Tradeoff: road-graph distance is an approximation for acoustic path; same-node walls, real material absorption and azimuth remain unresolved. Never call the current coefficients experimental measurements.

## Verification
`tests/test_acoustics.gd`, `test_zombie_acoustics.gd`, `test_acoustic_integration.gd`, `test_perception.gd`, plus existing world/UI/save regressions. See `docs/14_PERCEPTION_ACOUSTICS.md` for precise assumptions.
