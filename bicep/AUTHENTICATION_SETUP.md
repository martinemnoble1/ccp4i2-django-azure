# Azure AD Authentication Configuration for CCP4i2 Container Apps

## Overview

Azure Container Apps Easy Auth provides a zero-code authentication solution that sits in front of your applications. Users will be redirected to Azure AD login before accessing your applications.

## Step 1: Create Azure AD App Registration

Since I don't have directory permissions, you'll need to create the app registration manually:

### 1.1 Create the App Registration
1. Go to **Azure Portal** → **Microsoft Entra ID** → **App registrations** → **New registration**
2. Configure:
   - **Name:** `CCP4i2 Container Apps Authentication`
   - **Supported account types:** `Accounts in this organizational directory only (Cancer Research UK only - Single tenant)`
   - **Redirect URIs:** Select "Web" and add both:
     ```
     https://ccp4i2-bicep-web.whitecliff-258bc831.northeurope.azurecontainerapps.io/.auth/login/aad/callback
     https://ccp4i2-bicep-server.whitecliff-258bc831.northeurope.azurecontainerapps.io/.auth/login/aad/callback
     ```
3. Click **Register**

### 1.2 Configure the App Registration
After creation, configure these settings:

#### Authentication Settings
1. Go to **Authentication** in the app registration
2. Under **Implicit grant and hybrid flows** → Enable "ID tokens"

#### Create Client Secret
1. Go to **Certificates & secrets**
2. Click **New client secret**
3. Add description: "CCP4i2 Container Apps"
4. Set expiration (recommended: 12 months)
5. Click **Add** and **copy the secret value immediately** (it won't be shown again)

#### API Permissions
1. Go to **API permissions**
2. Click **Add a permission** → **Microsoft Graph** → **Delegated permissions**
3. Add `User.Read` permission
4. Click **Grant admin consent for Cancer Research UK**

### 1.3 Record Important Values
Copy these values for the deployment:
- **Application (client) ID** (from Overview page)
- **Client secret value** (from the secret you just created)

## Step 2: Deploy Authentication Configuration

Run the setup script with your app registration details:

```bash
cd /Users/nmemn/Developer/ccp4i2-django-azure/bicep
./setup-authentication.sh "<CLIENT_ID>" "<CLIENT_SECRET>"
```

Example:
```bash
./setup-authentication.sh "12345678-1234-1234-1234-123456789012" "abc123def456ghi789"
```

## Step 3: Configure User Access Restrictions

### 3.1 Enable User Assignment Requirement
1. Go to **Azure Portal** → **Microsoft Entra ID** → **Enterprise applications**
2. Find **CCP4i2 Container Apps Authentication**
3. Go to **Properties**
4. Set **Assignment required?** to **Yes**
5. Click **Save**

### 3.2 Add Authorized Users/Groups
1. In the same Enterprise application, go to **Users and groups**
2. Click **Add user/group**
3. Select users or groups from your organization who should have access
4. Click **Assign**

### 3.3 Configure Additional Security (Optional)
1. **Conditional Access:** Set up conditional access policies for additional security
2. **MFA Requirements:** Enable multi-factor authentication requirements
3. **Device Compliance:** Require managed/compliant devices

## How It Works

1. **User accesses app** → Redirected to Azure AD login portal
2. **User authenticates** → Azure AD validates credentials
3. **User authorized** → Redirected back to app with authentication token
4. **App receives request** → With user information in HTTP headers

## User Experience

- First access: Users see Microsoft login page
- After authentication: Direct access to applications
- Session persistence: Users stay logged in (configurable)
- Logout: Available via `/.auth/logout` endpoint

## User Information Available to Applications

Your Django and Next.js applications will receive these HTTP headers:
- `X-MS-CLIENT-PRINCIPAL-NAME`: User's email
- `X-MS-CLIENT-PRINCIPAL-ID`: User's object ID
- `X-MS-TOKEN-AAD-ACCESS-TOKEN`: Access token (if needed)
- `X-MS-TOKEN-AAD-ID-TOKEN`: ID token with user claims

## Testing Authentication

After deployment, test by:
1. Opening your web app: `https://ccp4i2-bicep-web.whitecliff-258bc831.northeurope.azurecontainerapps.io`
2. You should be redirected to Microsoft login
3. After successful login, you should be redirected back to your app

## Troubleshooting

### Common Issues
1. **"AADSTS50011: No reply address"**
   - Check redirect URIs in app registration match exactly
   - Ensure URLs are HTTPS and include the `.auth/login/aad/callback` path

2. **"AADSTS700016: Application not found"**
   - Verify the Client ID is correct
   - Check the app registration exists in the correct tenant

3. **Users can't access app**
   - Verify user assignment requirement setting
   - Check users are assigned to the enterprise application

### Monitoring
- **Application Insights:** Authentication events and errors
- **Azure AD Sign-in logs:** User authentication attempts
- **Container Apps logs:** Application-level authentication issues

## Disabling Authentication

To disable authentication:
```bash
# Update applications.json
# Set "enableAuthentication": { "value": false }
./scripts/deploy-applications.sh
```

## Security Best Practices

1. **Regular secret rotation:** Update client secrets before expiration
2. **Principle of least privilege:** Only assign necessary users
3. **Conditional access:** Implement additional access policies
4. **Monitoring:** Set up alerts for authentication failures
5. **Review permissions:** Regularly audit user assignments