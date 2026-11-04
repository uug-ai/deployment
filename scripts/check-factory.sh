#!/usr/bin/env bash
set -euo pipefail

if [[ "${CI:-false}" != true ]]; then
  echo "This smoke test changes Factory settings and restarts its pod. Run it only in a disposable CI cluster (CI=true)." >&2
  exit 1
fi

temporary="$(mktemp -d)"
pid=""
stop_forward() {
  if [[ -n "$pid" ]]; then
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      wait "$pid" || [[ "$?" == 143 ]]
    fi
    pid=""
  fi
}
cleanup() {
  stop_forward
  rm -f "$temporary/port-forward.log" "$temporary/login.json" "$temporary/config.json" "$temporary/saved.json" "$temporary/index.html"
  rmdir "$temporary"
}
trap cleanup EXIT

kubectl -n kerberos-factory rollout status deployment/factory --timeout=300s
kubectl -n kerberos-factory get deployment factory -o json | jq -e '
  .spec.template.spec as $pod |
  $pod.securityContext.fsGroup == 65532 and
  $pod.securityContext.seccompProfile.type == "RuntimeDefault" and
  ($pod.containers[] | select(.name == "factory") |
    .securityContext.runAsNonRoot == true and
    .securityContext.runAsUser == 65532 and .securityContext.runAsGroup == 65532 and
    .securityContext.readOnlyRootFilesystem == true and
    .securityContext.allowPrivilegeEscalation == false and
    .securityContext.capabilities.drop == ["ALL"] and
    .ports == [{"name":"http","containerPort":8080,"protocol":"TCP"}] and
    any(.volumeMounts[]; .mountPath == "/home/factory/config") and
    any(.volumeMounts[]; .mountPath == "/tmp") and
    .startupProbe.httpGet.path == "/healthz" and
    .readinessProbe.httpGet.port == "http" and
    .livenessProbe.httpGet.port == "http")'
kubectl -n kerberos-factory get service factory-nodeport -o json |
  jq -e '.spec.ports | any(.port == 80 and .targetPort == "http" and .nodePort == 30079)'
kubectl -n kerberos-factory get configmap agent-global-config agent-template-config
kubectl -n kerberos-factory exec deployment/factory -- /app/main healthcheck

forward() {
  kubectl -n kerberos-factory port-forward service/factory-nodeport 13979:80 > "$temporary/port-forward.log" 2>&1 &
  pid=$!
  for attempt in {1..30}; do
    if curl --fail --silent http://127.0.0.1:13979/healthz >/dev/null; then return; fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 1
  done
  cat "$temporary/port-forward.log" >&2
  echo "Factory Service port-forward did not become healthy." >&2
  exit 1
}
login() {
  curl --fail --silent --show-error -H 'Content-Type: application/json' \
    -d '{"username":"root","password":"kerberos"}' \
    http://127.0.0.1:13979/api/login > "$temporary/login.json"
  token="$(jq -er '.token | select(length > 0)' "$temporary/login.json")"
  if [[ "${GITHUB_ACTIONS:-false}" == true ]]; then echo "::add-mask::$token"; fi
}
forward
curl --fail --silent --show-error http://127.0.0.1:13979/ > "$temporary/index.html"
grep -qi '<html' "$temporary/index.html"
test "$(curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:13979/api/config)" = 401
login
curl --fail --silent --show-error -H "Authorization: Bearer $token" \
  http://127.0.0.1:13979/api/config > "$temporary/config.json"
jq -e '.data.type == "global"' "$temporary/config.json"
jq '.data | .timezone = (if .timezone == "UTC" then "Etc/GMT+1" else "UTC" end)' \
  "$temporary/config.json" > "$temporary/saved.json"
timezone="$(jq -r '.timezone' "$temporary/saved.json")"
curl --fail --silent --show-error -H "Authorization: Bearer $token" \
  -H 'Content-Type: application/json' --data-binary "@$temporary/saved.json" \
  http://127.0.0.1:13979/api/config | jq -e --arg timezone "$timezone" '.data.timezone == $timezone'
kubectl -n kerberos-factory get configmap agent-global-config -o json |
  jq -e --arg timezone "$timezone" '.data["_source.json"] | fromjson | .timezone == $timezone'

pod_uid() {
  kubectl -n kerberos-factory get pods -l app=factory -o json |
    jq -er '[.items[] | select(.metadata.deletionTimestamp == null)][0].metadata.uid'
}
old_pod="$(pod_uid)"
stop_forward
kubectl -n kerberos-factory rollout restart deployment/factory
kubectl -n kerberos-factory rollout status deployment/factory --timeout=300s
test "$old_pod" != "$(pod_uid)"
forward
login
curl --fail --silent --show-error -H "Authorization: Bearer $token" \
  http://127.0.0.1:13979/api/config | jq -e --arg timezone "$timezone" '.data.timezone == $timezone'
kubectl -n kerberos-factory exec deployment/factory -- /app/main healthcheck
echo "Factory passed: restricted runtime, Service routing, UI/auth/config, ConfigMap bootstrap and persisted settings after pod replacement."
