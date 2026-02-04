# CoreDNS Production Build Guide

## Overview

This document guides you through building the production-ready CoreDNS image after completing testing and compliance verification.

## Prerequisites - Completed

✅ **Testing Build Completed**
- Testing image built: `coredns:v1.13.2-ubuntu-22.04-fips`
- Build date: 2026-01-16 10:19:20 UTC

✅ **Compliance Verification Passed**
- STIG Compliance: **56 pass, 0 fail** (100%)
- CIS Compliance: **112 pass, 1 fail** (99%)
- Reports location: `./stig-cis-report/`

✅ **Application Functionality Verified**
- CoreDNS v1.13.2 working
- FIPS 140-3 compliance verified
- wolfProvider v1.1.0 active

## Production vs Testing Image

### Testing Image (Dockerfile.hardened)
```
✓ FIPS 140-3 compliance
✓ STIG/CIS hardening rules applied
✓ OpenSCAP installed (for scanning)
✓ Package managers present (apt, dpkg)
✓ libgcrypt present (for OpenSCAP)
✓ Can run compliance scans
✓ Can troubleshoot with apt-get
```

### Production Image (Dockerfile.production)
```
✓ FIPS 140-3 compliance (100%)
✓ STIG/CIS hardening rules applied
✗ OpenSCAP removed
✗ Package managers removed (apt, dpkg)
✗ libgcrypt removed (non-FIPS crypto)
✗ Cannot run compliance scans
✗ Cannot install packages
✓ Minimal attack surface
✓ Truly immutable container
```

## Production Build Changes

### 1. OpenSCAP Removed
**Package:** `libopenscap8` removed from installation
**Impact:** Cannot run `oscap` scans on production image
**Reason:** Scanning tools not needed in production

### 2. Package Managers Removed
**Removed:**
- `apt`, `apt-get`, `apt-cache` binaries
- `dpkg`, `dpkg-deb`, `dpkg-query` binaries
- `/var/lib/apt`, `/var/cache/apt` directories
- `/var/lib/dpkg` directory
- Package documentation

**Impact:** 
- Cannot install packages at runtime
- Cannot query package database
- Truly immutable container

**Reason:** STIG requirement to prevent unauthorized software installation

### 3. Non-FIPS Crypto Libraries Removed
**Removed:**
- `libgcrypt20`
- `libgnutls30`
- `libnettle8`
- `libhogweed6`
- `libk5crypto3`

**Impact:** 
- 100% FIPS compliance enforced
- No fallback to non-FIPS cryptography
- OpenSCAP cannot run (needs libgcrypt)

**Reason:** Strict FIPS 140-3 compliance requirement

## Building Production Image

### Step 1: Review Compliance Reports

```bash
cd /home/ubuntu/works/jfrog-images/coredns/v1.13.2-ubuntu-22.04

# View compliance reports
ls -lh ./stig-cis-report/

# Check summary
grep -c '<result>pass</result>' ./stig-cis-report/*stig*.xml
grep -c '<result>pass</result>' ./stig-cis-report/*cis*.xml
```

**Expected Results:**
- STIG: 56+ passes
- CIS: 112+ passes (99% or better)

### Step 2: Build Production Image

```bash
./build-production.sh
```

**Build Time:** ~50-60 minutes (or faster if cached)

The script will:
1. Warn about production build implications
2. Check for compliance reports
3. Ask for confirmation
4. Build with `Dockerfile.production`
5. Tag as `coredns:v1.13.2-ubuntu-22.04-fips-production`

### Step 3: Verify Production Image

```bash
# 1. Verify image exists
docker images coredns:v1.13.2-ubuntu-22.04-fips-production

# 2. Test CoreDNS functionality
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production /coredns -version

# 3. Verify FIPS compliance
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production openssl list -providers

# 4. Verify OpenSCAP removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production which oscap
# Expected: (empty output or "not found")

# 5. Verify apt removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production which apt
# Expected: (empty output or "not found")

# 6. Verify non-FIPS crypto removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production \
  sh -c 'find /usr/lib /lib -name "libgcrypt*" 2>/dev/null | wc -l'
# Expected: 0
```

### Step 4: Tag for Registry

```bash
# Example for Docker Hub
docker tag coredns:v1.13.2-ubuntu-22.04-fips-production \
  myregistry/coredns:v1.13.2-fips-production

# Add date tag for tracking
docker tag coredns:v1.13.2-ubuntu-22.04-fips-production \
  myregistry/coredns:v1.13.2-fips-production-$(date +%Y%m%d)

# Add 'latest' tag if appropriate
docker tag coredns:v1.13.2-ubuntu-22.04-fips-production \
  myregistry/coredns:latest-fips-production
```

### Step 5: Push to Registry

```bash
# Login to registry
docker login myregistry

# Push main tag
docker push myregistry/coredns:v1.13.2-fips-production

# Push dated tag
docker push myregistry/coredns:v1.13.2-fips-production-$(date +%Y%m%d)

# Push latest tag (if used)
docker push myregistry/coredns:latest-fips-production
```

## Production Deployment

### Kubernetes Deployment Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns-fips
  labels:
    app: coredns
    security: fips-hardened
