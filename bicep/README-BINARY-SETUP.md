# CCP4 BINARY.setup Container Job

## Overview
This script creates a specialized Azure Container Apps job that focuses solely on executing the `BINARY.setup` command for CCP4, assuming the CCP4 files have already been extracted to the Azure File Share.

## Prerequisites
- CCP4 tar.gz file must already be extracted in the Azure File Share
- Azure Container Apps environment must be set up
- Container registry with the CCP4i2 server image must be available
- `.env.deployment` file must exist with required environment variables

## Usage

### 1. Create and Start the Job
```bash
# Navigate to the scripts directory
cd bicep/scripts

# Create the BINARY.setup job
./setup-ccp4-binary-only.sh

# Start the job execution
az containerapp job start --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP
```

### 2. Monitor Execution
```bash
# View job execution status
az containerapp job execution list --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP --output table

# Follow real-time logs
az containerapp job logs show --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP --follow

# View completed execution logs
az containerapp job logs show --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP
```

### 3. Clean Up
```bash
# Delete the job after completion
az containerapp job delete --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP --yes
```

## What the Job Does

1. **Environment Setup**: Sets up the container environment and verifies Azure File Share mount
2. **Storage Mount Verification**: Automatically checks and creates the `ccp4data-mount` if missing
3. **Directory Location**: Automatically finds the extracted CCP4 directory (supports multiple naming conventions)
4. **BINARY.setup Execution**: Runs the BINARY.setup script with multiple fallback execution methods using the proper non-interactive approach:
   - `source ./BINARY.setup --run-from-script` (preferred non-interactive method)
   - `bash ./BINARY.setup --run-from-script` (fallback 1 with --run-from-script)
   - `sh ./BINARY.setup --run-from-script` (fallback 2 with --run-from-script)
   - `./BINARY.setup --run-from-script` (direct execution)
   - Legacy license acceptance methods (fallback for older versions)
5. **Comprehensive Logging**: Provides detailed output and error diagnostics
6. **Error Handling**: Captures exit codes and provides troubleshooting information

## Key Features

- **Automatic Storage Mount Setup**: Checks and creates the Azure File Share mount if missing
- **Focused Execution**: Only runs the BINARY.setup step, not the entire extraction process
- **Proper Non-Interactive Execution**: Uses the official `--run-from-script` flag for automated execution
- **Multiple Execution Methods**: Tries different ways to execute the setup script
- **Automatic License Acceptance**: Falls back to legacy license handling if needed
- **Detailed Diagnostics**: Comprehensive logging and error reporting
- **Environment Variables**: Sets appropriate CCP4 environment variables
- **File System Checks**: Verifies directory structure and file permissions
- **Resource Optimization**: Uses 1 CPU and 2GB memory (less than full setup job)
- **Mount Verification**: Validates storage mount before proceeding

## Non-Interactive Execution

The script uses the proper CCP4 approach for automated execution:
- **Primary method**: `--run-from-script` flag for non-interactive execution
- **Script detection**: Automatically checks if the flag is supported
- **Fallback methods**: Legacy license acceptance for older CCP4 versions
- **Multiple execution approaches**: source, bash, sh, and direct execution

⚠️ **Note**: The `--run-from-script` flag is the official CCP4 method for automated installations. If your CCP4 version doesn't support this flag, the script will fall back to automatic license acceptance methods.

## Troubleshooting

### Common Issues

1. **CCP4 Directory Not Found**
   - Ensure the CCP4 tar.gz has been fully extracted
   - Check the Azure File Share contents
   - Verify the extraction completed successfully

2. **BINARY.setup Not Found**
   - The script will list available setup-related files
   - Check if the extraction was complete
   - Verify file permissions

3. **License Acceptance Issues**
   - The script tries multiple methods to accept the license automatically
   - Check logs for specific license-related errors
   - Ensure you have appropriate CCP4 licensing

4. **Permission Issues**
   - The script automatically makes BINARY.setup executable
   - Check Azure File Share mount permissions

5. **Environment Issues**
   - The script sets CCP4_INSTALL_DIR and CCP4_MASTER variables
   - Check available disk space
   - Verify container environment

### Log Analysis
The job provides structured logging with these sections:
- Environment check
- Directory discovery
- File verification
- License handling attempts
- Execution attempts
- Post-setup verification
- Error diagnostics

## Resource Requirements
- CPU: 1.0 core
- Memory: 2.0 GB
- Timeout: 1 hour (3600 seconds)
- Retry Limit: 2 attempts

## Files Created
- Container Apps Job: `ccp4-binary-setup-job`
- Temporary files: `/tmp/ccp4-binary-setup-job.yaml` (cleaned up automatically)
- Log output: `/tmp/binary_setup_output.log` (within container)
- License response file: `/tmp/license_responses.txt` (temporary, within container)
