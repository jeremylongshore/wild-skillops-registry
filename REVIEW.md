# REVIEW.md

Reviewer law for the automated pull-request reviewer (MiniMax, two advisory lanes) on
`wild-skillops-registry`.

Report only defects introduced by this pull request, verified against the surrounding source. The
deterministic gate is CI (`bundle exec rspec` on Ruby 3.2 and 3.3, `bundle exec rubocop`); the
reviewer's job is what a test run and a linter cannot see: a broken invariant, a silently widened
boundary, a claim the diff does not support.

## What this repo is

A pure, in-memory Ruby library gem: the registry and discovery layer for skills published by the wild
ecosystem repos (register, find, version, track health, map dependencies, assign ownership, export).
It does **not** execute skills, enforce access control (that is `wild-capability-gate`), collect
telemetry (that is `wild-session-telemetry`), persist, or touch the network. Zero runtime
dependencies, stdlib only. Everything below follows from that: this gem is trusted because it is
inert and because the answers it gives about a skill's state are true.

## The purity boundary (highest-risk class)

Widest blast radius, because downstream repos load this gem inside a Rails process running AI agents.

- **Invariant: no I/O.** No network (`Net::HTTP`, `URI.open`, sockets), no filesystem (`File`, `IO`,
  `Dir`, `Tempfile`, `Marshal.load`), no subprocess (backticks, `system`, `spawn`, `Open3`), no
  `eval` / `instance_eval` on caller-supplied strings, no `ENV` read that changes behavior. Flag on
  sight, including inside a rescue or a debug helper.
- **Invariant: zero runtime dependencies.** The gemspec declares no `add_dependency` and must not
  gain one. A new `require` is fine only for stdlib (`json` and `time` are already used). An
  `add_dependency` line is a boundary change needing an owner decision, not a review nit.
- **Invariant: no persistence.** State lives in `Registry::Store`'s hash and nowhere else. Writing
  state to disk, a database, or a cache belongs in a different repo.

## Store and entry invariants

**The `Store` is the single source of truth.** Every mutation ends in `@store.add(updated_entry)`.
`Models::RegistryEntry` is immutable in practice: subsystems rebuild a whole entry and write it back.
Flag in-place mutation of an entry or skill, and an updated entry computed but never written back.
Note that `dependencies` is currently carried but never written: `Models::Dependency` exists and
`RegistryEntry` holds a `dependencies` array, but no subsystem populates it. `Registrar#register`
takes the empty default and every rebuild site passes `entry.dependencies` straight through. A PR
that adds a dependency writer is adding a subsystem, not tweaking one.

**Invariant: entry-rebuild completeness.** `RegistryEntry` carries five fields (`skill`, `versions`,
`health_status`, `owner`, `dependencies`), and four sites rebuild one by hand: `Registrar#update`,
`Registrar#replace_skill_in_entry`, `Health::Tracker#record`, `OwnershipResolver#assign`. A rebuild
that omits a field silently **erases** it for that skill, and a PR adding a sixth field must thread
it through all four. This is the easiest way to lose data here. Check it whenever an entry is built.

**Stale reads:** a caller holding an entry fetched before a write holds a stale object. Flag a method
that fetches once and writes twice, or that feeds a pre-fetch entry into a later rebuild.

## Lifecycle enforcement and what fail closed means

`Governance::LIFECYCLE_TRANSITIONS` is the graph (it is defined at module scope in
`lifecycle_manager.rb`, not nested inside the `LifecycleManager` class, so
`Governance::LifecycleManager::LIFECYCLE_TRANSITIONS` does not resolve): `draft -> active|retired`,
`active -> deprecated`, `deprecated -> retired`, `retired` terminal.

**Invariant: every lifecycle state change goes through `LifecycleManager#transition!` before it is
written.** `Registrar#deprecate` and `#retire` do. `Registrar#update` does **not**: it takes
`lifecycle_state` in its attrs hash straight into a rebuilt `Models::Skill`, whose constructor only
calls `.to_sym` on it. A PR leaning on that path to move states, or adding another unchecked write of
`lifecycle_state`, is bypassing the gate. Say so.

