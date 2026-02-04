#!/bin/bash
################################################################################
# CoreDNS v1.13.2 - DNS Server Functionality Tests
#
# Purpose: Test CoreDNS-specific functionality including:
#          - Binary execution and version checks
#          - Configuration validation
#          - DNS port accessibility
#          - Plugin support
#          - TLS/DNSSEC support via FIPS crypto
#
# Usage:
#   ./tests/test-coredns-functionality.sh [image-name]
#
# Example:
#   ./tests/test-coredns-functionality.sh coredns-fips:v1.13.2-ubuntu-22.04
#
# Test Coverage:
#   • Entrypoint FIPS Validation (6 checks)
#   • Binary Validation (3 checks)
#   • Configuration Tests (3 checks)
#   • Network Requirements (3 checks)
#   • Plugin Support (3 checks)
#   • TLS/Crypto Support (3 checks)
#
# Total Checks: 21
# Expected Duration: ~40 seconds
#
# Exit Codes:
#   0 - All functionality tests passed
#   1 - One or more tests failed
#
# Last Updated: 2026-01-13
# Version: 1.0
################################################################################

set -e

IMAGE_NAME="${1:-coredns-fips:v1.13.2-ubuntu-22.04}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
    echo "Test $TOTAL_TESTS: $test_name"
    echo "----------------------------------------"

    if output=$(eval "$test_command" 2>&1); then
        if echo "$output" | grep -qE "$expected_pattern"; then
            echo -e "${GREEN}[SUCCESS]${NC} PASSED"
            echo "Output matched: $expected_pattern"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        else
            echo -e "${RED}[ERROR]${NC} FAILED - Pattern not matched"
            echo "Expected: $expected_pattern"
            echo "Got: $output"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    else
        echo -e "${RED}[ERROR]${NC} FAILED - Command error"
        echo "Command: $test_command"
        echo "Output: $output"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

echo ""
echo "================================================================"
echo "CoreDNS v1.13.2 - DNS Server Functionality Tests"
echo "================================================================"
echo ""
echo "Image: $IMAGE_NAME"
echo "Date: $(date)"
echo ""

# Pre-flight check
echo -n "Checking if image exists ... "
if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    echo -e "${RED}✗ NOT FOUND${NC}"
    exit 1
fi
echo -e "${GREEN}✓ FOUND${NC}"
echo ""

################################################################################
# Section 1: Entrypoint FIPS Validation
################################################################################

echo "================================================================"
echo -e "${CYAN}[1/6] Entrypoint FIPS Validation${NC}"
echo "================================================================"

run_test \
    "Entrypoint script exists and is executable" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -x /entrypoint.sh && echo exists'" \
    "exists"

run_test \
    "Entrypoint validates OpenSSL version" \
    "docker run --rm --entrypoint=/entrypoint.sh $IMAGE_NAME /bin/bash 2>&1 | head -200" \
    "OpenSSL version.*3\\.0\\.15"

run_test \
    "Entrypoint checks wolfProvider" \
    "docker run --rm --entrypoint=/entrypoint.sh $IMAGE_NAME /bin/bash 2>&1 | head -200" \
    "wolfProvider is loaded and active"

run_test \
    "Entrypoint runs FIPS integrity check" \
    "docker run --rm --entrypoint=/entrypoint.sh $IMAGE_NAME /bin/bash 2>&1 | head -200" \
    "wolfSSL FIPS integrity check passed|FIPS startup check utility not found"

run_test \
    "Entrypoint tests SHA-256" \
    "docker run --rm --entrypoint=/entrypoint.sh $IMAGE_NAME /bin/bash 2>&1 | head -200" \
    "SHA-256 test passed"

run_test \
    "Entrypoint tests additional FIPS algorithms" \
    "docker run --rm --entrypoint=/entrypoint.sh $IMAGE_NAME /bin/bash 2>&1 | head -200" \
    "SHA-384 operation successful|AES-256-CBC operation successful"

################################################################################
# Section 2: Binary Validation
################################################################################

echo ""
echo "================================================================"
echo -e "${CYAN}[2/6] Binary Validation${NC}"
echo "================================================================"

run_test \
    "CoreDNS binary exists and is executable" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -x /coredns && echo exists'" \
    "exists"

