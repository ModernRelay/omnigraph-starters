# Demo Setup — AI Industry Intel

The quickest path to a populated SPIKE graph. Uses the existing `industry-intel` cookbook as-is.

## Prerequisites

### RustFS + binaries

RustFS must be running locally on `127.0.0.1:9000`. Verify with:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:9000/
```

If you get `000` (no connection), start a RustFS — as a native binary (macOS: `brew install rustfs/tap/rustfs`, then `rustfs server --address 127.0.0.1:9000 --access-key rustfsadmin --secret-key rustfsadmin ./data`) or in Docker ([install](https://docs.docker.com/get-docker/)):

```bash
docker run -d --name omnigraph-s3 -p 9000:9000 \
  -e RUSTFS_ACCESS_KEY=rustfsadmin -e RUSTFS_SECRET_KEY=rustfsadmin \
  -e RUSTFS_ALLOW_INSECURE_DEFAULT_CREDENTIALS=true rustfs/rustfs:latest /data
aws --endpoint-url http://127.0.0.1:9000 s3 mb s3://omnigraph-local   # create the bucket once
```

See the omnigraph repo's `docs/user/deployment.md` → *Testing against S3 locally* for the full `AWS_*` contract.

### Existing server on :8080

Bootstrap auto-starts an `omnigraph-server` on `:8080` against its own demo repo. If you'll be running your own server (later in this flow), check first:

```bash
curl -s -o /dev/null -w "server:%{http_code}\n" http://127.0.0.1:8080/healthz
```

If `200`, either stop the bootstrap server or rebind yours via `omnigraph-server --bind 127.0.0.1:8090`.

## Get the cookbook content

The `industry-intel` cookbook (schema, queries, seed) lives in the [omnigraph-cookbooks](https://github.com/ModernRelay/omnigraph-cookbooks) repo. Ask the user where to clone it (default: current directory):

```bash
git clone https://github.com/ModernRelay/omnigraph-cookbooks.git
```

Then move into the cookbook folder:

```bash
cd omnigraph-cookbooks/industry-intel
[ -f .env.omni ] || cp .env.omni.example .env.omni
set -a && source .env.omni && set +a
```

`.env.omni` is gitignored (it's just credentials). The repo ships `.env.omni.example` with the 7 required AWS vars — copy it on first run.

All commands below run from `industry-intel/`. If the clone is somewhere else, substitute the absolute path.

### First-time bucket creation

### Converge the cluster + load

The cookbook ships a `cluster.yaml` declaring the graph (`spike`), the
schema, and all 66 stored queries. One-time setup:

```bash
omnigraph cluster import --config .                # create the state ledger
omnigraph cluster plan   --config .                # preview (optional but wise)
omnigraph cluster apply  --config . --as <you>     # creates graphs/spike.omni, applies schema, publishes queries
omnigraph load --data seed.jsonl --mode overwrite graphs/spike.omni
```

Apply is idempotent — re-running it on a converged cluster is a no-op. No
RustFS, bucket, or credentials are involved on this path.

Expected output from load:

```
loaded graphs/spike.omni on branch main with overwrite: 109 nodes across 9 node types, 154 edges across 17 edge types
```

### Start the server

```bash
omnigraph-server --cluster . --bind 127.0.0.1:8080 --unauthenticated
```

`--cluster` serves the applied revision (the exclusive boot source).
`--unauthenticated` is for local dev — the server
refuses to start without bearer tokens, a policy, or this flag. Keep it
running (separate terminal or background). Every declared query is also a
direct HTTP endpoint: `POST /graphs/spike/queries/<name>`.

### Verify

```bash
omnigraph alias patterns disruption
```

Should return 2 patterns: SaaSpocalypse, Sovereign AI.

Try a traversal:

```bash
omnigraph alias pattern-signals pat-sovereign-ai
```

Should return 3 signals.

## What You Got

| Node | Count |
|------|-------|
| Pattern | 5 (Sovereign AI, SaaSpocalypse, Context Graphs, New Cyber Threats, Accelerated Research) |
| Signal | 15 (each with real dates and source URLs) |
| Element | 26 (products, frameworks, concepts across AI/ML) |
| Company | 17 |
| Expert | 7 |
| SourceEntity | 16 |
| InformationArtifact | 20 |
| Insight | 3 |
| KnowHow | 2 |

Plus 148 edges wiring the graph together.

## Next Steps

- **Explore queries** in `queries/*.gq`
- **Try aliases**: merge the cookbook's `omnigraph-config.example.yaml` `aliases:` into `~/.omnigraph/config.yaml`
- **For day-to-day ops** (adding signals, evolving schema, branches, embeddings): switch to the `omnigraph` skill (`npx skills add ModernRelay/omnigraph@omnigraph`)

## Optional: Reset

To wipe and reload the demo data from scratch:

```bash
omnigraph load --data seed.jsonl --mode overwrite graphs/spike.omni
```

`overwrite` truncates the branch before loading — safe for a demo repo, not for production.
