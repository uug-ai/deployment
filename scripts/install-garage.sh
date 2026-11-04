#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --prepare-only ) ]]; then
  echo "Usage: bash scripts/install-garage.sh [--prepare-only]" >&2
  exit 1
fi
kubectl apply -f "$ROOT/base/garage/namespace.yaml"

secret="$(kubectl -n garage get secret garage-credentials --ignore-not-found -o name)"
if [[ -z "$secret" ]]; then
  pvc="$(kubectl -n garage get pvc data-garage-0 --ignore-not-found -o name)"
  if [[ -n "$pvc" ]]; then
    echo "Garage data already exists without its credentials. Restore garage-credentials from backup; refusing to generate replacement keys." >&2
    exit 1
  fi
  kubectl -n garage create secret generic garage-credentials \
    --from-literal="rpc-secret=$(openssl rand -hex 32)" \
    --from-literal="access-key=GK$(openssl rand -hex 16)" \
    --from-literal="secret-key=$(openssl rand -hex 32)"
fi

if ! kubectl -n garage get secret garage-credentials -o json |
  jq -e '.data |
    (."rpc-secret" | @base64d | test("^[0-9a-f]{64}$")) and
    (."access-key" | @base64d | test("^GK[0-9a-f]{32}$")) and
    (."secret-key" | @base64d | test("^[0-9a-f]{64}$"))' > /dev/null; then
  echo "Garage credentials are missing or invalid; restore a valid garage-credentials Secret." >&2
  exit 1
fi
if [[ $# -eq 1 ]]; then
  echo "Garage credentials are ready; apply your Kustomize overlay next."
  exit 0
fi
kubectl apply -k "$ROOT/base/garage"
kubectl -n garage rollout status statefulset/garage --timeout=300s
kubectl -n garage exec garage-0 -- /garage bucket info mybucket > /dev/null
echo "Garage is available at garage.garage:3900 (region garage, bucket mybucket). Credentials are in Secret garage/garage-credentials."
