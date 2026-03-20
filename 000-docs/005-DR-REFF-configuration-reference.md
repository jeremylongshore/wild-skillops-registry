# 005 — Configuration Reference: wild-skillops-registry

**Type:** DR-REFF (Configuration Reference)
**Status:** Current — reflects v0.1.0 implementation

---

## Configuration Object

`WildSkillopsRegistry::Configuration` — accessed via `WildSkillopsRegistry.configuration`.

Configure before calling `WildSkillopsRegistry.build`:

```ruby
WildSkillopsRegistry.configure do |config|
  config.max_skills                   = 2_000
  config.max_versions_per_skill       = 100
  config.health_stale_threshold_hours = 12
end

registry = WildSkillopsRegistry.build
```

---

## Parameters

### `max_skills`

| Property | Value |
|----------|-------|
| Type | Integer |
| Default | `1_000` |
| Minimum | 1 |
| Error | `ArgumentError` if zero or negative |

Maximum number of skills the registry will hold. Once reached, registering a new skill name
raises `RegistryCapacityError`. Updating an existing skill never counts against this limit.

---

### `max_versions_per_skill`

| Property | Value |
|----------|-------|
| Type | Integer |
| Default | `50` |
| Minimum | 1 |
| Error | `ArgumentError` if zero or negative |

Maximum number of version snapshots stored per skill. Once reached, attempting to record
another version raises `VersionCapacityError`. The initial registration counts as version 1.

---

### `health_stale_threshold_hours`

| Property | Value |
|----------|-------|
| Type | Integer |
| Default | `24` |
| Minimum | 1 |
| Error | `ArgumentError` if zero or negative |

Hours after which a recorded health status is considered stale. `HealthStatus#stale?` returns
`true` when `(Time.now - last_checked_at) > (threshold * 3600)`. The aggregator uses this to
compute `stale_count` in its summary.

---

### `allowed_lifecycle_states`

| Property | Value |
|----------|-------|
| Type | `Array[Symbol]` |
| Default | `%i[draft active deprecated retired]` |
| Minimum | 1 element |
| Error | `ArgumentError` if empty or contains non-Symbol/String values |

Symbols representing valid lifecycle states. The lifecycle manager validates transitions only
against states in this list. Modifying this list does not change the transition graph — that
is defined in `Governance::LifecycleManager::LIFECYCLE_TRANSITIONS`.

---

### `allowed_health_states`

| Property | Value |
|----------|-------|
| Type | `Array[Symbol]` |
| Default | `%i[available degraded unavailable unknown]` |
| Minimum | 1 element |
| Error | `ArgumentError` if empty or contains non-Symbol/String values |

Symbols representing valid health states. `HealthStatus` validates its `state` argument against
this list at construction time.

---

## freeze!

After calling `configuration.freeze!`, all setters raise `ConfigurationFrozenError`. This is
intended for production use where configuration should be locked after initialization.

```ruby
WildSkillopsRegistry.configure { |c| c.max_skills = 5_000 }
WildSkillopsRegistry.configuration.freeze!

# Later attempts to modify will raise:
WildSkillopsRegistry.configure { |c| c.max_skills = 1 }
# => WildSkillopsRegistry::ConfigurationFrozenError
```

---

## reset_configuration!

Replaces the configuration with a fresh default instance. Used in tests via the `before` block
in `spec_helper.rb`. Do not call in production code.

```ruby
WildSkillopsRegistry.reset_configuration!
```
