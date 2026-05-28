# 007 — Operator Audit: wild-skillops-registry

**Type:** AT-AUDT (Audit)
**Date:** 2026-05-28
**Auditor:** /appaudit
**Subject:** `wild-skillops-registry` v0.1.0 — Ruby gem, in-memory skill/capability registry
**Audience:** senior Rails/Ruby engineer, first read, ~10 minutes to operate
**Reading order:** §1 → §4 → §3 → §5 for the fastest "what is this and why isn't it doing anything yet" picture.

---

## 1. Mission & boundaries

`wild-skillops-registry` is the **registry and discovery layer** for the [wild ecosystem](../../CLAUDE.md) — a family of 10 sibling Ruby/Rails coordination repos (rails introspection MCP, admin tools MCP, capability gate, session telemetry, transcript pipeline, gap miner, hook ops, permission analyzer, test flake forensics, and this one). It answers four questions for any consumer in the ecosystem:

1. **What skills exist?** (registry)
2. **Where do they live?** (which `wild-*` repo owns each skill)
3. **What state are they in?** (lifecycle, health, version)
4. **Who owns them?** (governance / ownership resolution)

Within the ecosystem typology this repo is **archetype D — Coordination / Registry** (per [`CLAUDE.md`](../CLAUDE.md) §Identity). It is a pure library gem — not an MCP server, not a Rails engine, not a daemon. The entire system lives in-process inside whatever Ruby host loads it.

### In scope (per [`001-PP-PLAN-repo-blueprint.md`](001-PP-PLAN-repo-blueprint.md))

- Registering skill definitions (name + repo + version + tags + category + capabilities + lifecycle)
- Discovery by name, tag, category, repo, lifecycle state, and substring search
- Versioning with bounded history per skill
- Health tracking with staleness detection
- Lifecycle governance with enforced state-machine transitions
- Ownership assignment per skill
- Dependency mapping between skills
- JSON and Markdown export

### Hard non-goals (CLAUDE.md "Safety Rules" 1-5)

- **No execution.** The registry holds metadata about skills; the repos own the actual code.
- **No access control.** That responsibility lives in `wild-capability-gate`. The registry records `capabilities_required` strings but does not enforce them.
- **No telemetry collection.** That is `wild-session-telemetry`.
- **No persistence.** Zero disk I/O, zero network I/O, zero subprocess spawning. The store is a `Hash` in memory ([`lib/wild_skillops_registry/registry/store.rb:9`](../lib/wild_skillops_registry/registry/store.rb)).
- **No runtime gem dependencies.** Stdlib only — verified in [`wild-skillops-registry.gemspec`](../wild-skillops-registry.gemspec). The only `require` outside the gem is `json` (stdlib) and `time` (stdlib).

The "no persistence + no network" constraints are the load-bearing design decisions. Every architectural choice downstream follows from them. They also constrain the gem to be embedded inside a host process that owns its own durability story — see §5 (failure modes) and §8 (v2 recommendations).

---

## 2. Registry architecture

The gem ships **22 Ruby source files** organised into seven concern areas, all hanging off the `WildSkillopsRegistry` top-level module ([`lib/wild_skillops_registry.rb`](../lib/wild_skillops_registry.rb)):

| Concern | Module | Files | Role |
|---|---|---|---|
| Public API | `WildSkillopsRegistry` | `wild_skillops_registry.rb` | `.configure`, `.build` factory, `RegistryFacade` |
| Config | `WildSkillopsRegistry` | `configuration.rb` | Validated, freezable config (caps, thresholds, allowed enums) |
| Errors | `WildSkillopsRegistry` | `errors.rb` | 7-class error hierarchy rooted at `Error < StandardError` |
| Models | `Models` | `skill.rb`, `skill_version.rb`, `dependency.rb`, `health_status.rb`, `owner.rb`, `registry_entry.rb` | Frozen-ish value objects with constructor validation |
| Registry core | `Registry` | `store.rb`, `registrar.rb`, `finder.rb` | The hash, the writer, the reader |
| Versioning | `Versioning` | `version_manager.rb`, `changelog_builder.rb` | Per-skill version history with cap |
| Health | `Health` | `tracker.rb`, `aggregator.rb` | Per-skill state + registry-wide rollup |
| Governance | `Governance` | `lifecycle_manager.rb`, `ownership_resolver.rb` | State machine + ownership writeback |
| Discovery | `Discovery` | `tag_index.rb`, `search_engine.rb` | Inverted tag index + weighted substring search |
| Export | `Export` | `json_exporter.rb`, `markdown_exporter.rb` | Serialisation for humans and machines |

