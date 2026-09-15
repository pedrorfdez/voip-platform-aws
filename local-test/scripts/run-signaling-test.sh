#!/usr/bin/env bash
# local-test/scripts/run-signaling-test.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Stop Git Bash (MSYS) on Windows from rewriting "/sipp/..." container
# paths into host Windows paths before they reach docker. No effect on
# Linux or macOS shells, where this variable is not read.
export MSYS_NO_PATHCONV=1

PASS=0
FAIL=0

run_scenario() {
    local name="$1" xml="$2"
    printf "%-45s" "  ${name}..."
    if docker compose run --rm sipp "kamailio:5060" -sf "/sipp/${xml}" -t t1 -m 1 -timeout 10s >/tmp/sipp-out.log 2>&1; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        tail -5 /tmp/sipp-out.log
        FAIL=$((FAIL + 1))
    fi
}

echo "==> Running SIP signaling tests against the local stack..."
run_scenario "Liveness — OPTIONS -> 405"   "01_options.xml"
run_scenario "Auth + DB — REGISTER -> 200" "02_register.xml"

echo "  Results: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]]
