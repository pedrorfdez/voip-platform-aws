#!/usr/bin/env bash
# Run the full local media test harness: signaling + real RTP audio,
# entirely in Docker, no AWS credentials or Terraform required.
# Usage: ./scripts/local-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_TEST_DIR="${SCRIPT_DIR}/../local-test"

cleanup() {
    echo ""
    echo "==> Tearing down local stack..."
    (cd "${LOCAL_TEST_DIR}" && docker compose down -v)
}
trap cleanup EXIT

cd "${LOCAL_TEST_DIR}"
[[ -f .env ]] || cp .env.example .env

echo "==> Building and starting the local media plane (postgres, kamailio, rtpengine)..."
docker compose up -d --build postgres kamailio rtpengine

echo "==> Waiting for Kamailio to bootstrap and connect to rtpengine..."
for _ in $(seq 1 20); do
    docker compose logs kamailio 2>&1 | grep -q "Bootstrap complete" && break
    sleep 1
done
docker compose logs kamailio 2>&1 | grep -q "Bootstrap complete" || {
    echo "ERROR: Kamailio did not finish bootstrapping in time."
    docker compose logs kamailio
    exit 1
}

echo ""
echo "==> Running SIP signaling tests..."
bash scripts/run-signaling-test.sh

echo ""
echo "==> Running end-to-end RTP audio test..."
bash scripts/run-audio-test.sh

echo ""
echo "==> All local media tests passed."