### The four central objects

- **`Registry::Store`** ([`store.rb`](../lib/wild_skillops_registry/registry/store.rb)) — a `Hash<String, RegistryEntry>` keyed on skill name. Enforces `max_skills` (default 1,000) at `add` time and raises `RegistryCapacityError` if exceeded. **Single source of truth** by AD-01: every other subsystem reads from and writes back to this hash. There is no parallel state.
- **`Registry::Registrar`** ([`registrar.rb`](../lib/wild_skillops_registry/registry/registrar.rb)) — the only write path. `register`, `update`, `deprecate`, `retire`. Each method coordinates **three side effects in one call**: store mutation, version snapshot recording, tag index reindex. By AD-03 this coordination is held in one class precisely so no caller can update one and forget the others.
- **`Registry::Finder`** ([`finder.rb`](../lib/wild_skillops_registry/registry/finder.rb)) — the read path. Six lookups: `find_by_name`, `find_by_name_or_nil`, `find_by_tag` (delegates to `TagIndex`), `find_by_repo`, `find_by_category`, `find_by_lifecycle`, plus `search` (substring) and `all`.
- **`RegistryFacade`** ([`wild_skillops_registry.rb:93`](../lib/wild_skillops_registry.rb)) — the dependency-injected struct returned by `WildSkillopsRegistry.build`. Callers hold one facade and reach into its 13 named subsystems (`registry.registrar`, `registry.finder`, `registry.health_tracker`, etc.) instead of wiring subsystems themselves. AD-02.

### How the subsystems compose

The factory in `WildSkillopsRegistry.build_components` ([`wild_skillops_registry.rb:65`](../lib/wild_skillops_registry.rb)) instantiates everything in one breath, threading the shared `store` and `tag_index` through dependents. Two important wiring details:

1. **`Finder` is instantiated twice** — once for the facade's own `.finder`, once nested inside `SearchEngine`. Same `store`, same `tag_index`. Harmless but worth knowing if you grep for `Finder.new`.
2. **`LifecycleManager` is stateless** (AD-05). It only validates transitions against a frozen `LIFECYCLE_TRANSITIONS` table ([`lifecycle_manager.rb:12-17`](../lib/wild_skillops_registry/governance/lifecycle_manager.rb)) and returns the target symbol. The state machine is therefore a table, not an object graph — easy to audit, easy to extend.

### Storage model

Every mutation **rebuilds the full `RegistryEntry`** and overwrites the slot in the store hash. `Health::Tracker#record`, `Governance::OwnershipResolver#assign`, and `Registrar#update` all follow this pattern: fetch entry → construct new `RegistryEntry` with one field replaced → `store.add(entry)`. This is AD-01 and AD-06: there is no field-level mutation API; replace-the-whole-entry is the only writing mode. The trade-off is one extra allocation per write, which the code explicitly accepts at expected scale (< 10,000 skills).

The `TagIndex` is the **one exception to "store is the only state"** (AD-04). It maintains a separate `Hash<String, Array<String>>` of `normalized_tag → [skill_names]` for O(1) tag lookup. The `Registrar` keeps it in sync on register (`#index`) and update (`#reindex`). If a caller bypasses the registrar, the tag index drifts — which is why the safety rules in CLAUDE.md call this out explicitly.

---

## 3. The critical path

A representative end-to-end flow. **"Agent A advertises skill → agent B looks up skill → coordination handshake"** — except in v0.1.0 there are no agents A or B (see §4); this is what the path *would* look like in a real consumer.

