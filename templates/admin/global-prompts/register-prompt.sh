#!/bin/bash
# Register the Fed Aura Capital system prompt in the MLflow Prompt Registry.
#
# The Prompt CRD does not exist on this cluster, so we register the prompt
# via the MLflow UI plugin REST API instead.
#
# Prerequisites:
#   - oc login (cluster admin)
#   - Target workspace namespace must have label opendatahub.io/dashboard=true
#
# Usage:
#   ./register-prompt.sh                    # registers in default workspace (project1)
#   ./register-prompt.sh my-workspace       # registers in a specific workspace

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_NAME="fed-aura-capital-system-prompt"
PROMPT_FILE="${SCRIPT_DIR}/fed-aura-capital-system-prompt.txt"
WORKSPACE="${1:-project1}"
MLFLOW_SVC="odh-dashboard-mlflow-ui"
MLFLOW_NS="redhat-ods-applications"
LOCAL_PORT=18343

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

cleanup() {
    if [ -n "${PF_PID:-}" ] && kill -0 "$PF_PID" 2>/dev/null; then
        kill "$PF_PID" 2>/dev/null
        wait "$PF_PID" 2>/dev/null || true
    fi
    rm -f "${TMPFILE:-}"
}
trap cleanup EXIT

if ! oc whoami &>/dev/null; then
    error "Not logged in to OpenShift. Run 'oc login' first."
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    error "Prompt file not found: $PROMPT_FILE"
    exit 1
fi

TOKEN=$(oc whoami -t)
BASE_URL="https://localhost:${LOCAL_PORT}"
API_URL="${BASE_URL}/api/v1/prompts"
TMPFILE=$(mktemp)

info "Workspace: ${WORKSPACE}"
info "Prompt: ${PROMPT_NAME}"

info "Port-forwarding to ${MLFLOW_SVC}..."
oc port-forward "svc/${MLFLOW_SVC}" "${LOCAL_PORT}:8343" -n "${MLFLOW_NS}" &>/dev/null &
PF_PID=$!
sleep 3

if ! kill -0 "$PF_PID" 2>/dev/null; then
    error "Port-forward failed. Is the MLflow UI plugin running?"
    exit 1
fi

AUTH_HEADER="X-Forwarded-Access-Token: ${TOKEN}"
USER_HEADER="X-Forwarded-User: $(oc whoami)"

HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' \
    -H "$AUTH_HEADER" -H "$USER_HEADER" \
    "${API_URL}/${PROMPT_NAME}?workspace=${WORKSPACE}")

PROMPT_TEMPLATE=$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" < "$PROMPT_FILE")

if [ "$HTTP_CODE" = "200" ]; then
    warn "Prompt '${PROMPT_NAME}' already exists in workspace '${WORKSPACE}', replacing..."
    curl -sk -o /dev/null -X DELETE \
        -H "$AUTH_HEADER" -H "$USER_HEADER" \
        "${API_URL}/${PROMPT_NAME}?workspace=${WORKSPACE}"
    info "Old prompt deleted"
fi

info "Creating prompt '${PROMPT_NAME}'..."

CODE=$(curl -sk -o "$TMPFILE" -w '%{http_code}' \
    -X POST \
    -H "$AUTH_HEADER" -H "$USER_HEADER" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${PROMPT_NAME}\", \"template\": ${PROMPT_TEMPLATE}, \"tags\": {\"description\": \"Fed Aura Capital prospect agent system prompt\"}}" \
    "${API_URL}?workspace=${WORKSPACE}")

if [ "$CODE" = "201" ]; then
    info "Prompt registered successfully"
else
    error "Failed to create prompt (HTTP ${CODE}): $(cat "$TMPFILE")"
    exit 1
fi

info "Done. View in RHOAI dashboard under MLflow > Prompts > ${PROMPT_NAME}"