**Fail closed here:** an unrecognized state yields **no** permitted transitions and raises
`LifecycleError`. `allowed_transitions` returning `LIFECYCLE_TRANSITIONS.fetch(state.to_sym, [])` is deliberate. A change that
makes an unknown state permissive, returns a default-allow list, rescues `LifecycleError` and
continues, or downgrades it to a warning is fail-open. That is a security-class defect, not a nit.

## Ordering, capacity, and unbounded growth

`Registrar#deprecate` and `#retire` write the entry to the store **first** and call
`record_version` second, and `record_version` can raise `VersionCapacityError` at
`max_versions_per_skill`. That leaves a committed state change with no version row. Flag new
operations repeating this write-then-record ordering; validate before the store write.

`max_skills` (1000) and `max_versions_per_skill` (50) are the only bounds on memory in a long-lived
process. `Store#add` deliberately permits an over-capacity write when the name already exists so
updates never fail. Flag a removed check, a silently raised default, or a new unbounded collection.

Real bug pattern here: `TagIndex#@index` and `VersionManager#@versions` are
`Hash.new { |h, k| h[k] = [] }`, so **reading an unknown key inserts it**. `TagIndex#lookup` and
`VersionManager#versions_for` grow the hash on every miss, and `TagIndex#all_tags` then reports tags
nobody registered. Flag new read paths that index either hash directly.

## Index and store must agree

`TagIndex` is a separate inverted index synced by `Registrar` at exactly two points: `#index` on
register and `#reindex` on update. There is no third. `Registrar` has no removal path at all, and
`TagIndex#remove_skill` and `Store#delete` both exist with no caller anywhere in `lib/`. So a PR that
adds skill removal is wiring an unexercised pair for the first time, and removing from the store
without calling `#remove_skill` in the same operation leaves the index pointing at a name that is
gone. Any new path that changes `skill.tags` must likewise update the index in the same operation,
and tag changes use `#reindex` (a bare `#index` leaves old tags pointing at the skill). `Finder#find_by_tag` uses `filter_map`, which hides a dangling name
rather than fixing it. Do not accept "the finder handles it".

## Export surface

The two exporters do not work the same way, and the difference decides what a new field leaks.
`JsonExporter` serializes whatever `#to_h` returns, all the way down, so **any new field added to a
model's `to_h` is published in the JSON export the moment it is added, with no export-side change.**
`MarkdownExporter` never calls `#to_h`: it hand-renders a fixed list of named fields, so a new model
field reaches Markdown only when someone adds a render line for it. `Models::Owner#to_h` includes
`contact`, in practice a human email address, and Markdown publishes that contact explicitly too. Flag a new field carrying a contact, credential,
token, internal URL, or free-text operator note unless the PR states it is meant to be exported.
Never quote a suspected secret: name the file, the line, and the fix.

## Validation and error taxonomy

Models validate in the constructor and raise the typed errors in `errors.rb` (`ValidationError`,
`NotFoundError`, `DuplicateSkillError`, `LifecycleError`, `ConfigurationFrozenError`,
`RegistryCapacityError`, `VersionCapacityError`). Flag a bare `StandardError` or `ArgumentError`
from library code where a typed error exists, and a rescue that swallows one into a `nil` return,
which turns a hard failure into a silent wrong answer. `Configuration` is freeze-on-configure: every
setter calls `assert_mutable!` first, and one that skips it is a hole in the freeze. Note that
`allowed_lifecycle_states` is configurable but unread by `Skill`, so do not call it enforced.

## Generated, vendored, and off-limits

`Gemfile.lock`, `pkg/`, `coverage/`, `vendor/bundle`, and `*.gem` are gitignored build output;
committing one is a `.gitignore` problem, not a content problem. `version.rb` `VERSION` is the
release handle and a bump belongs with a `CHANGELOG.md` entry. `000-docs/` is the canonical numbered
doc set: historical docs and AARs record what was known at their date and need a dated correction or
a successor, never a silent rewrite. `planning/` is pre-implementation history, not to be updated.

## Do not waste comments on

RuboCop's job (layout, line length, frozen string literals, method length, naming), RSpec style,
anything `.rubocop.yml` already configures, one idiomatic Ruby spelling over another, YARD docs,
speculative performance work on an in-memory hash of at most 1000 entries, or re-litigating
`000-docs/003-AT-ADEC-architecture-decisions.md` without a concrete defect to point at.

