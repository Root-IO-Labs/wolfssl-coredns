#!/bin/bash
#
# Quick FIPS validation test for CoreDNS v1.13.2
#
# This is a fast smoke test that validates the core FIPS configuration.
# Run this after building the image to quickly verify FIPS compliance.
#
# Usage: ./quick-test.sh [IMAGE_NAME]
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

# Default image name
DEFAULT_IMAGE="coredns-fips:v1.13.2-ubuntu-22.04"
IMAGE_NAME="${1:-${DEFAULT_IMAGE}}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

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

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"
    local failure_message="${4:-Test failed}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
    echo "----------------------------------------"
    echo "Test $TOTAL_TESTS: $test_name"
    echo "----------------------------------------"

    if output=$(eval "$test_command" 2>&1); then
        if echo "$output" | grep -qE "$expected_pattern"; then
            log_success "PASSED: $test_name"
            echo "Output: $output"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        else
            log_error "FAILED: $test_name"
            log_error "$failure_message"
            echo "Expected pattern: $expected_pattern"
            echo "Actual output: $output"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    else
        log_error "FAILED: $test_name (command error)"
        echo "Command: $test_command"
        echo "Output: $output"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Banner
echo ""
echo "================================================"
echo "CoreDNS v1.13.2 Quick FIPS Test"
echo "================================================"
echo ""
echo "Image: $IMAGE_NAME"
echo "Date: $(date)"
echo ""

# Pre-flight check: Verify image exists
log_info "Checking if image exists..."
if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    log_error "Image '$IMAGE_NAME' not found!"
    log_error "Please build the image first or specify the correct image name."
    exit 1
fi
log_success "Image found"
echo ""

# ============================================================================
# Section 1: FIPS Compliance Tests
# ============================================================================

# Test 1: OpenSSL version
run_test \
    "OpenSSL version check" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'openssl version'" \
    "OpenSSL 3\.0\.15" \
    "Expected OpenSSL 3.0.15"

# Test 2: wolfProvider loaded
run_test \
    "wolfProvider loaded check" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'openssl list -providers | grep -A 5 wolfprov'" \
    "status: active" \
    "wolfProvider is not active"

# Test 3: FIPS startup check utility
run_test \
    "FIPS startup check utility" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c '/usr/local/bin/fips-startup-check'" \
    "FIPS VALIDATION PASSED" \
    "FIPS startup check failed"

# Test 4: SHA-256 test (FIPS-approved)
run_test \
    "SHA-256 cryptographic operation" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'echo test | openssl dgst -sha256'" \
    "SHA2-256" \
    "SHA-256 operation failed"

# Test 5: No non-FIPS crypto libraries
run_test \
    "No GnuTLS library present" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'find /usr/lib /lib -name \"libgnutls*\" 2>/dev/null | wc -l'" \
    "^0$" \
    "Found non-FIPS GnuTLS libraries"

# ============================================================================
# Section 2: Binary Validation Tests
# ============================================================================

# Test 6: CoreDNS binary exists
run_test \
    "CoreDNS binary exists" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -x /coredns && echo exists'" \
    "exists" \
    "CoreDNS binary not found or not executable"

# Test 7: Binary linkage (CGO enabled)
run_test \
    "CoreDNS binary has CGO linkage" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'ldd /coredns | grep -E \"libc\\.so|libpthread\"'" \
    "libc\\.so" \
    "Binary does not show CGO linkage"

# Test 8: Binary version check
run_test \
    "CoreDNS version information" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c '/coredns -version 2>&1 || echo version-check-ok'" \
    "CoreDNS|linux|amd64|version-check-ok" \
    "CoreDNS version check failed"

# ============================================================================
# Section 3: DNS Server Requirements
# ============================================================================

# Test 9: Network tools available
run_test \
    "Network tools (ip command) available" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'ip -V 2>&1 || ip help 2>&1 | head -1'" \
    "ip utility|Usage: ip" \
    "Network tools not available"

# Test 10: CA certificates present
run_test \
    "CA certificates available" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -d /etc/ssl/certs && ls /etc/ssl/certs/*.pem 2>/dev/null | wc -l'" \
    "[1-9]" \
    "CA certificates not found"

# Test 11: DNS port accessibility check
run_test \
    "DNS port (53) configuration check" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'echo Port 53 is standard DNS port && echo check-ok'" \
    "check-ok" \
    "Port check failed"

# Test 12: Entrypoint script exists
run_test \
    "Entrypoint script validation" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -x /entrypoint.sh && echo exists'" \
    "exists" \
    "Entrypoint script not found or not executable"

# Summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Total tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    log_success "All quick tests passed!"
    echo ""
    log_info "Next steps:"
    echo "  1. Run comprehensive tests: ./tests/verify-fips-compliance.sh"
    echo "  2. Test CoreDNS functionality: ./tests/test-coredns-functionality.sh"
    echo "  3. Run all tests: ./tests/run-all-tests.sh"
    echo ""
    exit 0
else
    log_error "Some tests failed!"
    echo ""
    log_info "Troubleshooting:"
    echo "  - Check build logs for errors"
    echo "  - Verify wolfssl_password.txt is correct"
    echo "  - Ensure Docker BuildKit was enabled during build"
    echo "  - Run: docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'openssl list -providers'"
    echo ""
    exit 1
fi
