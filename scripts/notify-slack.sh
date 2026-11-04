#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  echo "Usage: bash scripts/notify-slack.sh MESSAGE" >&2
  exit 1
fi

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  echo "::warning::SLACK_WEBHOOK_URL is not configured; skipping optional Slack notification."
  exit 0
fi

jq -n --arg text "$1" '{text: $text}' |
  curl --fail-with-body --silent --show-error --retry 3 \
    -H 'Content-Type: application/json' --data-binary @- "$SLACK_WEBHOOK_URL"
