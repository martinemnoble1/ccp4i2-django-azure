# Spring Cleaning - October 6, 2025

## Overview
After successful completion of the clean rebuild and deployment validation, obsolete documentation and scripts were archived.

## Archived Files

### Documentation (Obsolete)
- `DEPLOYMENT_FIXES.md` - Historical troubleshooting notes from initial deployments
- `DEPLOYMENT_STATUS.md` - Outdated status tracking document
- `README-BACKUP.md` - Old backup of README, superseded by current documentation
- `SHELL_SCRIPTS_UPDATES.md` - Historical notes about script changes
- `WORKING_DIRECTORY_FIX.md` - Specific fix documentation that's been incorporated
- `MAINTENANCE_VM_DEPLOYMENT.md` - VM-based deployment approach (deprecated)

### Scripts (Obsolete)
- `deploy-master.sh` - Root-level deployment script, replaced by `scripts/deploy-*.sh`
- `update-db-password.sh` - One-time utility script, preserved in git history
- `create-db.sh` (from root) - Old database creation script from Sept 21

### Directories
- `Deprecated/` - Entire directory containing VM-related cruft and deprecation notes

## Retained Files

### Active Documentation
- ✅ `DEPLOYMENT_GUIDE.md` - Main deployment documentation
- ✅ `QUICK_REFERENCE.md` - Command reference
- ✅ `AUTHENTICATION_SETUP.md` - Azure AD configuration
- ✅ `PRIVATE_VNET_DEPLOYMENT.md` - Private network architecture
- ✅ `SECURITY_ARCHITECTURE.md` - Security design documentation
- ✅ `MANAGEMENT_CONTAINER.md` - Maintenance job documentation
- ✅ `WORKER_SETUP.md` - Worker configuration
- ✅ `README-BINARY-SETUP.md` - **CRITICAL** CCP4 binary setup procedures

### Active Code
- ✅ `infrastructure/` - Bicep templates for infrastructure
- ✅ `scripts/` - Active deployment and maintenance scripts
- ✅ `.env.deployment` - Current environment configuration
- ✅ `.env.deployment.template` - Template for new deployments

## System Status at Cleanup Time

### Successful Clean Rebuild Completed
- ✅ Fresh CCP4 9.0.011 installation to Azure Files
- ✅ Python packages installed with CCP4's Python 3.9 (binary compatibility)
- ✅ PYTHONPATH handling fixed in startup scripts
- ✅ All services operational: web, server, worker
- ✅ Health checks passing
- ✅ Security locked down: all services using private endpoints only

### Key Technical Achievements
- Binary module compatibility resolved (psycopg2, numpy, scipy with Python 3.9)
- NumPy <2.0 constraint validated
- PYTHONPATH restoration after CCP4 setup sourcing working correctly
- Complete private network deployment verified

## Archive Disposition
This archive can be safely deleted after:
1. Git commit confirms all changes are tracked
2. 30-day retention period (for reference if needed)
3. Verification that no references exist in active documentation

## Notes
Files in this archive represent the evolutionary history of the deployment but are no longer needed for ongoing operations. All essential information has been consolidated into the retained documentation.

Last successful deployment: applications-20251006-095611
Docker images: server:20251006-092815, web:20251004-214722
