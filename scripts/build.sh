#!/usr/bin/env bash
# Build, tag, and push the SIP server image to ECR.
# The image tag is the short git commit SHA of the current HEAD.
# After a successful push, this script updates container_image in nonprod.tfvars.
#
# Usage: ./scripts/build.sh
#
# Requirements:
#   - docker
#   - aws CLI (authenticated, with ECR push permissions)
#   - terraform

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_DIR="${REPO_ROOT}/environments/nonprod"
TFVARS_FILE="${ENV_DIR}/nonprod.tfvars"
SIP_SERVER_DIR="${REPO_ROOT}/sip-server"

# --- Verify requirements ---
for cmd in docker aws terraform git; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "ERROR: '${cmd}' is not installed or not in PATH."
        exit 1
    fi
done

# --- Derive image tag from git commit SHA ---
TAG=$(git -C "${REPO_ROOT}" rev-parse --short HEAD)
echo "==> Image tag: ${TAG}"

# --- Read ECR URL ---
# Primary: Terraform state output. This works when the environment is provisioned.
# Fallback: parse the repository URL from the existing container_image in nonprod.tfvars.
#   ECR repositories persist across terraform destroy cycles, so the URL in tfvars
#   is always valid even when the rest of the state is empty.
echo "==> Reading ECR repository URL..."
ECR_URL=$(terraform -chdir="${ENV_DIR}" output -raw ecr_repository_url 2>/dev/null || true)

if [[ -z "${ECR_URL}" ]]; then
    echo "    Terraform state unavailable. Parsing URL from nonprod.tfvars..."
    CURRENT_IMAGE=$(grep 'container_image' "${TFVARS_FILE}" | sed 's/.*= *"\(.*\)"/\1/')
    ECR_URL="${CURRENT_IMAGE%:*}"
fi

if [[ -z "${ECR_URL}" ]]; then
    echo "ERROR: Could not determine ECR repository URL."
    echo "  Set container_image in nonprod.tfvars, or run './scripts/up.sh' first."
    exit 1
fi

IMAGE="${ECR_URL}:${TAG}"
echo "    Image: ${IMAGE}"

# --- Derive AWS region from the ECR URL ---
# ECR URLs follow the pattern: <account>.dkr.ecr.<region>.amazonaws.com/<repo>
AWS_REGION=$(echo "${ECR_URL}" | cut -d'.' -f4)
echo "    Region: ${AWS_REGION}"

# --- Authenticate Docker with ECR ---
echo ""
echo "==> Authenticating with ECR..."
aws ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${ECR_URL%%/*}"

# --- Build image ---
echo ""
echo "==> Building image..."
docker build \
    --platform linux/amd64 \
    --tag "${IMAGE}" \
    "${SIP_SERVER_DIR}"

# --- Push image ---
echo ""
echo "==> Pushing image..."
docker push "${IMAGE}"

# --- Update container_image in nonprod.tfvars ---
echo ""
echo "==> Updating container_image in nonprod.tfvars..."
# BSD sed (macOS) requires a backup extension with -i; GNU sed (Linux) does not.
# The .bak file is removed immediately after so the behaviour is identical on both.
sed -i.bak "s|container_image = \".*\"|container_image = \"${IMAGE}\"|" "${TFVARS_FILE}"
rm -f "${TFVARS_FILE}.bak"

echo "    container_image = \"${IMAGE}\""

echo ""
echo "==> Done."
echo "    Run './scripts/up.sh' to deploy the new image."