### Step-by-step with real method names

```ruby
# === Process startup: build one registry, hold it ===
registry = WildSkillopsRegistry.build
# => RegistryFacade with 13 subsystems wired against one Store + TagIndex

# === Agent A (wild-hook-ops process) advertises a skill ===
skill = WildSkillopsRegistry::Models::Skill.new(
  name: 'hook.trigger',
  description: 'Triggers a lifecycle hook on a registered event',
  repo: 'wild-hook-ops',
  version: '1.0.0',
  tags: %w[hooks lifecycle trigger],
  category: :workflow,
  capabilities_required: ['cap:hooks:write'],
  lifecycle_state: :draft
)
# Skill#initialize runs validate_name!, validate_version! (semver regex),
# validate_tags! (downcased), validate_category! (whitelist).
# Raises ValidationError on any failure.

entry = registry.registrar.register(skill)
# 1. Registrar guards DuplicateSkillError if name already in store
# 2. Builds RegistryEntry(skill:, versions: [], health_status: nil, owner: nil, dependencies: [])
# 3. store.add(entry) — enforces RegistryCapacityError
# 4. version_manager.record_version('hook.trigger', '1.0.0', changes: ['Initial registration'])
# 5. tag_index.index('hook.trigger', %w[hooks lifecycle trigger])
# Returns the RegistryEntry

# === Agent A promotes draft → active after validation ===
registry.registrar.update('hook.trigger', lifecycle_state: :active)
# rebuild_skill copies all fields, swaps lifecycle_state.
# transition_skill calls LifecycleManager#transition!(:draft, :active) → OK.
# Store.add overwrites. Tag index reindexed (no-op here since tags unchanged).
# A version snapshot is recorded ONLY if compute_changes produced non-empty diff.
# NOTE: a lifecycle change alone does not produce a version snapshot — compute_changes
# diffs description, version, tags, category, repo but NOT lifecycle_state. This is a
# subtle gap worth a v2 fix (see §8).

# === Agent A reports health after each tick ===
registry.health_tracker.record('hook.trigger', state: :available, message: 'OK')
# Tracker.record builds HealthStatus, rebuilds full RegistryEntry, store.add().
# HealthStatus#initialize validates state against configuration.allowed_health_states.

# === Agent B (wild-capability-gate process) looks up a skill ===
entry = registry.finder.find_by_name('hook.trigger')
# Store.fetch raises NotFoundError if absent. find_by_name_or_nil returns nil instead.
caps = entry.skill.capabilities_required
# => ['cap:hooks:write']  — agent B uses this to make its gating decision OUT-OF-BAND

# === Agent B discovers all skills tagged 'hooks' ===
hook_skills = registry.finder.find_by_tag('hooks')
# TagIndex#lookup → ['hook.trigger', ...] → Store.fetch_or_nil for each → filter_map nils

# === The "coordination handshake" ===
# There is NO handshake primitive in v0.1.0. The registry is a passive lookup.
# Agent B reads metadata, decides what to do, calls Agent A's skill via whatever
# transport Agent A exposes — HTTP, MCP, gRPC, in-process Ruby. The registry never
# sees the actual invocation.
```

### What's missing in this critical path

The phrase "coordination handshake" in the audit prompt is aspirational. v0.1.0 has **no signalling, no events, no callbacks, no pubsub**. A consumer that wants to be notified when `hook.trigger` flips from `:available` to `:degraded` must poll `registry.health_tracker.status_for('hook.trigger')` on its own cadence. This is a deliberate v0.1.0 scope cut (see §6 trade-off T-3) and a candidate for v2 (see §8).

---

## 4. Adoption status — the elephant in the room

**Honest read: wild-skillops-registry exists, is well-built, is fully tested (251 passing, 0 RuboCop offenses), and is not currently consumed by any other repo in the wild ecosystem.**

