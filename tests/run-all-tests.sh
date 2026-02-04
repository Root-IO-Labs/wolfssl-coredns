#!/bin/bash
################################################################################
# CoreDNS v1.13.2 - Master Test Runner
#
# Purpose: Run all FIPS compliance and functionality tests in sequence
#
# Usage:
#   ./tests/run-all-tests.sh [image-name]
#
# Example:
#   ./tests/run-all-tests.sh coredns-fips:v1.13.2-ubuntu-22.04
#
# Test Suites:
#   1. Quick Test (12 checks)
#   2. FIPS Compliance Verification (51 checks)
#   3. CoreDNS Functionality Tests (15 checks)
#   4. Non-FIPS Algorithm Blocking (11 checks)
#   5. Cryptographic Path Validation (24 checks)
#
# Total Checks: ~113
# Expected Duration: ~3-4 minutes
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more test suites failed
#
# Last Updated: 2026-01-13
# Version: 1.0
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
IMAGE_NAME="${1:-coredns-fips:v1.13.2-ubuntu-22.04}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_SUITES=5
PASSED_SUITES=0
FAILED_SUITES=0

# Test results
declare -A SUITE_STATUS
declare -A SUITE_TIME

print_banner() {
    echo ""
    echo "================================================================================"
    echo -e "${BOLD}${CYAN}CoreDNS v1.13.2 - Master Test Runner${NC}"
    echo "================================================================================"
    echo ""
    echo "Image: $IMAGE_NAME"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Total Test Suites: $TOTAL_SUITES"
    echo ""
}

run_test_suite() {
    local suite_num="$1"
    local suite_name="$2"
    local script_name="$3"

    echo ""
    echo "================================================================================"
    echo -e "${CYAN}[Suite $suite_num/$TOTAL_SUITES] $suite_name${NC}"
    echo "================================================================================"
    echo "Script: $script_name"
    echo ""

    # Check if script exists
    if [ ! -f "$SCRIPT_DIR/$script_name" ]; then
        echo -e "${RED}✗ ERROR: Test script not found: $script_name${NC}"
        SUITE_STATUS[$suite_num]="MISSING"
        SUITE_TIME[$suite_num]="0"
        FAILED_SUITES=$((FAILED_SUITES + 1))
        return 1
    fi

    # Make script executable
    chmod +x "$SCRIPT_DIR/$script_name"

    # Run the test suite and measure time
    local start_time=$(date +%s)

    if "$SCRIPT_DIR/$script_name" "$IMAGE_NAME"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        SUITE_STATUS[$suite_num]="PASSED"
        SUITE_TIME[$suite_num]="$duration"
        PASSED_SUITES=$((PASSED_SUITES + 1))

        echo ""
        echo -e "${GREEN}✓ Suite $suite_num PASSED${NC} (${duration}s)"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        SUITE_STATUS[$suite_num]="FAILED"
        SUITE_TIME[$suite_num]="$duration"
        FAILED_SUITES=$((FAILED_SUITES + 1))

        echo ""
        echo -e "${RED}✗ Suite $suite_num FAILED${NC} (${duration}s)"
        return 1
    fi
}

print_summary() {
    echo ""
    echo "================================================================================"
    echo -e "${BOLD}Final Test Report${NC}"
    echo "================================================================================"
    echo ""

    # Suite-by-suite results
    echo "Suite Results:"
    echo "-------------"
    for i in $(seq 1 $TOTAL_SUITES); do
        local status="${SUITE_STATUS[$i]}"
        local time="${SUITE_TIME[$i]}"

        case $status in
            "PASSED")
                echo -e "  Suite $i: ${GREEN}✓ PASSED${NC} (${time}s)"
                ;;
            "FAILED")
                echo -e "  Suite $i: ${RED}✗ FAILED${NC} (${time}s)"
                ;;
            "MISSING")
                echo -e "  Suite $i: ${RED}✗ MISSING${NC}"
                ;;
            *)
                echo -e "  Suite $i: ${YELLOW}? UNKNOWN${NC}"
                ;;
        esac
    done

    echo ""
    echo "Overall Results:"
    echo "----------------"
    echo "Total Suites: $TOTAL_SUITES"
    echo -e "Passed: ${GREEN}$PASSED_SUITES${NC}"
    echo -e "Failed: ${RED}$FAILED_SUITES${NC}"

    # Calculate total time
    local total_time=0
    for i in $(seq 1 $TOTAL_SUITES); do
        total_time=$((total_time + ${SUITE_TIME[$i]}))
    done
    echo "Total Time: ${total_time}s ($(($total_time / 60))m $(($total_time % 60))s)"

    echo ""
}

