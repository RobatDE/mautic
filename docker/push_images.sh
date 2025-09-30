#!/usr/bin/env bash
set -euo pipefail

# Build and push the single Mautic image using the root Dockerfile.
# Usage:
#   ./push_images.sh [tag]
# Examples:
#   ./push_images.sh            # uses :latest
#   ./push_images.sh v1.0.0     # uses :v1.0.0
#
# You must be authenticated to GHCR beforehand, e.g.:
#   echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
#
# Override defaults by exporting env vars before running:
#   IMAGE (default: ghcr.io/expona-ai/mautic)
#   NO_CACHE=1 (to build with --no-cache)

TAG="${1:-latest}"
IMAGE="${IMAGE:-ghcr.io/expona-ai/mautic-web-service}"
NO_CACHE_FLAG=""
if [[ "${NO_CACHE:-0}" == "1" ]]; then
  NO_CACHE_FLAG="--no-cache"
fi

START_HUMAN=$(date)
START=$(date '+%s')
echo "[$START_HUMAN] Starting build for image: ${IMAGE}:${TAG}"

# Build using the root Dockerfile and repository root as context
DOCKERFILE="./Dockerfile"
CONTEXT_DIR="."

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "Dockerfile not found at $DOCKERFILE"
  exit 1
fi

set -x
docker build ${NO_CACHE_FLAG} -f "$DOCKERFILE" "$CONTEXT_DIR" -t "${IMAGE}:${TAG}"
set +x

# Push the image
set -x
docker push "${IMAGE}:${TAG}"
set +x

END_HUMAN=$(date)
END=$(date '+%s')
DELTA=$((END - START))

echo "[$END_HUMAN] Finished build and push: ${IMAGE}:${TAG}"
echo "Duration: ${DELTA} seconds."
