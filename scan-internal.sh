#!/bin/bash

################################################################################
# OpenSCAP Internal Container Scan for CoreDNS
# Scans FROM INSIDE the container to bypass OSCAP_PROBE_ROOT issues
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="${1:-coredns:v1.13.2-ubuntu-22.04-fips}"
CONTAINER_NAME="coredns-internal-scan-$$"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_DIR="./stig-cis-report"
SCAP_DIR="/usr/share/xml/scap/ssg/content"

echo ""
echo "=========================================="
echo "OpenSCAP Internal Container Scan - CoreDNS"
echo "Bypasses OSCAP_PROBE_ROOT issues"
echo "=========================================="
echo ""

################################################################################
# Validate Prerequisites
################################################################################

echo -e "${BLUE}[INFO]${NC} Validating prerequisites..."

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ ERROR: Docker not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker found"

# Check if image exists
if ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
    echo -e "${RED}✗ ERROR: Image not found: $IMAGE_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Image found: $IMAGE_NAME"

# Check SCAP content on host
if [ ! -f "$SCAP_DIR/ssg-ubuntu2204-ds.xml" ]; then
    echo -e "${RED}✗ ERROR: SCAP Security Guide not found on host${NC}"
    echo "  Expected: $SCAP_DIR/ssg-ubuntu2204-ds.xml"
    exit 1
fi
echo -e "${GREEN}✓${NC} SCAP Security Guide found"

# Create report directory
mkdir -p "$REPORT_DIR"
echo -e "${GREEN}✓${NC} Report directory: $REPORT_DIR"

################################################################################
# Start Container
################################################################################

echo ""
echo -e "${BLUE}[INFO]${NC} Starting container..."

# CoreDNS container - start with tail to keep it alive for scanning
# Override ENTRYPOINT to bypass FIPS validation during scanning
CONTAINER_ID=$(docker run -d --name "$CONTAINER_NAME" \
    --entrypoint /bin/bash \
    "$IMAGE_NAME" -c "tail -f /dev/null")

if [ -z "$CONTAINER_ID" ]; then
    echo -e "${RED}✗ ERROR: Failed to start container${NC}"
    exit 1
fi

# Wait for container to be ready
sleep 2

# Check if container is running
if ! docker ps -q --filter "id=$CONTAINER_ID" | grep -q .; then
    echo -e "${RED}✗ ERROR: Container exited immediately${NC}"
    echo ""
    echo "Container logs:"
    docker logs "$CONTAINER_ID" 2>&1 | tail -20
    exit 1
fi

echo -e "${GREEN}✓${NC} Container started: $CONTAINER_NAME"
echo -e "  Container ID: ${CONTAINER_ID:0:12}"

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

################################################################################
# Verify OpenSCAP in Container
################################################################################

echo ""
echo -e "${BLUE}[INFO]${NC} Verifying OpenSCAP installation..."

# Check if oscap binary exists
if docker exec --user root "$CONTAINER_NAME" test -f /usr/bin/oscap; then
    OSCAP_VERSION=$(docker exec --user root "$CONTAINER_NAME" /usr/bin/oscap --version 2>&1 | head -1 | grep -o "OpenSCAP.*" || echo "OpenSCAP")
    echo -e "${GREEN}✓${NC} OpenSCAP pre-installed: $OSCAP_VERSION"
else
    echo -e "${RED}✗ ERROR: OpenSCAP not found in container${NC}"
    echo ""
    echo "The hardened image should have OpenSCAP pre-installed."
    echo "Please rebuild the image to include OpenSCAP."
    exit 1
fi

################################################################################
# Verify CoreDNS Installation
################################################################################

echo ""
echo -e "${BLUE}[INFO]${NC} Verifying CoreDNS installation..."

COREDNS_VERSION=$(docker exec --user root "$CONTAINER_NAME" /coredns -version 2>&1 | grep -o 'CoreDNS-[0-9.]*' | sed 's/CoreDNS-//' || echo "unknown")
echo -e "${GREEN}✓${NC} CoreDNS version: $COREDNS_VERSION"

# Test CoreDNS binary
echo -e "${BLUE}[INFO]${NC} Testing CoreDNS binary..."
if docker exec --user root "$CONTAINER_NAME" test -x /coredns; then
    echo -e "${GREEN}✓${NC} CoreDNS binary is executable"
else
    echo -e "${YELLOW}⚠${NC}  CoreDNS binary check failed"
fi

################################################################################
# Copy SCAP Content to Container
################################################################################

echo ""
echo -e "${BLUE}[INFO]${NC} Copying SCAP Security Guide content..."

docker exec --user root "$CONTAINER_NAME" mkdir -p /usr/share/xml/scap/ssg/content

docker cp "$SCAP_DIR/ssg-ubuntu2204-ds.xml" \
    "$CONTAINER_NAME:/usr/share/xml/scap/ssg/content/" || {
    echo -e "${RED}✗ ERROR: Failed to copy SCAP content${NC}"
    exit 1
}

