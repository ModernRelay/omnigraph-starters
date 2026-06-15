# Migration & Deprecations (pre-0.7.0 → 0.7.0)

The rest of this skill teaches the **current 0.7.0 surface only**. Consult this page solely when you meet an old config file, command, flag, route, or error and need its current form. Pre-0.7.0 spellings keep working as deprecated aliases (they print a warning) unless marked **removed**.

## Config files

| Before (pre-0.7.0) | Now (0.7.0) |
|---|---|
| `omnigraph.yaml` (one combined file) | **`cluster.yaml`** (team deployment) + **`~/.omnigraph/config.yaml`** (operator) |
| `cli.actor` | `operator.actor` |
| `cli.graph` / `server.graph` | `defaults.default_graph` (+ `defaults.server`) |
| `targets:` / `target:` | `graphs:` / `graph:` |
| `omnigraph init` scaffolds `omnigraph.yaml` | `init` scaffolds nothing — start a `cluster.yaml` from [`cluster.md`](cluster.md) |

- **Migrate:** `omnigraph config migrate [--write]` splits a legacy `omnigraph.yaml` — team half → `cluster.yaml`, personal half → `~/.omnigraph/config.yaml`.
- The legacy file still loads (printing a per-key deprecation notice; silence with `OMNIGRAPH_SUPPRESS_YAML_DEPRECATION=1`, or hard-fail with `OMNIGRAPH_NO_LEGACY_CONFIG=1`).

## CLI addressing (RFC-011)

| Before | Now |
|---|---|
| `--target <name>` | **removed** — use `--server <name\|url>`, `--store <uri>`, or `--profile <name>` (SKILL.md → *Addressing a graph*) |
| positional `http(s)://` URL → a server | **removed** — address a remote with `--server <url>` |
| `--as` on a served (remote) write | no-op — the server resolves the actor from the bearer token (`--as` applies to direct `--store` writes) |

The `omnigraph-server --target` **boot** flag is a different flag and is unchanged.

## CLI verbs

| Before | Now |
|---|---|
| `omnigraph ingest …` | `omnigraph load --from main --mode merge …` |
| `omnigraph read` | `omnigraph query` |
| `omnigraph change` | `omnigraph mutate` |
| `omnigraph query lint` / `query check` | `omnigraph lint` |

## HTTP routes

| Before | Now |
|---|---|
| `POST /ingest` | `POST /load` |
| `POST /read` | `POST /query` |
| `POST /change` | `POST /mutate` |

The old routes remain as **deprecated aliases** (retained indefinitely), carrying `Deprecation: true` + `Link: <successor>` response headers.

## Server token resolution

| Before | Now |
|---|---|
| `graphs.<name>.bearer_token_env` in `omnigraph.yaml` | `omnigraph login <server>` → `~/.omnigraph/credentials`, or `OMNIGRAPH_TOKEN_<NAME>` |

The legacy `bearer_token_env` chain is still honored as a fallback for a URL that matches no operator `servers:` entry.

## Older removals (still worth knowing)

- The transactional **Run** state machine, its `/runs` routes, and the `run_publish` / `run_abort` Cedar actions were **removed in v0.4.0**. Writes publish directly — use `GET /commits` for history and the `change` action for write gating; `/runs` returns 404.