## Claims, evidence, and anti-ratchet

"251 tests passing" and "0 RuboCop offenses" are checkable claims, and green CI proves only that the
checks that ran passed, not that a boundary held. A test added alongside a change does not prove
correctness if it asserts the new behavior tautologically. Flag unsupported words (verified, safe,
production-ready, complete), a diff that does materially more or less than its description, and any
claim that the purity or lifecycle boundary held when the diff shows otherwise.

On a re-review the bar does not rise: drop findings the update resolved, and do not invent objections
on unchanged lines previously accepted. Prefer a few high-conviction findings. If the change is
correct, in-boundary, and honest, reply `lgtm`. The reviewer is advisory only, never blocks a merge.

## Sources

Every code-grounded claim above was checked against the working tree at commit `b3d271f`, the tip of
`ci/minimax-review`, by opening the file and reading the line. A documented invariant is not an
enforced one, so each entry below points at the code that either enforces the claim or is the reason
it holds. Three claims failed the check and were corrected in place before this list was written;
they are marked CORRECTED.

**Repo shape and gate**

- Zero runtime dependencies, no `add_dependency`: `wild-skillops-registry.gemspec:5-24`
- Deterministic gate is rspec on Ruby 3.2 and 3.3 plus rubocop: `.github/workflows/ci.yml:14`, `.github/workflows/ci.yml:25-29`
- 251 examples, 0 failures: verified by running `bundle exec rspec` at this commit

**Purity boundary**

- No network, filesystem, subprocess, `eval`, or behavior-changing `ENV` read anywhere in `lib/`: verified by pattern scan over `lib/`, zero hits
- Only stdlib requires, `json` and `time`: `lib/wild_skillops_registry/export/json_exporter.rb:3`, `lib/wild_skillops_registry/models/skill.rb:3`, `lib/wild_skillops_registry/models/skill_version.rb:3`, `lib/wild_skillops_registry/models/health_status.rb:3`
- No persistence, state is one hash: `lib/wild_skillops_registry/registry/store.rb:9`

**Store and entry invariants**

- Every mutation ends in `@store.add`: `lib/wild_skillops_registry/registry/registrar.rb:20`, `:39`, `:102`; `lib/wild_skillops_registry/health/tracker.rb:27`; `lib/wild_skillops_registry/governance/ownership_resolver.rb:23`
- `RegistryEntry` carries five fields: `lib/wild_skillops_registry/models/registry_entry.rb:8`, `:10`
- Rebuild site 1, `Registrar#update`: `lib/wild_skillops_registry/registry/registrar.rb:32-38`
- Rebuild site 2, `Registrar#replace_skill_in_entry`: `lib/wild_skillops_registry/registry/registrar.rb:95-101`
- Rebuild site 3, `Health::Tracker#record`: `lib/wild_skillops_registry/health/tracker.rb:20-26`
- Rebuild site 4, `OwnershipResolver#assign`: `lib/wild_skillops_registry/governance/ownership_resolver.rb:16-22`
- `dependencies` is carried but never written: `lib/wild_skillops_registry/registry/registrar.rb:19` takes the empty default at `lib/wild_skillops_registry/models/registry_entry.rb:10`, and the only other mentions pass it through at `registrar.rb:37`, `registrar.rb:100`, `health/tracker.rb:25`, `governance/ownership_resolver.rb:21`

**Lifecycle**

- CORRECTED, the constant is `Governance::LIFECYCLE_TRANSITIONS` at module scope, not `Governance::LifecycleManager::LIFECYCLE_TRANSITIONS`: `lib/wild_skillops_registry/governance/lifecycle_manager.rb:12-17`, class opens at `:19`
- Transition graph values: `lib/wild_skillops_registry/governance/lifecycle_manager.rb:13-16`
- `deprecate` and `retire` route through `transition!`: `lib/wild_skillops_registry/registry/registrar.rb:48`, `:57`, via `:79-80`
- `Registrar#update` does not, it passes `lifecycle_state` through the attrs hash: `lib/wild_skillops_registry/registry/registrar.rb:74`
- `Models::Skill` only calls `.to_sym` on `lifecycle_state`: `lib/wild_skillops_registry/models/skill.rb:35`
- Unknown state yields no permitted transitions and raises: `lib/wild_skillops_registry/governance/lifecycle_manager.rb:26-31`, `:37`

