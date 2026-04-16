#!/usr/bin/env bash
set -euo pipefail

DOCKER_ADDRESS="localhost"
PROJECT_NAME="r"
RABBITMQ_USER="${RABBITMQ_USER:-admin}"
RABBITMQ_PASS="${RABBITMQ_PASS:-admin}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-60}"

RABBITMQ1_NAME="rabbitmq1"
RABBITMQ2_NAME="rabbitmq2"
RABBITMQ3_NAME="rabbitmq3"
RABBITMQ4_NAME="rabbitmq4"
RABBITMQ5_NAME="rabbitmq5"

RABBITMQ1_API="http://${DOCKER_ADDRESS}:15673/api/overview"
RABBITMQ2_API="http://${DOCKER_ADDRESS}:15674/api/overview"
RABBITMQ3_API="http://${DOCKER_ADDRESS}:15675/api/overview"
RABBITMQ4_API="http://${DOCKER_ADDRESS}:15676/api/overview"
RABBITMQ5_API="http://${DOCKER_ADDRESS}:15677/api/overview"

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  echo "[$(timestamp)] $*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

get_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
    return 0
  fi

  return 1
}

COMPOSE_CMD="$(get_compose_cmd)" || fail "Neither 'docker compose' nor 'docker-compose' is available."

wait_for_management_api() {
  local name="$1"
  local url="$2"
  local elapsed=0

  log "Waiting for $name management API at $url..."

  until curl -fsS -u "$RABBITMQ_USER:$RABBITMQ_PASS" "$url" >/dev/null 2>&1; do
    sleep 1
    elapsed=$((elapsed + 1))

    if (( elapsed >= WAIT_TIMEOUT_SECONDS )); then
      fail "Timed out waiting for $name management API after ${WAIT_TIMEOUT_SECONDS}s"
    fi
  done

  log "$name management API is available"
}

wait_for_all_nodes() {
  wait_for_management_api "$RABBITMQ1_NAME" "$RABBITMQ1_API"
  wait_for_management_api "$RABBITMQ2_NAME" "$RABBITMQ2_API"
  wait_for_management_api "$RABBITMQ3_NAME" "$RABBITMQ3_API"
  wait_for_management_api "$RABBITMQ4_NAME" "$RABBITMQ4_API"
  wait_for_management_api "$RABBITMQ5_NAME" "$RABBITMQ5_API"
}

cluster_node() {
  local node="$1"
  local target="$2"

  log "Joining $node to cluster with $target..."

  docker exec "$node" /bin/bash -c "
    rabbitmqctl stop_app &&
    rabbitmqctl reset &&
    rabbitmqctl join_cluster rabbit@$target &&
    rabbitmqctl start_app
  " >/dev/null

  log "$node joined rabbit@$target"
}

verify_cluster_membership() {
  local expected_nodes=("$@")
  local cluster_status

  log "Verifying cluster membership..."

  cluster_status="$(docker exec "$RABBITMQ1_NAME" /bin/bash -c 'rabbitmqctl cluster_status')" \
    || fail "Unable to get cluster status from $RABBITMQ1_NAME"

  echo "$cluster_status"

  for node in "${expected_nodes[@]}"; do
    if ! grep -q "rabbit@${node}" <<<"$cluster_status"; then
      fail "Expected node rabbit@${node} was not found in cluster status"
    fi
  done

  log "Cluster membership verified"
}

show_overview() {
  log "RabbitMQ cluster overview from ${RABBITMQ1_NAME}:"
  docker exec "$RABBITMQ1_NAME" /bin/bash -c "rabbitmqctl cluster_status" || true
}

start_cluster() {
  log "Starting RabbitMQ containers with project '$PROJECT_NAME'..."
  $COMPOSE_CMD -p "$PROJECT_NAME" up -d --build
}

main() {
  start_cluster
  wait_for_all_nodes

  cluster_node "$RABBITMQ2_NAME" "$RABBITMQ1_NAME"
  cluster_node "$RABBITMQ3_NAME" "$RABBITMQ1_NAME"
  cluster_node "$RABBITMQ4_NAME" "$RABBITMQ1_NAME"
  cluster_node "$RABBITMQ5_NAME" "$RABBITMQ1_NAME"

  verify_cluster_membership \
    "$RABBITMQ1_NAME" \
    "$RABBITMQ2_NAME" \
    "$RABBITMQ3_NAME" \
    "$RABBITMQ4_NAME" \
    "$RABBITMQ5_NAME"

  show_overview

  log "Everything is set!"
}

main "$@"
