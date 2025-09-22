# CCP4i2 Django Azure Deployment Administration Guide

## Overview

This repository contains the complete Azure infrastructure and application deployment for CCP4i2 (Collaborative Computational Project No. 4 Interface 2) - a Django-based crystallographic software suite with Next.js frontend, deployed on Azure Container Apps with private networking and Azure AD authentication.

## Architecture Summary

- **Frontend**: Next.js web application (Container App)
- **Backend**: Django REST API server (Container App)
- **Database**: Azure Database for PostgreSQL (Private endpoint)
- **Storage**: Azure Storage Account with File Shares (Private endpoint)
- **Container Registry**: Azure Container Registry (Private endpoint)
- **Security**: Azure Key Vault for secrets (Private endpoint)
- **Networking**: Private VNet with dedicated subnets and NSGs
- **Authentication**: Azure AD Easy Auth integration
- **Scientific Software**: CCP4 suite installed via container jobs

## Prerequisites

### Required Tools
```bash
# Azure CLI with Container Apps extension
az --version
az extension add --name containerapp

# Bicep CLI
az bicep --version

# Docker (for local image building)
docker --version
```

### Required Permissions
- **Azure**: Contributor role on target subscription
- **Azure AD**: Application Administrator (for authentication setup)
- **Resource Groups**: Owner permissions for RBAC assignments

## Quick Deployment

### Step 1: Infrastructure Setup

```bash
cd /Users/nmemn/Developer/ccp4i2-django

# Make scripts executable
chmod +x azure/deploy-to-aca.sh
chmod +x azure/deploy-container-app.sh

## Directory Structure

```
bicep/
├── infrastructure/                 # Infrastructure as Code
│   ├── infrastructure.bicep       # Main infrastructure template
│   ├── infrastructure.json        # Compiled ARM template
│   ├── applications.bicep         # Container Apps template
│   ├── applications.json          # Compiled ARM template
│   └── applications.parameters.json # Application parameters
├── scripts/                       # Deployment scripts
│   ├── deploy-infrastructure.sh   # Deploy base infrastructure
│   ├── deploy-applications.sh     # Deploy container applications
│   ├── build-and-push.sh         # Build and push container images
│   └── install-ccp4-containerapp.sh # CCP4 installation
├── setup-authentication.sh        # Configure Azure AD auth
├── test-authentication.sh         # Test authentication
├── .env.deployment                # Environment variables
└── README.md                      # This file
```

## Initial Deployment

### 1. Infrastructure Deployment
```bash
cd bicep/
./scripts/deploy-infrastructure.sh
```
**Creates:**
- Resource Group
- Virtual Network with subnets
- Azure Container Registry
- PostgreSQL Database
- Storage Account with File Shares
- Key Vault with secrets
- Container Apps Environment
- Private endpoints for all services

### 2. Application Images
```bash
# Build and push container images
./scripts/build-and-push.sh
```

### 3. CCP4 Software Installation
```bash
# Install CCP4 scientific software suite
./scripts/install-ccp4-containerapp.sh
```

### 4. Application Deployment
```bash
# Deploy Django and Next.js applications
./scripts/deploy-applications.sh
```

### 5. Authentication Setup (Optional)
```bash
# Configure Azure AD authentication
./setup-authentication.sh <CLIENT_ID> <CLIENT_SECRET>
```

## Day-to-Day Administration

### Environment Status Check
```bash
# Check all resources
az resource list --resource-group ccp4i2-bicep-rg-ne --output table

# Check container apps status
az containerapp list --resource-group ccp4i2-bicep-rg-ne \
  --query '[].{Name:name, Status:properties.provisioningState, URL:properties.configuration.ingress.fqdn}' \
  --output table

# Check authentication status
./test-authentication.sh
```

### Application Management

#### Scaling Applications
```bash
# Scale web app (1-5 replicas)
az containerapp update \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne \
  --min-replicas 2 \
  --max-replicas 8

# Scale server app (1-10 replicas)
az containerapp update \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --min-replicas 2 \
  --max-replicas 15
```

#### Application Logs
```bash
# View web app logs
az containerapp logs show \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne \
  --follow

