# Build Script Working Directory Fix

## Issue
The `build-and-push.sh` script was trying to build Docker images from the wrong directory, causing the build to fail because it couldn't find the source code and Dockerfiles.

## Solution
Updated the script to:

1. **Dynamic Path Resolution**: Calculate the correct working directory relative to the script location
2. **Proper Directory Structure**: Navigate to `../../ccp4i2-django` from the bicep directory
3. **Environment File Handling**: Load `.env.deployment` from the bicep directory even when working from a different directory
4. **Error Checking**: Validate that the working directory exists before proceeding

## Directory Structure Expected:
```
ccp4i2-django-azure/
├── bicep/
│   ├── scripts/
│   │   └── build-and-push.sh
│   └── .env.deployment
└── ../ccp4i2-django/
    ├── server/
    ├── client/
    └── Docker/
        ├── Dockerfile.server
        └── Dockerfile.web
```

## Script Flow:
1. Set PATH for Azure CLI
2. Calculate working directory: `bicep/../../ccp4i2-django`
3. Validate directory exists
4. Change to working directory
5. Load environment variables from bicep directory
6. Build and push images using relative paths from ccp4i2-django

## Key Changes:
- **Working Directory**: Now correctly navigates to `../../ccp4i2-django`
- **Environment Loading**: Loads `.env.deployment` from bicep directory using absolute path
- **Image Tag Saving**: Saves image tag back to bicep directory
- **Error Handling**: Validates paths before proceeding

This ensures the Docker builds can find all source code and Dockerfiles in the correct location.