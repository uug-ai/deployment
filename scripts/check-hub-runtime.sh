#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="${1:?Usage: bash scripts/check-hub-runtime.sh /path/to/charts/hub}"

assert_contains() {
  local rendered="$1" pattern="$2"
  if ! grep -Eq -- "$pattern" <<< "$rendered"; then
    printf 'Missing expected Hub runtime setting: %s\n' "$pattern" >&2
    return 1
  fi
}

nodeport="$(awk '
  /^---/ { selected=0 }
  /name: hub-frontend-nodeport$/ { selected=1 }
  selected { print }
' "$ROOT/base/hub/kerberos-hub-nodeports.yaml")"
assert_contains "$nodeport" 'targetPort: http$'
assert_contains "$nodeport" 'port: 80$'
assert_contains "$nodeport" 'nodePort: 32080'

HARDENED_FLAGS=(
  --set kerberoshub.frontend.containerPort=8080
  --set-json 'kerberoshub.frontend.securityContext={"runAsNonRoot":true,"runAsUser":65532,"runAsGroup":65532,"readOnlyRootFilesystem":true,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}}'
  --set-json 'kerberoshub.frontend.volumes=[{"name":"frontend-tmp","emptyDir":{"medium":"Memory","sizeLimit":"16Mi"}}]'
  --set-json 'kerberoshub.frontend.volumeMounts=[{"name":"frontend-tmp","mountPath":"/tmp"}]'
)

for runtime in legacy hardened; do
  flags=()
  port=80
  if [[ "$runtime" == hardened ]]; then
    flags=("${HARDENED_FLAGS[@]}")
    port=8080
  fi
  rendered="$(helm template hub "$CHART_DIR" \
    --values "$ROOT/base/hub/kerberos-hub-values.yaml" \
    --set mode=ui --set kerberoshub.frontend.demoEnabled=true "${flags[@]}")"
  for frontend in hub-frontend hub-frontend-demo; do
    resource="$(awk -v source="# Source: hub/templates/kerberos-hub/$frontend.yaml" '
      /^---/ { selected=0 }
      /^# Source:/ { selected=($0 == source); next }
      selected { print }
    ' <<< "$rendered")"
    assert_contains "$resource" 'targetPort: http$'
    assert_contains "$resource" 'port: 80$'
    assert_contains "$resource" "containerPort: $port$"
    assert_contains "$resource" 'name: http$'
    if [[ "$runtime" == hardened ]]; then
      for setting in 'runAsNonRoot: true' 'runAsUser: 65532' \
        'runAsGroup: 65532' 'readOnlyRootFilesystem: true' \
        'allowPrivilegeEscalation: false' 'type: RuntimeDefault' \
        'drop:' '- ALL' 'medium: Memory' 'sizeLimit: 16Mi' \
        'mountPath: /tmp' 'name: frontend-tmp'; do
        assert_contains "$resource" "^[[:space:]]*(- )?$setting$"
      done
    fi
    echo "OK ($runtime): $frontend routes http to $port"
  done
done

echo "Hub frontend NodePort and chart runtime checks passed."
