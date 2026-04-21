# GTM Intel — a graph-shaped account intelligence starter

A starter for GTM teams that want **one queryable graph** of their accounts, products, usage profile, investors, spend estimates, and the research that produced every fact — instead of five Snowflake tables and a pile of Hex notebooks.

Built on [Omnigraph](https://github.com/ModernRelay/omnigraph). Enrichment powered by the [Parallel Task API](https://docs.parallel.ai/task-api/task-quickstart). Swap the seed for your own accounts; keep the shape.

> The 15 accounts shipped as seed are real companies, but their `status` labels (customer / prospect / cold) are illustrative — chosen so the demo query returns a clean result. Swap in your own CRM snapshot to make it yours.

## Why this exists

Every GTM data team ends up in the same place:

- Clearbit / ZoomInfo / Apollo give you firmographics that are **flat, stale, and uncited**.
- Your CRM has opportunities but no idea what an account actually *runs* or who co-invests with whom.
- Snowflake joins across "account × investor × product × usage" turn into 6-way self-joins that nobody re-writes on demand.
- LLM enrichment workflows produce plausible strings with no provenance — you can't tell "Series C" from last month's blog post from "Series C" from today's filing.

So every "who looks like our best customer?" or "which accounts did the most recent news cycle affect?" question becomes an ad-hoc Hex notebook. Repeat forever.

**This starter proposes a different shape.** A graph where:

- **Usage/workload is the pivot, not headcount.** What an account *runs* predicts spend far better than how many people it has.
- **Investors are first-class nodes**, not comma-separated strings — because shared cap tables are one of the strongest lookalike signals you have.
- **Every fact is a `Claim`** with a pointer to the `ResearchRun` that produced it, its prompt version, its confidence, its reasoning, and the source URL. Prompt drift is auditable for free.
- **No CRM mirror.** Salesforce owns Opportunities, Stages, Activities. This graph feeds the CRM; it doesn't replace it.

## The aha

One graph query. Six self-joins in Snowflake. Runs in <100ms on the seed:

```bash
omnigraph read --alias lookalikes
```

> Find every prospect that shares **both an investor and a workload category** with an existing customer, ranked by the prospect's bottoms-up annual spend on that workload.

On the shipped seed:

| Prospect | Shared investor | Workload | Est. $/yr | Looks like |
|---|---|---|---|---|
| Cognition (Devin) | Founders Fund | sandbox | $12.0M | Cursor |
| Pika Labs | Lightspeed | inference | $6.5M | Suno |
| Factory | Sequoia | sandbox | $3.0M | Sourcegraph (Amp) |
| Krea | Matrix Partners | inference | $2.1M | Suno |

Cognition tops the list because we already sell into one of its co-investors' portfolio — Cursor — and it runs the same category of workload at higher volume. **That's an outbound list ranked by expected revenue, not by data volume.**

The equivalent SQL is left as an exercise for whoever owns the Fivetran pipeline.

## What the graph looks like

```
      InvestsIn            ObservedTechSignal
   ┌───────────┐          ┌─────────────────┐
   │           ▼          ▼                 │
┌────────┐  ┌──────────┐  Builds  ┌─────────┐  Drives  ┌──────────┐  OfKind  ┌────────────────┐
│Investor│─▶│ Account  │─────────▶│ Product │─────────▶│ Workload │─────────▶│WorkloadCategory│
└────────┘  └──────────┘          └─────────┘          └──────────┘          └────────────────┘
    │         │                                            │
 LedRound     │ RaisedRound                          EstimatedBy
    ▼         ▼                                            ▼
 ┌──────────────┐                                  ┌──────────────┐
 │ FundingRound │                                  │ SpendEstimate│
 └──────────────┘                                  └──────────────┘

           ┌─────────────┐  TriggeredBy  ┌───────────┐
           │ ResearchRun │──────────────▶│ TechSignal│
           └─────────────┘               └───────────┘
                │ AssertedClaim
                ▼
             ┌──────┐  AboutAccount ─▶ Account
             │Claim │  AboutProduct ─▶ Product
             └──────┘  GroundedInSource ─▶ Source
                │ Supersedes ─▶ Claim
                ▼
```

### Nodes

- **Account** — `status: customer | opportunity | prospect | cold`
- **Product** — what the account ships (`kind: coding-agent | consumer-agent | foundation-model | vertical-saas | …`)
- **Workload** + **WorkloadCategory** — *what that product runs as*: `training | inference | sandbox | batch | eval | data-pipeline`. Workload is per-account; WorkloadCategory is a shared reference node so "same kind of workload" is a graph join, not a string compare.
- **SpendEstimate** — `annualUSD`, `method: bottoms-up | headcount-derived | self-reported`, `confidence`
- **Investor** / **FundingRound** / **LedRound** / **RaisedRound**
- **TechSignal** — dated observables (funding, hiring, launches). Monitor API writes here.
- **ResearchRun** — one enrichment execution; carries `promptVersion` + `schemaVersion`
- **Claim** — one asserted fact (e.g. `headcount = 268`). Immutable. Change = new Claim + `Supersedes` edge.
- **Source** — URL-level provenance; every Claim can ground in many Sources.

### Design choices worth preserving when you fork it

1. **Workload is the pivot.** `Account → Product → Workload → SpendEstimate` is the canonical traversal. Every "what is this account worth?" read uses it.
2. **Claim + ResearchRun = bitemporal.** `validFrom/validTo` on Claim + `ranAt` + version tags on ResearchRun means prompt iteration is auditable. Change the prompt, re-run, diff the Claims — no Snowflake-table history-table ceremony.
3. **Investor is a first-class node.** Shared cap tables are the single strongest lookalike predictor on this dataset. Hard to express as a string.
4. **No CRM mirror.** No `Opportunity`, `Stage`, `Activity`, `Contact` types. This graph *feeds* your CRM — stays small and focused.

## Provenance, for real

Every fact in the graph answers four questions without leaving the graph:

1. **Who says?** → `Claim → GroundedInSource → Source.url`
2. **How confident?** → `Claim.confidence` (straight from Parallel's `FieldBasis`)
3. **Which prompt version produced this?** → `Claim ← AssertedClaim ← ResearchRun.promptVersion`
4. **When did it change?** → `Supersedes` chain + `ResearchRun.ranAt`

Run one query to see it:

```bash
omnigraph read --alias claim-drift acct-cognition headcount
```

```
old.value | new.value | rOld.promptVersion | rNew.promptVersion | rOld.ranAt                | rNew.ranAt
----------+-----------+--------------------+--------------------+---------------------------+---------------------------
35        | 72        | v3                 | v4                 | 2026-02-15T09:00:00.000Z  | 2026-04-15T09:00:00.000Z
```

One prompt bump later, `35 → 72` employees, with the reasoning and source URL still attached on both sides.

## Quick Start

Prerequisite: Omnigraph ≥ 0.2.2 installed (`brew install modernrelay/tap/omnigraph` or see [repo](https://github.com/ModernRelay/omnigraph)).

```bash
cd gtm-intel

# Lint schema + queries (file-only, no server needed)
omnigraph query lint --schema ./schema.pg --query ./queries/lookalikes.gq

# One-time init + load the illustrative seed (local path or s3://)
omnigraph init --schema ./schema.pg /tmp/gtm-intel/repo
omnigraph load --data ./seed.jsonl --mode overwrite /tmp/gtm-intel/repo

# Start the server (keep it running)
omnigraph-server --bind 127.0.0.1:8090 /tmp/gtm-intel/repo &

# The aha
omnigraph read --alias lookalikes

# "Who looks like Cursor?"
omnigraph read --alias lookalikes-for acct-cursor

# What does this account actually run?
omnigraph read --alias account-workload acct-cognition

# Top spenders in a given workload category
omnigraph read --alias top-spend wlc-sandbox

# Claim lineage — what changed across prompt versions?
omnigraph read --alias claim-drift acct-cognition headcount

# Every Claim from one ResearchRun
omnigraph read --alias run-output trun_demo_v4_apr
```

To deploy against shared RustFS / S3 storage, replace the local path with `s3://...` and source credentials from `.env.omni`.

## Live enrichment — Parallel Task API → graph

The real value isn't the seed — it's that *every* Parallel Task run can write into this graph with full FieldBasis provenance preserved.

```bash
cd demo
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export PARALLEL_API_KEY=...

python enrich.py --accounts acct-cognition acct-factory
# → out/claims-run-<stamp>.jsonl

omnigraph load --data demo/out/claims-run-<stamp>.jsonl --mode merge /tmp/gtm-intel/repo
omnigraph read --alias claims-for acct-cognition
```

What `enrich.py` does, per account:

1. Fires one `task_run.create` with a **typed output schema** (`headcount`, `latest_funding_stage`, `primary_workload_kind`, `estimated_annual_revenue_usd`, …).
2. Reads the result's `output.content` + `output.basis` — Parallel returns one `FieldBasis` per field with `confidence`, `reasoning`, and `citations[].url`.
3. Emits **one `Claim` node per field**, one `Source` node per citation URL (deterministic slug via `uuid5(url)` so re-runs are idempotent), and the edges to wire them back to the existing `Account`.
4. Drops a single JSONL patch ready for `omnigraph load --mode merge`.

The whole adapter is ~130 lines. No row-to-object mapping layer. No "enrichment warehouse" to keep in sync.

### Live → continuous: the Monitor API loop

`TechSignal` + `TriggeredBy` exist so Monitor API webhook events land as first-class nodes, not log lines:

1. `POST /v1alpha/monitors` with a query like `"AI infra company funding announcements"`.
2. On `monitor.event.detected`, upsert a `TechSignal`.
3. Trigger `enrich.py` against the affected account, then emit `TriggeredBy: ResearchRun → TechSignal`.
4. Now this question is one query: *"show every ResearchRun triggered by a funding signal in the last 30 days and the Claims it changed."*

## Forking this for your GTM

The shape is general. Swap the seed and the output schema, keep the bones:

- **Change the workload categories** (`WorkloadCategory`) to match your wedge — `training/inference/sandbox` if you sell compute, or `data-ingest/transform/reverse-etl` if you sell data infra, or `shipment/returns/fulfillment` if you sell logistics. It's a single node type.
- **Change the Product kinds** (`Product.kind` enum) to the segments you track.
- **Extend the Claim predicates** by editing `demo/enrich.py`'s `OUTPUT_SCHEMA` — every top-level field becomes one Claim. No schema migration needed on the graph side.
- **Bring your own accounts** by replacing `seed.jsonl` — or by writing via the `add-account` / `link-invests` / `link-builds` mutations.

## Files

- `schema.pg` — Executable Omnigraph schema (source of truth)
- `seed.md` / `seed.jsonl` — Illustrative roster (15 accounts, 31 investors, 3 rounds, 3 signals, 2 runs, 7 claims, 5 sources, 6 workload categories)
- `queries/*.gq` — Reads and mutations
- `omnigraph.yaml` — CLI config with ~35 aliases
- `demo/enrich.py` — Parallel Task API → Omnigraph patch, end to end
- `CLAUDE.md` — Scoped agent guidance for this starter

## Reference

- [Omnigraph](https://github.com/ModernRelay/omnigraph) — CLI, schema, `.gq` query language
- [Parallel Task API](https://docs.parallel.ai/task-api/task-quickstart) — the research primitive
- [Parallel Monitor API](https://docs.parallel.ai/monitor-api/monitor-quickstart) — continuous tracking