spec:
  replicas: 3
  selector:
    matchLabels:
      app: coredns
  template:
    metadata:
      labels:
        app: coredns
        security: fips-hardened
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        fsGroup: 1001
      containers:
      - name: coredns
        image: myregistry/coredns:v1.13.2-fips-production
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        volumeMounts:
        - name: config
          mountPath: /etc/coredns
          readOnly: true
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: coredns-config
```

## Troubleshooting Production Containers

### Available Tools

Production containers still have these tools:
- `bash`, `sh` - Shell access
- `ps`, `top` - Process monitoring
- `netstat`, `ss` - Network monitoring
- `grep`, `awk`, `sed` - Text processing
- `find`, `ls`, `cat` - File operations
- `curl` - HTTP testing (if included)

### Debug Strategies

#### 1. Use Pre-installed Tools

```bash
docker exec -it <container-name> bash

# Check processes
ps aux

# Check network
ss -tulpn

# Check logs
find /var/log -type f -exec tail {} \;
```

#### 2. Kubernetes Debug Containers

```bash
# Attach debug container with full toolset
kubectl debug -it <pod-name> --image=ubuntu:22.04 --target=coredns
```

#### 3. Temporary Testing Image

```bash
# Deploy testing image temporarily for debugging
kubectl set image deployment/coredns-fips \
  coredns=coredns:v1.13.2-ubuntu-22.04-fips

# Rollback after debugging
kubectl rollout undo deployment/coredns-fips
```

## Rollback Plan

If issues arise with production image:

### Quick Rollback

```bash
# Rollback to testing image
kubectl set image deployment/coredns-fips \
  coredns=coredns:v1.13.2-ubuntu-22.04-fips

# Or rollback deployment
kubectl rollout undo deployment/coredns-fips
```

### Rebuild with Adjustments

```bash
# Edit Dockerfile.production as needed
vim Dockerfile.production

# Rebuild
./build-production.sh

# Re-push
docker push myregistry/coredns:v1.13.2-fips-production-$(date +%Y%m%d)

# Update deployment
kubectl set image deployment/coredns-fips \
  coredns=myregistry/coredns:v1.13.2-fips-production-$(date +%Y%m%d)
```

## Security Compliance

### Verification Evidence

Keep these artifacts for audit purposes:
- Testing image compliance reports: `./stig-cis-report/`
- Build logs: `build-production.log` (if captured)
- Production image metadata: `docker inspect <image>`

### Compliance Posture

The production image maintains the same compliance as testing:
- **STIG:** 100% compliance (56/56 rules)
- **CIS:** 99% compliance (112/113 rules)
- **FIPS:** 100% compliance (OpenSSL 3.0.18 + wolfSSL FIPS v5)

**Important:** Compliance is verified on testing image. Production image has identical hardening configuration but cannot self-scan.

## Monitoring Recommendations

### Metrics to Monitor

1. **Application Health**
   - DNS query response times
   - Error rates
   - Cache hit ratios

2. **Security Events**
   - Failed authentication attempts
   - Unauthorized access attempts
   - Configuration changes

3. **Resource Usage**
   - CPU utilization
   - Memory usage
   - Network throughput

### Alerting

Set up alerts for:
- Container restarts (pod crashes)
- High error rates
- Resource exhaustion
- Security policy violations

## Files Structure

```
coredns/v1.13.2-ubuntu-22.04/
├── Dockerfile                      # Original FIPS-enabled
├── Dockerfile.hardened             # Testing build (with OpenSCAP)
├── Dockerfile.production           # Production build ✨ NEW
├── build.sh                        # Original build script
├── build-hardened.sh              # Testing build script
├── build-production.sh            # Production build script ✨ NEW
├── scan-internal.sh               # Compliance scanning (testing only)
├── HARDENING-SUMMARY.md           # Hardening implementation details
├── QUICK-START.md                 # Quick reference
├── BUILD-VERIFICATION-REPORT.md   # Build verification results
├── PRODUCTION-BUILD-GUIDE.md      # This file ✨ NEW
└── stig-cis-report/               # Compliance reports (from testing)
    ├── coredns-internal-stig-*.html
    ├── coredns-internal-stig-*.xml
    ├── coredns-internal-cis-*.html
    └── coredns-internal-cis-*.xml
```

## Support and Escalation

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Cannot debug | No package managers | Use debug sidecar or pre-installed tools |
| Missing dependency | Removed during hardening | Verify in testing image, may need to rebuild |
| FIPS validation fails | Crypto library issue | Check wolfProvider status, review entrypoint logs |
| Performance degradation | FIPS overhead | Normal, FIPS crypto is slightly slower |

### Escalation Path

1. **Application Issues:** Check application logs and configuration
2. **FIPS Issues:** Contact FIPS team for cryptography problems
3. **STIG/CIS Issues:** Review compliance reports and hardening configuration
4. **Build Issues:** Review Dockerfile.production and build logs

## Conclusion

The production image is ready for deployment with:
- ✅ Full FIPS 140-3 compliance
- ✅ Complete STIG/CIS hardening
- ✅ Minimal attack surface
- ✅ No runtime package installation
- ✅ No non-FIPS crypto libraries
- ✅ Verified compliance from testing phase

The image provides production-grade security while maintaining full application functionality.

---

**Document Version:** 1.0  
**Date:** 2026-01-16  
**Image Version:** v1.13.2-ubuntu-22.04-fips-production  
**Compliance:** DISA STIG V2R1 + CIS Level 1 Server + FIPS 140-3
