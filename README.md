# Omnigraph Starters

A collection of opinionated, ready-to-run graph starters built on [Omnigraph](https://github.com/ModernRelay/omnigraph). Each starter is a self-contained schema + seed + query set for a specific use case.

Starters use whatever schema fits the domain — some apply the SPIKE intelligence framework, others use their own domain model.

## Starters

| Starter | Framework | Status | Description |
|---------|-----------|--------|-------------|
| [`industry-intel/`](./industry-intel) | SPIKE | ✅ ready | AI/ML industry intelligence — patterns, signals, elements, companies |
| `company-context/` | Decision ledger | 🚧 planned | Internal company context — decisions, traces, actors, artifacts |
| `biomed-research/` | SPIKE | 🚧 planned | Biotech & medical research tracking — trials, therapeutics, mechanisms |
| `competitor-intel/` | SPIKE | 🚧 planned | Competitor intelligence — launches, pricing moves, positioning shifts |

## Frameworks

### SPIKE (intelligence mapping)

Maps complex, fast-moving domains into a graph of **Signals, Patterns, Insights, Know-Hows, and Elements**.

| Primitive | Question | Look for |
|-----------|----------|----------|
| **SIGNAL** | What just moved? | weak signal, data point, evidence |
| **PATTERN** | Is this movement persistent? | trends, shifts, contradictions |
| **INSIGHT** | How does this shift our perspective? | new paradigm, second-order effect |
| **KNOW-HOW** | How can we adopt it? | best practice, protocol |
| **ELEMENT** | What makes it possible? | product, framework, concept |

Good fit for: AI, Biotech, Fintech, Crypto, Geopolitics, Macroeconomics — anywhere complex, fast-moving, and worth mapping. The framework stays the same; only the seed data changes.

See [`industry-intel/README.md`](./industry-intel/README.md) for a worked example.

### Other frameworks

Starters aren't required to use SPIKE. A decision-ledger starter (Actor / Decision / Trace / Artifact) models internal company context; a CRM-shaped starter would model accounts, contacts, and touchpoints. The repo is a home for whatever graph shapes prove useful.

## Repo Structure

```
omnigraph-starters/
├── README.md              ← you are here
├── CLAUDE.md              ← repo-wide agent guidance
├── industry-intel/        ← starter
│   ├── README.md
│   ├── CLAUDE.md
│   ├── schema.pg
│   ├── seed.md
│   ├── seed.jsonl
│   ├── omnigraph.yaml
│   ├── .env.omni          (gitignored)
│   └── queries/*.gq
└── <more starters>/
```

Each starter folder is fully self-contained — you `cd` into it to work with it.

## Getting Started

1. Pick a starter — see [`industry-intel/README.md`](./industry-intel/README.md) as the reference example.
2. Make sure you have a running Omnigraph instance — see the [Omnigraph repo](https://github.com/ModernRelay/omnigraph).
3. Follow the starter's own Quick Start section.

## Contributing a New Starter

1. Create a new folder (e.g. `biomed-research/`)
2. Add `schema.pg`, `README.md`, `CLAUDE.md`, `omnigraph.yaml`, and `queries/`
3. Seed data goes in `seed.md` (tabular, human-readable) + `seed.jsonl` (Omnigraph load format)
4. Pick the schema shape that fits the domain — reuse SPIKE primitives if they fit, design something else if they don't
5. Add the starter to the table above with its framework

The point of a starter is that it's opinionated and ready-to-run, not generic. Commit to a domain, seed it with real data, ship it.
