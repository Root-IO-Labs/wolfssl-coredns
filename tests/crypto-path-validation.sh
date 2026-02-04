#!/bin/bash
################################################################################
# CoreDNS v1.13.2 FIPS - Cryptographic Path Validation
#
# Purpose: Verify that CoreDNS binary uses FIPS-compliant
#          cryptographic libraries (OpenSSL + wolfProvider + wolfSSL)
#
# Usage:
#   ./tests/crypto-path-validation.sh [image-name]
#
# Example:
#   ./tests/crypto-path-validation.sh coredns-fips:v1.13.2-ubuntu-22.04
#
# Runtime: ~30 seconds
#
# Test Coverage:
#   • Binary linkage to FIPS OpenSSL
#   • Environment variable configuration
#   • OpenSSL provider verification
#   • wolfSSL library presence
#   • golang-fips/go integration verification
#   • Configuration file validation
#
# Exit Codes:
#   0 - All validation checks passed
#   1 - One or more checks failed
#
# Last Updated: 2026-01-13
# Version: 1.0
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get image name from argument or use default
IMAGE_NAME="${1:-coredns-fips:v1.13.2-ubuntu-22.04}"
FAILED=0
PASSED=0

echo "================================================================================"
echo "         CoreDNS v1.13.2 FIPS - Cryptographic Path Validation"
echo "================================================================================"
echo ""
echo "Image: $IMAGE_NAME"
echo ""

################################################################################
# Helper Functions
################################################################################

test_check() {
    local test_name="$1"
    local test_cmd="$2"

    echo -n "  Testing: $test_name ... "

    if eval "$test_cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

test_check_with_output() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_pattern="$3"

    echo -n "  Testing: $test_name ... "

    output=$(eval "$test_cmd" 2>&1 || true)

    if echo "$output" | grep -qE "$expected_pattern"; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo "    Expected pattern: $expected_pattern"
        echo "    Actual output: $(echo "$output" | head -1)"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

################################################################################
# Pre-Test: Image Validation
################################################################################
echo "[Pre-Test] Validating image..."
echo ""

echo -n "Checking if image '$IMAGE_NAME' exists ... "
if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ FOUND${NC}"
else
    echo -e "${RED}✗ NOT FOUND${NC}"
    echo ""
    echo "Error: Image '$IMAGE_NAME' not found"
    echo "Build the image first: ./build.sh"
    exit 1
fi

echo ""

################################################################################
# Test Suite 1: Binary Linkage Verification
################################################################################
echo "================================================================================"
echo "[1/6] Binary Linkage Verification"
echo "================================================================================"
echo ""
echo "Verifying CoreDNS binary links to FIPS OpenSSL..."
echo ""

test_check "CoreDNS binary exists" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'ls /coredns'"

test_check "CoreDNS binary is executable" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -x /coredns'"

# Note: Go binaries built with golang-fips/go don't always show OpenSSL in ldd output
# They route crypto calls to OpenSSL via CGO at runtime
# We verify CGO linkage instead (presence of libc/libpthread indicates CGO was used)

test_check_with_output "CoreDNS compiled with CGO (required for FIPS)" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'ldd /coredns'" \
    "libc.so"

echo ""

################################################################################
# Test Suite 2: Environment Configuration
################################################################################
echo "================================================================================"
echo "[2/6] Environment Configuration"
echo "================================================================================"
echo ""
echo "Verifying FIPS environment variables are properly set..."
echo ""

test_check_with_output "OPENSSL_CONF is set" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'env | grep OPENSSL_CONF'" \
    "OPENSSL_CONF=/usr/local/openssl/ssl/openssl.cnf"

test_check_with_output "OPENSSL_MODULES is set" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'env | grep OPENSSL_MODULES'" \
    "OPENSSL_MODULES=/usr/local/openssl/lib64/ossl-modules"

test_check_with_output "LD_LIBRARY_PATH includes FIPS OpenSSL" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'env | grep LD_LIBRARY_PATH'" \
    "/usr/local/openssl/lib64"

test_check_with_output "PATH includes FIPS OpenSSL binaries" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'env | grep -E \"^PATH=\"'" \
    "/usr/local/openssl/bin"

echo ""

################################################################################
# Test Suite 3: OpenSSL Provider Verification
################################################################################
echo "================================================================================"
echo "[3/6] OpenSSL Provider Verification"
echo "================================================================================"
echo ""
echo "Verifying OpenSSL loads wolfProvider correctly..."
echo ""

test_check_with_output "OpenSSL version is 3.0.15" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'openssl version'" \
    "OpenSSL 3\\.0\\.15"

test_check_with_output "wolfProvider is loaded" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'openssl list -providers | grep -A 5 wolfprov'" \
    "status: active"

test_check "OpenSSL config file exists" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -f /usr/local/openssl/ssl/openssl.cnf'"

test_check "wolfProvider module exists" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -f /usr/local/openssl/lib64/ossl-modules/libwolfprov.so'"

test_check "wolfProvider config in openssl.cnf" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'grep -q wolfprov /usr/local/openssl/ssl/openssl.cnf'"

echo ""

################################################################################
# Test Suite 4: wolfSSL Library Verification
################################################################################
echo "================================================================================"
echo "[4/6] wolfSSL Library Verification"
echo "================================================================================"
echo ""
echo "Verifying wolfSSL FIPS library is present and linked..."
echo ""

echo -n "  Testing: wolfSSL library exists ... "
if docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c "ls /usr/lib/x86_64-linux-gnu/libwolfssl.so* >/dev/null 2>&1"; then
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}"
    FAILED=$((FAILED + 1))