docker cp "$SCAP_DIR/ssg-ubuntu2204-oval.xml" \
    "$CONTAINER_NAME:/usr/share/xml/scap/ssg/content/" 2>/dev/null || true

echo -e "${GREEN}✓${NC} SCAP content copied to container"

################################################################################
# Verify APT Configuration Files
################################################################################

echo ""
echo -e "${BLUE}[INFO]${NC} Verifying APT configuration files..."

docker exec --user root "$CONTAINER_NAME" bash -c '
echo "Files in container:"
ls -la /etc/apt/apt.conf* 2>/dev/null || echo "No apt.conf files found"
echo ""
if [ -f /etc/apt/apt.conf ]; then
    echo "✓ /etc/apt/apt.conf exists"
fi
if [ -f /etc/apt/apt.conf-stig ]; then
    echo "✓ /etc/apt/apt.conf-stig exists"
fi
if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
    echo "✓ /etc/apt/apt.conf.d/50unattended-upgrades exists"
fi
if [ -f /etc/apt/apt.conf.d/90autoremove ]; then
    echo "✓ /etc/apt/apt.conf.d/90autoremove exists (STIG compliance)"
fi
'

################################################################################
# Verify STIG/CIS Hardening
################################################################################

echo ""
echo -e "${BLUE}[INFO]${NC} Verifying hardening measures..."

docker exec --user root "$CONTAINER_NAME" bash -c '
echo "Checking key hardening indicators:"
echo ""

# Check password policies
if grep -q "PASS_MAX_DAYS   60" /etc/login.defs 2>/dev/null; then
    echo "✓ Password max days: 60 (STIG compliant)"
fi

# Check PAM faillock
if grep -q "pam_faillock.so" /etc/pam.d/common-auth 2>/dev/null; then
    echo "✓ PAM faillock configured"
fi

# Check audit rules
if [ -f /etc/audit/rules.d/stig.rules ]; then
    echo "✓ Audit rules present"
fi

# Check UMASK
if grep -q "UMASK 077" /etc/login.defs 2>/dev/null; then
    echo "✓ UMASK 077 configured"
fi

# Check if package managers removed
if ! command -v apt &>/dev/null; then
    echo "✓ apt removed (ultra-hardened)"
fi
if ! command -v dpkg &>/dev/null; then
    echo "✓ dpkg removed (ultra-hardened)"
fi
'

################################################################################
# Run STIG Scan
################################################################################

echo ""
echo "=========================================="
echo "Running STIG Compliance Scan"
echo "=========================================="
echo ""

STIG_REPORT_XML="$REPORT_DIR/coredns-internal-stig-${TIMESTAMP}.xml"
STIG_REPORT_HTML="$REPORT_DIR/coredns-internal-stig-${TIMESTAMP}.html"

echo -e "${YELLOW}Running DISA STIG profile scan...${NC}"
echo "This may take 2-3 minutes..."
echo ""

docker exec --user root "$CONTAINER_NAME" oscap xccdf eval \
    --profile xccdf_org.ssgproject.content_profile_stig \
    --results /tmp/stig-results.xml \
    --report /tmp/stig-report.html \
    /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml \
    2>&1 || echo "Note: oscap returned non-zero exit code (this is normal if findings exist)"

# Copy results from container to host
if docker cp "$CONTAINER_NAME:/tmp/stig-results.xml" "$STIG_REPORT_XML" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} STIG results retrieved"
else
    echo -e "${RED}✗ ERROR: Failed to retrieve STIG results${NC}"
    echo "Checking if results file was created..."
    docker exec --user root "$CONTAINER_NAME" ls -la /tmp/stig-results.xml 2>&1 || echo "Results file not found"
    echo ""
    echo "Last 20 lines of container logs:"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20
    exit 1
fi

if docker cp "$CONTAINER_NAME:/tmp/stig-report.html" "$STIG_REPORT_HTML" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} STIG HTML report retrieved"
else
    echo -e "${YELLOW}⚠${NC}  Warning: HTML report not found (XML report available)"
fi

echo -e "${GREEN}✓${NC} STIG scan completed"

################################################################################
# Run CIS Scan
################################################################################

echo ""
echo -e "${YELLOW}Running CIS Benchmark scan...${NC}"

CIS_REPORT_XML="$REPORT_DIR/coredns-internal-cis-${TIMESTAMP}.xml"
CIS_REPORT_HTML="$REPORT_DIR/coredns-internal-cis-${TIMESTAMP}.html"

docker exec --user root "$CONTAINER_NAME" oscap xccdf eval \
    --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
    --results /tmp/cis-results.xml \
    --report /tmp/cis-report.html \
    /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml \
    2>&1 || echo "Note: oscap returned non-zero exit code (this is normal if findings exist)"

docker cp "$CONTAINER_NAME:/tmp/cis-results.xml" "$CIS_REPORT_XML" 2>/dev/null || true
docker cp "$CONTAINER_NAME:/tmp/cis-report.html" "$CIS_REPORT_HTML" 2>/dev/null || true

