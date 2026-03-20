# 003 — Architecture Decisions: wild-skillops-registry

**Type:** AT-ADEC (Architecture Decision Record)
**Status:** Current — reflects v0.1.0 implementation

---

## AD-01: Single in-memory store as source of truth

**Decision:** All subsystems read from and write back to `Registry::Store`. No subsystem holds
its own copy of a `RegistryEntry`. Updates always replace the full entry.

**Rationale:** Avoids split-brain state where health tracker and ownership resolver hold different
versions of the same entry. All reads see consistent state by going through one store.

**Trade-off:** Entry replacement is slightly less efficient than field mutation. Acceptable for
expected registry sizes (< 10,000 skills) and avoids a class of bugs.

---

## AD-02: RegistryFacade as the public API surface

**Decision:** `WildSkillopsRegistry.build` returns a single `RegistryFacade` struct that exposes
all subsystems as named accessors.

**Rationale:** Callers should not wire subsystems themselves. The facade makes the dependency
graph explicit and testable. It is a struct (attr_readers + initialize via kwargs) rather than a
service locator, so callers can use any subset.

**Trade-off:** Facade grows proportionally with subsystems. If it becomes unwieldy, split into
domain-specific facades (discovery facade, governance facade, etc.).

---

## AD-03: Registrar owns all coordination for writes

**Decision:** `Registrar` is the only object that touches the store AND the version manager AND
the tag index in a single operation.

**Rationale:** Ensures these three concerns stay in sync. If they were updated separately by
callers, tag index could drift from store contents.

**Interface contract:** Any code path that modifies a `Skill` must go through `Registrar`.
Direct store writes that bypass `Registrar` are unsafe by design.

---

## AD-04: TagIndex is a separate inverted index, not derived from store

**Decision:** `TagIndex` maintains its own hash of `tag -> [skill_names]`. It is kept in sync
by the registrar at register, update, and deprecate/retire time.

**Rationale:** O(1) tag lookup without scanning all entries. Trade-off is that it must be kept
in sync by the registrar. The reindex operation handles tag set changes atomically.

**Consistency rule:** `TagIndex#reindex` (not `#index`) must be used for updates to prevent
stale entries accumulating.

---

## AD-05: Lifecycle transitions are enforced centrally

**Decision:** `LifecycleManager` owns a static transition table. All state changes must call
`transition!` first. The manager is stateless — it does not hold the skill, only validates
and returns the target state.

**Rationale:** Keeps the transition rule set in one place. Prevents duplicated guard logic
across registrar, registrar update, deprecate, and retire.

**Permitted transitions:**
```
draft      -> active, retired
active     -> deprecated
deprecated -> retired
retired    -> (terminal)
```

---

## AD-06: Health updates replace entries; no separate health store

**Decision:** `Health::Tracker#record` rebuilds the `RegistryEntry` with a new `HealthStatus`
and writes it back to the store.

**Rationale:** Keeps the store as the single source of truth. Avoids a second map keyed on
skill name that could drift.

**Trade-off:** Slightly more allocation per health update. Negligible at expected scale.

---

## AD-07: SearchEngine wraps Finder; Finder#search is still public

**Decision:** `Finder#search` does basic substring matching. `SearchEngine#search` adds
relevance scoring on top by calling `Finder#all` directly.

**Rationale:** Keeps Finder's search useful for simple cases without requiring a SearchEngine.
SearchEngine is the recommended API for user-facing queries.

**Search field weights:**
- Name match: 3 points
- Tag match: 2 points
- Description match: 1 point

---

## AD-08: Zero runtime dependencies

**Decision:** The gem has no runtime gem dependencies. Only Ruby stdlib.

**Rationale:** Registry library should be embeddable without pulling in additional transitive
dependencies. Ecosystem repos can use it without worrying about version conflicts.
