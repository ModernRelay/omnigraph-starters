#!/bin/sh
# First-deploy bootstrap for the Omnigraph Railway template (0.9 cluster mode).
#
# Runs as Railway's preDeployCommand. Assembles a cluster config directory
# from the bundled cookbook, points its storage at the Railway Bucket, and
# converges it with `omnigraph cluster apply`. Apply is declarative and
# convergent, so re-deploys are no-ops for an already-applied cluster; the
# graph itself is never re-initialized or overwritten. No seed data is
# loaded — the deploy is schema-only; operators fill the graph from their
# own sources (see deploy/railway/README.md → Loading data).

set -e

: "${OMNIGRAPH_CLUSTER_URI:?OMNIGRAPH_CLUSTER_URI must be set (s3://<bucket>/<prefix> — the cluster storage root on the Railway Bucket)}"
: "${OMNIGRAPH_COOKBOOK:=industry-intel}"

COOKBOOK_DIR="/opt/cookbooks/${OMNIGRAPH_COOKBOOK}"
if [ ! -f "${COOKBOOK_DIR}/cluster.yaml" ]; then
  echo "init: unknown cookbook '${OMNIGRAPH_COOKBOOK}' (no ${COOKBOOK_DIR}/cluster.yaml)" >&2
  echo "init: bundled cookbooks: $(ls /opt/cookbooks)" >&2
  exit 1
fi

CONFIG_DIR=$(mktemp -d)
cp -R "${COOKBOOK_DIR}/." "${CONFIG_DIR}/"

# Point cluster storage at the Bucket. Cookbook cluster.yamls deliberately
# omit `storage:` (local default = the config directory), so the deploy
# injects it; a cookbook that ever ships one is rewritten to the env value
# so the Bucket stays authoritative.
if grep -q '^storage:' "${CONFIG_DIR}/cluster.yaml"; then
  sed -i "s|^storage:.*|storage: ${OMNIGRAPH_CLUSTER_URI}|" "${CONFIG_DIR}/cluster.yaml"
else
  printf '\nstorage: %s\n' "${OMNIGRAPH_CLUSTER_URI}" >> "${CONFIG_DIR}/cluster.yaml"
fi

# Cookbooks without their own `policies:` get the template bundles (three
# roles wired to the template's bearer tokens). A cookbook that declares
# policies keeps them — 0.9 validates strictly and one bundle owns each
# scope, so injecting a second one would be refused.
if ! grep -q '^policies:' "${CONFIG_DIR}/cluster.yaml"; then
  mkdir -p "${CONFIG_DIR}/policies"
  cp /opt/railway-config/policy.railway.yaml        "${CONFIG_DIR}/policies/railway.policy.yaml"
  cp /opt/railway-config/server.policy.railway.yaml "${CONFIG_DIR}/policies/server.policy.yaml"
  GRAPH_ID=$(sed -n '/^graphs:/,/^[^ ]/{s/^  \([A-Za-z0-9_-]*\):$/\1/p;}' "${CONFIG_DIR}/cluster.yaml" | head -1)
  : "${GRAPH_ID:?init: could not derive the graph id from cluster.yaml}"
  cat >> "${CONFIG_DIR}/cluster.yaml" <<EOF

policies:
  railway:
    file: policies/railway.policy.yaml
    applies_to: [${GRAPH_ID}]
  server:
    file: policies/server.policy.yaml
    applies_to: [cluster]
EOF
  echo "init: injected template policy bundles for graph '${GRAPH_ID}'"
else
  echo "init: cookbook ships its own policies — leaving them in place"
fi

echo "init: validating cluster config (cookbook=${OMNIGRAPH_COOKBOOK}, storage=${OMNIGRAPH_CLUSTER_URI})"
omnigraph cluster validate --config "${CONFIG_DIR}"

# Import creates the state ledger on a FRESH bucket only; an existing
# ledger (every re-deploy) is left in place and `apply` converges against
# it. Any other import failure is fatal and shown in the deploy log.
if import_out=$(omnigraph cluster import --config "${CONFIG_DIR}" 2>&1); then
  echo "init: initialized fresh cluster state ledger"
elif printf '%s' "${import_out}" | grep -q 'state_already_exists'; then
  echo "init: cluster state ledger already present — converging via apply"
else
  printf '%s\n' "${import_out}" >&2
  exit 1
fi
omnigraph cluster apply --config "${CONFIG_DIR}" --as act-admin

echo "init: cluster converged; server boots config-free from ${OMNIGRAPH_CLUSTER_URI}"
