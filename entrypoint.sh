#!/bin/bash
# CoreDNS FIPS-enabled Entrypoint Script
# This script validates FIPS compliance before starting CoreDNS

set -e

echo "========================================="
echo "CoreDNS FIPS Validation"
echo "========================================="

# 1. Validate GOLANG_FIPS environment variable
echo "Step 1: Checking GOLANG_FIPS environment variable..."
if [ "$GOLANG_FIPS" != "1" ]; then
    echo "❌ ERROR: GOLANG_FIPS is not set to 1"
    echo "   Current value: ${GOLANG_FIPS:-<not set>}"
    echo "   Required: GOLANG_FIPS=1"
    exit 1
fi
echo "✅ GOLANG_FIPS=1 (enabled)"

# 2. Validate OpenSSL FIPS provider
echo ""
echo "Step 2: Checking OpenSSL FIPS provider..."
if ! openssl list -providers 2>&1 | grep -qi "fips"; then
    echo "❌ ERROR: FIPS provider not loaded in OpenSSL"
    echo ""
    echo "Available providers:"
    openssl list -providers 2>&1 || true
    exit 1
fi
echo "✅ FIPS provider loaded"

# 3. Validate wolfProvider
echo ""
echo "Step 3: Checking wolfProvider..."
if ! openssl list -providers 2>&1 | grep -qi "wolfSSL Provider"; then
    echo "❌ ERROR: wolfProvider not found"
    echo ""
    echo "Available providers:"
    openssl list -providers 2>&1 || true
    exit 1
fi
echo "✅ wolfProvider loaded"

# 4. Display OpenSSL version
echo ""
echo "Step 4: OpenSSL version information..."
openssl version 2>&1 || true

# 5. Display provider details
echo ""
echo "Step 5: Provider details..."
openssl list -providers -verbose 2>&1 | head -20 || true

echo ""
echo "========================================="
echo "✅ FIPS Validation: PASSED"
echo "========================================="
echo ""
echo "Starting CoreDNS..."
echo ""

# Execute CoreDNS with all passed arguments
exec "$@"
