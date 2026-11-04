#!/usr/bin/env bash
set -uo pipefail

kubectl get pods,pvc -A -o wide
kubectl get events -A --sort-by=.lastTimestamp
for namespace in garage mongodb rabbitmq vernemq kerberos-vault kerberos-agent kerberos-hub; do
  if ! pods="$(kubectl -n "$namespace" get pods -o name)"; then
    echo "::warning::Could not list pods in $namespace."
    continue
  fi
  for pod in $pods; do
    if ! kubectl -n "$namespace" describe "$pod"; then
      echo "::warning::Could not describe $namespace/$pod."
    fi
    if ! kubectl -n "$namespace" logs "$pod" --all-containers=true --tail=80 --prefix; then
      echo "::warning::Logs unavailable for $namespace/$pod."
    fi
  done
done
