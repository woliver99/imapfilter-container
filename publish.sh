#!/usr/bin/env bash
# ==============================================================================
# publish.sh - Build and publish container to GitHub Packages (ghcr.io)
# ==============================================================================
set -euo pipefail

REGISTRY="ghcr.io"
REPO_OWNER="woliver99"
IMAGE_NAME="imapfilter-container"
FULL_IMAGE="${REGISTRY}/${REPO_OWNER}/${IMAGE_NAME}"
VERSION="${1:-}"

# Terminal colors
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}${BOLD}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}${BOLD}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}${BOLD}[WARN]${NC} $*"; }
err()   { echo -e "${RED}${BOLD}[ERROR]${NC} $*" >&2; }

# Ensure script is run from project root
if [[ ! -f "Dockerfile" || ! -f "config.lua" ]]; then
    err "This script must be executed from the root of the imapfilter-container repository."
    exit 1
fi

# Detect container runtime (docker or podman)
if command -v docker >/dev/null 2>&1; then
    CONTAINER_CLI="docker"
elif command -v podman >/dev/null 2>&1; then
    CONTAINER_CLI="podman"
else
    err "Neither 'docker' nor 'podman' was found in PATH. Please install a container engine."
    exit 1
fi

info "Using container CLI: ${CONTAINER_CLI}"

# 1. Build container image
info "Building container image '${FULL_IMAGE}:latest'..."
BUILD_ARGS=(-t "${FULL_IMAGE}:latest")

if [[ -n "${VERSION}" ]]; then
    BUILD_ARGS+=(-t "${FULL_IMAGE}:${VERSION}")
    info "Also tagging as '${FULL_IMAGE}:${VERSION}'"
fi

"${CONTAINER_CLI}" build "${BUILD_ARGS[@]}" .
ok "Container image built successfully."

# 2. Check / perform authentication with ghcr.io
info "Checking authentication with ${REGISTRY}..."

login_to_registry() {
    # If environment variable token is set, use it directly
    local env_token="${CR_PAT:-${GITHUB_TOKEN:-${GHCR_TOKEN:-}}}"
    if [[ -n "${env_token}" ]]; then
        info "Authenticating with ${REGISTRY} using environment token..."
        echo "${env_token}" | "${CONTAINER_CLI}" login "${REGISTRY}" -u "${REPO_OWNER}" --password-stdin
        return 0
    fi

    # Check if existing credentials exist in Docker config
    if "${CONTAINER_CLI}" login "${REGISTRY}" --get-login >/dev/null 2>&1; then
        ok "Already logged into ${REGISTRY}."
        return 0
    fi

    warn "Not authenticated with ${REGISTRY}."
    echo
    echo "To push images to GitHub Packages, a GitHub Personal Access Token (PAT)"
    echo "with 'write:packages' scope is required."
    echo "Generate one at: https://github.com/settings/tokens/new?scopes=write:packages,read:packages"
    echo
    read -rp "GitHub Username [${REPO_OWNER}]: " INPUT_USER
    INPUT_USER="${INPUT_USER:-${REPO_OWNER}}"
    read -rsp "GitHub Personal Access Token: " INPUT_TOKEN
    echo

    if [[ -z "${INPUT_TOKEN}" ]]; then
        err "No token provided. Aborting publish."
        exit 1
    fi

    echo "${INPUT_TOKEN}" | "${CONTAINER_CLI}" login "${REGISTRY}" -u "${INPUT_USER}" --password-stdin
}

login_to_registry
ok "Authenticated with ${REGISTRY}."

# 3. Push container image to GitHub Packages
info "Pushing '${FULL_IMAGE}:latest' to ${REGISTRY}..."
"${CONTAINER_CLI}" push "${FULL_IMAGE}:latest"

if [[ -n "${VERSION}" ]]; then
    info "Pushing '${FULL_IMAGE}:${VERSION}' to ${REGISTRY}..."
    "${CONTAINER_CLI}" push "${FULL_IMAGE}:${VERSION}"
fi

echo
ok "Container published successfully to GitHub Packages!"
echo -e "Image: ${BOLD}${FULL_IMAGE}:latest${NC}"
if [[ -n "${VERSION}" ]]; then
    echo -e "Image: ${BOLD}${FULL_IMAGE}:${VERSION}${NC}"
fi
echo -e "Package URL: ${BLUE}https://github.com/${REPO_OWNER}/${IMAGE_NAME}/pkgs/container/${IMAGE_NAME}${NC}"
echo
info "If the package does not yet display on your repository page, connect it once in GitHub:"
info "1. Visit: https://github.com/users/${REPO_OWNER}/packages/container/package/${IMAGE_NAME}"
info "2. On the right sidebar under 'Repository source', click 'Connect repository' -> select '${REPO_OWNER}/${IMAGE_NAME}'"
