#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${1:-kerberos/hub}"

assert_contains() {
  if ! grep -Eq -- "$2" <<< "$1"; then
    printf 'Missing expected deployment runtime setting: %s\n' "$2" >&2
    exit 1
  fi
}

nodeport="$(awk '
  /^---/ { selected=0 }
  /name: hub-frontend-nodeport$/ { selected=1 }
  selected { print }
' "$ROOT/base/hub/kerberos-hub-nodeports.yaml")"
assert_contains "$nodeport" 'targetPort: http$'
assert_contains "$nodeport" 'nodePort: 32080'

rendered="$(helm template hub "$CHART" --values "$ROOT/base/hub/kerberos-hub-values.yaml" \
  --set mode=ui --set kerberoshub.frontend.demoEnabled=true)"
if grep -q 'image: "docker.io/ghcr.io/' <<< "$rendered"; then
  echo "Fully qualified GHCR image was prefixed with docker.io" >&2
  exit 1
fi
for name in hub-frontend hub-frontend-demo; do
  deployment="$(awk -v name="$name" '
    function emit() { if (deployment && matched) printf "%s", block }
    /^---$/ { emit(); block=""; deployment=0; matched=0 }
    { block=block $0 "\n" }
    /^kind: Deployment$/ { deployment=1 }
    $0 == "  name: " name { matched=1 }
    END { emit() }
  ' <<< "$rendered")"
  for setting in 'containerPort: 8080' 'runAsNonRoot: true' 'runAsUser: 65532' \
    'readOnlyRootFilesystem: true' 'mountPath: /tmp' 'name: frontend-tmp'; do
    assert_contains "$deployment" "^[[:space:]]*(- )?$setting$"
  done
  assert_contains "$deployment" 'image: "ghcr.io/uug-ai/hub-frontend:v1.19.28"$'
  echo "OK: $name uses the promoted image and matching hardened runtime"
done
echo "Deployment Hub runtime preflight passed."