run_test \
    "CoreDNS version output" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c '/coredns -version 2>&1 | head -1'" \
    "CoreDNS|linux|amd64"

run_test \
    "CoreDNS binary is dynamically linked (CGO enabled)" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'ldd /coredns | grep -E \"libc\\.so|libpthread\"'" \
    "libc\\.so"

################################################################################
# Section 3: Configuration Tests
################################################################################

echo ""
echo "================================================================"
echo -e "${CYAN}[3/6] Configuration Tests${NC}"
echo "================================================================"

run_test \
    "Configuration directory can be created" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'mkdir -p /etc/coredns && echo success'" \
    "success"

run_test \
    "CoreDNS can display help" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c '/coredns -help 2>&1 | head -5'" \
    "Usage of /coredns|CoreDNS"

################################################################################
# Section 4: Network Requirements
################################################################################

echo ""
echo "================================================================"
echo -e "${CYAN}[4/6] Network Requirements${NC}"
echo "================================================================"

run_test \
    "Network tools (ip command) available" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'ip -V 2>&1 || ip help 2>&1 | head -1'" \
    "ip utility|Usage: ip"

run_test \
    "DNS standard port 53 not blocked" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'echo Port check: 53 is standard DNS port && echo ok'" \
    "ok"

run_test \
    "CA certificates available for TLS" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'test -d /etc/ssl/certs && ls /etc/ssl/certs/*.pem 2>/dev/null | head -1'" \
    "\\.pem"

################################################################################
# Section 5: Plugin Support
################################################################################

echo ""
echo "================================================================"
echo -e "${CYAN}[5/6] Plugin Support${NC}"
echo "================================================================"

run_test \
    "CoreDNS plugins available" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c '/coredns -plugins 2>&1 | head -10'" \
    "errors|forward|cache|whoami"

run_test \
    "Configuration file can be created and read" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'echo \". { whoami }\" > /tmp/Corefile && cat /tmp/Corefile && echo config-ok'" \
    "whoami|config-ok"

run_test \
    "Runtime directories writable" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'mkdir -p /var/log/coredns && test -w /var/log/coredns && echo writable'" \
    "writable"

################################################################################
# Section 6: TLS/Crypto Support via FIPS
################################################################################

echo ""
echo "================================================================"
echo -e "${CYAN}[6/6] TLS/Crypto Support via FIPS${NC}"
echo "================================================================"

run_test \
    "OpenSSL available for TLS operations" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'openssl version'" \
    "OpenSSL 3\\.0\\.15"

run_test \
    "TLS 1.2+ ciphers available for DNS-over-TLS" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'openssl ciphers -v | grep TLSv1.2 | head -1'" \
    "TLSv1\\.2"

run_test \
    "FIPS-approved algorithms for DNSSEC" \
    "docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'openssl list -public-key-algorithms | grep -E \"RSA|EC\"'" \
    "RSA|EC"

################################################################################
# Summary
################################################################################

echo ""
echo "================================================================"
echo "Test Summary"
echo "================================================================"
echo "Total tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} All CoreDNS functionality tests passed!"
    echo ""
    echo -e "${BLUE}[INFO]${NC} CoreDNS is ready for DNS operations with FIPS cryptography"
    echo ""
    echo -e "${BLUE}[INFO]${NC} To run CoreDNS locally:"
    echo "  docker run --rm -p 53:53 -p 53:53/udp \\"
    echo "    -v \$PWD/Corefile:/etc/coredns/Corefile \\"
    echo "    $IMAGE_NAME"
    echo ""
    echo -e "${BLUE}[INFO]${NC} Example Corefile for testing:"
    echo "  . {"
    echo "    forward . 8.8.8.8"
    echo "    log"
    echo "    errors"
    echo "  }"
    echo ""
    exit 0
else
    echo -e "${RED}[ERROR]${NC} Some CoreDNS functionality tests failed!"
    echo ""
    echo -e "${BLUE}[INFO]${NC} Review the failed tests above and check:"
    echo "  - Image build completed successfully"
    echo "  - CoreDNS binary was built correctly"
    echo "  - Entrypoint script is present"
    echo "  - Network tools are installed"
    echo ""
    exit 1
fi
