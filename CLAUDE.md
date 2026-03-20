# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Identity

- **Repo:** wild-skillops-registry
- **Ecosystem:** wild (see `../CLAUDE.md` for ecosystem-level rules)
- **Archetype:** D — Coordination / Registry
- **Mission:** Registry and discovery layer for skills/capabilities across all wild ecosystem repos
- **Namespace:** WildSkillopsRegistry
- **Language:** Ruby 3.2+, pure library gem (no MCP, no ActiveRecord)
- **Status:** v0.1.0 complete — all 10 epics implemented, 251 tests passing, 0 RuboCop offenses

## What This Repo Does

- Registers skills/capabilities from across the wild ecosystem (each repo publishes what it can do)
- Discovers available skills by name, tag, category, repo, capability level, lifecycle state
- Versions skill definitions (track when skills change, deprecate old versions)
- Tracks health per skill (available/degraded/unavailable/unknown) with staleness detection
- Maps dependencies between skills
- Manages governance — ownership assignment and lifecycle state enforcement
- Exports the registry as JSON or human-readable Markdown

## What This Repo Does NOT Do

- Execute skills (repos own their execution)
- Enforce access control (that is wild-capability-gate)
- Collect telemetry (that is wild-session-telemetry)
- Persist state to disk or a database
- Communicate over a network (no HTTP, no sockets)
- Operate as an MCP server or HTTP service

## Directory Layout

```
wild-skillops-registry/
  000-docs/               canonical documentation
  lib/
    wild_skillops_registry.rb            entry point, configure interface, build factory
    wild_skillops_registry/
      configuration.rb                   validated config with freeze! support
      errors.rb                          error hierarchy
      version.rb                         VERSION = '0.1.0'
      models/                            Skill, SkillVersion, Dependency, HealthStatus, Owner, RegistryEntry
      registry/                          Store, Registrar, Finder
      versioning/                        VersionManager, ChangelogBuilder
      health/                            Tracker, Aggregator
      governance/                        LifecycleManager, OwnershipResolver
      discovery/                         TagIndex, SearchEngine
      export/                            JsonExporter, MarkdownExporter
  spec/
    spec_helper.rb
    support/fixtures.rb                  RegistryFixtures module — all test helpers
    wild_skillops_registry/              unit specs (mirrors lib/ structure)
    integration/                         full_registry_pipeline_spec, multi_repo_registration_spec
    adversarial/                         malformed_input_spec, edge_cases_spec
  planning/               pre-implementation notes
  Gemfile
  Rakefile
  wild-skillops-registry.gemspec
```

## Build Commands

```bash
bundle install
bundle exec rspec                    # run all 251 specs
bundle exec rubocop                  # lint (must be 0 offenses)
bundle exec rake                     # default: runs rspec
```

## Key Design Decisions

1. `WildSkillopsRegistry.build` returns a `RegistryFacade` — a single struct exposing all subsystems. Callers hold one object.
2. The `Store` is the single source of truth. All subsystems write back through the store when mutating an entry (health, ownership, skill updates all replace the entry in the store).
3. Lifecycle transitions are enforced by `LifecycleManager` before any state change is written. Invalid transitions raise `LifecycleError`.
4. `TagIndex` maintains a separate inverted index for O(1) tag lookups. It is kept in sync by the `Registrar` on register and update.
5. `SearchEngine` wraps `Finder` and adds relevance scoring. `Finder#search` does basic substring matching; `SearchEngine#search` scores by field weight.
6. No external runtime dependencies. All stdlib only.

## Safety Rules for Claude Code

1. Never add code that makes network calls, reads from disk, or spawns processes.
2. Never persist state to files or databases — this is always in-memory.
3. Never bypass the `Store` — all mutations must go through the store so the single source of truth is maintained.
4. Always enforce lifecycle transitions through `LifecycleManager` before writing a new state.
5. Do not add runtime gem dependencies. Zero runtime deps by design.
6. Do not mutate configuration after freeze! — use reset_configuration! in tests only.
7. Tag mutations must go through `TagIndex#reindex` (not `#index`) to avoid stale entries.

## Key Canonical Docs

| Doc | Purpose |
|-----|---------|
| 000-docs/001-PP-PLAN-repo-blueprint.md | Mission, boundaries, users, use cases |
| 000-docs/002-PP-PLAN-epic-build-plan.md | 10-epic build narrative |
| 000-docs/003-AT-ADEC-architecture-decisions.md | Why things are shaped the way they are |
| 000-docs/004-DR-REFF-data-contracts.md | Skill registration schema and data contracts |
| 000-docs/005-DR-REFF-configuration-reference.md | All config parameters with types and defaults |
| 000-docs/006-OD-GUID-operator-guide.md | Usage flow, config examples, export reading |

## Before Working Here

1. Read `../CLAUDE.md` for ecosystem-level rules and work sequence standards.
2. Read `000-docs/001-PP-PLAN-repo-blueprint.md` for mission and boundaries.
3. Read `000-docs/003-AT-ADEC-architecture-decisions.md` before changing any structural decisions.
4. Run `bundle exec rspec` and confirm 251 examples, 0 failures before making changes.
5. Run `bundle exec rubocop` and confirm 0 offenses before committing.
6. Safety rule 1 is non-negotiable: no network, disk, or subprocess access.
