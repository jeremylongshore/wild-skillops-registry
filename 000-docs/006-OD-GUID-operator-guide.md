# 006 — Operator Guide: wild-skillops-registry

**Type:** OD-GUID (Operator Guide)
**Status:** Current — reflects v0.1.0 implementation

---

## Overview

This guide covers practical workflows for operators using `wild-skillops-registry`.

---

## 1. Setup and configuration

```ruby
require 'wild_skillops_registry'

WildSkillopsRegistry.configure do |config|
  config.max_skills                   = 500
  config.health_stale_threshold_hours = 6
end

registry = WildSkillopsRegistry.build
```

The `registry` object exposes all subsystems. Hold it as a long-lived object in your process.

---

## 2. Registering skills from a repo

Each wild repo should register its skills at startup or during a setup step:

```ruby
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

registry.registrar.register(skill)
```

Activate after validation:

```ruby
registry.registrar.update('hook.trigger', lifecycle_state: :active)
```

---

## 3. Discovering skills

```ruby
# By name
entry = registry.finder.find_by_name('hook.trigger')

# By tag
hooks_skills = registry.finder.find_by_tag('hooks')

# By category
workflow_skills = registry.finder.find_by_category(:workflow)

# By repo
hook_ops_skills = registry.finder.find_by_repo('wild-hook-ops')

# By lifecycle state
active_skills = registry.finder.find_by_lifecycle(:active)

# Substring search (returns results ordered by relevance)
results = registry.search_engine.search('trigger')
```

---

## 4. Recording health

Call this after each deployment or health check cycle:

```ruby
registry.health_tracker.record('hook.trigger', state: :available, message: 'All good')
registry.health_tracker.record('hook.trigger', state: :degraded, message: 'Response P99 > 500ms')
registry.health_tracker.record('hook.trigger', state: :unavailable, message: 'Service down')
```

Check staleness:

```ruby
registry.health_tracker.stale?('hook.trigger')  # true if > threshold hours since last check
```

Get a registry-wide summary:

```ruby
summary = registry.health_aggregator.summary
# => {
#   total_skills: 12,
#   tracked: 9,
#   untracked: 3,
#   counts: { available: 7, degraded: 1, unavailable: 1, unknown: 0 },
#   stale_count: 2
# }

# Find stale entries to re-check:
registry.health_aggregator.stale_entries.each do |entry|
  puts "#{entry.name} — health not checked recently"
end

# Find untracked (never had health recorded):
registry.health_aggregator.untracked_entries.map(&:name)
```

---

## 5. Lifecycle management

Valid transitions: `draft -> active`, `draft -> retired`, `active -> deprecated`, `deprecated -> retired`.

```ruby
# Promote to active
registry.registrar.update('hook.trigger', lifecycle_state: :active)

# Deprecate with reason
registry.registrar.deprecate('hook.trigger', reason: 'Replaced by hook.trigger.v2')

# Retire
registry.registrar.retire('hook.trigger')
```

Invalid transitions raise `LifecycleError`. Retired skills are terminal — no further transitions.

---

## 6. Ownership assignment

```ruby
registry.ownership_resolver.assign('hook.trigger', team: 'platform', contact: 'ops@example.com')

# Check who owns a skill:
owner = registry.ownership_resolver.owner_for('hook.trigger')
puts "#{owner.team} (#{owner.contact})"

# Find all skills owned by a team:
registry.ownership_resolver.entries_for_team('platform').map(&:name)

# Find unowned skills:
registry.ownership_resolver.unowned_entries.map(&:name)
```

---

## 7. Exporting the registry

```ruby
# Full JSON export (pretty-printed)
puts registry.json_exporter.export_json(pretty: true)

# Single skill JSON
puts registry.json_exporter.export_skill('hook.trigger')

# Full Markdown catalog
puts registry.markdown_exporter.export

# Single skill Markdown
puts registry.markdown_exporter.export_skill('hook.trigger')

# Changelog for a skill
puts registry.changelog_builder.build_text('hook.trigger')
```

---

## 8. Reading the health summary

The health summary `counts` hash uses the configured `allowed_health_states` as keys.
Default keys: `:available`, `:degraded`, `:unavailable`, `:unknown`.

```ruby
summary = registry.health_aggregator.summary
puts "#{summary[:counts][:available]} healthy"
puts "#{summary[:counts][:degraded]} degraded"
puts "#{summary[:stale_count]} stale entries need re-checking"
puts "#{summary[:untracked]} skills have no health data"
```

---

## 9. Tag-based exploration

```ruby
# All tags indexed in the registry
registry.tag_index.all_tags

# All skills with a given tag
registry.finder.find_by_tag('rails').map(&:name)
```

---

## 10. Error handling reference

```ruby
begin
  registry.registrar.register(skill)
rescue WildSkillopsRegistry::DuplicateSkillError => e
  # Name already registered
rescue WildSkillopsRegistry::ValidationError => e
  # Skill fields failed validation
rescue WildSkillopsRegistry::RegistryCapacityError => e
  # Registry is full
end

begin
  registry.registrar.deprecate('my.skill')
rescue WildSkillopsRegistry::LifecycleError => e
  # Transition not allowed from current state
rescue WildSkillopsRegistry::NotFoundError => e
  # Skill not found
end
```