# View server app logs  
az containerapp logs show \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --follow

# View logs from specific time
az containerapp logs show \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --since 1h
```

#### Container Access
```bash
# Connect to running server container
az containerapp exec \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --command "/bin/bash"

# Connect to web container
az containerapp exec \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne \
  --command "/bin/bash"
```

## Application Updates

### 1. Code Updates and Redeployment

#### Update Application Images
```bash
# Build new images with updated code
./scripts/build-and-push.sh

# The script will:
# - Build new Docker images
# - Push to Azure Container Registry  
# - Update IMAGE_TAG in .env.deployment
```

#### Deploy Updated Applications
```bash
# Deploy with new images
./scripts/deploy-applications.sh

# Or deploy with specific image tag
IMAGE_TAG=20250922-120000 ./scripts/deploy-applications.sh
```

#### Rolling Updates
Container Apps automatically perform rolling updates:
- New revision is created with updated image
- Traffic gradually shifts to new revision
- Old revision is decommissioned
- Zero-downtime deployment

#### Manual Revision Management
```bash
# List all revisions
az containerapp revision list \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --output table

# Activate specific revision
az containerapp revision activate \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --revision <REVISION_NAME>

# Set traffic distribution
az containerapp traffic set \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --revision-weight <REVISION1>=80 <REVISION2>=20
```

### 2. Configuration Updates

#### Environment Variables
```bash
# Update environment variables
az containerapp update \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --set-env-vars NEW_SETTING=value

# Remove environment variable
az containerapp update \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --remove-env-vars OLD_SETTING
```

#### Secrets Management
```bash
# Add new secret to Key Vault
az keyvault secret set \
  --vault-name kv-ne-kmayz3 \
  --name "new-secret" \
  --value "secret-value"

# Update container app to use new secret
# Edit applications.bicep and redeploy
./scripts/deploy-applications.sh
```

### 3. Database Updates

#### Schema Migrations
```bash
# Connect to server container
az containerapp exec \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --command "/bin/bash"

# Inside container, run Django migrations
python manage.py migrate

# Or run migrations as a job
az containerapp job create \
  --name migration-job \
  --resource-group ccp4i2-bicep-rg-ne \
  --environment ccp4i2-bicep-env-ne \
  --image ccp4acrnekmay.azurecr.io/ccp4i2/server:latest \
  --command "python manage.py migrate"
```

#### Database Backup
```bash
# Create backup (from within server container)
pg_dump -h ccp4i2-bicep-db-ne.postgres.database.azure.com \
        -U ccp4i2 \
        -d postgres \
        --no-password > backup_$(date +%Y%m%d_%H%M%S).sql
```

## Taking Down Applications

### 1. Stop Applications (Maintenance Mode)
```bash
# Scale to zero (stop serving traffic)
az containerapp update \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne \
  --min-replicas 0 \
  --max-replicas 0

az containerapp update \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --min-replicas 0 \
  --max-replicas 0

# Verify applications are stopped
az containerapp show \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne \
  --query properties.template.scale
```

### 2. Delete Applications Only
```bash
# Delete container apps (keeps infrastructure)
az containerapp delete \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne \
  --yes

az containerapp delete \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --yes

# Keep: Database, Storage, Network, Key Vault
```

### 3. Delete Entire Infrastructure
```bash
# ⚠️  WARNING: This deletes EVERYTHING including data!
az group delete \
  --name ccp4i2-bicep-rg-ne \
  --yes \
  --no-wait

# This removes:
# - All container apps
# - Database and ALL data
# - Storage and ALL files  
# - Container images
# - Network infrastructure
# - Key Vault and secrets
```

## Bringing Applications Back Up

### 1. Restart Stopped Applications
```bash
# Scale back up from zero
az containerapp update \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne \
  --min-replicas 1 \
  --max-replicas 5

az containerapp update \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --min-replicas 1 \
  --max-replicas 10
```

### 2. Recreate Deleted Applications
```bash
# If apps were deleted but infrastructure exists
./scripts/deploy-applications.sh
```

### 3. Full Infrastructure Rebuild
```bash
# If everything was deleted
./scripts/deploy-infrastructure.sh
./scripts/build-and-push.sh
./scripts/install-ccp4-containerapp.sh
./scripts/deploy-applications.sh

