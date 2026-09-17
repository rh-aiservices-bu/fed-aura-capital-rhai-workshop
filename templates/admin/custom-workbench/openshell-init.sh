#!/bin/bash
# Auto-configure OpenShell gateway via port-forward.
# Sourced from /etc/profile.d/ when a terminal opens in the workbench.

OPENSHELL_GW_NAME="${OPENSHELL_GW_NAME:-openshift}"
OPENSHELL_GW_PORT="${OPENSHELL_GW_PORT:-8080}"

command -v openshell &>/dev/null || return 0
command -v kubectl &>/dev/null  || return 0

_openshell_pf_running() {
    pgrep -f "kubectl port-forward.*openshell.*${OPENSHELL_GW_PORT}" &>/dev/null
}

_openshell_start_pf() {
    kubectl port-forward statefulset/openshell "${OPENSHELL_GW_PORT}:${OPENSHELL_GW_PORT}" &>/dev/null &
    disown
    sleep 2
}

if openshell gateway list 2>/dev/null | grep -q "$OPENSHELL_GW_NAME"; then
    _openshell_pf_running || _openshell_start_pf
    return 0
fi

_openshell_start_pf

if openshell gateway add "http://localhost:${OPENSHELL_GW_PORT}" --name "$OPENSHELL_GW_NAME" --local &>/dev/null; then
    echo "OpenShell gateway '${OPENSHELL_GW_NAME}' ready (localhost:${OPENSHELL_GW_PORT})"
fi

unset -f _openshell_pf_running _openshell_start_pf
