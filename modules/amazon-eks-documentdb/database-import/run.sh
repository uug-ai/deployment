#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-kerberos-hub}"
timeout="${TIMEOUT:-5m}"
job_name="hub-documentdb-import"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

for command_name in kubectl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
done

flavor="$(kubectl get configmap mongodb-config \
  --namespace "$namespace" \
  --output jsonpath='{.data.MONGODB_FLAVOR}')"
retry_writes="$(kubectl get configmap mongodb-config \
  --namespace "$namespace" \
  --output jsonpath='{.data.MONGODB_RETRY_WRITES}')"
ca_bundle="$(kubectl get secret mongodb-ca \
  --namespace "$namespace" \
  --output jsonpath='{.data.global-bundle\.pem}')"

if [[ "${flavor,,}" != "documentdb" ]]; then
  echo "Refusing import: mongodb-config MONGODB_FLAVOR must be documentdb" >&2
  exit 1
fi
if [[ "${retry_writes,,}" != "false" ]]; then
  echo "Refusing import: mongodb-config MONGODB_RETRY_WRITES must be false" >&2
  exit 1
fi
if [[ -z "$ca_bundle" ]]; then
  echo "Refusing import: mongodb-ca/global-bundle.pem is missing" >&2
  exit 1
fi

kubectl delete job "$job_name" \
  --namespace "$namespace" \
  --ignore-not-found=true \
  --wait=true
kubectl apply --kustomize "$script_dir" --namespace "$namespace"

if ! kubectl wait \
  --namespace "$namespace" \
  --for=condition=complete \
  --timeout="$timeout" \
  "job/$job_name"; then
  kubectl logs --namespace "$namespace" "job/$job_name" --all-containers=true || true
  exit 1
fi

kubectl logs --namespace "$namespace" "job/$job_name" --all-containers=true