print_banner

# Pre-flight check: Verify image exists
echo "Pre-flight checks:"
echo "------------------"
echo -n "Checking if image exists ... "
if docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ FOUND${NC}"
else
    echo -e "${RED}✗ NOT FOUND${NC}"
    echo ""
    echo "Error: Image '$IMAGE_NAME' not found"
    echo "Please build the image first: ./build.sh"
    exit 1
fi

echo -n "Checking Docker is running ... "
if docker ps > /dev/null 2>&1; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ NOT RUNNING${NC}"
    echo ""
    echo "Error: Docker daemon not running"
    exit 1
fi

echo ""
echo "Starting test execution..."
sleep 1

################################################################################
# Test Suite 1: Quick Test
################################################################################

run_test_suite 1 \
    "Quick FIPS Validation" \
    "quick-test.sh"

################################################################################
# Test Suite 2: FIPS Compliance Verification
################################################################################

run_test_suite 2 \
    "Comprehensive FIPS Compliance" \
    "verify-fips-compliance.sh"

################################################################################
# Test Suite 3: CoreDNS Functionality Tests
################################################################################

run_test_suite 3 \
    "CoreDNS Functionality" \
    "test-coredns-functionality.sh"

################################################################################
# Test Suite 4: Non-FIPS Algorithm Blocking
################################################################################

run_test_suite 4 \
    "Non-FIPS Algorithm Blocking" \
    "check-non-fips-algorithms.sh"

################################################################################
# Test Suite 5: Cryptographic Path Validation
################################################################################

run_test_suite 5 \
    "Cryptographic Path Validation" \
    "crypto-path-validation.sh"

################################################################################
# Final Report
################################################################################

print_summary

if [ $FAILED_SUITES -eq 0 ]; then
    echo "================================================================================"
    echo -e "${GREEN}${BOLD}✓ ALL TEST SUITES PASSED${NC}"
    echo "================================================================================"
    echo ""
    echo "FIPS 140-3 Compliance Verified:"
    echo "  • wolfSSL FIPS v5.8.2 (Certificate #4718)"
    echo "  • wolfProvider v1.1.0 active and functional"
    echo "  • All non-FIPS crypto libraries removed"
    echo "  • golang-fips/go routing all crypto/* to FIPS OpenSSL"
    echo "  • CoreDNS binary using FIPS cryptography verified"
    echo "  • DNS server functionality validated"
    echo "  • TLS/DNSSEC support with FIPS algorithms confirmed"
    echo ""
    echo "The image is READY FOR PRODUCTION USE with full FIPS 140-3 compliance."
    echo ""
    echo "Next Steps:"
    echo "  1. Run standalone: docker run -p 53:53/udp -p 53:53/tcp $IMAGE_NAME"
    echo "  2. Deploy to Kubernetes: kubectl apply -f coredns-deployment.yaml"
    echo "  3. Test DNS queries: dig @localhost example.com"
    echo "  4. Monitor logs: kubectl logs -n kube-system -l k8s-app=coredns"
    echo ""
    exit 0
else
    echo "================================================================================"
    echo -e "${RED}${BOLD}✗ TEST FAILURES DETECTED${NC}"
    echo "================================================================================"
    echo ""
    echo "Failed Suites: $FAILED_SUITES / $TOTAL_SUITES"
    echo ""
    echo "Action Required:"
    echo "  1. Review the detailed output above for each failed suite"
    echo "  2. Check the specific error messages and failure reasons"
    echo "  3. Common issues:"
    echo "     - Image not built correctly (missing FIPS components)"
    echo "     - wolfProvider not loaded or misconfigured"
    echo "     - Non-FIPS libraries still present"
    echo "     - CoreDNS binary not compiled with golang-fips/go"
    echo "     - Environment variables not set correctly"
    echo "  4. Rebuild the image: ./build.sh"
    echo "  5. Re-run tests: ./tests/run-all-tests.sh"
    echo ""
    echo "For detailed logs, run individual test suites:"
    echo "  ./tests/quick-test.sh"
    echo "  ./tests/verify-fips-compliance.sh"
    echo "  ./tests/test-coredns-functionality.sh"
    echo "  ./tests/check-non-fips-algorithms.sh"
    echo "  ./tests/crypto-path-validation.sh"
    echo ""
    exit 1
fi
