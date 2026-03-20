# 004 — Data Contracts: wild-skillops-registry

**Type:** DR-REFF (Data Reference)
**Status:** Current — reflects v0.1.0 implementation

---

## Skill Registration Schema

When calling `Registrar#register`, pass a `Models::Skill` instance. The skill is validated at
construction time. The following table describes every field:

| Field | Type | Required | Default | Constraints |
|-------|------|----------|---------|-------------|
| `name` | String | Yes | — | Non-empty, globally unique in the registry, stripped |
| `description` | String | Yes | — | Non-empty, stripped |
| `repo` | String | Yes | — | Non-empty, stripped (name of wild repo that owns this skill) |
| `version` | String | Yes | — | Must match `/\A\d+\.\d+\.\d+/` (semver x.y.z) |
| `tags` | Array[String] | No | `[]` | Strings only, normalized to lowercase+stripped |
| `category` | Symbol | No | `:workflow` | One of the VALID_CATEGORIES (see below) |
| `capabilities_required` | Array[String] | No | `[]` | Strings only |
| `lifecycle_state` | Symbol | No | `:draft` | One of allowed_lifecycle_states |
| `registered_at` | Time | No | `Time.now` | Set by registry, not caller |

### Valid categories

```
:introspection  :admin  :telemetry  :analysis  :workflow  :governance
```

---

## SkillVersion Schema

Recorded automatically by `VersionManager#record_version`. Not directly constructed by callers.

| Field | Type | Description |
|-------|------|-------------|
| `skill_name` | String | Name of the skill this version belongs to |
| `version` | String | Version string at the time of this snapshot |
| `changes` | Array[String] | Human-readable change descriptions |
| `created_at` | Time | When this version was recorded |

---

## Dependency Schema

Callers may attach dependencies to entries via `Models::Dependency`. The registrar does not
manage dependencies automatically — dependencies are stored in `RegistryEntry#dependencies`.

| Field | Type | Required | Default | Constraints |
|-------|------|----------|---------|-------------|
| `skill_name` | String | Yes | — | Non-empty |
| `depends_on` | String | Yes | — | Name of the required skill |
| `dependency_type` | Symbol | No | `:required` | One of `:required`, `:optional` |
| `description` | String | No | `nil` | Optional human description |

---

## HealthStatus Schema

Created by `Health::Tracker#record`.

| Field | Type | Description |
|-------|------|-------------|
| `skill_name` | String | Name of the skill |
| `state` | Symbol | One of `allowed_health_states` (default: `:available`, `:degraded`, `:unavailable`, `:unknown`) |
| `last_checked_at` | Time | When the health was last recorded |
| `message` | String\|nil | Optional message (e.g. error description) |
| `stale?` | Boolean | Computed — true if `(now - last_checked_at) > health_stale_threshold_hours * 3600` |

---

## Owner Schema

Created by `Governance::OwnershipResolver#assign`.

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `skill_name` | String | Yes | Non-empty |
| `team` | String | Yes | Non-empty |
| `contact` | String\|nil | No | Optional email or handle |

---

## RegistryEntry Schema (read view)

Returned by all `Finder` and `Registrar` methods.

| Field | Type | Description |
|-------|------|-------------|
| `skill` | Models::Skill | The current skill definition |
| `versions` | Array[SkillVersion] | All recorded version snapshots |
| `health_status` | HealthStatus\|nil | Current health, nil if not recorded |
| `owner` | Owner\|nil | Current owner, nil if not assigned |
| `dependencies` | Array[Dependency] | Declared dependencies, empty by default |

### to_h output (JSON export shape)

```json
{
  "skill": {
    "name": "introspect.schema",
    "description": "Introspects Rails schema at runtime",
    "repo": "wild-rails-safe-introspection-mcp",
    "version": "1.2.0",
    "tags": ["introspection", "schema", "rails"],
    "category": "introspection",
    "capabilities_required": ["cap:schema:read"],
    "lifecycle_state": "active",
    "registered_at": "2024-06-01T12:00:00Z"
  },
  "versions": [
    { "skill_name": "introspect.schema", "version": "1.0.0", "changes": ["Initial registration"], "created_at": "..." },
    { "skill_name": "introspect.schema", "version": "1.2.0", "changes": ["version bumped to 1.2.0"], "created_at": "..." }
  ],
  "health_status": {
    "skill_name": "introspect.schema",
    "state": "available",
    "last_checked_at": "2024-06-01T14:00:00Z",
    "message": null,
    "stale": false
  },
  "owner": { "skill_name": "introspect.schema", "team": "platform", "contact": "eng@example.com" },
  "dependencies": []
}
```

---

## Error Hierarchy

| Error Class | Superclass | Raised When |
|-------------|------------|-------------|
| `ValidationError` | `Error` | Skill field is invalid at construction |
| `NotFoundError` | `Error` | Referenced skill not in registry |
| `DuplicateSkillError` | `Error` | Registering a name that already exists |
| `LifecycleError` | `Error` | Invalid lifecycle transition attempted |
| `ConfigurationFrozenError` | `Error` | Modifying configuration after `freeze!` |
| `RegistryCapacityError` | `Error` | Registry at `max_skills` limit |
| `VersionCapacityError` | `Error` | Skill at `max_versions_per_skill` limit |
