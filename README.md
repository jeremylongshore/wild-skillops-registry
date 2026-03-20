# wild-skillops-registry

Registry and discovery layer for skills and capabilities across the wild ecosystem.

**Archetype:** D — Coordination / Registry
**Namespace:** `WildSkillopsRegistry`
**Version:** 0.1.0
**Ruby:** >= 3.2.0
**Runtime dependencies:** none

---

## What it does

- **Register** skills/capabilities published by wild ecosystem repos
- **Discover** skills by name, tag, category, repo, lifecycle state, or full-text search
- **Version** skill definitions and build changelogs
- **Track health** per skill (available / degraded / unavailable / unknown) with staleness detection
- **Map dependencies** between skills
- **Manage governance** — lifecycle transitions and ownership assignment
- **Export** the registry as JSON or Markdown

## What it does not do

- Execute skills (repos own their execution)
- Enforce access control (that is `wild-capability-gate`)
- Collect telemetry (that is `wild-session-telemetry`)
- Persist state to disk
- Make network calls

---

## Setup

```ruby
# Gemfile
gem 'wild-skillops-registry'
```

```bash
bundle install
```

---

## Usage

### Build a registry

```ruby
registry = WildSkillopsRegistry.build
```

### Register a skill

```ruby
skill = WildSkillopsRegistry::Models::Skill.new(
  name: 'introspect.schema',
  description: 'Introspects Rails schema at runtime',
  repo: 'wild-rails-safe-introspection-mcp',
  version: '1.0.0',
  tags: %w[introspection schema rails],
  category: :introspection,
  capabilities_required: ['cap:schema:read'],
  lifecycle_state: :draft
)

registry.registrar.register(skill)
```

### Discover skills

```ruby
registry.finder.find_by_name('introspect.schema')
registry.finder.find_by_tag('rails')
registry.finder.find_by_category(:admin)
registry.finder.find_by_repo('wild-admin-tools-mcp')
registry.finder.find_by_lifecycle(:active)
registry.finder.search('schema')             # substring match on name/description/tags
registry.search_engine.search('introspect')  # relevance-scored results
```

### Track health

```ruby
registry.health_tracker.record('introspect.schema', state: :available, message: 'healthy')
registry.health_tracker.stale?('introspect.schema')
registry.health_aggregator.summary
```

### Lifecycle transitions

```ruby
registry.registrar.update('introspect.schema', lifecycle_state: :active)
registry.registrar.deprecate('introspect.schema', reason: 'Replaced by v2')
registry.registrar.retire('introspect.schema')
```

### Ownership

```ruby
registry.ownership_resolver.assign('introspect.schema', team: 'platform', contact: 'eng@example.com')
registry.ownership_resolver.entries_for_team('platform')
registry.ownership_resolver.unowned_entries
```

### Export

```ruby
puts registry.json_exporter.export_json(pretty: true)
puts registry.markdown_exporter.export
puts registry.changelog_builder.build_text('introspect.schema')
```

---

## Configuration

```ruby
WildSkillopsRegistry.configure do |config|
  config.max_skills                   = 2_000
  config.max_versions_per_skill       = 100
  config.health_stale_threshold_hours = 12
end
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `max_skills` | Integer | 1000 | Maximum skills in the registry |
| `max_versions_per_skill` | Integer | 50 | Maximum version snapshots per skill |
| `health_stale_threshold_hours` | Integer | 24 | Hours before a health check is considered stale |
| `allowed_lifecycle_states` | Array[Symbol] | `[:draft, :active, :deprecated, :retired]` | Valid lifecycle states |
| `allowed_health_states` | Array[Symbol] | `[:available, :degraded, :unavailable, :unknown]` | Valid health states |

---

## Build

```bash
bundle install
bundle exec rspec          # 251 examples, 0 failures
bundle exec rubocop        # 0 offenses
bundle exec rake           # default: runs rspec
```

---

## Lifecycle transition rules

| From | To | Allowed? |
|---|---|---|
| `draft` | `active` | Yes |
| `draft` | `retired` | Yes |
| `active` | `deprecated` | Yes |
| `deprecated` | `retired` | Yes |
| `retired` | any | No (terminal) |
| `active` | `draft` | No |
| `draft` | `deprecated` | No |
| `active` | `retired` | No |

---

## Ecosystem

Part of the [wild ecosystem](https://github.com/jeremylongshore). Related repos:

- `wild-capability-gate` — access control gating
- `wild-session-telemetry` — telemetry collection
- `wild-rails-safe-introspection-mcp` — runtime introspection
