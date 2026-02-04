# CoreDNS v1.13.2 - FIPS 140-3 Compliant

FIPS 140-3 compliant Docker image for CoreDNS v1.13.2 using wolfSSL FIPS v5 (Certificate #4718) via wolfProvider and golang-fips/go.

## Overview

This implementation provides a **fully FIPS 140-3 compliant** version of CoreDNS that:
- Provides DNS services with full FIPS 140-3 cryptographic compliance
- Uses **wolfSSL FIPS v5.8.2** (Certificate #4718) for all cryptographic operations
- Routes all Go `crypto/*` package calls through **golang-fips/go** → OpenSSL 3.0.15 → **wolfProvider** → wolfSSL FIPS
- **Removes ALL non-FIPS crypto libraries** (GnuTLS, Nettle, libgcrypt, etc.)
- Requires **NO application code changes** - standard Go code works as-is
- Supports **DNS-over-TLS**, **DNS-over-HTTPS**, and **DNSSEC** with FIPS algorithms

### Architecture

```
CoreDNS v1.13.2 (Go binary)
        ↓
golang-fips/go (FIPS-patched Go toolchain)
        ↓
OpenSSL 3.0.15 (provider architecture)
        ↓
wolfProvider v1.1.0 (OpenSSL → wolfSSL bridge)
        ↓
wolfSSL FIPS v5.8.2 (Certificate #4718)
```

### DNS Features with FIPS Cryptography

CoreDNS plugins that benefit from FIPS compliance:
- **DNS-over-TLS (DoT)** - TLS 1.2+ with FIPS-approved cipher suites
- **DNS-over-HTTPS (DoH)** - HTTPS with FIPS TLS
- **DNSSEC** - On-the-fly signing with FIPS RSA/ECDSA algorithms
- **gRPC** - gRPC-based plugin communication with FIPS TLS
- **Forward/Upstream** - Secure upstream communication with FIPS TLS

## Build Variants

Two Dockerfile variants are available:

1. **Dockerfile** - FIPS 140-3 compliant CoreDNS image
2. **Dockerfile.hardened** - FIPS 140-3 + DISA STIG V2R1 + CIS Level 1 Server hardened image

## Requirements

### Build Requirements
- Docker 20.10+ with BuildKit support
- 8GB+ RAM available
- 20GB+ free disk space
- `wolfssl_password.txt` file (commercial wolfSSL FIPS package password)

### Required Files
- `Dockerfile` - Standard FIPS 140-3 compliant build
- `Dockerfile.hardened` - FIPS + STIG/CIS hardened build
- `build.sh` - Build script for standard Dockerfile
- `build-hardened.sh` - Build script for Dockerfile.hardened
- `wolfssl_password.txt` - wolfSSL FIPS package password (not committed to repository)

### Runtime Requirements
- Linux kernel 3.10+ (standard requirement for containers)
- UDP/TCP port 53 available (DNS)
- TCP port 853 available (optional, for DNS-over-TLS)
- TCP port 443 available (optional, for DNS-over-HTTPS)

## Quick Start

### 1. Build the Image

#### Standard FIPS Build

```bash
# Basic build
./build.sh

# Build with custom tag
./build.sh --tag my-registry.com/coredns-fips:v1.13.2

# Build and push to registry
./build.sh --push --registry my-registry.com
```

#### Hardened Build (FIPS + STIG/CIS)

```bash
# Build hardened variant
./build-hardened.sh

# Output image tag: coredns:v1.13.2-ubuntu-22.04-fips
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

### Standard Build (Dockerfile)

The standard build creates a FIPS 140-3 compliant CoreDNS image through 6 stages:

#### Stage 1: OpenSSL 3.0.15 with FIPS Module
- Downloads and compiles OpenSSL 3.0.15
- Enables FIPS provider support
- Installs to `/usr/local/openssl`

#### Stage 2: wolfSSL FIPS v5.8.2
- Downloads commercial wolfSSL FIPS package (password-protected)
- Compiles with FIPS v5 validation
- Runs FIPS hash generation
- Installs to `/usr/local`

#### Stage 3: wolfProvider v1.1.0
- Clones wolfProvider from GitHub
- Builds OpenSSL → wolfSSL bridge module
- Installs to OpenSSL modules directory

#### Stage 4: golang-fips/go Toolchain
- Clones golang-fips/go repository
- Applies FIPS patches to Go standard library
- Compiles custom Go toolchain (Go 1.24)
- Routes crypto/* to OpenSSL via CGO

#### Stage 5: CoreDNS v1.13.2
- Clones CoreDNS v1.13.2 from GitHub
- Builds with golang-fips/go (CGO_ENABLED=1)
- Creates binary: `/coredns`

#### Stage 6: FIPS-Compliant Runtime Image
- **CRITICAL**: Copies FIPS components BEFORE apt-get
- Installs runtime dependencies
- **Removes ALL non-FIPS crypto libraries** (3-step process)
- Verifies FIPS compliance at build time
- Configures entrypoint with validation

### Hardened Build (Dockerfile.hardened)

The hardened build includes all standard FIPS build stages plus additional STIG/CIS hardening in Stage 6:

- Password policies (STIG UBTU-22-411015)
- Password complexity requirements (STIG UBTU-22-611015/611020)
- Account lockout policies (STIG UBTU-22-412010/412020-035)
- SHA-512 password hashing (STIG UBTU-22-611045)
- File permissions and ownership (STIG UBTU-22-232085/232100/232120/232055)
- Kernel security parameters (sysctl hardening)
- SSH hardening configuration
- Sudo hardening
- Audit rules configuration
- SUID/SGID bit removal
- Package manager removal (prevents runtime package installation)
- Non-root user execution (UID 1001)

### Manual Build Commands

#### Standard FIPS Build
```bash
DOCKER_BUILDKIT=1 docker build \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  -t coredns-fips:v1.13.2-ubuntu-22.04 \
  .
```

#### Hardened Build
```bash
DOCKER_BUILDKIT=1 docker build \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  -t coredns:v1.13.2-ubuntu-22.04-fips \
  -f Dockerfile.hardened \
  .
```

### Build Artifacts

**Standard Build Output:**
- Image: `coredns-fips:v1.13.2-ubuntu-22.04`
- Size: ~500-600 MB
- Runtime user: root (default)

**Hardened Build Output:**
- Image: `coredns:v1.13.2-ubuntu-22.04-fips`
- Size: ~500-650 MB (additional hardening packages)
- Runtime user: non-root (UID 1001)
- Additional artifacts: Audit rules, PAM configurations, sysctl parameters

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
   - OpenSSL 3.0.15 version check
   - wolfProvider active status
   - wolfSSL FIPS integrity check (CAST)
   - SHA-256 cryptographic operation test

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

## Configuration

### Environment Variables

#### FIPS Configuration
- `OPENSSL_CONF` - Path to OpenSSL config (default: `/usr/local/openssl/ssl/openssl.cnf`)
- `OPENSSL_MODULES` - OpenSSL modules directory (default: `/usr/local/openssl/lib64/ossl-modules`)
- `LD_LIBRARY_PATH` - Includes FIPS OpenSSL and wolfSSL paths

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

# Check wolfProvider module
docker run --rm coredns-fips:v1.13.2-ubuntu-22.04 \
  ls -la /usr/local/openssl/lib64/ossl-modules/
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

### Security Hardening (Dockerfile.hardened)

The hardened variant includes DISA STIG V2R1 and CIS Level 1 Server benchmark controls:

- **Access Control**: Account lockout after 3 failed attempts (15-minute lockout), maximum 10 concurrent sessions, su command restricted to empty sugroup
- **Password Security**: 15-character minimum length, 4 character classes required, SHA-512 hashing, 5-password history, 60-day maximum age
- **Kernel Hardening**: Address space randomization, core dumps disabled, dmesg restriction, pointer obfuscation, ptrace scope limitation
- **Network Security**: TCP SYN cookies enabled, ICMP redirects disabled, source routing disabled, martian packet logging enabled
- **Audit and Logging**: Audit rules for time changes and identity modifications, sudo logging enabled, verbose SSH logging
- **File System Security**: UMASK 077, restrictive permissions on system files (0755 for executables, 0640 for logs), SUID/SGID bits removed

### Compliance Differences

| Feature | Dockerfile | Dockerfile.hardened |
|---------|-----------|---------------------|
| FIPS 140-3 | Yes | Yes |
| wolfSSL FIPS v5 (Certificate #4718) | Yes | Yes |
| DISA STIG V2R1 | No | Yes |
| CIS Level 1 Server | No | Yes |
| Runtime user | root | non-root (UID 1001) |
| Package managers | Included | Removed |
| Audit rules | No | Yes |
| Password policies | Default | STIG-compliant |
| Kernel hardening | Default | STIG/CIS parameters |

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

### v1.13.2-fips (2026-01-13)
- Initial FIPS 140-3 compliant build
- CoreDNS v1.13.2
- wolfSSL FIPS v5.8.2 (Certificate #4718)
- golang-fips/go with Go 1.24
- OpenSSL 3.0.15
- wolfProvider v1.1.0
- Ubuntu 22.04 base
- Comprehensive test suite (113 checks)
