# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Repo-wide guidance. Each cookbook also has its own `CLAUDE.md` — read both when working inside one.

## What This Repo Is

A collection of Omnigraph graph cookbooks. Each cookbook is self-contained in its folder (schema, seed, queries, cluster config — no application code). Four cookbooks ship today: `industry-intel/` (AI/ML intel on the SPIKE framework — Signal, Pattern, Insight, KnowHow, Element), `pharma-intel/` (pharma competitive intelligence), `second-brain/` (personal-life automation graph), and `vc-os/` (venture-capital operating system). See `README.md` for the full list and planned cookbooks.

## Architecture

- **Storage**: all four cookbooks are **filesystem-backed cluster** deployments — `cluster apply` creates the derived root `graphs/<id>.omni`; **no object store / RustFS needed**. (S3-compatible storage, `s3://bucket/prefix`, is supported for production; the SPIKE cookbooks document an optional S3 path.) `init` and `load` write storage directly — one-time setup ops that bypass the server.
- **Runtime**: `omnigraph-server` reads from storage at startup and exposes HTTP on `127.0.0.1:8080`. Day-to-day CLI calls (`query`, `mutate`) go through the server.
- **CLI config**: Per-operator settings (identity, named servers, defaults, **aliases**) live in `~/.omnigraph/config.yaml` (per-user, never committed). Each cookbook ships an `omnigraph-config.example.yaml` whose `aliases:` you merge in — short names binding to the graph's stored queries, invoked with `omnigraph alias <name> [args]` (e.g. `omnigraph alias pattern-signals pat-sovereign-ai`). Alias arg values are JSON-parsed first, then fall back to string — `29` is an integer, `"29"` is a string. Cookbooks ship no `omnigraph.yaml` (it is not read in 0.7+).
- **Auth**: filesystem clusters need no credentials. For an optional S3 backend, `.env.omni` (git-ignored) holds the `AWS_*` creds; source it before CLI commands: `set -a && source .env.omni && set +a`.
- **Versioning**: omnigraph storage is strict single-version (0.8.0 = internal schema v4) — a binary refuses a graph created by a different-format release, in both directions, at open. For these cookbooks the fix is trivial because seeds are the source of truth: delete the local `graphs/` and `__cluster/` dirs, then re-run `cluster apply` + `load` the seed. The export/import rebuild recipe (engine upgrade guide) is only needed for graphs holding data you added yourself. `omnigraph version` prints the binary's format version; `snapshot` and `/healthz` report a graph's.

**Prerequisite**: just the `omnigraph`/`omnigraph-server` binaries — no object store. `lint` works with nothing running; once a server is up, verify with `curl http://127.0.0.1:8080/healthz`.

## Canonical Workflow

1. **Edit** `schema.pg` or `queries/*.gq`. Comments in both use `//` not `#`.
2. **Lint** — `omnigraph lint --schema schema.pg --query queries/<file>.gq` validates queries against the schema. Run after any edit. This is a pure file check: no server, no storage needed — use it as the tight inner loop while editing. Everything below requires the server running.
3. **Schema changes** — plan before apply, always. Every cookbook is a cluster directory: edit the `.pg`, then `omnigraph cluster plan --config .` (shows real migration steps) and `omnigraph cluster apply --config . --as <you>`, then restart the `--cluster` server. Use `@rename_from(...)` for property/type renames.
4. **Data changes** — pick the right write command: `mutate` for edits; `load` for bulk JSONL with a **required** `--mode` (`merge` upsert · `append` strict-insert · `overwrite` clean-slate, destructive). `load --from main --branch <name>` forks a review branch in one shot. `load` works local **and** remote. Review bulk loads on a branch, then merge.
5. **Never string-interpolate** into `.gq` bodies or `--params` — parameterize everything.

**Cluster deployment model.** Every cookbook is a cluster directory: its
`cluster.yaml` declares the deployment (graph, schema, stored queries);
`omnigraph cluster apply` converges it (creating the graph at
`graphs/<id>.omni`) and `omnigraph-server --cluster .` serves it. Per-operator
settings (aliases, defaults, identity) live in `~/.omnigraph/config.yaml`
(per-user); each cookbook ships an `omnigraph-config.example.yaml` to merge in.
Never commit `graphs/` or `__cluster/` (gitignored).

There are no repo-level build, test, or lint commands. Validation happens per-cookbook via `omnigraph lint`. CI is not configured in this repo.

## Working in a Cookbook

Always `cd` into the cookbook folder first — configs and paths are relative:

```bash
cd industry-intel
omnigraph lint --schema schema.pg --query queries/signals.gq
```

Start the server once per session from inside the cookbook folder — `query`, `mutate`, and `snapshot` all go through it:

```bash
omnigraph-server --cluster . --unauthenticated   # every cookbook is a cluster directory
# binds 127.0.0.1:8080; local dev — the server refuses to start without auth/policy or this flag
```

Leave it running in a separate terminal or background process.

## Skills and Docs

- `industry-intel/skill/` — bootstrap a new SPIKE graph (elicitation + research + apply/load); install with `npx skills add https://github.com/ModernRelay/omnigraph-cookbooks/tree/main/industry-intel/skill`
- **`omnigraph` skill** (day-to-day ops) lives in the engine repo — `npx skills add ModernRelay/omnigraph@omnigraph` ([ModernRelay/omnigraph](https://github.com/ModernRelay/omnigraph/tree/main/skills/omnigraph)). The operational guide and schema-design docs live in that repo and on the docs site.

When working on schema or ops questions, consult the engine repo's docs rather than duplicating guidance here.

## Railway Deploy

`railway.toml` (repo root — Railway requires it there) + `deploy/railway/` deploy any cookbook's schema as a managed cloud service backed by a Railway Bucket (S3-compatible). Key facts, all detailed in `deploy/railway/README.md`:

- **Schema-only**: `init.sh` fetches `OMNIGRAPH_SCHEMA_URL` (any HTTPS `.pg`) and runs `omnigraph init` on first boot; seed data is not auto-loaded. Idempotent across re-deploys.
- The Dockerfile pins the engine via `ARG OMNIGRAPH_REF` — bump it on engine releases. Schemas are fetched at deploy time, so new cookbooks need no image rebuild.
- Sharp edges documented there: service region **must** match the Bucket region (cross-region makes writes unusable), keep a **single replica** (single-writer store — replicas corrupt the graph), and direct `load` to the Bucket requires a version-matched CLI run in-region (prefer `mutate` through the server).
- Auth is admin/writer/reader bearer tokens with a Cedar policy baked in at `deploy/railway/config/policy.yaml`; the `omnigraph.yaml` there is the deploy image's server config, not the deprecated cookbook-level file.

## When Adding a New Cookbook

- Create the folder with `README.md`, `CLAUDE.md`, `schema.pg`, `cluster.yaml` (the deployment), `omnigraph-config.example.yaml` (example operator aliases), `queries/`, and seed data (`seed.md` + `seed.jsonl`)
- Ship real seed data, not placeholders
- A `@key` value (`slug` by convention) must appear only once per `seed.jsonl` — since 0.8.0 a key repeated within one load batch fails the whole load. Same for duplicate edge rows on `@unique(src)`/`@unique(src,dst)` edges.
- Keep the cookbook's README and CLAUDE in sync with its schema
- Expose agent-facing operations as aliases in the operator config (ship them in `omnigraph-config.example.yaml`), not raw CLI invocations

Omnigraph reference: [ModernRelay/omnigraph](https://github.com/ModernRelay/omnigraph).