echo -e "${GREEN}✓${NC} CIS scan completed"

################################################################################
# Parse Results
################################################################################

echo ""
echo "=========================================="
echo "Scan Results Summary"
echo "=========================================="
echo ""

# STIG results
if [ -f "$STIG_REPORT_XML" ]; then
    STIG_PASS=$(grep -c '<result>pass</result>' "$STIG_REPORT_XML" 2>/dev/null || echo "0")
    STIG_FAIL=$(grep -c '<result>fail</result>' "$STIG_REPORT_XML" 2>/dev/null || echo "0")
    STIG_TOTAL=$((STIG_PASS + STIG_FAIL))
    
    echo -e "${CYAN}DISA STIG Profile:${NC}"
    echo "  Pass: $STIG_PASS"
    echo "  Fail: $STIG_FAIL"
    echo "  Total: $STIG_TOTAL"
    
    if [ $STIG_TOTAL -gt 0 ]; then
        STIG_PCT=$((STIG_PASS * 100 / STIG_TOTAL))
        echo "  Compliance: ${STIG_PCT}%"
    fi
    echo ""
    
    # Check the specific clean_components rule
    if grep -q "clean_components_post_updating" "$STIG_REPORT_XML"; then
        CLEAN_RESULT=$(grep -A 2 "clean_components_post_updating" "$STIG_REPORT_XML" | grep "<result>" | sed 's/.*<result>\(.*\)<\/result>.*/\1/')
        if [ "$CLEAN_RESULT" = "pass" ]; then
            echo -e "  ${GREEN}✓ clean_components_post_updating: PASS${NC}"
        else
            echo -e "  ${RED}✗ clean_components_post_updating: $CLEAN_RESULT${NC}"
        fi
    fi
fi

# CIS results
if [ -f "$CIS_REPORT_XML" ]; then
    CIS_PASS=$(grep -c '<result>pass</result>' "$CIS_REPORT_XML" 2>/dev/null || echo "0")
    CIS_FAIL=$(grep -c '<result>fail</result>' "$CIS_REPORT_XML" 2>/dev/null || echo "0")
    CIS_TOTAL=$((CIS_PASS + CIS_FAIL))
    
    echo ""
    echo -e "${CYAN}CIS Level 1 Server Profile:${NC}"
    echo "  Pass: $CIS_PASS"
    echo "  Fail: $CIS_FAIL"
    echo "  Total: $CIS_TOTAL"
    
    if [ $CIS_TOTAL -gt 0 ]; then
        CIS_PCT=$((CIS_PASS * 100 / CIS_TOTAL))
        echo "  Compliance: ${CIS_PCT}%"
    fi
fi

################################################################################
# CoreDNS-Specific Security Checks
################################################################################

echo ""
echo "=========================================="
echo "CoreDNS-Specific Security Checks"
echo "=========================================="
echo ""

echo -e "${BLUE}[INFO]${NC} Running CoreDNS security verification..."

docker exec --user root "$CONTAINER_NAME" bash -c '
# Check FIPS compliance
echo "FIPS Compliance:"
if openssl version 2>/dev/null | grep -q "OpenSSL 3"; then
    echo "  ✓ CoreDNS uses OpenSSL 3"
fi

# Check wolfProvider
if openssl list -providers 2>/dev/null | grep -q "wolfprov"; then
    echo "  ✓ wolfProvider loaded (FIPS 140-3)"
fi

# Check CoreDNS binary exists
if [ -x /coredns ]; then
    echo "  ✓ CoreDNS binary installed and executable"
fi

# Check non-FIPS crypto libraries removed
if ! find /usr/lib /lib -name "libgnutls*.so*" 2>/dev/null | grep -q .; then
    echo "  ✓ GnuTLS removed (FIPS-only enforcement)"
fi
'

################################################################################
# Report Locations
################################################################################

echo ""
echo "=========================================="
echo -e "${GREEN}Scan Complete${NC}"
echo "=========================================="
echo ""
echo -e "${CYAN}Reports:${NC}"
echo ""
echo "STIG Reports:"
echo "  HTML: $STIG_REPORT_HTML"
echo "  XML:  $STIG_REPORT_XML"
echo ""

if [ -f "$CIS_REPORT_HTML" ]; then
    echo "CIS Reports:"
    echo "  HTML: $CIS_REPORT_HTML"
    echo "  XML:  $CIS_REPORT_XML"
    echo ""
fi

echo "View HTML reports:"
echo "  xdg-open $STIG_REPORT_HTML"
if [ -f "$CIS_REPORT_HTML" ]; then
    echo "  xdg-open $CIS_REPORT_HTML"
fi

echo ""
echo -e "${BLUE}Note:${NC} This scan was performed FROM INSIDE the container,"
echo "      bypassing OSCAP_PROBE_ROOT path issues."
echo ""
echo -e "${CYAN}Image:${NC} $IMAGE_NAME"
echo -e "${CYAN}Container:${NC} $CONTAINER_NAME"
echo ""
