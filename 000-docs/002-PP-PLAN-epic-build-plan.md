# 002 — Epic Build Plan: wild-skillops-registry

**Type:** PP-PLAN (Planning)
**Status:** Complete — all 10 epics implemented at v0.1.0

---

## Epic Overview

| Epic | Name | Key Deliverables |
|------|------|-----------------|
| 1 | Core Models | Skill, SkillVersion, Dependency, HealthStatus, Owner, RegistryEntry |
| 2 | Registry Store | Capacity-bounded in-memory store with atomic read/write |
| 3 | Registrar | Register, update, deprecate, retire skills with validation |
| 4 | Finder | Query by name, tag, repo, category, lifecycle |
| 5 | Version Management | Version history, capacity limits, changelog generation |
| 6 | Health Tracking | Per-skill health recording, staleness detection, aggregation |
| 7 | Lifecycle Governance | Transition enforcement, terminal state, ownership resolution |
| 8 | Discovery | TagIndex (inverted), SearchEngine (relevance-scored) |
| 9 | Export | JSON and Markdown export with full metadata rendering |
| 10 | Configuration & Facade | Validated config, freeze! support, RegistryFacade wiring |

---

## Epic Narratives

### Epic 1 — Core Models

Establish the data vocabulary. `Skill` is the canonical unit. `RegistryEntry` is the composite read view.
All models validate at construction and raise `ValidationError` for structural violations.
`HealthStatus` reads configuration for allowed states at construction time.

### Epic 2 — Registry Store

The store is the single source of truth. All writes replace the full `RegistryEntry` (immutable-style
replacement rather than mutation). Capacity is checked on every add for new names. Updates to existing
names are allowed regardless of capacity.

### Epic 3 — Registrar

Three mutation verbs: register (new), update (replace attrs), deprecate/retire (lifecycle change).
The registrar orchestrates: validates input, calls lifecycle manager for transitions, records versions,
and keeps the tag index in sync. It owns the coordination but delegates each concern.

### Epic 4 — Finder

Pure read interface. No mutations. Delegates to store and tag index. `search` is a convenience
wrapper doing substring matching; `SearchEngine` adds relevance scoring on top.

### Epic 5 — Version Management

`VersionManager` records one `SkillVersion` per version event (initial registration and each update
that produces a change). Capacity is enforced per-skill. `ChangelogBuilder` formats version history
newest-first as lines or text.

### Epic 6 — Health Tracking

`Tracker` records health by replacing the entry in the store with an updated `HealthStatus`.
`Aggregator` summarizes state counts, stale counts, and tracked/untracked coverage across the
entire registry.

### Epic 7 — Lifecycle Governance

`LifecycleManager` owns the transition table. Calling `transition!` raises `LifecycleError` on
invalid transitions and returns the target state on success. `OwnershipResolver` assigns/replaces
owner by replacing the entry in the store.

### Epic 8 — Discovery

`TagIndex` is an inverted hash mapping normalized tags to skill name arrays. `reindex` is used for
updates to maintain correctness. `SearchEngine` wraps `Finder` with field-weighted relevance scoring.

### Epic 9 — Export

`JsonExporter` calls `to_h` on each `RegistryEntry` and serializes. `MarkdownExporter` renders a
complete catalog with sections for core skill info, owner, health (including stale detection), and
dependencies.

### Epic 10 — Configuration and Facade

`Configuration` is a mutable/freezable settings object. `WildSkillopsRegistry.build` is the factory
that wires all subsystems into a `RegistryFacade` struct. Tests call `reset_configuration!` in a
`before` block to ensure isolation.
