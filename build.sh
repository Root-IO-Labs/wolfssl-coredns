#!/bin/bash
#
# Build script for CoreDNS v1.13.2 FIPS-enabled image
#
# Usage: ./build.sh [OPTIONS]
#
# Options:
#   --tag TAG          Custom image tag (default: coredns-fips:v1.13.2-ubuntu-22.04)
#   --no-cache         Build without cache
#   --push             Push to registry after build
#   --registry URL     Registry URL for push
#   --help             Show this help message
#

set -e

# Default configuration
DEFAULT_TAG="coredns-fips:v1.13.2-ubuntu-22.04"
IMAGE_TAG="${DEFAULT_TAG}"
NO_CACHE=""
PUSH=false
REGISTRY=""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Build script for CoreDNS v1.13.2 FIPS-enabled image

Usage: $0 [OPTIONS]

Options:
    --tag TAG          Custom image tag (default: ${DEFAULT_TAG})
    --no-cache         Build without cache
    --push             Push to registry after build
    --registry URL     Registry URL for push (required if --push is used)
    --help             Show this help message

Examples:
    # Basic build
    $0

    # Build with custom tag
    $0 --tag my-registry.com/coredns-fips:v1.13.2

    # Build and push to registry
    $0 --push --registry my-registry.com

    # Build without cache
    $0 --no-cache

Environment Variables:
    DOCKER_BUILDKIT    Set to 1 (required for build)

Requirements:
    - Docker 20.10+ with BuildKit support
    - wolfssl_password.txt file in current directory
    - 8GB+ RAM available
    - 20GB+ free disk space

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Banner
echo ""
echo "========================================"
echo "CoreDNS v1.13.2 FIPS Build"
echo "========================================"
echo ""

# Pre-flight checks
log_info "Running pre-flight checks..."

# Check if wolfssl_password.txt exists
if [ ! -f "wolfssl_password.txt" ]; then
    log_error "wolfssl_password.txt not found!"
    log_error "This file is required for building wolfSSL FIPS v5"
    exit 1
fi
log_success "wolfssl_password.txt found"

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    log_error "Dockerfile not found!"
    exit 1
fi
log_success "Dockerfile found"

# Check Docker BuildKit
if [ "${DOCKER_BUILDKIT:-0}" != "1" ]; then
    log_warning "DOCKER_BUILDKIT is not set to 1"
    log_info "Setting DOCKER_BUILDKIT=1 for this build"
    export DOCKER_BUILDKIT=1
fi
log_success "Docker BuildKit enabled"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_error "Docker command not found!"
    exit 1
fi
log_success "Docker is available"

# Check Docker version
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
log_info "Docker version: ${DOCKER_VERSION}"

# If push is requested, validate registry
if [ "$PUSH" = true ]; then
    if [ -z "$REGISTRY" ]; then
        log_error "--push requires --registry URL"
        exit 1
    fi
    # Update tag with registry if not already included
    if [[ "$IMAGE_TAG" != *"$REGISTRY"* ]]; then
        IMAGE_TAG="${REGISTRY}/${IMAGE_TAG}"
    fi
    log_info "Will push to registry: ${REGISTRY}"
fi

echo ""
log_info "Build configuration:"
echo "  Image tag: ${IMAGE_TAG}"
echo "  Cache: $([ -z "$NO_CACHE" ] && echo "enabled" || echo "disabled")"
echo "  Push: ${PUSH}"
echo ""

# Confirm build
read -p "Proceed with build? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warning "Build cancelled by user"
    exit 0
fi

# Start build
echo ""
log_info "Starting FIPS build (this will take ~50-60 minutes)..."
log_info "Build stages:"
echo "  1. OpenSSL 3.0.15 with FIPS module"
echo "  2. wolfSSL FIPS v5.8.2 (Certificate #4718)"
echo "  3. wolfProvider v1.1.0"
echo "  4. golang-fips/go toolchain (longest stage)"
echo "  5. CoreDNS v1.13.2 binary"
echo "  6. FIPS-compliant runtime image"
echo ""

# Record start time
START_TIME=$(date +%s)

# Run Docker build
if docker buildx build \
    --secret id=wolfssl_password,src=wolfssl_password.txt \
    -t "${IMAGE_TAG}" \
    ${NO_CACHE} \
    -f Dockerfile .; then

    # Calculate build time
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    BUILD_TIME_MIN=$((BUILD_TIME / 60))
    BUILD_TIME_SEC=$((BUILD_TIME % 60))

    echo ""
    log_success "Build completed successfully!"
    log_info "Build time: ${BUILD_TIME_MIN}m ${BUILD_TIME_SEC}s"
    echo ""

    # Show image info
    log_info "Image information:"
    docker images "${IMAGE_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    echo ""

    # Push if requested
    if [ "$PUSH" = true ]; then
        log_info "Pushing image to registry..."
        if docker push "${IMAGE_TAG}"; then
            log_success "Image pushed successfully!"
        else
            log_error "Failed to push image"
            exit 1
        fi
        echo ""
    fi

    # Show verification commands
    log_info "Verification commands:"
    echo ""
    echo "  # Verify wolfProvider is loaded"
    echo "  docker run --rm ${IMAGE_TAG} openssl list -providers"
    echo ""
    echo "  # Test FIPS-approved algorithm"
    echo "  docker run --rm ${IMAGE_TAG} sh -c 'echo test | openssl dgst -sha256'"
    echo ""
    echo "  # Check for non-FIPS crypto libraries (should be empty)"
    echo "  docker run --rm ${IMAGE_TAG} find /usr/lib /lib -name 'libgnutls*'"
    echo ""
    echo "  # Run CoreDNS with FIPS validation"
    echo "  docker run --rm -p 53:53 -p 53:53/udp ${IMAGE_TAG}"
    echo ""

    log_success "Build process complete!"

else
    log_error "Build failed!"
    exit 1
fi
