# CoreDNS Production Build Checklist

## Pre-Build Verification

### ✅ Testing Phase Complete
- [x] Testing image built: `coredns:v1.13.2-ubuntu-22.04-fips`
- [x] Build date: 2026-01-16 10:19:20 UTC
- [x] Image size: 440MB

### ✅ Compliance Verification Complete
- [x] STIG scan completed: **56 pass, 0 fail (100%)**
- [x] CIS scan completed: **112 pass, 1 fail (99%)**
- [x] Reports saved: `./stig-cis-report/`
- [x] Reports reviewed and approved

### ✅ Application Functionality Verified
- [x] CoreDNS v1.13.2 working
- [x] FIPS 140-3 compliance verified
- [x] wolfProvider v1.1.0 active
- [x] No application errors

## Production Build Preparation

### ✅ Files Created
- [x] `Dockerfile.production` - Production Dockerfile
- [x] `build-production.sh` - Production build script (executable)
- [x] `PRODUCTION-BUILD-GUIDE.md` - Comprehensive guide
- [x] `PRODUCTION-BUILD-CHECKLIST.md` - This checklist

### ✅ Dockerfile.production Changes Applied
- [x] Header updated with production note
- [x] Labels updated (version, build.type, build.hardening)
- [x] OpenSCAP package (`libopenscap8`) removed
- [x] OpenSCAP verification code removed
- [x] FIPS crypto removal section uncommented
- [x] Package manager removal enhanced
- [x] Production notes added

### ✅ Build Script Created
- [x] `build-production.sh` created
- [x] Script made executable
- [x] Warnings added for production implications
- [x] Compliance report check added
- [x] User confirmation required
- [x] Verification steps documented

### ✅ Documentation Complete
- [x] Production build guide created
- [x] Verification steps documented
- [x] Deployment examples included
- [x] Troubleshooting guide added
- [x] Rollback procedures documented

## Production Build Execution

### Step 1: Final Review
- [ ] Review `Dockerfile.production` for accuracy
- [ ] Verify compliance reports are acceptable
- [ ] Confirm no application changes needed
- [ ] Notify stakeholders of production build

### Step 2: Build Production Image
```bash
./build-production.sh
```

**Checklist:**
- [ ] Script asks for confirmation
- [ ] Build completes without errors
- [ ] Build time: ~50-60 minutes (or faster if cached)
- [ ] Image tagged: `coredns:v1.13.2-ubuntu-22.04-fips-production`

### Step 3: Verify Production Image

#### Basic Verification
```bash
# Verify image exists
docker images coredns:v1.13.2-ubuntu-22.04-fips-production
```
- [ ] Image exists in local registry
- [ ] Image size is reasonable (similar to testing image)

#### Application Testing
```bash
# Test CoreDNS version
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production /coredns -version
```
- [ ] CoreDNS version displays correctly
- [ ] FIPS validation passes
- [ ] No errors in output

#### FIPS Compliance
```bash
# Verify wolfProvider
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production openssl list -providers
```
- [ ] wolfProvider is listed
- [ ] wolfProvider is active
- [ ] FIPS validation passes

#### OpenSCAP Removal Verification
```bash
# Verify OpenSCAP removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production which oscap
```
- [ ] Output is empty or "not found"
- [ ] No oscap binary present

```bash
# Verify libopenscap library removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production \
  sh -c 'find /usr/lib -name "*openscap*" | wc -l'
```
- [ ] Output is 0

#### Package Manager Removal Verification
```bash
# Verify apt removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production which apt
```
- [ ] Output is empty or "not found"

```bash
# Verify dpkg removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production which dpkg
```
- [ ] Output is empty or "not found"

```bash
# Verify apt directories removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production \
  sh -c 'ls -d /var/lib/apt /var/cache/apt 2>/dev/null | wc -l'
```
- [ ] Output is 0

#### Non-FIPS Crypto Removal Verification
```bash
# Verify libgcrypt removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production \
  sh -c 'find /usr/lib /lib -name "libgcrypt*" 2>/dev/null | wc -l'
```
- [ ] Output is 0

```bash
# Verify libgnutls removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production \
  sh -c 'find /usr/lib /lib -name "libgnutls*" 2>/dev/null | wc -l'
```
- [ ] Output is 0

```bash
# Verify libnettle removed
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips-production \
  sh -c 'find /usr/lib /lib -name "libnettle*" 2>/dev/null | wc -l'
```
- [ ] Output is 0

### Step 4: Tag for Production Registry

```bash
# Replace <registry> with your actual registry
REGISTRY="<your-registry-url>"
DATE_TAG=$(date +%Y%m%d)

# Main production tag
docker tag coredns:v1.13.2-ubuntu-22.04-fips-production \
  ${REGISTRY}/coredns:v1.13.2-fips-production

# Dated tag for tracking
docker tag coredns:v1.13.2-ubuntu-22.04-fips-production \
  ${REGISTRY}/coredns:v1.13.2-fips-production-${DATE_TAG}

# Latest tag (optional)
docker tag coredns:v1.13.2-ubuntu-22.04-fips-production \
  ${REGISTRY}/coredns:latest-fips-production
```