A `grep -r "WildSkillopsRegistry\\|wild_skillops_registry" --include="*.rb"` across the eight sibling `wild-*` repos returns **zero hits outside this repo's own code and test fixtures.** The closest thing to ecosystem integration that exists today is [`spec/integration/multi_repo_registration_spec.rb`](../spec/integration/multi_repo_registration_spec.rb), which simulates 10 fictional sibling-repo registrations against an in-process registry — useful as a contract test, not evidence of real adoption.

This is the gap between mission and reality. The blueprint claims (§Users) that "Wild ecosystem repos register skills they own" and that "`wild-capability-gate` reads skill `capabilities_required` to make gating decisions." Neither is true in v0.1.0. The repo is **standalone software that describes a coordination problem nobody else is currently using it to solve.**

### Who should consume it, and what the integration looks like

| Consumer repo | Why it should integrate | What the integration looks like |
|---|---|---|
| **wild-capability-gate** | This is the *primary* intended consumer per the blueprint. The gate makes per-skill access-control decisions; the registry holds `Skill#capabilities_required`. Without the registry the gate has to maintain its own parallel list of skills + their required caps, which guarantees drift. | At startup, capability-gate is constructed with a `RegistryFacade` (or builds its own). On each gate decision: `entry = finder.find_by_name(skill_name)` → read `entry.skill.capabilities_required` → check requesting principal's grants → allow/deny + record decision. No write path needed — gate is a pure consumer. |
| **wild-admin-tools-mcp** | The admin-tools MCP server exposes operational commands as MCP tools. Each tool *is* a skill. Registering them with skillops gives operators one place to discover all admin surface area + health + ownership across repos. | At MCP boot, iterate the tools the server exposes; for each, call `registry.registrar.register(skill_for_tool)` with `category: :admin`, populate `capabilities_required` from the tool's existing capability declaration. On graceful shutdown call `registrar.deprecate` for tools that go away. Periodic `health_tracker.record` from a background fiber after each tool invocation. |
| **wild-rails-safe-introspection-mcp** | Symmetric case to admin-tools. Each introspection capability (`introspect.schema`, `introspect.routes`, etc.) is a skill of `category: :introspection`. The README at [`lib/wild_skillops_registry.rb`](../lib/wild_skillops_registry.rb) uses `introspect.schema` as the canonical example — the integration is already sketched. | Same shape as admin-tools-mcp: register on boot, health-track on tick, deprecate on shutdown. |
| **wild-hook-ops** | Hooks are first-class skills — `hook.trigger`, `hook.register`, `hook.list`. The operator guide already uses `hook.trigger` as its example. | Register hooks at boot. Lifecycle-promote `:draft → :active` after the hook passes its smoke test. Use `registrar.deprecate(name, reason: ...)` when a hook is replaced. |
| **wild-session-telemetry** | Telemetry could *consume* the registry to label collected events with skill metadata (which repo, which lifecycle state at collection time). It could also publish its own collector skills (`telemetry.collect.events`, `telemetry.export.json`) so other tools can find them. | Two-way: register collector skills as `:telemetry`; on each emitted event, optionally enrich with `registry.finder.find_by_name(event.skill_name)&.skill&.repo`. |

### What "adoption" actually requires

Adoption is a per-consumer-repo workstream of roughly the following shape: (a) decide the registration boundary — what counts as a skill in that repo, (b) write a `register_skills.rb` or equivalent boot file that constructs the `Skill` objects and calls `registry.registrar.register`, (c) decide how the registry is shared — single in-process registry per host, or one-per-process where each process is short-lived, (d) decide the health-reporting cadence, (e) decide who owns the registry's lifecycle (since v0.1.0 has no persistence — when the host dies, the registry dies with it; see §5 and §8).

Until at least one sibling repo does this, the gem is technically excellent infrastructure with no field validation. **This is the single highest-priority v2 recommendation** — see §8.

---

## 5. Failure modes & blast radius

The gem is intentionally small and in-memory, which constrains the failure modes to a manageable list. Blast radius is always "the host process" — there is no shared state, no network, no disk.

