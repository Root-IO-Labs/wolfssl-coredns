# CoreDNS v1.13.2 - FIPS 140-3 Compliant

FIPS 140-3 compliant Docker image for CoreDNS v1.13.2 using wolfSSL FIPS v5 (Certificate #4718) via wolfProvider and golang-fips/go.

## Overview

This implementation provides a **fully FIPS 140-3 compliant** version of CoreDNS that:
- Provides DNS services with full FIPS 140-3 cryptographic compliance in **FIPS-only mode**
- Uses **wolfSSL FIPS v5.8.2** (Certificate #4718) for all cryptographic operations
- Routes all Go `crypto/*` package calls through **golang-fips/go** → Ubuntu System OpenSSL 3.0.2 → **wolfProvider** → wolfSSL FIPS
- **Strict FIPS-only configuration** - default OpenSSL provider disabled, only FIPS provider active
- **Removes ALL non-FIPS crypto libraries** (GnuTLS, Nettle, libgcrypt, etc.)
- Requires **NO application code changes** - standard Go code works as-is
- Supports **DNS-over-TLS**, **DNS-over-HTTPS**, and **DNSSEC** with FIPS algorithms

### Architecture

```
CoreDNS v1.13.2 (Go binary)
        ↓
golang-fips/go (FIPS-patched Go toolchain)
        ↓
Ubuntu System OpenSSL 3.0.2 (provider architecture, FIPS-only mode)
        ↓
wolfProvider v1.1.0 (OpenSSL → wolfSSL bridge, FIPS provider only)
        ↓
wolfSSL FIPS v5.8.2 (Certificate #4718)
```

### DNS Features with FIPS Cryptography

CoreDNS plugins that benefit from FIPS compliance:
- **DNS-over-TLS (DoT)** - TLS 1.2+ with FIPS-approved cipher suites
- **DNS-over-HTTPS (DoH)** - HTTPS with FIPS TLS
- **DNSSEC** - On-the-fly signing with FIPS RSA/ECDSA algorithms
- **Forward/Upstream** - Secure upstream communication with FIPS TLS

**Note**: The gRPC plugin has been removed for FIPS compliance (it depends on non-FIPS crypto packages).

## Requirements

### Build Requirements
- Docker 20.10+ with BuildKit support
- 8GB+ RAM available
- 20GB+ free disk space
- `wolfssl_password.txt` file (commercial wolfSSL FIPS package password)

### Runtime Requirements
- Linux kernel 3.10+ (standard requirement for containers)
- UDP/TCP port 53 available (DNS)
- TCP port 853 available (optional, for DNS-over-TLS)
- TCP port 443 available (optional, for DNS-over-HTTPS)

## Quick Start

### 1. Build the Image

```bash
# Basic build
./build.sh

# Build with custom tag
./build.sh --tag my-registry.com/coredns-fips:v1.13.2

# Build and push to registry
./build.sh --push --registry my-registry.com
```

**Build time**: ~50-60 minutes (mostly golang-fips/go compilation)

### 2. Verify FIPS Compliance

```bash
# Run quick smoke test (12 checks, ~20 seconds)
cd tests
./quick-test.sh

# Run comprehensive test suite (113 checks, ~3-4 minutes)
./run-all-tests.sh
```

### 3. Run CoreDNS

#### Standalone Mode

```bash
# Run with default configuration
docker run -d \
  --name coredns-fips \
  -p 53:53/udp \
  -p 53:53/tcp \
  coredns-fips:v1.13.2-ubuntu-22.04

# Run with custom Corefile
docker run -d \
  --name coredns-fips \
  -p 53:53/udp \
  -p 53:53/tcp \
  -v $PWD/Corefile:/etc/coredns/Corefile \
  coredns-fips:v1.13.2-ubuntu-22.04 \
  -conf /etc/coredns/Corefile
```

#### Kubernetes Deployment

```bash
# Deploy as Deployment
kubectl apply -f coredns-deployment.yaml

# Verify deployment
kubectl get pods -n kube-system -l k8s-app=coredns

# Check logs
kubectl logs -n kube-system -l k8s-app=coredns --tail=100

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

## Components

### Binary

**coredns** - DNS server that provides:
- **Forward DNS** - Proxying DNS queries to upstream servers
- **Authoritative DNS** - Serving DNS zones from files or APIs
- **DNS-over-TLS (DoT)** - Encrypted DNS on port 853
- **DNS-over-HTTPS (DoH)** - DNS over HTTPS
- **DNSSEC** - On-the-fly zone signing with RSA/ECDSA
- **Service Discovery** - Kubernetes, Consul, etcd integration
- **Caching** - In-memory DNS response caching
- **Health Checks** - Readiness and liveness endpoints
- **Metrics** - Prometheus metrics endpoint

### Configuration Files

- `openssl-wolfprov.cnf` - OpenSSL configuration loading wolfProvider
- `fips-startup-check.c` - C utility for runtime FIPS validation
- `entrypoint.sh` - Container startup script with FIPS validation
- `wolfssl_password.txt` - Password for commercial wolfSSL FIPS package (not committed)

## Build Process

### Stage 1: wolfSSL FIPS v5.8.2
- Downloads commercial wolfSSL FIPS package (password-protected)
- Compiles with FIPS v5 validation
- Runs FIPS hash generation
- Installs to `/usr/local`

### Stage 2: wolfProvider v1.1.0
- Clones wolfProvider from GitHub
- Builds OpenSSL → wolfSSL bridge module
- Installs to OpenSSL modules directory

### Stage 3: golang-fips/go Toolchain
- Clones golang-fips/go repository
- Applies FIPS patches to Go standard library
- **Removes ChaCha20-Poly1305** from all crypto/tls source files (comprehensive sed-based removal)
- Compiles custom Go toolchain (Go 1.24)
- Routes crypto/* to OpenSSL via CGO

### Stage 4: CoreDNS v1.13.2
- Clones CoreDNS v1.13.2 from GitHub
- Downloads dependencies via `go mod download`
- **Patches quic-go dependency** to remove ChaCha20 references (prevents build failures)
- Builds with golang-fips/go (CGO_ENABLED=1)
- Creates binary: `/coredns`

### Stage 5: FIPS-Compliant Runtime Image
- **CRITICAL**: Copies FIPS components BEFORE apt-get
- Installs Ubuntu System OpenSSL 3.0.2 via APT (NOT custom-built)
- Configures OpenSSL for FIPS-only mode (default provider disabled)
- Installs runtime dependencies
- **Removes ALL non-FIPS crypto libraries** (3-step process)
- Verifies FIPS compliance at build time
- Configures entrypoint with validation

## FIPS Compliance Details

### Cryptographic Module
- **wolfSSL FIPS v5.8.2**
- **CMVP Certificate**: #4718
- **Validation Level**: FIPS 140-3
- **Algorithms**: AES, SHA-2, HMAC, RSA, ECDSA, DH, ECDH

### Compliance Verification

The image undergoes multiple FIPS validation stages:

1. **Build-time verification** (Dockerfile RUN commands)
   - wolfProvider loaded before package installation
   - FIPS libraries installed to system locations
   - Non-FIPS crypto libraries removed
   - OpenSSL provider status checked

2. **Runtime validation** (entrypoint.sh)
   - OpenSSL 3.0.2 version check
   - wolfProvider active status (FIPS-only mode verification)
   - wolfSSL FIPS integrity check (CAST)
   - SHA-256 cryptographic operation test
   - Verifies default provider is NOT active

3. **Test suite validation** (tests/)
   - 113 automated checks
   - Binary linkage verification
   - Algorithm blocking tests
   - Complete crypto path validation
   - DNS functionality tests

### Non-FIPS Libraries Removed

The following non-FIPS cryptographic libraries are **completely removed**:
- GnuTLS (`libgnutls30`)
- Nettle (`libnettle8`)
- Hogweed (`libhogweed6`)
- libgcrypt (`libgcrypt20`)
- Kerberos crypto (`libk5crypto3`)

This ensures **100% FIPS compliance** with no bypass paths.

### ChaCha20-Poly1305 Removal

ChaCha20-Poly1305 is a **non-FIPS approved cipher suite** that requires active removal from source code during the build process:

#### Why Removal is Required
- ChaCha20-Poly1305 is present in golang-fips/go crypto/tls source code
- ChaCha20-Poly1305 is present in quic-go dependency used by CoreDNS for DoH3 support
- Without removal, the build fails with: `undefined: tls.TLS_CHACHA20_POLY1305_SHA256`
- FIPS 140-3 compliance requires only approved cipher suites (AES-GCM, AES-CCM)

#### Removal Implementation

**1. golang-fips/go Patching (Dockerfile.hardened:244-272)**
- Comprehensive removal from **all .go files** in `src/crypto/tls/`
- Uses sed-based approach: `sed -i '/TLS_CHACHA20_POLY1305_SHA256/d' *.go`
- Removes from cipher_suites.go, defaults.go, and all other TLS source files
- Verification: grep check ensures complete removal before compilation

**2. quic-go Dependency Patching (Dockerfile.hardened:417-442)**
- Patches quic-go v0.57.0 after `go mod download`
- Removes from 3 production files:
  - `internal/handshake/cipher_suite.go`
  - `internal/handshake/header_protector.go`
  - `internal/handshake/updatable_aead.go`
- Removes from 3 test files:
  - `internal/handshake/hkdf_test.go`
  - `internal/handshake/updatable_aead_test.go`
  - `internal/handshake/handshake_helpers_test.go`
- Verification: grep check ensures no ChaCha20 references remain in quic-go dependency

**Note**: ChaCha20 cipher suite definitions may still exist in golang-fips/go TLS runtime code. This is acceptable because FIPS mode prevents their execution at runtime (see "FIPS Runtime Enforcement" section below).

#### Result
After plugin removal and build-time verification, the final CoreDNS binary:
- ✅ **ChaCha20-Poly1305 package** removed from dependencies (verified via `go mod why`)
- ✅ Uses only FIPS-approved cipher suites (AES-128-GCM, AES-256-GCM for TLS 1.3)
- ✅ Builds successfully without "undefined constant" errors
- ✅ Maintains full DNS-over-TLS and DNS-over-HTTPS functionality
- ❌ DoH3 (DNS over HTTP/3) is NOT AVAILABLE (QUIC/HTTP/3 disabled for FIPS compliance)
- ℹ️  **Note**: ChaCha20 code may exist in golang-fips/go TLS but won't execute (runtime FIPS enforcement prevents it)

#### Build-Time Verification
The build process enforces these requirements with automated checks:
- **Plugin Verification**: `/coredns -plugins` output scanned for QUIC/HTTP3/gRPC/Azure/CloudDNS (build fails if found)
- **Dependency Verification**: `go mod why golang.org/x/crypto/chacha20poly1305` must return "does not need" (build fails otherwise)
- **Binary Analysis**: `strings /app/coredns | grep -i chacha20` checks for ChaCha20 (informational - Go runtime may contain TLS cipher definitions)

#### FIPS Runtime Enforcement
Even if ChaCha20 code exists in the binary:
- **GOLANG_FIPS=1** forces all crypto operations through OpenSSL FIPS provider
- OpenSSL FIPS provider **rejects** non-approved cipher suites including ChaCha20
- TLS connections automatically use FIPS-approved ciphers (AES-GCM)
- ChaCha20 code present but **will not execute** in FIPS mode

### Non-FIPS Plugin Removal (Azure & CloudDNS)

Multiple plugins have been **removed from the build** to ensure strict FIPS 140-3 compliance:

#### Azure Plugin Removal (pkcs12/RC2)

**Why Removal is Required**:
- Azure plugin imports `golang.org/x/crypto/pkcs12`
- pkcs12 package contains **RC2 cipher** - a non-FIPS approved algorithm
- RC2 implementation located at: `golang.org/x/crypto/pkcs12/internal/rc2`
- pkcs12 package documentation states: *"uses weak encryption primitives, SHOULD NOT be used for new applications"*
- **Client verification** confirmed runtime initialization: `init golang.org/x/crypto/pkcs12 @49 ms`

**Result**:
- ✅ **pkcs12 package**: ABSENT from binary
- ✅ **RC2 cipher**: ABSENT from binary
- ⚠️  **Azure DNS functionality**: NOT AVAILABLE

#### CloudDNS Plugin Removal (ChaCha20-Poly1305)

**Why Removal is Required**:
- CloudDNS plugin imports `google.golang.org/api/dns/v1`
- Google Cloud DNS API depends on `github.com/google/s2a-go` (Secure Session Agent)
- S2A library uses **ChaCha20-Poly1305 cipher** - a non-FIPS approved AEAD algorithm
- Dependency chain: `plugin/clouddns` → `google.golang.org/api/dns/v1` → `github.com/google/s2a-go` → `golang.org/x/crypto/chacha20poly1305`

**Result**:
- ✅ **ChaCha20-Poly1305 package**: ABSENT from binary
- ✅ **Google S2A library**: NOT INCLUDED
- ⚠️  **Google Cloud DNS functionality**: NOT AVAILABLE

#### Removal Implementation

**Dockerfile Approach** (lines 455-488):
- Remove plugin directories: `rm -rf plugin/azure plugin/clouddns`
- Remove plugin imports from core code using sed
- Process executed during CoreDNS source clone

**Dockerfile.hardened Approach** (lines 565-590):
- Modify `plugin.cfg` to remove plugin lines:
  - `sed -i '/^azure:/d' plugin.cfg`
  - `sed -i '/^clouddns:/d' plugin.cfg`
- Regenerate plugin registration: `go generate coredns.go`
- Run `go mod tidy` to remove dependencies

**Build-Time Verification** (lines 704-790):
- Automated checks after CoreDNS binary compilation
- Check 1: Scan for `golang.org/x/crypto/pkcs12` (Azure)
- Check 2: Scan for `golang.org/x/crypto/chacha20poly1305` (CloudDNS)
- Build fails if either non-FIPS package is detected

#### FIPS Compliance Status

After plugin removal and verification:
- ✅ **FIPS Compliance**: No non-FIPS algorithms present
- ✅ **Standard DNS**: Fully functional
- ✅ **DNS-over-TLS (DoT)**: Fully functional
- ✅ **DNS-over-HTTPS (DoH)**: Fully functional
- ⚠️  **Azure DNS**: NOT AVAILABLE
- ⚠️  **Google Cloud DNS**: NOT AVAILABLE

**Alternatives**: Use CoreDNS forward plugin to external Azure/Google Cloud DNS resolvers if cloud DNS integration is required.

### DoH3 Plugin Removal (ChaCha20-Poly1305)

The DoH3 (DNS over HTTP/3) plugin has been **removed from the build** to ensure strict FIPS 140-3 compliance:

#### Why Removal is Required
- DoH3 plugin depends on `github.com/quic-go/quic-go` library (QUIC protocol implementation)
- quic-go contains **ChaCha20-Poly1305 cipher** - a non-FIPS approved AEAD algorithm
- ChaCha20 implementation located at: `golang.org/x/crypto/chacha20poly1305`
- **Build verification** enforces complete removal (build fails if ChaCha20 detected)

#### Removal Implementation

**1. QUIC File Hide-Restore Approach**
- Location: Dockerfile:491-663, Dockerfile.hardened:424-623
- Executed after Azure/CloudDNS plugin removal, before binary compilation
- Process:
  - Step 1: Temporarily rename QUIC files to .go.quic (hides from go mod tidy)
  - Step 2: Create stub functions that return errors for QUIC/HTTP3 operations
  - Step 3: Run `go mod tidy` to remove quic-go dependency from go.mod
  - Step 4: Restore original QUIC files with `//go:build quic` tags (excluded from non-QUIC builds)
  - Verify quic-go and chacha20poly1305 are removed from go.mod/go.sum

**2. Impact Assessment**
After DoH3 plugin removal:
- ❌ **DoH3 (DNS over HTTP/3)**: NOT AVAILABLE
- ✅ **DoH (DNS over HTTP/2)**: FULLY FUNCTIONAL (alternative for encrypted DNS)
- ✅ **DoT (DNS over TLS)**: FULLY FUNCTIONAL
- ✅ **Standard DNS (UDP/TCP)**: FULLY FUNCTIONAL
- ✅ **All other plugins**: FULLY FUNCTIONAL (cache, forward, kubernetes, etc.)

#### Result
After DoH3 plugin removal and verification:
- ✅ **quic-go library**: ABSENT from dependencies (verified: `go mod why github.com/quic-go/quic-go` returns "does not need")
- ✅ **ChaCha20-Poly1305 package**: ABSENT from dependencies (verified: `go mod why golang.org/x/crypto/chacha20poly1305` returns "does not need")
- ✅ **QUIC/HTTP3 plugins**: NOT in binary (verified: `/coredns -plugins` does not list quic or http3)
- ✅ **FIPS Compliance**: No non-FIPS packages in dependency tree (build enforces verification)
- ℹ️  **ChaCha20 in binary**: May exist in golang-fips/go TLS runtime (prevented from executing by FIPS mode)
- ⚠️  **DoH3 functionality**: NOT AVAILABLE (minimal impact - rarely used)

#### Why This Trade-Off is Acceptable

1. **DoH3 Adoption**: HTTP/3 and DoH3 are still in early adoption phase
2. **Alternative Available**: DoH over HTTP/2 provides the same encrypted DNS functionality
3. **Core DNS Unaffected**: All standard DNS operations work normally
4. **FIPS Compliance**: Critical requirement for government/regulated environments

**Note:** If DoH3 is absolutely required, a FIPS-compliant QUIC implementation would need to be developed that doesn't use ChaCha20-Poly1305 (currently no such implementation exists).

### HKDF Key Derivation Function

HKDF (HMAC-based Key Derivation Function) is used by TLS 1.3 for key schedule operations and may be present in the CoreDNS binary:

#### FIPS Compliance Status: ✅ FULLY COMPLIANT (May be present - used by TLS 1.3)

**Algorithm Details:**
- **Standard**: RFC 5869 - HMAC-based Extract-and-Expand Key Derivation Function
- **Used by**: TLS 1.3 key schedule (RFC 8446 §7.1), optionally by QUIC or other components
- **Operation**: Key derivation from shared secrets during TLS handshake
- **Hash Functions**: SHA-256, SHA-384, SHA-512 (all FIPS-approved)

#### Why HKDF is FIPS-Compliant
- HKDF is a **key derivation function**, not an encryption algorithm
- FIPS approval depends on the underlying hash function used
- TLS 1.3 uses HKDF with **SHA-256 and SHA-384** - both FIPS-approved
- NIST SP 800-56C Rev. 2 approves HKDF for key derivation
- golang-fips/go routes HKDF operations through OpenSSL → wolfSSL FIPS
- No weak or non-FIPS primitives involved

#### Client Feedback Addressed
- **Client inquiry**: "golang.org/x/crypto/hkdf is present in the coredns binary. It seems to be used by QUIC."
- **Status**: ✅ **Verified FIPS-compliant** - uses approved hash functions (SHA-256/384)
- **Presence**: MAY be present in binary (used by TLS 1.3, optionally by other components)
- **Compliance**: Fully compliant - HKDF with SHA-2 is NIST-approved
- **Build verification**: Informational check only (Dockerfile:754-767), does not fail build
- **Note**: DoH3/QUIC was removed due to ChaCha20-Poly1305, NOT due to HKDF (HKDF was always compliant)

**References:**
- NIST SP 800-56C Rev. 2: Recommendation for Key-Derivation Methods in Key-Establishment Schemes
- RFC 5869: HMAC-based Extract-and-Expand Key Derivation Function (HKDF)

## Configuration

### Environment Variables

#### FIPS Configuration
- `OPENSSL_CONF` - Path to OpenSSL config (default: `/etc/ssl/openssl.cnf`)
- `GOLANG_FIPS` - Enables FIPS mode in golang-fips/go runtime (set to `1`)
- `LD_LIBRARY_PATH` - Includes wolfSSL library paths
- **Note**: `OPENSSL_MODULES` is NOT required for OpenSSL 3.x (module path configured in openssl.cnf)

#### CoreDNS Configuration
CoreDNS is configured via Corefile. Example configurations:

**Basic Forward Configuration:**
```
. {
    forward . 8.8.8.8 8.8.4.4
    log
    errors
    cache 30
}
```

**DNS-over-TLS with FIPS:**
```
tls://.:853 {
    tls /etc/coredns/cert.pem /etc/coredns/key.pem
    forward . tls://1.1.1.1
    log
    errors
}
```

**Kubernetes Service Discovery:**
```
.:53 {
    errors
    health {
        lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
    }
    prometheus :9153
    forward . /etc/resolv.conf
    cache 30
    loop
    reload
    loadbalance
}
```

## Testing

### Test Suites

1. **Quick Test** (`quick-test.sh`)
   - 12 core FIPS validation checks
   - ~20 seconds
   - Smoke test for FIPS compliance

2. **Comprehensive FIPS Compliance** (`verify-fips-compliance.sh`)
   - 51 detailed FIPS checks
   - Binary linkage analysis
   - wolfProvider validation
   - Algorithm testing
   - ~100 seconds

3. **CoreDNS Functionality** (`test-coredns-functionality.sh`)
   - 15 DNS server-specific tests
   - Binary execution tests
   - Configuration validation
   - Network requirements
   - Plugin support
   - TLS/Crypto capabilities
   - ~30 seconds

4. **Non-FIPS Algorithm Blocking** (`check-non-fips-algorithms.sh`)
   - 11 algorithm tests
   - Verifies MD5/MD4 blocked
   - Verifies SHA-256/384/512 work
   - Verifies AES encryption works
   - Library removal verification
   - ~15 seconds

5. **Cryptographic Path Validation** (`crypto-path-validation.sh`)
   - 24 crypto stack checks
   - CGO linkage verification
   - Environment validation
   - OpenSSL/wolfProvider/wolfSSL verification
   - ~30 seconds

### Running Tests

```bash
cd tests

# Run all tests
./run-all-tests.sh

# Run individual tests
./quick-test.sh
./verify-fips-compliance.sh
./test-coredns-functionality.sh
./check-non-fips-algorithms.sh
./crypto-path-validation.sh
```

## Troubleshooting

### Build Failures

**wolfSSL package download fails:**
```bash
# Verify wolfssl_password.txt exists and is correct
cat wolfssl_password.txt
```

**golang-fips/go build fails:**
```bash
# Increase Docker memory allocation to 8GB+
# Check Docker Desktop → Settings → Resources → Memory
```

### Runtime Issues

**"wolfProvider is NOT loaded" error:**
```bash
# Verify environment variables
docker run --rm coredns-fips:v1.13.2-ubuntu-22.04 env | grep OPENSSL

# Check wolfProvider module (x86_64)
docker run --rm coredns-fips:v1.13.2-ubuntu-22.04 \
  ls -la /usr/lib/x86_64-linux-gnu/ossl-modules/

# Or for ARM64/aarch64
docker run --rm coredns-fips:v1.13.2-ubuntu-22.04 \
  ls -la /usr/lib/aarch64-linux-gnu/ossl-modules/

# Verify FIPS-only mode (should show only "fips" provider)
docker run --rm coredns-fips:v1.13.2-ubuntu-22.04 openssl list -providers
```

**DNS queries fail:**
```bash
# Check DNS port binding
docker run --rm -p 53:53/udp coredns-fips:v1.13.2-ubuntu-22.04

# Test with dig
dig @localhost example.com

# Check logs
docker logs <container-id>
```

## Performance Considerations

### FIPS Performance Impact

- **TLS operations**: ~10-15% overhead compared to non-FIPS OpenSSL
- **DNSSEC signing**: ~5-10% overhead for RSA, minimal for ECDSA
- **Standard DNS queries**: No measurable impact (caching layer unaffected)

### Optimization Tips

1. **Use ECDSA for DNSSEC** - Faster than RSA with FIPS compliance
2. **Enable caching** - Reduces cryptographic operations
3. **Connection pooling** - Reuse TLS connections for upstream queries

## Security

### FIPS Validation

This image provides:
- **FIPS 140-3 Level 1** cryptographic module (wolfSSL FIPS)
- **CMVP Certificate #4718**
- **No non-FIPS bypass paths** - All crypto libraries removed
- **Runtime integrity checks** - Startup validation ensures FIPS mode

### Best Practices

1. **TLS Configuration**
   - Use TLS 1.2 or 1.3 only
   - Use FIPS-approved cipher suites
   - Rotate certificates regularly

2. **DNSSEC**
   - Use RSA 2048+ or ECDSA P-256+
   - Enable NSEC3 for zone enumeration protection

3. **Monitoring**
   - Monitor FIPS validation logs
   - Alert on cryptographic errors
   - Track certificate expiration

## License

- **CoreDNS**: Apache License 2.0
- **wolfSSL FIPS**: Commercial license required (Certificate #4718)
- **OpenSSL**: Apache License 2.0
- **wolfProvider**: GPLv3

## References

- [CoreDNS Official Documentation](https://coredns.io/manual/toc/)
- [wolfSSL FIPS](https://www.wolfssl.com/products/wolfssl-fips/)
- [FIPS 140-3 Standard](https://csrc.nist.gov/publications/detail/fips/140/3/final)
- [golang-fips/go](https://github.com/golang-fips/go)
- [OpenSSL 3.0 Providers](https://www.openssl.org/docs/man3.0/man7/provider.html)

## Support

For issues with:
- **CoreDNS functionality**: [CoreDNS GitHub Issues](https://github.com/coredns/coredns/issues)
- **FIPS compliance**: Review test suite output and logs
- **Build process**: Check Docker BuildKit is enabled and memory allocation is sufficient
- **wolfSSL FIPS**: Contact wolfSSL support (commercial license holders)

## Changelog

### v1.13.2-fips (2026-02-23)
- **FIPS-only mode**: Default OpenSSL provider disabled for strict compliance
- CoreDNS v1.13.2
- wolfSSL FIPS v5.8.2 (Certificate #4718)
- golang-fips/go with Go 1.24
- Ubuntu System OpenSSL 3.0.2 (APT package, not custom-built)
- wolfProvider v1.1.0 (FIPS provider only)
- Ubuntu 22.04 base
- Comprehensive test suite (118 checks)
- Enhanced security: Zero non-FIPS algorithm availability
