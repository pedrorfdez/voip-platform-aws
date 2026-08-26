#!/usr/bin/env bash
# Provision the nonprod environment.
# Usage: ./scripts/up.sh [--yes]
# --yes  Auto-approve the plan without an interactive prompt.

set -euo pipefail

ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../environments/nonprod" && pwd)"
AUTO_APPROVE=""

for arg in "$@"; do
    case "${arg}" in
        --yes) AUTO_APPROVE="-auto-approve" ;;
        *) echo "ERROR: Unknown argument: ${arg}"; exit 1 ;;
    esac
done

echo "==> Initializing Terraform..."
terraform -chdir="${ENV_DIR}" init -upgrade

echo ""
echo "==> Applying nonprod environment..."
# shellcheck disable=SC2086
terraform -chdir="${ENV_DIR}" apply -var-file=nonprod.tfvars ${AUTO_APPROVE}

echo ""
echo "==> Outputs:"
terraform -chdir="${ENV_DIR}" output

echo ""
echo "==> Environment is ready."
echo "    Run './scripts/verify.sh' to confirm the platform is operational."
