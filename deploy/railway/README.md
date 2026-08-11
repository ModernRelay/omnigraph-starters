# Deploy an Omnigraph cookbook on Railway

One-click deploys of any cookbook in this repo against a managed
S3-compatible bucket on [Railway](https://railway.com). No AWS account
needed; Railway provisions the storage, generates the bearer tokens, and
converges the cookbook's cluster config on first boot.

## What you get

| Piece                  | Where it runs                                                            |
| ---------------------- | ------------------------------------------------------------------------ |
| `omnigraph-server`     | Single Railway service (this repo's `deploy/railway/Dockerfile`)         |
| Storage                | Railway Bucket — first-party S3, unlimited free S3 ops + bucket egress   |
| Cluster config         | The bundled cookbook's directory (`cluster.yaml` + schema + stored queries + policies), selected via `OMNIGRAPH_COOKBOOK` and converged by `omnigraph cluster apply` at deploy time |
| Auth (3 actors)        | `act-admin` / `act-writer` / `act-reader` bearer tokens auto-generated at deploy (industry-intel: `act-analyst` instead of `act-writer` — see Authorization model) |
| Authz                  | Cedar policy bundles applied as cluster state (template bundles injected for cookbooks without their own) |
| Public HTTPS endpoint  | Railway-managed `*.up.railway.app` domain with auto-SSL                  |

The template is **schema-only**: it applies the cookbook's cluster config
(schema + stored queries + policies) and then stops. The graph starts
empty and ready to receive your real data via the `omnigraph` CLI or the
HTTP API. Demo `seed.jsonl` files from the cookbooks are not auto-loaded.

Total cost on Railway Hobby: ~$0.015/GB-month for stored data + the
service's compute. No volumes attached — all state lives in the Bucket.
Bucket egress and S3 API operations are free and unlimited, but note that
*uploads from the service to the Bucket* (every `cluster apply` / `load` /
`change`) count as **service egress** and are billed at Railway's standard
public egress rate — Buckets are not on the private network.

## Deploy

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/TEMPLATE_CODE?utm_medium=integration&utm_source=button&utm_campaign=omnigraph)

At deploy time, pick the cookbook via the `OMNIGRAPH_COOKBOOK` variable —
one of `industry-intel` (default), `pharma-intel`, `second-brain`,
`vc-os`, or `dev-graph`. The cookbook cluster configs are bundled in the
image; the deploy converges the one you pick onto the Bucket and serves
its graph at `/graphs/<id>/…`.

| Cookbook | `OMNIGRAPH_COOKBOOK` | Graph id |
|---|---|---|
| AI/ML industry intelligence (SPIKE) | `industry-intel` | `spike` |
| Pharma competitive intelligence | `pharma-intel` | `pharma` |
| Personal life automation | `second-brain` | `brain` |
| Venture-capital operating system | `vc-os` | `vcos` |
| Software-development knowledge graph | `dev-graph` | `dev` |

To deploy your **own** schema, fork this repo, add a cookbook directory
(`cluster.yaml` + `schema.pg` + optional `queries/` and `policies/`), add
a `COPY` line for it in `deploy/railway/Dockerfile`, and point your
Railway service at the fork.

> **Status:** `TEMPLATE_CODE` in the button URL above is a placeholder —
> replace it with the real template code (and `utm_campaign` with the
> template name) once the template is published on Railway. Until then,
> deploy manually:
>
> ```bash
> railway init
> railway bucket create graph-storage --region <closest-to-you>
> railway add --service omnigraph
> # The ${{secret(48)}} template function only runs on a *template* deploy,
> # not via `railway variable set` — so generate real tokens yourself here:
> ADMIN=$(openssl rand -hex 24); WRITER=$(openssl rand -hex 24); READER=$(openssl rand -hex 24)
> railway variable set --service omnigraph --skip-deploys \
>   "OMNIGRAPH_COOKBOOK=industry-intel" \
>   "OMNIGRAPH_CLUSTER_URI=s3://\${{graph-storage.BUCKET}}/cluster" \
>   "AWS_ENDPOINT_URL=\${{graph-storage.ENDPOINT}}" \
>   "AWS_ENDPOINT_URL_S3=\${{graph-storage.ENDPOINT}}" \
>   "AWS_ACCESS_KEY_ID=\${{graph-storage.ACCESS_KEY_ID}}" \
>   "AWS_SECRET_ACCESS_KEY=\${{graph-storage.SECRET_ACCESS_KEY}}" \
>   "AWS_REGION=\${{graph-storage.REGION}}" \
>   "OMNIGRAPH_SERVER_BEARER_TOKENS_JSON={\"act-admin\":\"$ADMIN\",\"act-writer\":\"$WRITER\",\"act-reader\":\"$READER\"}"
> # industry-intel ships its own policy with act-analyst instead of act-writer:
> #   …TOKENS_JSON={"act-admin":"$ADMIN","act-analyst":"$WRITER","act-reader":"$READER"}
> # Make sure the service's region matches the Bucket region (railway scale)
> railway up --service omnigraph
> ```

## Service region — this is critical, not cosmetic

**You must place the service in the same region as the Bucket.** A Railway
service with no explicit region (`region: null`, the default) deploys to
the workspace's default region — which is almost never the Bucket's region.
Because `omnigraph-server` makes **many sequential S3 round-trips per
operation**, a cross-region service↔Bucket hop multiplies that RTT on every
read and write. Measured on a deliberately mismatched deploy (service on
default region, Bucket in `sjc`):

| Operation | Cross-region (mismatched) | In-region (expected) |
| --------- | ------------------------- | -------------------- |
| `/healthz` (no Bucket) | ~390 ms | ~390 ms |
| `snapshot` read | **~5.7 s** | sub-second |
| single-node write | **~46 s** | ~1 s |

So a mismatch isn't "a bit slower" — it makes the graph effectively
unusable for writes. The Bucket region is fixed at creation; set the
**service** region to match it (Railway dashboard → service **Settings →
Region**, or pin it in config-as-code via
[`multiRegionConfig`](https://docs.railway.com/config-as-code/reference#multi-region-configuration)
using the identifier from the table below). Verify after deploy that the
service's region matches the Bucket's.

Mind the two naming schemes: the **Bucket CLI** uses short codes
(`sjc` / `iad` / `ams` / `sin`), while the **service** region picker (and
config-as-code) uses the full identifiers. Match them up:

| Location               | Bucket code | Service identifier        |
| ---------------------- | ----------- | ------------------------- |
| California, US West    | `sjc`       | `us-west2`                |
| Virginia, US East      | `iad`       | `us-east4-eqdc4a`         |
| Amsterdam, EU West     | `ams`       | `europe-west4-drams3a`    |
| Singapore, SE Asia     | `sin`       | `asia-southeast1-eqsg3a`  |

Because no Railway Volume is attached, changing the service region later
is zero-downtime — only volume-backed services incur migration downtime.

## Scaling and availability

**Keep this service at a single replica.** Railway's production-readiness
checklist recommends ≥2 replicas, but that assumes a stateless service.
`omnigraph-server` is a single-writer store backed by one shared Bucket
prefix, and Railway load-balances replicas randomly with no sticky
sessions — two replicas would race on the same S3 objects and can corrupt
the graph. Do **not** raise the replica count or add multi-region
replicas in the dashboard. Durability comes from Railway's Bucket storage
plus the `ON_FAILURE` restart policy; for point-in-time safety, run
`omnigraph export` / `snapshot` to a second location on a schedule, since
Buckets have no built-in snapshot/versioning.

## Required environment variables

The template configures these for you. Listed here so you understand
what each does (and to make manual deploys reproducible).

| Variable                              | Value at deploy                                                                          |
| ------------------------------------- | ---------------------------------------------------------------------------------------- |
| `OMNIGRAPH_COOKBOOK`                  | Which bundled cookbook cluster config to converge. Default `industry-intel`.             |
| `OMNIGRAPH_CLUSTER_URI`               | `s3://${{Bucket.BUCKET}}/cluster` — the cluster storage root; the server boots config-free from it |
| `AWS_ENDPOINT_URL`                    | `${{Bucket.ENDPOINT}}` — read by Lance's `object_store`                                  |
| `AWS_ENDPOINT_URL_S3`                 | `${{Bucket.ENDPOINT}}` — read by the omnigraph S3 adapter (set both for cross-version safety) |
| `AWS_ACCESS_KEY_ID`                   | `${{Bucket.ACCESS_KEY_ID}}`                                                              |
| `AWS_SECRET_ACCESS_KEY`               | `${{Bucket.SECRET_ACCESS_KEY}}`                                                          |
| `AWS_REGION`                          | `${{Bucket.REGION}}`                                                                     |
| `OMNIGRAPH_SERVER_BEARER_TOKENS_JSON` | `{"act-admin":"${{secret(48)}}","act-writer":"${{secret(48)}}","act-reader":"${{secret(48)}}"}` — keys are ACTOR IDS the policy bundles reference (industry-intel: use `act-analyst` in place of `act-writer`) |
| `GEMINI_API_KEY` (optional)           | Empty by default; supply yours at deploy time to unlock text-input vector search         |

### Embeddings + Gemini

Four of the five cookbooks (`industry-intel`, `second-brain`, `vc-os`,
`dev-graph`) have schemas with `Vector(...) @embed("...")` fields. The
deploy does **not** populate those vectors — they stay null unless you run
`omnigraph embed` against the deployed graph.

Practical consequences:

- Without `GEMINI_API_KEY`, the deploy still works for every query type
  we ship in the cookbook (`get_*`, `recent_*`, traversals like
  `pattern_signals`, FTS via `search(...)`). Only `nearest(field, "text",
  k)` queries that need to embed a *text* input at query time return 500
  with `"GEMINI_API_KEY is required when nearest() needs a string
  embedding"`.
- With `GEMINI_API_KEY` set, the same vector queries work once you've
  populated the embedding columns via `omnigraph embed` (workstation-
  initiated; runs against the running server).
- `pharma-intel` has no `@embed` fields and never needs the key.

The Railway template marks `GEMINI_API_KEY` as an **optional user-input
variable** — the deploy UI shows a blank field with the description
above. Leave it blank to skip; set it to a Gemini API key to enable
text-input vector search later.

`${{Bucket.*}}` and `${{secret(N)}}` are Railway's reference-variable
and template-function syntax — they resolve at deploy time without
appearing in build logs.

## Get your tokens

After the first deploy:

1. Open the omnigraph service in the Railway dashboard.
2. Go to the **Variables** tab.
3. Find `OMNIGRAPH_SERVER_BEARER_TOKENS_JSON`. Railway shows the
   resolved JSON; copy the three tokens.

Then call the server (multi-graph routes — the graph id comes from the
cookbook table above):

```bash
ENDPOINT="https://$YOUR_SERVICE.up.railway.app"
TOKEN="$ADMIN_TOKEN_FROM_VARS"

curl -fsS "$ENDPOINT/healthz" | jq .
curl -fsS -H "Authorization: Bearer $TOKEN" "$ENDPOINT/graphs" | jq .
curl -fsS -H "Authorization: Bearer $TOKEN" \
  "$ENDPOINT/graphs/spike/snapshot?branch=main" | jq '.tables[] | select(.row_count > 0)'
```

## Authorization model

Policy is **applied cluster state** (omnigraph ≥ 0.9), not a server flag.
Cookbooks without their own `policies:` get the template bundles
(`deploy/railway/config/*.railway.yaml`), which define three roles wired
to the token JSON's actor ids:

| Actor        | Can do                                                                       |
| ------------ | ---------------------------------------------------------------------------- |
| `act-admin`  | Everything: stored queries, `read`, `export`, `change`, `schema_apply`, `branch_*`, `GET /graphs` |
| `act-writer` | Stored queries, `read`, `export`, `change` on any branch; `branch_create` against unprotected branches |
| `act-reader` | Stored read queries, `read`, `export` on any branch                          |

`main` is protected — only `act-admin` can target it with
`branch_create` or run `schema_apply` / `branch_delete` / `branch_merge`
anywhere. `GET /graphs` (registry enumeration) is a server-scoped action
granted to admins by the cluster-bound bundle.

**industry-intel ships its own policy bundles** with its own roles:
`act-admin` (graph list), `act-analyst` (stored mutations + data-plane
writes), `act-reader` (stored read queries + reads). Generate the token
JSON with those actor ids for that cookbook.

Bearer tokens are SHA-256 hashed on server startup; the plaintext lives
only in the Railway-encrypted env var, not in process memory. Constant-
time comparison. The server refuses to boot with no tokens configured
unless `--unauthenticated` is passed explicitly.

## Rotation

Open the Variables tab → click the regenerate icon on a specific
sub-field of `OMNIGRAPH_SERVER_BEARER_TOKENS_JSON`, or edit the JSON
inline. Click **Redeploy** to pick up the change.

## Customizing the policy

Policy bundles are cluster state, converged by `cluster apply` on every
deploy. For a different role/group structure:

1. Fork this repo.
2. Edit `deploy/railway/config/policy.railway.yaml` (cookbooks with their
   own `policies/` directory: edit those instead).
3. Validate locally: `omnigraph cluster validate --config <cookbook-dir>`
   (for the template bundles, run a local init simulation or validate the
   assembled config).
4. Push the fork and point your Railway service at it; the next deploy's
   `cluster apply` converges the change. Since 0.9 policy YAML validates
   strictly — unknown fields are errors, one bundle owns each scope, and
   server-scoped actions (`graph_list`) cannot carry branch scopes.

## Re-deploy and schema changes

The `preDeployCommand` runs `omnigraph-railway-init.sh` between build and
start on every deploy. The script assembles the cookbook's cluster config,
points `storage:` at `OMNIGRAPH_CLUSTER_URI`, and runs
`cluster validate` → `cluster import` (fresh Bucket only) →
`cluster apply`. Apply is declarative and convergent:

- **Fresh Bucket** → initializes the ledger, creates the graph, applies
  schema, stored queries, and policies.
- **Existing cluster** → converges to the declared state; an unchanged
  config is a no-op (`no changes … converged: true`). No data loss across
  re-deploys.

Schema changes ship the same way: edit the cookbook's `schema.pg` in your
fork and redeploy — `cluster apply` plans and applies the migration.
Cluster-managed graphs **refuse** direct `omnigraph schema apply`; the
cluster config is the single owner of the schema.

## Upgrading the engine (`OMNIGRAPH_REF` bumps)

Omnigraph storage is **strict-single-version**: when a release changes the
storage format (v0.9.0 did — internal schema v6; v0.8.0's v4 before it),
the new binary refuses to open a graph created by the old one, and vice
versa. There is no in-place migration.

That means bumping `OMNIGRAPH_REF` across a format-changing release with an
existing graph in the Bucket **breaks the next deploy — loudly, by
design**: `cluster apply` refuses the old-format graph rather than
touching it. Nothing is corrupted; the deploy just fails until you rebuild.

Rebuild as part of the bump:

1. **With the old binary** (matching the currently deployed REF):
   `omnigraph export` the graph to local files (data, vectors, and blobs
   are preserved; commit history and branches are not — export each branch
   you need separately).
2. Empty the cluster's storage: `railway bucket -b graph-storage delete`
   and recreate it (same region), or delete the cluster prefix's objects.
3. Deploy the new REF; first-boot `init.sh` re-creates the cluster and
   graph from the bundled cookbook config.
4. **With the new binary**, reload the data — an in-region
   `load --mode overwrite` against the graph URI, or `mutate` through the
   server in batches.

Verify with `GET /healthz`, which reports the storage-format version the
server is serving. Releases that do **not** change the storage format
(check the release notes) redeploy cleanly with no rebuild.

Also pre-flight your data against 0.9's stricter write validation (see the
engine's upgrade guide): `load --mode append` now refuses duplicate ids
(use `--mode merge` for upserts), and one keyed `load`/`mutate` stages at
most 8,192 rows / 32 MiB per table (`--mode overwrite` is uncapped). A
failed load publishes no commit.

## Loading data

The deploy is schema-only; you fill the graph yourself. Two paths:

- **Through the server: `omnigraph load` or `mutate` over HTTPS** with a
  writer/admin bearer token. Since 0.9, `load` works against a served
  remote too (`--server` + `--graph`); the server performs the writes in
  its own region, so it's version-safe and avoids cross-network S3. Keyed
  loads (`--mode merge`/`append`) are capped at 8,192 rows / 32 MiB per
  table per request — chunk bigger imports, or use `--mode overwrite` for
  a whole-table seed.
- **Direct to the Bucket (`omnigraph load s3://…/graphs/<id>.omni`):
  version-pinned and in-region only.** Two hazards:
  1. **Version skew fails the load.** Your local CLI must match the
     deployed `OMNIGRAPH_REF`. The storage-format gate is enforced at
     open, in both directions, before anything is written. Check up
     front: `omnigraph version` prints the binary's format version (the
     `internal-schema` line) and `omnigraph snapshot` / `GET /healthz`
     report the graph's.
  2. **Run it in-region.** A direct load from a laptop across the world to
     the Bucket pays the cross-region RTT on every one of its many
     sequential S3 calls — minutes-to-hours for a few hundred rows. Run
     the loader from the Bucket's region (or go through the server).

## Switching cookbooks

`OMNIGRAPH_COOKBOOK` selects the cluster config that `cluster apply`
converges. Changing it against an existing cluster does **not** remove the
previous cookbook's graph — apply is additive/convergent per declared
resource, and removing graphs is approval-gated by design. To switch a
running service to a different cookbook cleanly, destroy the Bucket
(`railway bucket -b graph-storage delete` — the bucket is named with the
global `-b/--bucket` flag, not a positional) and redeploy; the next deploy
re-creates the cluster from the newly selected cookbook.

## Local validation

```bash
# Build the image
docker build -f deploy/railway/Dockerfile -t omnigraph-railway:test .

# Verify the binaries and the bundled cookbook configs landed
docker run --rm omnigraph-railway:test omnigraph version
docker run --rm omnigraph-railway:test ls /opt/cookbooks

# Run the full preDeploy + serve flow against a local RustFS
docker run --rm \
  -e OMNIGRAPH_COOKBOOK=industry-intel \
  -e OMNIGRAPH_CLUSTER_URI=s3://omnigraph-local/railway-test \
  -e AWS_ENDPOINT_URL_S3=http://host.docker.internal:9000 \
  -e AWS_ACCESS_KEY_ID=rustfsadmin \
  -e AWS_SECRET_ACCESS_KEY=rustfsadmin \
  -e AWS_REGION=us-east-1 \
  -e AWS_S3_FORCE_PATH_STYLE=true \
  -e AWS_ALLOW_HTTP=true \
  omnigraph-railway:test \
  sh -c '/usr/local/bin/omnigraph-railway-init.sh'
```

## Pinning + maintenance

The Dockerfile pins the omnigraph engine to a specific tag via
`ARG OMNIGRAPH_REF=v0.9.0`. Bump that on every omnigraph release that
changes server behavior, the policy schema, or the CLI surface — and if
the release changes the storage format, follow
[Upgrading the engine](#upgrading-the-engine-omnigraph_ref-bumps) above:
existing graphs must be rebuilt or the next deploy fails. The cookbook
cluster configs **are** baked into the image (a cluster config is a
directory, not one fetchable file), so cookbook changes ship with a
rebuild — which Railway does automatically on every deploy from the repo.

Because the service builds from this GitHub repo (not a prebuilt image),
merges to `main` surface an update PR to everyone who deployed the
template — keep a changelog and call out breaking changes (e.g. an
`OMNIGRAPH_REF` bump) so deployers know what they're accepting.

## Files

```
railway.toml             # build/deploy/preDeployCommand/healthcheck (at repo root — Railway reads it from here)
deploy/railway/
├── Dockerfile           # Pulls prebuilt omnigraph release binaries + bundles cookbook cluster configs
├── .dockerignore        # Trims context to schema/seed/queries/yaml only
├── scripts/
│   └── init.sh          # Idempotent cluster validate → import (fresh only) → apply
└── config/
    ├── policy.railway.yaml         # act-admin / act-writer / act-reader graph policy (injected)
    └── server.policy.railway.yaml  # cluster-scoped graph_list gate (injected)
```

`railway.toml` lives at the repo root because Railway reads its config from a service's root directory by default; everything else stays under `deploy/railway/` for tidiness.
