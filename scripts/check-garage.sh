#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --restart ) ]]; then
  echo "Usage: bash scripts/check-garage.sh [--restart]" >&2
  exit 1
fi
if ! command -v aws > /dev/null; then
  echo "AWS CLI is required for the Garage S3 smoke test." >&2
  exit 1
fi
temporary="$(mktemp -d)"
pid=""
cleanup() {
  if [[ -n "$pid" ]]; then kill "$pid"; fi
  rm -f "$temporary/upload" "$temporary/download" "$temporary/port-forward.log" "$temporary/aws-config"
  rmdir "$temporary"
}
trap cleanup EXIT

access_key="$(kubectl -n garage get secret garage-credentials -o jsonpath='{.data.access-key}' | base64 --decode)"
secret_key="$(kubectl -n garage get secret garage-credentials -o jsonpath='{.data.secret-key}' | base64 --decode)"
if [[ "${GITHUB_ACTIONS:-false}" == true ]]; then
  echo "::add-mask::$access_key"
  echo "::add-mask::$secret_key"
fi
forward() {
  kubectl -n garage port-forward service/garage 13900:3900 > "$temporary/port-forward.log" 2>&1 &
  pid=$!
  for attempt in {1..30}; do
    if curl --silent --output /dev/null http://127.0.0.1:13900/; then return; fi
    if ! kill -0 "$pid"; then break; fi
    sleep 1
  done
  cat "$temporary/port-forward.log" >&2
  echo "Garage port-forward did not become ready." >&2
  exit 1
}
forward

export AWS_ACCESS_KEY_ID="$access_key" AWS_SECRET_ACCESS_KEY="$secret_key"
export AWS_DEFAULT_REGION=garage AWS_EC2_METADATA_DISABLED=true
export AWS_PAGER=""
unset AWS_SESSION_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
export AWS_CONFIG_FILE="$temporary/aws-config"
printf '[default]\ns3 =\n    addressing_style = path\n' > "$AWS_CONFIG_FILE"
object="ci-smoke/$(openssl rand -hex 16)"
openssl rand -hex 128 > "$temporary/upload"
endpoint="http://127.0.0.1:13900"
aws --endpoint-url "$endpoint" s3api put-object \
  --bucket mybucket --key "$object" --body "$temporary/upload"
if [[ $# -eq 1 ]]; then
  kill "$pid"
  wait "$pid" || [[ "$?" == 143 ]]
  pid=""
  kubectl -n garage rollout restart statefulset/garage
  kubectl -n garage rollout status statefulset/garage --timeout=300s
  forward
fi
aws --endpoint-url "$endpoint" s3api get-object \
  --bucket mybucket --key "$object" "$temporary/download"
cmp "$temporary/upload" "$temporary/download"
echo "Garage S3 authenticated PUT/GET passed through the Kubernetes Service (object mybucket/$object retained)."
