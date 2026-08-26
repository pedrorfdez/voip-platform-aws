#!/usr/bin/env bash
# Verify that the SIP platform is operational after deployment.
# Usage: ./scripts/verify.sh [NLB_IP_OR_DNS]
# If no address is provided, this script reads it from Terraform state.
# Requirement: sipp must be installed.
#   Debian/Ubuntu: sudo apt install sipp
#   macOS:         brew install sipp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/../environments/nonprod"
SIPP_DIR="${SCRIPT_DIR}/sipp"
TARGET="${1:-}"

# --- Verify sipp is installed ---
if ! command -v sipp &>/dev/null; then
    echo "ERROR: sipp is not installed."
    echo "  Debian/Ubuntu: sudo apt install sipp"
    echo "  macOS:         brew install sipp"
    exit 1
fi

# --- Get the NLB address ---
if [[ -z "${TARGET}" ]]; then
    echo "==> Reading NLB address from Terraform state..."
    TARGET=$(terraform -chdir="${ENV_DIR}" output -raw nlb_dns_name 2>/dev/null || true)
    if [[ -z "${TARGET}" ]]; then
        echo "ERROR: Could not read nlb_dns_name from Terraform state."
        echo "  Run './scripts/up.sh' first, or pass the NLB address as an argument."
        echo "  Example: ./scripts/verify.sh 108.132.141.244"
        exit 1
    fi
fi

echo "    Target: ${TARGET}:5060"
echo ""

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local xml="$2"
    local output

    printf "%-45s" "  ${name}..."

    if output=$(sipp "${TARGET}:5060" \
        -sf "${SIPP_DIR}/${xml}" \
        -t t1 \
        -m 1 \
        -timeout 10s \
        < /dev/null 2>&1); then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        echo "${output}" | grep -E "^(Error|Unexpected|Timeout|SIP)" | head -5 || echo "${output}" | tail -5
        FAIL=$((FAIL + 1))
    fi
}

echo "==> Running SIP verification tests..."
echo ""
run_test "Liveness — OPTIONS → 405"     "01_options.xml"
run_test "Auth + DB — REGISTER → 200"   "02_register.xml"
echo ""
echo "---------------------------------------------------"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "---------------------------------------------------"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "  To debug: check CloudWatch logs at /ecs/ringr-sip-nonprod"
    exit 1
fi