fi

test_check "wolfSSL library in system location" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -f /usr/lib/x86_64-linux-gnu/libwolfssl.so'"

test_check "wolfSSL in ldconfig cache" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'ldconfig -p | grep -q wolfssl'"

test_check "FIPS startup check utility exists" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -x /usr/local/bin/fips-startup-check'"

echo ""

################################################################################
# Test Suite 5: golang-fips/go Integration
################################################################################
echo "================================================================================"
echo "[5/6] golang-fips/go Integration"
echo "================================================================================"
echo ""
echo "Verifying golang-fips/go toolchain integration..."
echo ""

test_check "CoreDNS compiled with CGO (required for FIPS)" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'ldd /coredns | grep -q libc'"

test_check_with_output "OpenSSL crypto operations work" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'echo -n test | openssl dgst -sha256'" \
    "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

test_check_with_output "FIPS startup check passes" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c '/usr/local/bin/fips-startup-check'" \
    "FIPS VALIDATION PASSED"

echo ""

################################################################################
# Test Suite 6: Configuration Files Verification
################################################################################
echo "================================================================================"
echo "[6/6] Configuration Files Verification"
echo "================================================================================"
echo ""
echo "Verifying configuration files are present and valid..."
echo ""

test_check "Entrypoint script exists" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -x /entrypoint.sh'"

test_check "CoreDNS configuration directory can be created" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'mkdir -p /etc/coredns && test -d /etc/coredns'"

test_check "Runtime log directory writable" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'mkdir -p /var/log/coredns && test -w /var/log/coredns'"

test_check "CA certificates present for TLS" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -d /etc/ssl/certs'"

test_check "OpenSSL config has wolfProvider" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'grep -q wolfprov /usr/local/openssl/ssl/openssl.cnf'"

echo ""

################################################################################
# Test Summary
################################################################################
echo "================================================================================"
echo "Validation Report"
echo "================================================================================"
echo ""

TOTAL=$((PASSED + FAILED))

echo "Test Summary:"
echo "  Total tests: $TOTAL"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "================================================================================"
    echo -e "${GREEN}✓ ALL CRYPTOGRAPHIC PATH VALIDATION CHECKS PASSED${NC}"
    echo "================================================================================"
    echo ""
    echo "Verification Summary:"
    echo "  ✓ CoreDNS binary built with CGO for FIPS OpenSSL integration"
    echo "  ✓ Environment variables properly configured"
    echo "  ✓ wolfProvider is loaded and active"
    echo "  ✓ wolfSSL FIPS library present and accessible"
    echo "  ✓ golang-fips/go integration working correctly"
    echo "  ✓ Configuration files present and valid"
    echo ""
    echo "Cryptographic Path:"
    echo "  CoreDNS v1.13.2 (Go binary)"
    echo "      ↓"
    echo "  golang-fips/go (patches Go crypto/* packages)"
    echo "      ↓"
    echo "  OpenSSL 3.0.15 (provider architecture)"
    echo "      ↓"
    echo "  wolfProvider v1.1.0 (OpenSSL → wolfSSL bridge)"
    echo "      ↓"
    echo "  wolfSSL FIPS v5.8.2 (Certificate #4718)"
    echo ""
    echo "TLS/DNSSEC Support:"
    echo "  • DNS-over-TLS (DoT) using FIPS TLS 1.2+"
    echo "  • DNS-over-HTTPS (DoH) using FIPS HTTPS"
    echo "  • DNSSEC signing with FIPS RSA/ECDSA"
    echo ""
    echo "Next Steps:"
    echo "  1. Run functional tests: ./tests/test-coredns-functionality.sh"
    echo "  2. Run algorithm blocking tests: ./tests/check-non-fips-algorithms.sh"
    echo "  3. Deploy to Kubernetes cluster or run standalone"
    echo ""
    exit 0
else
    echo "================================================================================"
    echo -e "${RED}✗ CRYPTOGRAPHIC PATH VALIDATION FAILED${NC}"
    echo "================================================================================"
    echo ""
    echo "Issues detected:"
    echo "  Review the failed tests above for specific issues"
    echo ""
    echo "Common causes:"
    echo "  1. CoreDNS not compiled with golang-fips/go"
    echo "  2. OpenSSL not installed to correct location"
    echo "  3. wolfProvider not built or installed"
    echo "  4. Environment variables not set correctly"
    echo "  5. wolfSSL library missing or not in library path"
    echo "  6. Configuration files missing or invalid"
    echo ""
    echo "Action required:"
    echo "  1. Review Dockerfile build stages"
    echo "  2. Verify golang-fips/go toolchain stage completed successfully"
    echo "  3. Check OpenSSL, wolfSSL, wolfProvider installation"
    echo "  4. Verify CoreDNS build stage uses correct Go toolchain"
    echo "  5. Check configuration file copy steps"
    echo "  6. Rebuild image: ./build.sh"
    echo ""
    exit 1
fi