| Failure mode | Trigger | Symptom | Blast radius | Mitigation today |
|---|---|---|---|---|
| **Registry lost on process restart** | Host process exits. | Registry is empty on next boot until consumers re-register. Health history, version history, ownership assignments all gone. | The entire host process. **No persistence at all** by design. | None in v0.1.0. Consumers must re-register on every boot. See §8 — this is the most important v2 gap. |
| **Tag index drift** | A caller mutates a skill's tags without going through `Registrar#update` (e.g., reaching into the `Models::Skill` instance directly — note `Skill` only exposes `attr_reader` so this requires `instance_variable_set` shenanigans). | `Finder#find_by_tag` returns stale or missing results. The store remains correct. | Lookup correctness only. | Class-level convention enforced by safety rule in CLAUDE.md ("Tag mutations must go through `TagIndex#reindex`"). Not enforced by code. |
| **Capacity exhaustion (skills)** | `Store#add` called when `@entries.size >= max_skills` (default 1,000) and the name is new. | Raises `RegistryCapacityError`. **Existing skill names can still be overwritten**, so updates to known skills always succeed. | Single registration attempt fails loudly. | Caller catches and either raises capacity threshold via config or rejects the registration upstream. |
| **Capacity exhaustion (versions)** | `VersionManager#record_version` called when `@versions[skill_name].size >= max_versions_per_skill` (default 50). | Raises `VersionCapacityError`. Skill stays at last known version snapshot. | Single update fails; skill's state in the store is unchanged because `record_version` is called *after* `store.add` in `Registrar#update` — the store has the new skill but the version history is missing the snapshot. **This is a soft inconsistency: store and version_manager can disagree about the latest version.** | None in v0.1.0. Worth a v2 audit to make the registrar transactional. |
| **Lifecycle race** | Two threads call `Registrar.deprecate` on the same active skill concurrently. | Both fetch the same entry; both call `transition!(:active, :deprecated)` (succeeds for both since manager is stateless); both `store.add`; last writer wins. Two version snapshots recorded. | Duplicate version snapshots; one redundant `Deprecated:` log line. | **Ruby GIL** makes the individual hash mutations atomic; the *compound* fetch-then-write sequence is not. Single-threaded hosts are safe. For multi-threaded hosts, the host must wrap registrar calls in a mutex. **There is no mutex in the gem itself.** |
| **Stale health unnoticed** | Consumer never calls `health_tracker.record` again after a successful boot. | `health_status.stale?` returns `true` after `health_stale_threshold_hours` (default 24h). `aggregator.summary[:stale_count]` rises. No automatic action. | None unless an operator polls. | `Health::Aggregator#stale_entries` is intended to be polled by operators or a watchdog. v2 could surface this through a callback. |
| **Invalid state from a corrupted call** | Caller bypasses `Models::Skill.new` (e.g., constructs a `RegistryEntry` directly with a `Skill` instance whose `lifecycle_state` is `:wat`). | Subsequent `LifecycleManager#transition!` raises with a confusing `Cannot transition from 'wat'` message; finder filters silently skip the entry. | Single skill becomes a poison entry. | Constructor validation in `Skill.new` is the gate; bypass requires deliberate misuse. |
| **Configuration mutation after freeze** | Caller calls `WildSkillopsRegistry.configure { |c| ... }` after `c.freeze!` has been called. | Raises `ConfigurationFrozenError`. | The single misconfiguration attempt fails. | By design — call `freeze!` after process boot. |
| **Network/disk partition** | N/A — the gem makes no network or disk calls. | Cannot occur. | None. | Constraint enforced by safety rule 1 in CLAUDE.md. |

The two most operationally important entries above are **"Registry lost on process restart"** (which makes the gem dependent on consumers being well-behaved on every boot) and **"Lifecycle race"** (which makes the gem unsafe in multi-threaded hosts without external synchronisation). Both are deliberate v0.1.0 simplifications; both deserve explicit consumer-facing documentation that does not currently exist.

---

## 6. Trade-off analysis

The interesting design questions, with the rationale chosen by the author plus the alternatives that were not taken.

### T-1: In-memory store vs persistent backing store

