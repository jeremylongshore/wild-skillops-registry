# 001 — Repo Blueprint: wild-skillops-registry

**Type:** PP-PLAN (Planning)
**Status:** Complete — implemented at v0.1.0

---

## Mission

`wild-skillops-registry` is the canonical registry and discovery layer for skills and capabilities
published by wild ecosystem repositories. It provides discoverability, versioning, health tracking,
and governance so that any consumer in the ecosystem can answer: "What skills exist, where do they
live, what state are they in, and who owns them?"

---

## Boundaries

### In scope

- Registering skill definitions from any wild ecosystem repo
- Querying skills by name, tag, category, repo, lifecycle state, full-text
- Tracking health state (available/degraded/unavailable/unknown) with staleness detection
- Versioning skill definitions as they evolve
- Lifecycle governance (draft/active/deprecated/retired) with enforced transitions
- Ownership assignment per skill
- Dependency mapping between skills
- Exporting the registry as JSON or Markdown

### Out of scope

- Skill execution (each repo executes its own skills)
- Access control enforcement (that is `wild-capability-gate`)
- Telemetry collection (that is `wild-session-telemetry`)
- Persistence to disk or database
- Network communication
- MCP server or HTTP service

---

## Users

| User | How They Use This |
|------|------------------|
| Wild ecosystem repos | Register skills they own, update them as they evolve |
| Operators | Query the registry to understand what skills exist and their health |
| `wild-capability-gate` | Read skill `capabilities_required` to make gating decisions |
| Governance tooling | Enforce lifecycle rules, audit ownership coverage |

---

## Use Cases

1. A new repo (`wild-hook-ops`) comes online and registers three skills it owns
2. An operator queries all skills tagged `admin` to understand admin surface area
3. A CI pipeline records health status after deploying a skill update
4. A governance script finds all skills with no assigned owner
5. A developer exports the full registry as Markdown for team review
6. A deprecation workflow transitions `hook.trigger` from active to deprecated
7. An aggregation dashboard reads health summary counts per state
