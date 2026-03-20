# Changelog

All notable changes to `wild-skillops-registry` will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-03-20

### Added
- Initial implementation of all 10 epics
- `Models::Skill` — validated skill definition with semver enforcement
- `Models::SkillVersion` — versioned snapshot of a skill
- `Models::Dependency` — dependency relationship between skills
- `Models::HealthStatus` — health state tracking with staleness detection
- `Models::Owner` — skill ownership metadata
- `Models::RegistryEntry` — full composite read view of a skill
- `Registry::Store` — capacity-bounded in-memory registry store
- `Registry::Registrar` — register, update, deprecate, retire skills
- `Registry::Finder` — query by name, tag, repo, category, lifecycle, substring search
- `Versioning::VersionManager` — version history with per-skill capacity limit
- `Versioning::ChangelogBuilder` — human-readable changelog generation
- `Health::Tracker` — record and overwrite health status per skill
- `Health::Aggregator` — aggregate health summary and stale detection across registry
- `Governance::LifecycleManager` — enforced lifecycle transitions (draft/active/deprecated/retired)
- `Governance::OwnershipResolver` — assign and query skill ownership by team
- `Discovery::TagIndex` — inverted tag index with O(1) lookup and reindexing
- `Discovery::SearchEngine` — relevance-scored substring search across name/description/tags
- `Export::JsonExporter` — full registry and single-skill JSON export
- `Export::MarkdownExporter` — human-readable Markdown catalog with health/owner/dependency rendering
- `WildSkillopsRegistry.build` — factory method returning a fully-wired `RegistryFacade`
- Validated configuration with `freeze!` support and `reset_configuration!` for tests
- 251 tests, 0 failures, 0 RuboCop offenses
