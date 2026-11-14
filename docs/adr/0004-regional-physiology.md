# ADR 0004 — Regional body state, effects on actions, and legacy migration

**Status:** accepted, 2026-11-14.

## Decision
Maintain an independent, deterministic regional `Anatomy` module under `Physiology`: 7 regions, 5 tissue integrities, wound records and 4 sensory organs. The existing systemic physiology owns blood/water/heat/energy/sleep and uses local injuries as causal inputs. The kernel queries body capabilities before allowing actions, derives action duration from current functional state and interrupts work when hand/leg functionality changes. Presentation receives only observations, not tissue integrity values.

## Rejected alternatives
Single HP and injury percentage icons conceal physical consequences and misrepresent impairment. A massive nested ECS per organ would currently overburden the early seven-location sandbox and Android 10 target. Full clinical pathology is outside the scope of a game with no experimental calibration.

## Key consequences
- Wounds have independent bleeding sources/contamination/bandages; no universal instant healing.
- Adrenaline alters perception of pain, physical readiness and fine motor control, without repairing tissues.
- Partial mobility changes actual walking time; extreme loss of function blocks it; failing hands interrupt repairs.
- New save field `body.anatomy` and identical fields in NPC bodies are migrated from old single-wound values; old world build/content hash preserved for compatibility.
- All new action parameter dictionary keys are regular strings to avoid invalid JSON/save validation.
- Fractions, masses and pain coefficients are explicit approximations, not clinical data.

## Verification
`test_anatomy.gd`, `test_body_actions.gd`, `test_physiology.gd`, `test_perception.gd`, `test_transactions.gd`, `test_world.gd`, full Godot 4.6.3 CI. Target rules in `docs/15_BODY_PHYSIOLOGY.md`.