# Reconfigure authentication if needed
./setup-authentication.sh <CLIENT_ID> <CLIENT_SECRET>
```

## Monitoring and Troubleshooting

### Application Health
```bash
# Check application health
curl -f https://ccp4i2-bicep-web.whitecliff-258bc831.northeurope.azurecontainerapps.io/health || echo "Web app unhealthy"
curl -f https://ccp4i2-bicep-server.whitecliff-258bc831.northeurope.azurecontainerapps.io/health || echo "Server app unhealthy"

# Check replica status
az containerapp replica list \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --output table
```

### Resource Usage
```bash
# Container Apps metrics
az monitor metrics list \
  --resource /subscriptions/$(az account show --query id -o tsv)/resourceGroups/ccp4i2-bicep-rg-ne/providers/Microsoft.App/containerApps/ccp4i2-bicep-server \
  --metric "CpuUsage"

# Database metrics  
az monitor metrics list \
  --resource /subscriptions/$(az account show --query id -o tsv)/resourceGroups/ccp4i2-bicep-rg-ne/providers/Microsoft.DBforPostgreSQL/flexibleServers/ccp4i2-bicep-db-ne \
  --metric "cpu_percent"
```

### Log Analysis
```bash
# Application Insights (if configured)
az monitor app-insights query \
  --app ccp4i2-bicep-ne-logs \
  --analytics-query "requests | where timestamp > ago(1h) | summarize count() by resultCode"

# Container logs with filters
az containerapp logs show \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --filter "severity=='Error'"
```

## Security Management

### Authentication Management
```bash
# Check authentication configuration
az containerapp auth show \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne

# Update authentication settings
az containerapp auth update \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne \
  --action RedirectToLoginPage
```

### Certificate Management
```bash
# Container Apps automatically manage SSL certificates
# Check certificate status
az containerapp show \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne \
  --query properties.configuration.ingress.customDomains
```

### Access Control
```bash
# Review RBAC assignments
az role assignment list \
  --scope /subscriptions/$(az account show --query id -o tsv)/resourceGroups/ccp4i2-bicep-rg-ne

# Check Key Vault access policies
az keyvault show \
  --name kv-ne-kmayz3 \
  --query properties.accessPolicies
```

## Backup and Disaster Recovery

### Database Backup
```bash
# Automated backups are enabled by default
# Check backup retention
az postgres flexible-server backup list \
  --resource-group ccp4i2-bicep-rg-ne \
  --server-name ccp4i2-bicep-db-ne

# Restore from backup
az postgres flexible-server restore \
  --resource-group ccp4i2-bicep-rg-ne \
  --name ccp4i2-bicep-db-restored \
  --source-server ccp4i2-bicep-db-ne \
  --restore-time "2025-09-22T10:00:00Z"
```

### Storage Backup
```bash
# CCP4 data and application files are in Azure File Shares
# Enable soft delete and versioning
az storage account blob-service-properties update \
  --account-name stornekmayz3n2 \
  --enable-delete-retention true \
  --delete-retention-days 30
```

### Container Image Backup
```bash
# Images are stored in Azure Container Registry
# Enable geo-replication for disaster recovery
az acr replication create \
  --registry ccp4acrnekmay \
  --location westeurope
```

## Cost Management

### Resource Optimization
```bash
# Check resource usage and costs
az consumption usage list \
  --start-date $(date -d "30 days ago" +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d)

# Optimize container app scaling
az containerapp update \
  --name ccp4i2-bicep-web \
  --resource-group ccp4i2-bicep-rg-ne \
  --min-replicas 0  # Scale to zero during off-hours

# Schedule scaling with Azure Automation
```

### Storage Optimization
```bash
# Clean up old container images
az acr repository delete \
  --name ccp4acrnekmay \
  --repository ccp4i2/server \
  --tag old-tag

# Archive old CCP4 data
# Move infrequently accessed data to cool/archive tiers
```

## Troubleshooting Common Issues

### Application Won't Start
```bash
# Check container logs
az containerapp logs show --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne

# Check image pull issues
az containerapp revision list --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne

