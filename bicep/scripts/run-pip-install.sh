#!/bin/bash

# CCP4 Extraction Job Wrapper
# This script is a thin wrapper around run-maintenance-job.sh
# for CCP4 tar extraction and BINARY.setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMMAND='mkdir -p /mnt/ccp4data/py-packages && . /mnt/ccp4data/ccp4-9/bin/ccp4.setup-sh && echo "📦 Installing all packages with CCP4 Python 3.9..." && /mnt/ccp4data/ccp4-9/bin/ccp4-python -m pip install --target /mnt/ccp4data/py-packages -r /usr/src/app/requirements.txt -r /usr/src/app/requirements-azure.txt 2>&1 | tee /mnt/ccp4data/pip-install.log && echo "✅ Package installation completed successfully"'

exec "$SCRIPT_DIR/run-maintenance-job.sh" "$COMMAND" "CCP4 Python Package Installation"
