# Omnigraph Cookbooks

Opinionated, ready-to-run graph cookbooks built on [Omnigraph](https://github.com/ModernRelay/omnigraph). Each cookbook is a self-contained schema, seed, and query set for a specific use case.

## Cookbooks

| Cookbook | Status | Description |
|----------|--------|-------------|
| [`industry-intel/`](industry-intel) | ✅ ready | AI/ML industry intelligence graph |
| [`pharma-intel/`](pharma-intel) | ✅ ready | Pharma competitive intelligence |
| [`second-brain/`](second-brain) | ✅ ready | Personal life automation graph |
| [`vc-os/`](vc-os) | ✅ ready | Venture-capital operating system |
| [`dev-graph/`](dev-graph) | ✅ ready | Software-development work: planning, code, release, ops + governance |
| `company-context/` | 🚧 planned | Internal decisions, traces, actors, artifacts |
| `biomed-research/` | 🚧 planned | Biotech & medical research tracking |
| `competitor-intel/` | 🚧 planned | Competitor launches, pricing, positioning |

## Agent Skills

The bootstrap skill ships with the `industry-intel` cookbook it builds from, and installs with the `npx skills` CLI:

| Skill | Description |
|-------|-------------|
| [`industry-intel/skill`](industry-intel/skill) | Bootstrap a new SPIKE graph from scratch — choose demo or custom, elicit domain + sources, adapt schema, research seed content, apply + load |

Install (direct-path form):

```bash
npx skills add https://github.com/ModernRelay/omnigraph-cookbooks/tree/main/industry-intel/skill
```

> **Day-to-day operations** are covered by the **`omnigraph` skill**, which ships in the engine repo (co-versioned with the CLI): `npx skills add ModernRelay/omnigraph@omnigraph` ([ModernRelay/omnigraph](https://github.com/ModernRelay/omnigraph/tree/main/skills/omnigraph)). The operating guide and schema-design docs live in that repo and on the docs site.

Typical flow: use the bootstrap skill once to set up a new graph, then the `omnigraph` skill for day-to-day operations.

## Repo Structure

```
omnigraph-cookbooks/
├── README.md  CLAUDE.md  LICENSE
├── railway.toml  deploy/railway/   ← container deploy (Dockerfile, config)
└── <cookbook>/                     ← industry-intel, pharma-intel, second-brain, vc-os, dev-graph
    ├── README.md
    ├── CLAUDE.md
    ├── schema.pg
    ├── cluster.yaml
    ├── seed.md
    ├── seed.jsonl
    ├── omnigraph-config.example.yaml
    └── queries/*.gq
```

The `industry-intel` cookbook additionally ships the bootstrap skill at
[`industry-intel/skill/`](industry-intel/skill). Each cookbook is fully
self-contained — `cd` in and follow its README.

## Getting Started

1. Pick a cookbook.
2. Make sure you have a running Omnigraph instance — see the [Omnigraph repo](https://github.com/ModernRelay/omnigraph).
3. Follow the cookbook's Quick Start. Every cookbook is a **cluster
   directory** (aligned to omnigraph 0.9.0): `omnigraph cluster apply`
   creates the graph and publishes the stored queries;
   `omnigraph-server --cluster .` serves them — no object store needed to
   get started.

## SPIKE Framework

The `industry-intel/` cookbook uses SPIKE, an opinionated graph modeling lens:

- `Signal`: a dated external fact, movement, or observation
- `Pattern`: a recurring theme formed, contradicted, or driven by signals
- `Insight`: a synthesized interpretation explaining why a pattern matters
- `KnowHow`: an actionable practice or playbook grounded in the graph
- `Element`: a concrete product, framework, company, or concept the signals are about

SPIKE is a cookbook-level convention, not a requirement for every graph in this repo.

## Contributing

Create a new folder, add a schema, seed, queries, and docs. Ship real seed data, not placeholders.
