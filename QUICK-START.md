# CoreDNS STIG/CIS Hardening - Quick Start Guide

## 🚀 Quick Commands

### Build the Hardened Image
```bash
./build-hardened.sh
```
**Time:** ~50-60 minutes  
**Output:** `coredns:v1.13.2-ubuntu-22.04-fips`

### Run Compliance Scan
```bash
./scan-internal.sh coredns:v1.13.2-ubuntu-22.04-fips
```
**Time:** ~3-5 minutes  
**Output:** HTML/XML reports in `./stig-cis-report/`

### Test FIPS Compliance
```bash
# Verify wolfProvider loaded
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips openssl list -providers

# Test CoreDNS
docker run --rm coredns:v1.13.2-ubuntu-22.04-fips /coredns -version
```

## 📋 Implementation Checklist

- [x] Step 1: OpenSSL updated to 3.0.18
- [x] Step 2: Dockerfile.hardened created
- [x] Step 2.5: FIPS crypto removal commented out (for OpenSCAP)
- [x] Step 3: STIG/CIS hardening packages added
- [x] Step 4: STIG/CIS configuration rules applied
- [x] Step 5: Package manager removal added
- [x] Step 6: build-hardened.sh created
- [x] Step 7: scan-internal.sh created

## 🎯 Expected Results

### DISA STIG
- **Target:** ~100% compliance
- **Profile:** DISA STIG V2R1

### CIS Level 1 Server
- **Target:** ~99% compliance (107/108 pass)
- **Expected Failure:** 1 rule (acceptable)

## 📁 Key Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Original FIPS-enabled (OpenSSL 3.0.18) |
| `Dockerfile.hardened` | FIPS + STIG/CIS hardened |
| `build-hardened.sh` | Build script for hardened image |
| `scan-internal.sh` | Compliance scanning script |
| `HARDENING-SUMMARY.md` | Detailed implementation documentation |

## 🔒 Security Features

### FIPS 140-3 Compliance
- OpenSSL 3.0.18 with FIPS module
- wolfSSL FIPS v5.8.2 (Certificate #4718)
- wolfProvider v1.1.0
- golang-fips/go toolchain

### STIG/CIS Hardening
- Password policies (60-day expiration, 15-char minimum)
- Account lockout (3 failed attempts)
- PAM faillock integration
- File permission hardening
- Kernel parameter hardening
- SSH hardening (FIPS ciphers only)
- Audit rules configured
- Package managers removed

## ⚠️ Important Notes

1. **OpenSCAP Dependencies:** The crypto library removal section is commented out to allow scanning
2. **FIPS Team Sections:** Do NOT modify FIPS-related code (OpenSSL, wolfSSL, wolfProvider)
3. **Multi-arch Support:** Works on x86_64 and ARM64
4. **Non-root User:** CoreDNS runs as UID 1001

## 📚 Documentation

- Full details: `HARDENING-SUMMARY.md`
- Original README: `README.md`
- Test scripts: `tests/` directory

## 🧪 Testing Workflow

1. **Build:** `./build-hardened.sh` (50-60 min)
2. **Scan:** `./scan-internal.sh coredns:v1.13.2-ubuntu-22.04-fips` (3-5 min)
3. **Review:** Open HTML reports in `./stig-cis-report/`
4. **Test:** Run CoreDNS functionality tests in `tests/` directory

## 🆘 Troubleshooting

### Build fails
- Check `wolfssl_password.txt` exists
- Ensure Docker BuildKit enabled: `export DOCKER_BUILDKIT=1`
- Verify 8GB+ RAM and 20GB+ disk space available

### Scan fails with "libgcrypt not found"
- Crypto removal section should be commented out in `Dockerfile.hardened`
- Rebuild the image if needed

### Low compliance score
- Review HTML reports for specific failures
- Compare with Python reference implementation
- Check all STIG/CIS configuration sections were applied

## 📞 Support

For issues or questions:
1. Review `HARDENING-SUMMARY.md` for detailed implementation
2. Check Python reference: `/home/ubuntu/works/jfrog-images/python/3.12-ubuntu-22.04/`
3. Consult hardening plan documentation

---

**Status:** ✅ Ready for Build and Testing  
**Date:** 2026-01-16