**Ordering, capacity, unbounded growth**

- Store write before `record_version` in `deprecate`: `lib/wild_skillops_registry/registry/registrar.rb:49-50` with the write at `:102`
- Same ordering in `retire`: `lib/wild_skillops_registry/registry/registrar.rb:58-59`
- `record_version` raises `VersionCapacityError`: `lib/wild_skillops_registry/versioning/version_manager.rb:17-21`
- `max_skills` 1000 and `max_versions_per_skill` 50: `lib/wild_skillops_registry/configuration.rb:16-17`
- `Store#add` permits an over-capacity write for an existing name: `lib/wild_skillops_registry/registry/store.rb:16`
- Default-block hashes that insert on read: `lib/wild_skillops_registry/discovery/tag_index.rb:8`, `lib/wild_skillops_registry/versioning/version_manager.rb:9`
- Read paths that grow them: `lib/wild_skillops_registry/discovery/tag_index.rb:30`, `lib/wild_skillops_registry/versioning/version_manager.rb:33`, `:37`, `:41`
- `all_tags` reports whatever those misses inserted: `lib/wild_skillops_registry/discovery/tag_index.rb:34`

**Index and store agreement**

- `#index` on register: `lib/wild_skillops_registry/registry/registrar.rb:22`
- `#reindex` on update: `lib/wild_skillops_registry/registry/registrar.rb:41`
- CORRECTED, there is no removal sync because there is no removal path: `TagIndex#remove_skill` is defined at `lib/wild_skillops_registry/discovery/tag_index.rb:37` and `Store#delete` at `lib/wild_skillops_registry/registry/store.rb:39`, and neither has a caller anywhere in `lib/`
- `Finder#find_by_tag` uses `filter_map`: `lib/wild_skillops_registry/registry/finder.rb:23`

**Export surface**

- CORRECTED, only `JsonExporter` serializes `#to_h`: `lib/wild_skillops_registry/export/json_exporter.rb:17`, `:28`
- CORRECTED, `MarkdownExporter` hand-renders named fields and never calls `#to_h`: `lib/wild_skillops_registry/export/markdown_exporter.rb:35-91`
- `Models::Owner#to_h` includes `contact`: `lib/wild_skillops_registry/models/owner.rb:20`
- Markdown publishes that contact explicitly: `lib/wild_skillops_registry/export/markdown_exporter.rb:62-63`

**Validation and error taxonomy**

- The seven typed errors: `lib/wild_skillops_registry/errors.rb:5-26`
- Models validate in the constructor: `lib/wild_skillops_registry/models/skill.rb:28-36`, `lib/wild_skillops_registry/models/owner.rb:10-12`
- Every `Configuration` setter calls `assert_mutable!` first: `lib/wild_skillops_registry/configuration.rb:25`, `:32`, `:41`, `:50`, `:57`, with the guard at `:74-78`. Note that these setters raise `ArgumentError` for a bad value because no typed error covers that case, so their `ArgumentError` is not the pattern the taxonomy rule is aimed at
- `allowed_lifecycle_states` is configurable but unread by `Skill`: defined at `lib/wild_skillops_registry/configuration.rb:49-54`, never read outside `Configuration`, while `allowed_health_states` is read at `lib/wild_skillops_registry/models/health_status.rb:15` and `lib/wild_skillops_registry/health/aggregator.rb:15`

**Generated, vendored, off-limits**

- Gitignored build output: `.gitignore:4` coverage, `:6` pkg, `:9` vendor/bundle, `:10` Gemfile.lock, `:11` `*.gem`
- `VERSION` is the release handle: `lib/wild_skillops_registry/version.rb:4`
- Canonical numbered doc set, eight files including the architecture decisions record: `000-docs/003-AT-ADEC-architecture-decisions.md`
- Pre-implementation history: `planning/epics.md`, `planning/notes.md`, `planning/roadmap.md`
- What `.rubocop.yml` configures on top of RuboCop defaults: `.rubocop.yml:12-68`