# Verify environment variables and secrets
az containerapp show --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne --query properties.template.containers[0].env
```

### Database Connection Issues
```bash
# Test database connectivity from container
az containerapp exec \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --command "pg_isready -h ccp4i2-bicep-db-ne.postgres.database.azure.com -U ccp4i2"

# Check private endpoint resolution
nslookup ccp4i2-bicep-db-ne.postgres.database.azure.com
```

### Authentication Issues
```bash
# Test authentication endpoints
curl -I https://ccp4i2-bicep-web.whitecliff-258bc831.northeurope.azurecontainerapps.io/.auth/me

# Check Azure AD app registration
az ad app show --id cc780b24-ca44-4fec-b8e6-48d0c696a888

# Review sign-in logs in Azure Portal
```

### Network Connectivity Issues
```bash
# Check private endpoints
az network private-endpoint list --resource-group ccp4i2-bicep-rg-ne

# Verify NSG rules
az network nsg rule list --resource-group ccp4i2-bicep-rg-ne --nsg-name ccp4i2-bicep-ne-container-apps-nsg

# Test internal connectivity
az containerapp exec --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne --command "curl -I http://ccp4i2-bicep-web"
```

## Emergency Procedures

### Critical Application Issue
1. **Immediate**: Scale problematic app to 0 replicas
2. **Investigate**: Check logs and metrics
3. **Rollback**: Activate previous working revision
4. **Communicate**: Notify users of service status

### Data Corruption
1. **Immediate**: Stop all applications (scale to 0)
2. **Assess**: Determine extent of corruption
3. **Restore**: From most recent good backup
4. **Validate**: Test restored system before resuming service

### Security Incident  
1. **Immediate**: Revoke compromised credentials
2. **Isolate**: Disable affected resources
3. **Investigate**: Review audit logs
4. **Remediate**: Apply security patches and updates

## Useful Commands Reference

```bash
# Quick status check
alias ccp4-status='az containerapp list --resource-group ccp4i2-bicep-rg-ne --query "[].{Name:name, Status:properties.provisioningState, Replicas:properties.template.scale.minReplicas}" -o table'

# Quick log check
alias ccp4-logs='az containerapp logs show --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne --tail 50'

# Quick restart
alias ccp4-restart='az containerapp revision restart --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne --revision $(az containerapp revision list --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne --query "[0].name" -o tsv)'
```

## Support and Documentation

- **Azure Container Apps**: [Official Documentation](https://docs.microsoft.com/azure/container-apps/)
- **CCP4 Software**: [CCP4 Documentation](https://www.ccp4.ac.uk/)
- **Django**: [Django Documentation](https://docs.djangoproject.com/)
- **Next.js**: [Next.js Documentation](https://nextjs.org/docs)

## Maintenance Schedule

### Daily
- Check application health and performance
- Review error logs
- Monitor resource usage

### Weekly  
- Update container images with latest code
- Review authentication logs
- Check backup status

### Monthly
- Update base infrastructure if needed
- Review and rotate secrets
- Analyze cost optimization opportunities
- Test disaster recovery procedures

---

**⚠️ Important Notes:**
- Always test changes in a non-production environment first
- Keep backup of configuration files and deployment scripts
- Monitor Azure service health and planned maintenance
- Regularly review and update authentication policies
- Document any custom changes or configurations
az storage account create --name ccp4i2storage --resource-group ccp4i2-rg --location eastus --sku Standard_LRS

# PostgreSQL database
az postgres flexible-server create \
  --name ccp4i2-db \
  --resource-group ccp4i2-rg \
  --location eastus \
  --admin-user ccp4i2 \
  --admin-password $(openssl rand -base64 16) \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 15
```

### 5. Create Container App

```bash
# Create environment
az containerapp env create \
  --name ccp4i2-env \
  --resource-group ccp4i2-rg \
  --location eastus

# Deploy application
az containerapp create \
  --name ccp4i2-app \
  --resource-group ccp4i2-rg \
  --environment ccp4i2-env \
  --yaml azure/container-app.yml
```

## Configuration

### Environment Variables

Create a `.env` file in your project root:

