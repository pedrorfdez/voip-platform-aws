#!/usr/bin/env bash
# Destroy the nonprod environment to stop all AWS costs.
# Usage: ./scripts/down.sh [--yes]
# --yes  Auto-approve destruction without an interactive prompt.
#
# Cost implication: all running resources are removed.
# The ECR repository and its images are retained.

set -euo pipefail

ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../environments/nonprod" && pwd)"
AUTO_APPROVE=""

for arg in "$@"; do
    case "${arg}" in
        --yes) AUTO_APPROVE="-auto-approve" ;;
        *) echo "ERROR: Unknown argument: ${arg}"; exit 1 ;;
    esac
done

echo "==> Destroying nonprod environment..."
echo "    This action removes all running AWS resources and stops all costs."
echo ""

# shellcheck disable=SC2086
terraform -chdir="${ENV_DIR}" destroy -var-file=nonprod.tfvars ${AUTO_APPROVE}

echo ""
echo "==> Done. All nonprod resources are removed."
echo "    Run './scripts/up.sh' to recreate the environment."
