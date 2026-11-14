# ADR 0001 — First playable, 2026-11-14

## Context
The user requests a playable first prototype with all systems and polished touch UI, and explicitly asks parallel agents to accelerate implementation. The normative specification spans years of development. No honest first build can claim all target acceptance scenarios.

## Decision
Use Godot 4.6.3 typed GDScript, pure RefCounted domain modules, a single SimulationKernel transaction boundary, detached ObserverSnapshot and filesystem adapter. Build a finite settlement vertical slice: cold night, clean water, shelter, wound care, social help and working radio. Every major domain family participates at reduced fidelity, documented per model; unsupported target behaviors stay visibly specified, never mocked as implemented.

Simulation advances only through actions; one second integer clock, maximum 10s physics steps. Frame frequency and navigation cannot change time. Long actions store elapsed progress; completion consumes resources once, cancellation preserves already elapsed physiology/environment. Materials reserved by the exclusive action lifecycle (no concurrent player commands); validate again at commit.

Prototype uses typed command objects at the boundary with validated Dictionary module payloads carrying SI suffixes; specialized Quantity types and complete module migration registries remain specified. Ordered module execution: weather/heat → items → physiology → world → action completion → observer. Modules exchange read-only context and kernel-routed effects. Journal/trace capped to bounded windows. Config content is data-only.

## Alternatives
A web game would improve link sharing but diverge from Godot/Android constraints. An exhaustive bottom-up engine would postpone gameplay. Chosen slice provides reviewable consequences with a modest, explicit model scope.

## Consequences and verification
Approximate physiology, atmosphere, ecology and social behavior are gameplay assumptions, not experimentally calibrated predictions. No universal HP. Hidden biological/chemical truth stays in debug only. Native Android build and SM-T515 profiling require a device/toolchain and are not claimed by desktop tests. Unit, integration, replay, interrupted-action save, corrupt-save recovery and UI layout tests accompany the build.