```bash
# Database
DB_NAME=ccp4i2
DB_USER=ccp4i2
DB_PASSWORD=your_secure_password
DB_HOST=ccp4i2-db.postgres.database.azure.com
DB_PORT=5432

# Django
DJANGO_SECRET_KEY=your_django_secret_key
DEBUG=false
ALLOWED_HOSTS=localhost,127.0.0.1,your-app-name.azurecontainerapps.io

# Application
CCP4_DATA_PATH=/mnt/ccp4data
UVICORN_WORKERS=2
```

### CCP4 Data Setup

Upload your CCP4 installation to the Azure File Share:

```bash
# Get storage account key
STORAGE_KEY=$(az storage account keys list --resource-group ccp4i2-rg --account-name ccp4i2storage --query '[0].value' -o tsv)

# Upload CCP4 data
az storage file upload-batch \
  --account-name ccp4i2storage \
  --account-key $STORAGE_KEY \
  --destination ccp4data \
  --source /path/to/your/ccp4/installation
```

## Scaling and Performance

### Auto-scaling Configuration

The application is configured to scale based on HTTP traffic:

```yaml
scale:
  minReplicas: 1
  maxReplicas: 10
  rules:
    - name: http-scaling
      http:
        metadata:
          concurrentRequests: "10"
```

### Resource Allocation

- **Nginx**: 0.5 CPU, 1GB RAM
- **Web Client**: 0.5 CPU, 1GB RAM
- **API Server**: 1.0 CPU, 2GB RAM

## Monitoring and Logging

### View Logs

```bash
# View application logs
az containerapp logs show \
  --name ccp4i2-app \
  --resource-group ccp4i2-rg \
  --follow
```

### Application Insights

Enable monitoring:

```bash
az monitor app-insights component create \
  --app ccp4i2-app \
  --location eastus \
  --resource-group ccp4i2-rg
```

## Troubleshooting

### Common Issues

1. **Build Failures**

   ```bash
   # Check build logs
   az acr task logs --registry ccp4i2acr --name build-task-name
   ```

2. **Database Connection Issues**

   ```bash
   # Check database connectivity
   az postgres flexible-server connect \
     --name ccp4i2-db \
     --admin-user ccp4i2 \
     --query "SELECT version();"
   ```

3. **File Share Issues**
   ```bash
   # List files in share
   az storage file list \
     --account-name ccp4i2storage \
     --share-name ccp4data
   ```

### Health Checks

The application includes health checks for all services:

- Database connectivity
- API server responsiveness
- Web client availability

## Cost Optimization

### Estimated Monthly Costs

- **Container Apps**: $0.16/hour per container instance
- **PostgreSQL**: $0.016/hour (Burstable B1ms)
- **Storage**: $0.06/GB/month
- **Container Registry**: $0.67/month (Basic tier)

### Cost Saving Tips

1. Use spot instances for non-production workloads
2. Set up auto-scaling to reduce instances during low traffic
3. Use Azure reservations for predictable workloads
4. Monitor usage and adjust resource allocation

## Security

### Network Security

- All traffic goes through Azure Front Door/App Gateway
- Database access restricted to Container Apps environment
- File shares secured with Azure AD authentication

### Secrets Management

Use Azure Key Vault for sensitive data:

```bash
# Create Key Vault
az keyvault create --name ccp4i2-kv --resource-group ccp4i2-rg

# Store secrets
az keyvault secret set --vault-name ccp4i2-kv --name db-password --value $DB_PASSWORD
```

## Backup and Recovery

### Database Backups

Azure Database for PostgreSQL provides automatic backups:

```bash
# List available backups
az postgres flexible-server backup list \
  --resource-group ccp4i2-rg \
  --name ccp4i2-db
```

### File Share Backups

```bash
# Enable backup for storage account
az backup protection enable-for-azurefileshare \
  --resource-group ccp4i2-rg \
  --vault-name ccp4i2-backup-vault \
  --storage-account ccp4i2storage \
  --azure-file-share ccp4data
```

## Support

For issues or questions:

1. Check Azure Container Apps documentation
2. Review application logs
3. Contact Azure support for infrastructure issues
4. Check CCP4i2 community forums for application-specific issues
