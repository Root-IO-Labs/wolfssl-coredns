#!/bin/bash
################################################################################
# Non-FIPS Algorithm Blocking Test for CoreDNS v1.13.2
#
# Verifies that non-FIPS algorithms are properly blocked
#
# Usage:
#   ./check-non-fips-algorithms.sh [image_name]
#
# Default image: coredns-fips:v1.13.2-ubuntu-22.04
#
# Last Updated: 2026-01-13
# Version: 1.0
################################################################################

IMAGE_NAME="${1:-coredns-fips:v1.13.2-ubuntu-22.04}"
FAILED_TESTS=0
PASSED_TESTS=0

echo "========================================"
echo "Non-FIPS Algorithm Blocking Test"
echo "========================================"
echo "Image: $IMAGE_NAME"
echo ""

###############################################################################
# Helper Functions
###############################################################################

test_blocked_algorithm() {
    local algo="$1"
    local test_cmd="$2"

    echo -n "Testing: $algo is blocked ... "
    output=$(docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c "$test_cmd" 2>&1 || true)

    if echo "$output" | grep -qi "unsupported\|error\|disabled\|unknown"; then
        echo "✓ PASS (correctly blocked)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo "✗ FAIL ($algo should be blocked!)"
        echo "  Output: $output" | head -3
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

test_allowed_algorithm() {
    local algo="$1"
    local test_cmd="$2"
    local expected="$3"

    echo -n "Testing: $algo works (FIPS-approved) ... "
    output=$(docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c "$test_cmd" 2>&1)

    if echo "$output" | grep -q "$expected"; then
        echo "✓ PASS"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo "✗ FAIL ($algo should work!)"
        echo "  Output: $output" | head -3
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

###############################################################################
# Test Suite 1: Blocked Hash Algorithms
###############################################################################

echo "========================================"
echo "Test Suite 1: Blocked Hash Algorithms"
echo "========================================"

test_blocked_algorithm "MD5" "echo -n 'test' | openssl dgst -md5"
test_blocked_algorithm "MD4" "echo -n 'test' | openssl dgst -md4"

echo ""

###############################################################################
# Test Suite 2: Approved Hash Algorithms
###############################################################################

echo "========================================"
echo "Test Suite 2: Approved Hash Algorithms"
echo "========================================"

test_allowed_algorithm "SHA-256" \
    "echo -n 'test' | openssl dgst -sha256" \
    "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

test_allowed_algorithm "SHA-384" \
    "echo -n 'test' | openssl dgst -sha384" \
    "768412320f7b0aa5812fce428dc4706b3cae50e02a64caa16a782249bfe8efc4b7ef1ccb126255d196047dfedf17a0a9"

test_allowed_algorithm "SHA-512" \
    "echo -n 'test' | openssl dgst -sha512" \
    "ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff"

echo ""

###############################################################################
# Test Suite 3: Encryption Algorithms
###############################################################################

echo "========================================"
echo "Test Suite 3: Encryption Algorithms"
echo "========================================"

echo -n "Testing: AES-256-CBC works (FIPS-approved) ... "
output=$(docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'echo -n "test" | openssl enc -aes-256-cbc -K $(printf "0%.0s" {1..64}) -iv $(printf "0%.0s" {1..32}) | base64 -w0 | head -c 20' 2>&1)
if [ ! -z "$output" ]; then
    echo "✓ PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo -n "Testing: AES-128-CBC works (FIPS-approved) ... "
output=$(docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c 'echo -n "test" | openssl enc -aes-128-cbc -K $(printf "0%.0s" {1..32}) -iv $(printf "0%.0s" {1..32}) | base64 -w0 | head -c 20' 2>&1)
if [ ! -z "$output" ]; then
    echo "✓ PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

###############################################################################
# Test Suite 4: Library Removal Verification
###############################################################################

echo ""
echo "========================================"
echo "Test Suite 4: Library Removal Verification"
echo "========================================"

echo -n "Testing: GnuTLS library removed ... "
count=$(docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c "find /usr/lib /lib -name 'libgnutls*.so*' 2>/dev/null | wc -l")
if [ "$count" -eq 0 ] 2>/dev/null; then
    echo "✓ PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL (found $count GnuTLS libraries)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo -n "Testing: Nettle library removed ... "
count=$(docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c "find /usr/lib /lib -name 'libnettle*.so*' 2>/dev/null | wc -l")
if [ "$count" -eq 0 ] 2>/dev/null; then
    echo "✓ PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL (found $count Nettle libraries)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo -n "Testing: Hogweed library removed ... "
count=$(docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c "find /usr/lib /lib -name 'libhogweed*.so*' 2>/dev/null | wc -l")
if [ "$count" -eq 0 ] 2>/dev/null; then
    echo "✓ PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL (found $count Hogweed libraries)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo -n "Testing: libgcrypt removed ... "
count=$(docker run --rm --entrypoint=/bin/bash $IMAGE_NAME -c "find /usr/lib /lib -name 'libgcrypt*.so*' 2>/dev/null | wc -l")
if [ "$count" -eq 0 ] 2>/dev/null; then
    echo "✓ PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL (found $count libgcrypt libraries)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

###############################################################################
# Test Summary
###############################################################################

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Total Tests: $((PASSED_TESTS + FAILED_TESTS))"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo "✓ ALL TESTS PASSED"
    echo ""
    echo "Non-FIPS algorithms are properly blocked."
    echo "FIPS-approved algorithms work correctly."
    exit 0
else
    echo "✗ SOME TESTS FAILED"
    echo ""
    echo "Please review failed tests above."
    exit 1
fi
