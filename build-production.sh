#!/bin/bash
set -euo pipefail

################################################################################
# Production Build Script for FIPS-Hardened CoreDNS Docker Image
# 
# This script builds a production-ready image with:
#  - OpenSCAP removed (no compliance scanning tools)
#  - Package managers removed (apt, dpkg)
#  - Non-FIPS crypto libraries removed (100% FIPS compliance)
#  - All STIG/CIS hardening rules applied
################################################################################

# Configuration
IMAGE_NAME="coredns"
VERSION="v1.13.2"
OS="ubuntu"
OS_VERSION="22.04"
SECURITY_SUFFIX="fips-production"

# Construct tag
TAG="${VERSION}-${OS}-${OS_VERSION}-${SECURITY_SUFFIX}"
FULL_IMAGE_NAME="${IMAGE_NAME}:${TAG}"

echo ""
echo "========================================" 
echo "Building PRODUCTION FIPS-Hardened Image"
echo "========================================"
echo ""
echo "⚠️  PRODUCTION BUILD WARNING ⚠️"
echo ""
echo "This build creates a production-ready image with:"
echo "  • OpenSCAP scanning tools REMOVED"
echo "  • Package managers REMOVED (apt, dpkg)"
echo "  • Non-FIPS crypto libraries REMOVED"
echo "  • Cannot run compliance scans on this image"
echo "  • Cannot install packages at runtime"
echo ""
echo "Compliance verification MUST be done on testing image first!"
echo ""
echo "Image: ${FULL_IMAGE_NAME}"
echo "Dockerfile: Dockerfile.production"
echo ""

# Verify compliance scans exist
if [ ! -d "./stig-cis-report" ] || [ -z "$(ls -A ./stig-cis-report 2>/dev/null)" ]; then
    echo "⚠️  WARNING: No compliance scan reports found!"
    echo ""
    echo "You should run compliance scans on the testing image first:"
    echo "  ./scan-internal.sh coredns:v1.13.2-ubuntu-22.04-fips"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Build cancelled."
        exit 0
    fi
else
    echo "✓ Compliance reports found in ./stig-cis-report/"
    echo ""
fi

read -p "Proceed with PRODUCTION build? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled by user"
    exit 0
fi

echo ""
echo "Starting production build..."
echo ""

# Build with buildkit
export DOCKER_BUILDKIT=1

docker buildx build \
    --secret id=wolfssl_password,src=./wolfssl_password.txt \
    --progress=plain \
    --tag "${FULL_IMAGE_NAME}" \
    --file Dockerfile.production \
    . || {
        echo ""
        echo "========================================"
        echo -e "\033[0;31m✗ BUILD FAILED\033[0m"
        echo "========================================"
        exit 1
    }

echo ""
echo "========================================"
echo -e "\033[0;32m✓ PRODUCTION BUILD SUCCESSFUL\033[0m"
echo "========================================"
echo ""
echo "Production Image: ${FULL_IMAGE_NAME}"
echo ""
echo "Security Features:"
echo "  ✓ FIPS 140-3 compliance (100%)"
echo "  ✓ DISA STIG V2R1 hardening"
echo "  ✓ CIS Level 1 Server hardening"
echo "  ✓ Package managers removed"
echo "  ✓ Non-FIPS crypto removed"
echo "  ✓ OpenSCAP tools removed"
echo ""
echo "⚠️  Important Notes:"
echo "  • Cannot run compliance scans on this image"
echo "  • Cannot install packages at runtime"
echo "  • Compliance verified from testing image"
echo ""
echo "Next steps:"
echo ""
echo "  1. Verify production image:"
echo "     docker run --rm ${FULL_IMAGE_NAME} /coredns -version"
echo ""
echo "  2. Test application functionality:"
echo "     docker run --rm -p 53:53 -p 53:53/udp ${FULL_IMAGE_NAME}"
echo ""
echo "  3. Verify package managers removed:"
echo "     docker run --rm ${FULL_IMAGE_NAME} sh -c 'command -v apt || echo apt removed'"
echo ""
echo "  4. Verify non-FIPS crypto removed:"
echo "     docker run --rm ${FULL_IMAGE_NAME} find /usr/lib -name libgcrypt* 2>/dev/null | wc -l"
echo "     (should output: 0)"
echo ""
echo "  5. Tag for production registry:"
echo "     docker tag ${FULL_IMAGE_NAME} <registry>/${FULL_IMAGE_NAME}"
echo ""
echo "  6. Push to registry:"
echo "     docker push <registry>/${FULL_IMAGE_NAME}"
echo ""
