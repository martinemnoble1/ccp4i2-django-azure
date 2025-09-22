# Private VNet Deployment Guide

## Overview
The CCP4i2 deployment has been updated to use a secure private Virtual Network (VNet) architecture with private endpoints for all Azure services.

## Architecture Changes

### 🔒 Security Features
- **No Public Internet Access**: PostgreSQL, Storage, Key Vault, and Container Registry have no public endpoints
- **Private Endpoints**: All services communicate through Azure's private backbone
- **VNet Integration**: Container Apps run in dedicated subnets with proper network isolation
- **Private DNS**: Automatic name resolution for private endpoints
- **RBAC Authorization**: Key Vault uses role-based access control instead of access policies

### 🏗️ Infrastructure Components

#### Virtual Network (10.0.0.0/16)
- **Container Apps Subnet** (`10.0.1.0/24`): Delegated to Microsoft.App/environments
- **Private Endpoints Subnet** (`10.0.2.0/24`): Hosts all private endpoints
- **Management Subnet** (`10.0.3.0/24`): For future administrative access

#### Private Endpoints
- PostgreSQL Flexible Server
- Storage Account (File shares)
- Key Vault
- Container Registry

#### Network Security Groups
- Container Apps NSG: Allows HTTP/HTTPS traffic only
- Private Endpoints NSG: Restrictive security rules

## Deployment Process

### 1. Deploy Infrastructure
```bash
cd bicep/scripts
./deploy-infrastructure.sh
```

This deploys:
- Virtual Network with subnets
- Private DNS zones
- Storage Account with private endpoints
- PostgreSQL with private endpoints
- Key Vault with private endpoints
- Container Registry with private endpoints
- Container Apps Environment in VNet

### 2. Build and Push Images
```bash
./build-and-push.sh
```

This builds and pushes Docker images to the private Container Registry.

### 3. Deploy Applications
```bash
./deploy-applications.sh
```

This deploys:
- Django server container app
- Next.js web container app
- Proper RBAC role assignments for Key Vault access

## Configuration Details

### Database Connection
- **SSL Mode**: Required (secure connection over private network)
- **Host**: PostgreSQL FQDN resolves to private IP via private DNS zone
- **Certificate Validation**: Simplified for private endpoints (Azure-managed certificates)

### Key Vault Access
- **Authentication**: Managed Identity with RBAC
- **Role**: Key Vault Secrets User (least privilege)
- **Network**: Private endpoint only, no public access

### Storage Access
- **File Shares**: Mounted via private endpoints
- **Network**: All public access disabled
- **Authentication**: Storage account keys (for Container Apps storage mounts)

### Container Registry
- **Access**: Private endpoint only
- **Authentication**: Admin user credentials (stored in Key Vault)
- **Network**: No public Docker pulls

## Security Benefits

### ✅ Zero Trust Network
- No services exposed to public internet
- All communication encrypted in transit
- Network segmentation with dedicated subnets

### ✅ Defense in Depth
- Private endpoints + Network Security Groups
- RBAC authorization + Managed identities
- SSL/TLS encryption + Private DNS resolution

### ✅ Compliance Ready
- Meets enterprise security requirements
- Audit-ready with Azure Monitor integration
- Data residency within Azure regions

## Monitoring and Troubleshooting

### Network Connectivity
```bash
# Check Container Apps logs
az containerapp logs show --name ccp4i2-server --resource-group <rg-name>

# Check private endpoint status
az network private-endpoint list --resource-group <rg-name>

# Verify DNS resolution
az network private-dns zone list --resource-group <rg-name>
```

### Database Connectivity
The PostgreSQL connection now uses:
- Private endpoint FQDN (resolves to private IP)
- SSL encryption (required)
- Azure-managed certificates (simplified validation)

### Key Vault Access
- Uses system-assigned managed identity
- RBAC-based permissions (Key Vault Secrets User role)
- No access keys or connection strings needed

## Comparison: Before vs After

| Component | Before (Public) | After (Private) |
|-----------|----------------|-----------------|
| PostgreSQL | Public endpoint | Private endpoint only |
| Storage | Public access | Private endpoint only |
| Key Vault | Public access | Private endpoint only |
| Container Registry | Public pulls | Private endpoint only |
| Network | Internet-facing | VNet-isolated |
| Security | Basic firewall rules | Defense in depth |
| Compliance | Basic | Enterprise-ready |

## Future Enhancements

### 🔧 Additional Security
- Azure Bastion for secure management access
- Application Gateway with WAF for advanced protection
- Network Watcher for traffic analysis

### 📊 Enhanced Monitoring
- Azure Sentinel for security monitoring
- Network monitoring with flow logs
- Custom alerting for network anomalies

### 🚀 Performance
- ExpressRoute for hybrid connectivity
- Azure Front Door for global load balancing
- CDN integration for static content

This architecture provides enterprise-grade security while maintaining all functionality of your CCP4i2 research application.