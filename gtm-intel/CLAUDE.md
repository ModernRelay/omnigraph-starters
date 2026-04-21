# CLAUDE.md — gtm-intel

Scoped guidance for the `gtm-intel/` starter. Repo-wide conventions live in `../CLAUDE.md`.

## What This Is

A general-purpose GTM intelligence starter: Omnigraph schema + illustrative seed + a Parallel Task API adapter. Workload-centric (not headcount-centric), bitemporal-by-default via Claim/ResearchRun provenance, designed to *feed* a CRM rather than mirror one.

The seed roster (Cursor, Suno, Cognition, …) is illustrative — shaped so the `lookalikes` query returns a clean result. Forks are expected to swap the seed and the `demo/enrich.py` output schema for their own wedge.

## Key Files

- `schema.pg` — Executable Omnigraph schema. Source of truth.
- `README.md` — Aha query, ontology, quick start.
- `seed.md` / `seed.jsonl` — Illustrative roster (15 accounts, 31 investors, 2 research runs, 7 claims).
- `queries/*.gq` — Read and mutation queries.
- `omnigraph.yaml` — CLI config with aliases.
- `demo/enrich.py` — Parallel Task API → Omnigraph patch.

## Domain Model

**Core entities:** Account, Product, Workload, WorkloadCategory, SpendEstimate, Investor, FundingRound, TechSignal
**Provenance layer:** ResearchRun, Claim, Source

**Canonical traversal:** `Account → Product → Workload → SpendEstimate`. Every read about what an account is "worth" uses this path. Workload — not headcount — is the pivot.

**Claim lineage:** Every Claim is asserted by exactly one ResearchRun (which carries `promptVersion` + `schemaVersion`). Claims are immutable; change is modeled as a new Claim plus a `Supersedes` edge to the old one.

**Account status is illustrative.** `customer | opportunity | prospect | cold` labels on seeded accounts are chosen to make the lookalike query return compelling results, not to reflect any real-world customer relationships.

## Design choices to preserve

- **Flat `kind` enum on Product** — no subtypes or interfaces.
- **Workload as a first-class node** — not a property on Account.
- **WorkloadCategory as a reference node**, not a `kind` enum on Workload — "same kind of workload" becomes a shared-node join in queries instead of a cross-variable comparison. Slug prefix: `wlc-`.
- **Investor as a first-class node** — not a string tag.
- **No CRM mirror** — no Opportunity, Stage, Activity, or Contact node types. The graph feeds CRMs; it doesn't replace them.
- **Edges follow `VerbTargetType` naming** — `BuildsProduct`, `InvestsIn`, `AssertedClaim`.
- **`slug` is external identity everywhere.** Prefixes: `acct-`, `prod-`, `wl-`, `wlc-`, `spend-`, `inv-`, `round-`, `tsig-`, `run-`, `claim-`, `src-`.
- **Source uses `url` as `@unique`** in addition to `slug @key` — URLs are globally unique and the demo uses deterministic URL-derived source slugs to keep re-runs idempotent.

## The two aha queries

1. **Lookalike prospecting** (`queries/lookalikes.gq`) — prospects sharing investor + workload with a customer, ranked by spend.
2. **Claim drift** (`queries/claims.gq`) — how did one predicate's value change across prompt versions?

If someone asks "why Omnigraph instead of Snowflake" these two queries are the answer.

## Validation

```bash
omnigraph query lint --schema ./schema.pg --query ./queries/lookalikes.gq
```

Run `lint` against every `.gq` after schema or query edits.

## When Editing

- Keep README.md in sync with schema.pg and seed roster.
- If you add a new node type, make sure its `add-<name>` and link aliases exist in `omnigraph.yaml` and that the demo script can write them if relevant.
- Don't add backwards-compat shims. Use `@rename_from(...)` for property/type renames.
- Prefer narrower types: enums over strings, Date over String, I64 over String for currency.
