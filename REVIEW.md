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

**Invariant: entry-rebuild completeness.** `RegistryEntry` carries five fields (`skill`, `versions`,
`health_status`, `owner`, `dependencies`), and four sites rebuild one by hand: `Registrar#update`,
`Registrar#replace_skill_in_entry`, `Health::Tracker#record`, `OwnershipResolver#assign`. A rebuild
that omits a field silently **erases** it for that skill, and a PR adding a sixth field must thread
it through all four. This is the easiest way to lose data here. Check it whenever an entry is built.

**Stale reads:** a caller holding an entry fetched before a write holds a stale object. Flag a method
that fetches once and writes twice, or that feeds a pre-fetch entry into a later rebuild.

## Lifecycle enforcement and what fail closed means

`Governance::LifecycleManager::LIFECYCLE_TRANSITIONS` is the graph: `draft -> active|retired`,
`active -> deprecated`, `deprecated -> retired`, `retired` terminal.

**Invariant: every lifecycle state change goes through `LifecycleManager#transition!` before it is
written.** `Registrar#deprecate` and `#retire` do. `Registrar#update` does **not**: it takes
`lifecycle_state` in its attrs hash straight into a rebuilt `Models::Skill`, whose constructor only
calls `.to_sym` on it. A PR leaning on that path to move states, or adding another unchecked write of
`lifecycle_state`, is bypassing the gate. Say so.

**Fail closed here:** an unrecognized state yields **no** permitted transitions and raises
`LifecycleError`. `allowed_transitions` returning `fetch(state, [])` is deliberate. A change that
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

`TagIndex` is a separate inverted index synced by `Registrar`: `#index` on register, `#reindex` on
update, `#remove_skill` on removal. Any new path that changes `skill.tags` or removes a skill must
update the index in the same operation, and tag changes use `#reindex` (a bare `#index` leaves old
tags pointing at the skill). `Finder#find_by_tag` uses `filter_map`, which hides a dangling name
rather than fixing it. Do not accept "the finder handles it".

## Export surface

`JsonExporter` and `MarkdownExporter` serialize whatever `#to_h` returns, all the way down.
`Models::Owner#to_h` includes `contact`, in practice a human email address. **Any new field in a
model's `to_h` is published in every export.** Flag a new field carrying a contact, credential,
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