**Chosen:** Pure `Hash` in `Registry::Store`, no I/O of any kind.

**Alternative not taken:** SQLite via `sequel` / ActiveRecord, JSON file at a known path, Redis, embedded LMDB.

**Why this trade-off:** keeps the gem embeddable with zero runtime deps (AD-08) and zero ops burden. Lets the gem be loaded into any Ruby process — Rails app, MCP server, irb session, rake task — without any setup ritual. The cost is that durability is **entirely the host's problem**, and the gem has no answer for "what happens after a restart?" Per the operator guide, "hold it as a long-lived object in your process" — which works if your process is long-lived and fails the moment it isn't.

**Verdict:** correct for v0.1.0 (proves the model end-to-end without committing to a storage choice). **Wrong for v1.0.0** if the registry is supposed to be the source of truth across an ecosystem of independent processes — at that point durability and cross-process visibility become required, not optional. See §8.

### T-2: Replace-the-whole-entry vs field-level mutation

**Chosen:** every mutation rebuilds the `RegistryEntry` (skill, versions, health_status, owner, dependencies) and overwrites the store slot. AD-01 + AD-06.

**Alternative not taken:** mutable `RegistryEntry` with setters, or a CRDT-style merge operator.

**Why this trade-off:** the immutable-rebuild pattern eliminates an entire class of partial-update bugs. There is no path through the code where one subsystem has a half-updated entry while another reads the old one. The cost is one extra allocation per write, which the author explicitly accepts at expected scale.

**Verdict:** correct. This is the kind of conservative choice that pays for itself the first time a multi-threaded host is added. Keep it.

### T-3: No event/notification primitive

**Chosen:** the registry is a pure pull-based lookup. There is no `on_skill_registered`, no `on_health_change`, no callback registration, no pubsub.

**Alternative not taken:** an observer pattern on the store, a small in-process event bus, integration with `ActiveSupport::Notifications`.

**Why this trade-off:** pull is the simplest possible model. Every consumer can poll on whatever cadence makes sense for it; no consumer can break another consumer by raising in a callback. It is also the only model compatible with the "no runtime deps" constraint — adding `ActiveSupport::Notifications` would pull in ActiveSupport.

**Verdict:** correct for v0.1.0. **Becomes a real ergonomic problem** the moment two consumers want to coordinate ("notify capability-gate when a new skill is registered so it can prefetch the cap list"). v2 candidate; see §8.

### T-4: `RegistryFacade` vs service-locator / per-subsystem `require`

**Chosen:** one struct with 13 named accessors, built once by `WildSkillopsRegistry.build`. AD-02.

**Alternative not taken:** make each subsystem independently constructible by the caller, document the wiring in the README.

