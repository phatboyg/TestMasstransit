#!/usr/bin/env bash
set -euo pipefail

API_URL="http://localhost:15672/api/consumers"
API_USER="admin"
API_PASS="admin"
EXPECTED_COUNT=33
SLEEP_SECONDS=5
POST_DRAIN_WAIT_SECONDS=20

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  echo "[$(timestamp)] $*"
}

fail_with_error() {
  log "We found the error"
  log "$1"
  log "Current summary:"
  get_consumer_summary || true
  exit 1
}

get_consumer_summary() {
  curl -sS --fail "$API_URL" -u "$API_USER:$API_PASS" \
    | jq -r '
        group_by(.channel_details.node)
        | map({
            node: (.[0].channel_details.node | split("@")[1]),
            count: length
          })
        | .[]
        | "\(.node) \(.count)"
      '
}

get_single_expected_node() {
  local matches
  matches="$(get_consumer_summary | awk -v expected="$EXPECTED_COUNT" '$2 == expected { print $1 }')"

  local match_count
  match_count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$match_count" != "1" ]]; then
    return 1
  fi

  printf '%s\n' "$matches"
}

drain_node() {
  local node="$1"
  log "Draining node: $node"
  docker exec "$node" /bin/bash -c "rabbitmq-upgrade drain"
}

revive_node() {
  local node="$1"
  log "Reviving node: $node"
  docker exec "$node" /bin/bash -c "rabbitmq-upgrade revive"
}

wait_for_new_expected_node() {
  local old_node="$1"
  local new_node=""

  for ((i=1; i<=POST_DRAIN_WAIT_SECONDS; i++)); do
    if new_node="$(get_single_expected_node 2>/dev/null)" && [[ "$new_node" != "$old_node" ]]; then
      printf '%s\n' "$new_node"
      return 0
    fi

    sleep 1
  done

  return 1
}

while true; do
  log "Checking current consumer placement..."

  current_node="$(get_single_expected_node)" || fail_with_error "Expected exactly one node with $EXPECTED_COUNT consumers before drain."

  log "Current active node: $current_node ($EXPECTED_COUNT consumers)"

  drain_node "$current_node"

  log "Waiting for consumers to move to a different node..."
  new_node="$(wait_for_new_expected_node "$current_node")" \
    || fail_with_error "After drain, consumers did not settle onto a different node with $EXPECTED_COUNT consumers within $POST_DRAIN_WAIT_SECONDS seconds."

  log "Consumers moved to new node: $new_node ($EXPECTED_COUNT consumers)"

  revive_node "$current_node"

  log "Node $current_node revived successfully."
  log "Sleeping for $SLEEP_SECONDS seconds before next cycle..."
  sleep "$SLEEP_SECONDS"
done