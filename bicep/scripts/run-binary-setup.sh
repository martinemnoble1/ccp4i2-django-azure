#!/bin/bash

# CCP4 Binary Setup Job Wrapper
# This script is a thin wrapper around run-maintenance-job.sh
# for running CCP4 BINARY.setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMMAND="cd /mnt/ccp4data/ccp4-9 && ./BINARY.setup --run-from-script && echo '✅ BINARY.setup complete!'"

exec "$SCRIPT_DIR/run-maintenance-job.sh" "$COMMAND" "CCP4 Binary Setup"
