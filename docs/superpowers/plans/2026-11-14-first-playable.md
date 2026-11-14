# DEEPest First Playable Implementation Plan

> **For agentic workers:** Use executing-plans with parallel domain implementers explicitly requested by the user.

**Goal:** Deliver an offline playable survival loop with connected prototype models and polished Russian touch UI.

**Architecture:** Pure domain modules own body/environment/world/items; kernel is the only command boundary. Observer produces detached knowledge-limited snapshots. Save adapter persists versioned consistent state and in-progress action.

**Tech Stack:** Godot 4.6.3, typed GDScript, Control/Container UI.

**Spec:** docs/adr/0001-first-playable.md and normative docs 00–09.

## Global Constraints
Android 10 target; entirely offline; no universal HP; finite inventory; no UI state mutation; seed + action log reproducibility; no claim of scientific calibration.

## Review Focus
Invalid command must not mutate state. Cancel must retain elapsed consequences. Save corruption must preserve prior valid state. Hidden contamination must not leak into descriptions. Long sessions must keep journal bounded and resources nonnegative.

### Task 1: Domain models
- [x] Independent red→green domain tests for heat/combustion, body, items/fluids/craft/electricity and world/social/ecology.
- [x] Write each module model record and interface contract.

### Task 2: Integrated action kernel and persistence
- [x] Write tests for deterministic replay, invalid command no-op, movement graph, resource conservation, safe water, radio repairs, interruption and mid-action save/load.
- [x] Implement ActionCommand, kernel, deterministic parser, save checksums and backup recovery.
- [x] Run headless full suite.

### Task 3: Observer and interface
- [x] Detached observer, bounded journal, contextual disabled reasons, adaptive cards, touch navigation and accessible settings.
- [x] Exercise initial screen, action progress, inventory, body, save/load and portrait layout.

### Task 4: Delivery
- [x] Review integration, fix meaningful findings with regression tests; benchmark eight hours and 100 days.
- [x] Update actual implemented/tested/spec-only matrix, controls, launch commands; add CI and package runnable project.
