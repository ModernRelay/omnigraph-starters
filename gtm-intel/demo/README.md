# GTM Intel Demo — Parallel → Omnigraph

End-to-end demo of the enrichment loop: Parallel Task API runs produce structured output with full research basis, and the output is written into a graph rather than flattened into Snowflake rows. Every field Parallel returns becomes one `Claim` node with confidence, reasoning, and citation URLs attached — no remapping layer.

## What's here

- [`enrich.py`](./enrich.py) — fires a Parallel Task run per account, parses the `output` + `basis` response, and emits a JSONL patch ready for `omnigraph load --mode merge`.
- [`requirements.txt`](./requirements.txt) — just `parallel-web`.

## Prerequisites

1. A running Omnigraph server for the `gtm-intel` starter (see [`../README.md`](../README.md) Quick Start).
2. A Parallel API key (`export PARALLEL_API_KEY=...`).

## Run

```bash
cd gtm-intel/demo
pip install -r requirements.txt

export PARALLEL_API_KEY=sk-...
python enrich.py --accounts acct-cognition acct-factory acct-pika acct-krea
```

Output lands in `./out/claims-<run>.jsonl`. Load into the graph:

```bash
cd ..
omnigraph load --data ./demo/out/claims-<run>.jsonl --mode merge /tmp/gtm-intel/repo
# (or the s3:// URI you initialized with)
```

Then query the freshly-enriched claims:

```bash
omnigraph read --alias claims-for acct-cognition
```

## How it maps to the graph

Each Parallel Task response turns into a subgraph rooted at a `ResearchRun`:

```
ResearchRun(promptVersion=v5, schemaVersion=v2)
  ├─ AssertedClaim ─▶ Claim(predicate=headcount, value="72", confidence=high)
  │                        ├─ AboutAccount     ─▶ Account(acct-cognition)
  │                        └─ GroundedInSource ─▶ Source(url=...)
  ├─ AssertedClaim ─▶ Claim(predicate=latest_funding_stage, ...)
  └─ AssertedClaim ─▶ Claim(predicate=latest_lead_investor, ...)
```

- **One Claim per output field.** Flat output schema → atomic claims.
- **`confidence` comes straight from Parallel's FieldBasis.** No remapping.
- **Every citation URL becomes a Source.** Deterministic slug from the URL, so re-running doesn't duplicate sources.
- **Prompt + schema versions live on the `ResearchRun`.** Re-run with `PROMPT_VERSION = "v6"` and the graph now has two runs; combine with a `Supersedes` edge to audit drift.

## Monitor API integration (sketch)

The Monitor API handles the "new funding round appears" trigger. The flow:

1. `POST /v1alpha/monitors` with a query like `"AI infrastructure company funding announcements"` and a webhook URL pointing at your service.
2. Your webhook receives `monitor.event.detected` with an `event_group_id`.
3. Fetch the full events via `GET /v1alpha/monitors/{id}/event_groups/{gid}`.
4. For each event: upsert a `TechSignal` node, then call `enrich.py` with the affected account and emit a `TriggeredBy` edge from the new `ResearchRun` to the `TechSignal`.

The Omnigraph aliases for the signal/run/triggered-by path are in [`../omnigraph.yaml`](../omnigraph.yaml): `add-signal`, `add-run`, `link-triggered`, `link-observed`.

## Why this is nice

| Today (rows in Snowflake)                              | With Omnigraph                                           |
|--------------------------------------------------------|----------------------------------------------------------|
| `headcount` is a column; old values get overwritten    | Old Claim stays, new Claim points `Supersedes` at it     |
| Confidence is a float you remembered to log            | `confidence: enum(high\|medium\|low)` indexed on Claim   |
| "Which prompt asserted this?" = join on a version tag  | Direct edge: `ResearchRun --AssertedClaim--> Claim`      |
| "Lookalike prospects" = 6 self-joins                   | `omnigraph read --alias lookalikes`                      |
