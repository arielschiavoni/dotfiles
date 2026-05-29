---
name: d2-diagrams
description: Create polished software architecture and system diagrams with D2 (d2lang) and export to SVG/PNG. Use when the user wants a presentation-grade architecture diagram, system/component/infrastructure diagram, container diagram, deployment topology, or asks for D2 specifically.
---

# D2 Diagrams

Author architecture diagrams as code in D2 (https://d2lang.com). D2 has strong
auto-layout and produces clean, presentation-grade SVG/PNG, which makes it the
preferred choice for software architecture and infrastructure visuals.

## When to use D2 vs Mermaid

- **D2 (this skill)**: polished architecture / system / component /
  infrastructure / deployment diagrams, especially when exported to SVG/PNG for
  docs or slides, or when auto-layout matters.
- **Mermaid (`mermaid-diagrams` skill)**: flows that should render inline on
  GitHub/Markdown - flowcharts, sequence, state, ER, class diagrams.

## Workflow

1. **Understand the subject.** Read the relevant source, IaC, or docs first so
   the diagram reflects the real system (services, data stores, boundaries).
2. **Write a `.d2` source file.** Model nodes, containers, and connections.
3. **Render / validate** with the `d2` binary (already installed):
   ```bash
   d2 architecture.d2 architecture.svg            # render SVG
   d2 --layout elk architecture.d2 out.svg        # ELK layout for complex graphs
   d2 architecture.d2 architecture.png            # PNG export
   d2 fmt architecture.d2                          # format the source
   d2 --watch architecture.d2 out.svg             # live preview while iterating
   ```
   A failed render is also a syntax check - fix errors before presenting.

## Conventions

- Keep the `.d2` source in the repo as the source of truth; commit exported
  images only when they are meant to be viewed without tooling.
- Use containers (`group: { ... }`) to express boundaries (VPCs, services,
  modules) and nesting.
- Prefer the default (`dagre`) layout for small graphs; switch to
  `--layout elk` when edges cross heavily or the graph is large.
- Label connections to describe protocols/intent (e.g. `db -> cache: read-through`).

## Quick reference

```d2
client: Client
api: API Gateway

services: {
  auth: Auth Service
  orders: Orders Service
}

db: PostgreSQL { shape: cylinder }
cache: Redis { shape: cylinder }

client -> api: HTTPS
api -> services.auth: validate token
api -> services.orders: place order
services.orders -> db: read/write
services.orders -> cache: cache lookup
```