**Checklist:**
- [ ] Registry URL confirmed
- [ ] Main tag created
- [ ] Dated tag created
- [ ] Latest tag created (if using)
- [ ] Verify tags: `docker images | grep coredns`

### Step 5: Push to Production Registry

```bash
# Login to registry
docker login ${REGISTRY}

# Push main tag
docker push ${REGISTRY}/coredns:v1.13.2-fips-production

# Push dated tag
docker push ${REGISTRY}/coredns:v1.13.2-fips-production-${DATE_TAG}

# Push latest tag (if used)
docker push ${REGISTRY}/coredns:latest-fips-production
```

**Checklist:**
- [ ] Registry login successful
- [ ] Main tag pushed successfully
- [ ] Dated tag pushed successfully
- [ ] Latest tag pushed (if used)
- [ ] Verify in registry UI/CLI

## Post-Build Actions

### Documentation
- [ ] Update deployment manifests with new image tag
- [ ] Document production image build date and version
- [ ] Archive compliance reports as audit evidence
- [ ] Update internal wiki/documentation

### Deployment Preparation
- [ ] Create deployment manifests/configs
- [ ] Configure resource limits
- [ ] Set up health checks
- [ ] Configure monitoring and alerting
- [ ] Document rollback procedure

### Communication
- [ ] Notify DevOps team of new production image
- [ ] Notify security team of compliance status
- [ ] Notify application team of deployment readiness
- [ ] Schedule deployment window

## Production Deployment

### Pre-Deployment
- [ ] Deployment window scheduled
- [ ] Stakeholders notified
- [ ] Rollback plan documented
- [ ] Monitoring configured
- [ ] On-call team available

### Deployment
- [ ] Deploy to staging environment first
- [ ] Run smoke tests in staging
- [ ] Deploy to production
- [ ] Verify health checks passing
- [ ] Monitor for errors/issues

### Post-Deployment
- [ ] Application health checks passing
- [ ] DNS resolution working correctly
- [ ] No errors in logs
- [ ] Monitoring shows normal metrics
- [ ] Performance within acceptable range

## Audit and Compliance

### Evidence Collection
- [ ] Testing image compliance reports saved
- [ ] Production build logs saved
- [ ] Image metadata documented
- [ ] Deployment records updated

### Compliance Documentation
- [ ] STIG compliance: 100% (56/56 rules)
- [ ] CIS compliance: 99% (112/113 rules)
- [ ] FIPS compliance: 100% verified
- [ ] Reports stored in compliance system

## Troubleshooting

### If Build Fails
1. [ ] Check build logs for errors
2. [ ] Verify Dockerfile.production syntax
3. [ ] Check available disk space
4. [ ] Review recent changes
5. [ ] Rollback to working Dockerfile if needed

### If Verification Fails
1. [ ] Review specific failed check
2. [ ] Check if expected behavior for production
3. [ ] Compare with testing image
4. [ ] Consult PRODUCTION-BUILD-GUIDE.md
5. [ ] Rebuild if necessary

### If Deployment Fails
1. [ ] Check application logs
2. [ ] Verify FIPS validation passes
3. [ ] Check resource availability
4. [ ] Review configuration
5. [ ] Rollback to previous version if needed

## Rollback Plan

### Quick Rollback to Testing Image
```bash
# If production image has issues
kubectl set image deployment/coredns-fips \
  coredns=coredns:v1.13.2-ubuntu-22.04-fips

# Or use previous production version
kubectl rollout undo deployment/coredns-fips
```

**Checklist:**
- [ ] Rollback procedure documented
- [ ] Testing image available in registry
- [ ] Rollback tested in staging
- [ ] Team trained on rollback procedure

## Sign-Off

### Build Team
- [ ] Production image built successfully
- [ ] All verification checks passed
- [ ] Documentation complete
- [ ] Signed off by: _________________ Date: _________

### Security Team
- [ ] Compliance verified (100% STIG, 99% CIS)
- [ ] FIPS 140-3 compliance confirmed
- [ ] Production hardening approved
- [ ] Signed off by: _________________ Date: _________

### Application Team
- [ ] Application functionality verified
- [ ] Performance acceptable
- [ ] Ready for deployment
- [ ] Signed off by: _________________ Date: _________

### DevOps Team
- [ ] Image tagged and pushed to registry
- [ ] Deployment manifests updated
- [ ] Monitoring configured
- [ ] Ready for production deployment
- [ ] Signed off by: _________________ Date: _________

## Summary

**Production Image:**
- Name: `coredns:v1.13.2-ubuntu-22.04-fips-production`
- Registry: `<your-registry>/coredns:v1.13.2-fips-production`
- Build Date: _______________
- Compliance: 100% STIG, 99% CIS, 100% FIPS
- Status: ✅ Ready for Production Deployment

**Security Features:**
- ✅ FIPS 140-3 (OpenSSL 3.0.18 + wolfSSL FIPS v5)
- ✅ DISA STIG V2R1 hardening
- ✅ CIS Level 1 Server hardening
- ✅ Package managers removed
- ✅ Non-FIPS crypto removed
- ✅ OpenSCAP tools removed
- ✅ Truly immutable container

---

**Checklist Version:** 1.0  
**Date:** 2026-01-16  
**Image Version:** v1.13.2-ubuntu-22.04-fips-production
