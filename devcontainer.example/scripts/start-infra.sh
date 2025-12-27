#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INFRA_DIR="${WORKSPACE_DIR}/../../infrastructure"

if ! command -v docker >/dev/null 2>&1; then
    echo "Infra start skipped: docker not available"
    exit 1
fi

if [ ! -d "${INFRA_DIR}" ]; then
    echo "Infra start skipped: ${INFRA_DIR} not found"
    exit 1
fi

if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    echo "Infra start skipped: docker compose not available"
    exit 1
fi

if ! docker network inspect frappe-network >/dev/null 2>&1; then
    docker network create frappe-network >/dev/null
fi

DB_PASSWORD=""
INFRA_DEBUG=""
if [ -f "${WORKSPACE_DIR}/.devcontainer/.env" ]; then
    DB_PASSWORD=$(grep "^DB_PASSWORD=" "${WORKSPACE_DIR}/.devcontainer/.env" | cut -d= -f2)
    INFRA_DEBUG=$(grep "^INFRA_DEBUG=" "${WORKSPACE_DIR}/.devcontainer/.env" | cut -d= -f2)
fi

if [ "${INFRA_DEBUG}" = "1" ]; then
    LOG_DIR="${WORKSPACE_DIR}/.devcontainer/logs"
    LOG_FILE="${LOG_DIR}/start-infra.log"
    mkdir -p "${LOG_DIR}"
    exec > >(tee -a "${LOG_FILE}") 2>&1
    set -x
    echo "start-infra.sh $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "workspace_dir=${WORKSPACE_DIR}"
    echo "infra_dir=${INFRA_DIR}"
    echo "compose_cmd=${COMPOSE[*]}"
    echo "db_password_set=$([ -n "${DB_PASSWORD}" ] && echo yes || echo no)"
fi

infra_running=true
for container in frappe-mariadb frappe-redis-cache frappe-redis-queue frappe-redis-socketio; do
    if ! docker ps -q -f "name=^${container}$" >/dev/null 2>&1; then
        infra_running=false
        break
    fi
    if [ -z "$(docker ps -q -f "name=^${container}$")" ]; then
        infra_running=false
        break
    fi
done

if [ "${infra_running}" = "true" ]; then
    echo "Infra already running"
    exit 0
fi

(
    cd "${INFRA_DIR}"
    if [ -n "$DB_PASSWORD" ]; then
        COMPOSE_PROJECT_NAME=frappe-infra DB_PASSWORD="$DB_PASSWORD" ${COMPOSE[@]} up -d
    else
        COMPOSE_PROJECT_NAME=frappe-infra ${COMPOSE[@]} up -d
    fi
)