**Why this trade-off:** consumers should not have to know that `SearchEngine` needs a `Finder` which needs a `Store` and a `TagIndex`. The facade is the wiring diagram in code form. It does not prevent advanced callers from instantiating subsystems directly (they're all public classes); it just makes the happy path one method call.

**Verdict:** correct. Cheap to deliver, eliminates a documented wiring footgun.

### T-5: Substring search in `Finder` AND in `SearchEngine`

**Chosen:** `Finder#search` does unscored substring matching across name/description/tags; `SearchEngine#search` adds field-weighted relevance scoring (name=3, tag=2, description=1) on top. Both are public. AD-07.

**Alternative not taken:** consolidate into one search method with an optional scoring flag.

**Why this trade-off:** the cheap version (`Finder#search`) is the right answer for "is the substring anywhere?" The expensive version is the right answer for "which skill best matches this query?" Keeping both lets callers pick without paying for what they don't use.

**Verdict:** acceptable but slightly redundant. Risk: a future maintainer adds tokenisation to `SearchEngine` and forgets `Finder#search`, leaving a behavioural cliff between the two. Worth a v2 consolidation pass.

### Why v0.1.0 and not v1.0.0?

The version pin tells you everything: the *gem* is feature-complete against its own blueprint (10 epics, 251 tests, zero offenses), but **the ecosystem contract has not been validated in production by any consumer**. Adoption is the v1.0.0 gate. Until at least one sibling repo registers a real skill, calls `find_by_name` from production, and survives a restart cycle, the API surface is not field-tested and v1.0.0 would be premature. The author has correctly resisted that temptation.

---

## 7. Operator playbook

Practical recipes for working with a live registry. All examples assume `registry = WildSkillopsRegistry.build` is held somewhere reachable.

### Run the registry (inside any Ruby host)

```bash
bundle install
bundle exec irb -r wild_skillops_registry
```

```ruby
WildSkillopsRegistry.configure do |c|
  c.max_skills = 500
  c.health_stale_threshold_hours = 6
  c.freeze!
end
registry = WildSkillopsRegistry.build
```

### Inspect entries

```ruby
registry.store.size                              # how many skills are registered
registry.store.names                             # all names
registry.finder.all.map { |e| [e.name, e.lifecycle_state, e.health_status&.state] }
registry.tag_index.all_tags                      # all tags currently indexed
registry.health_aggregator.summary               # registry-wide health rollup
registry.ownership_resolver.unowned_entries.map(&:name)   # governance gap audit
registry.health_aggregator.stale_entries.map(&:name)      # what needs re-checking
```

### Export for review

```ruby
File.write('/tmp/registry.json', registry.json_exporter.export_json(pretty: true))
File.write('/tmp/registry.md',   registry.markdown_exporter.export)
```

Markdown export is sorted alphabetically and renders owner, health, and dependencies per skill — useful for a team review or a weekly state-of-the-registry email.

### Prune

There is no `Registrar#delete`. Lifecycle is the pruning mechanism: `deprecate` then `retire`. Retired skills stay in the store (they are still discoverable via `find_by_lifecycle(:retired)`). If you genuinely need to remove an entry, use `registry.store.delete(name)` and `registry.tag_index.remove_skill(name)` — both are public — but **this bypasses the version manager and ownership resolver**, leaving orphaned history. v2 should expose a proper `Registrar#purge`.

### Recover from a process restart

There is nothing to recover. The store is gone. Recovery is "every consumer re-registers on boot." If consumers are well-behaved, recovery is < 1 second after the host comes back up. If consumers boot in random order, there is a window during which `find_by_*` returns partial data — a consumer that depends on completeness should wait for an agreed-upon "all consumers have registered" signal that this gem **does not provide**.

The honest operational answer right now: design the consumer boot order, or accept eventual consistency, or wait for v2 to add a persistent backing store.

### Diagnose a "skill not found" surprise

1. `registry.store.include?('the.skill.name')` — is it actually registered?
2. `registry.store.names.grep(/partial/)` — is it under a slightly different name?
3. `registry.finder.find_by_repo('wild-foo')` — did the owning repo register anything at all?
4. `registry.tag_index.lookup('the_tag')` — if you were searching by tag, does the inverted index have it? (If the store has the skill but the index doesn't, the tag index drifted — see §5.)

---

## 8. Recommendations for v2

**Lead with consumer adoption.** Every other technical improvement on this list is premature until at least one sibling repo registers real skills against a real registry instance. Until then the gem is solving a hypothetical problem.

### Priority 1 — adoption (the only thing that actually matters)

- Pick `wild-capability-gate` as the **first integration target** (highest mission alignment per §4). Land a PR there that holds a `RegistryFacade`, reads `entry.skill.capabilities_required` on each gate decision, and falls back gracefully when the registry has no entry for the requested skill. Ship it. Take the lessons learned back into the registry API.
- Then `wild-admin-tools-mcp` and `wild-rails-safe-introspection-mcp` in parallel — both are symmetric register-on-boot consumers and exercise the multi-process case.
- Document a `examples/consumer-integration.rb` in this repo showing the canonical "register at boot, health-track on tick, deprecate on shutdown" pattern.

### Priority 2 — durability (after adoption proves the API surface)

- Add a pluggable persistence backend. `Registry::Store` becomes the interface; concrete implementations are `InMemoryStore` (today) and `JsonFileStore` / `SqliteStore` (new). Snapshot on every mutation; restore on `WildSkillopsRegistry.build(persistence: ...)`. Keeps the zero-deps default; persistence is opt-in.
- Or, alternatively: keep the gem pure in-memory and ship a sibling `wild-skillops-registry-persistence` gem that wraps the store. Matches the ecosystem's separation-of-concerns aesthetic.

### Priority 3 — coordination primitives (after Priority 2 proves multi-process is real)

- Lightweight in-process event hooks: `registry.on(:skill_registered) { |entry| ... }`. No external deps; stdlib `Observer` or a tiny inline event dispatcher. Solves the capability-gate prefetch case from T-3.
- Make `Registrar#update` transactional: roll back the `store.add` if `version_manager.record_version` raises `VersionCapacityError` (today the store and version manager can disagree — see §5).
- Add `Registrar#purge` that removes from store, tag index, version history, ownership in one call.

### Priority 4 — API hygiene

- Consolidate `Finder#search` and `SearchEngine#search` (T-5).
- Have `Registrar#update` record a lifecycle-only version snapshot when only `lifecycle_state` changes (today it doesn't — see §3 critical-path note).
- Make `WildSkillopsRegistry.build` accept overrides so test suites can inject a fake `LifecycleManager` or `Store` without rebuilding the full graph.

### What v2 should NOT do

Do not add a network transport, a daemon mode, or an MCP server inside this gem. Those are separate repos by design (see [`CLAUDE.md`](../CLAUDE.md) "What This Repo Does NOT Do"). The registry stays a library. If the ecosystem needs a registry-as-a-service, that is `wild-skillops-registry-mcp` or `wild-skillops-registry-server`, not this gem.

---

## Appendix A — file map for fast navigation

| File | Purpose |
|---|---|
| [`lib/wild_skillops_registry.rb`](../lib/wild_skillops_registry.rb) | Entry point, `.build` factory, `RegistryFacade` |
| [`lib/wild_skillops_registry/configuration.rb`](../lib/wild_skillops_registry/configuration.rb) | Validated freezable config |
| [`lib/wild_skillops_registry/errors.rb`](../lib/wild_skillops_registry/errors.rb) | 7-class error hierarchy |
| [`lib/wild_skillops_registry/registry/store.rb`](../lib/wild_skillops_registry/registry/store.rb) | The hash |
| [`lib/wild_skillops_registry/registry/registrar.rb`](../lib/wild_skillops_registry/registry/registrar.rb) | The only write path |
| [`lib/wild_skillops_registry/registry/finder.rb`](../lib/wild_skillops_registry/registry/finder.rb) | The read path |
| [`lib/wild_skillops_registry/governance/lifecycle_manager.rb`](../lib/wild_skillops_registry/governance/lifecycle_manager.rb) | State machine table |
| [`lib/wild_skillops_registry/health/tracker.rb`](../lib/wild_skillops_registry/health/tracker.rb) | Per-skill health |
| [`lib/wild_skillops_registry/health/aggregator.rb`](../lib/wild_skillops_registry/health/aggregator.rb) | Registry-wide rollup |
| [`lib/wild_skillops_registry/discovery/tag_index.rb`](../lib/wild_skillops_registry/discovery/tag_index.rb) | Inverted tag index |
| [`lib/wild_skillops_registry/discovery/search_engine.rb`](../lib/wild_skillops_registry/discovery/search_engine.rb) | Weighted substring search |
| [`spec/integration/multi_repo_registration_spec.rb`](../spec/integration/multi_repo_registration_spec.rb) | Multi-repo *simulation* (not real adoption) |
| [`000-docs/001-PP-PLAN-repo-blueprint.md`](001-PP-PLAN-repo-blueprint.md) | Mission, boundaries, users |
| [`000-docs/003-AT-ADEC-architecture-decisions.md`](003-AT-ADEC-architecture-decisions.md) | The 8 architecture decisions |
| [`000-docs/006-OD-GUID-operator-guide.md`](006-OD-GUID-operator-guide.md) | Recipes for direct consumers |
