#!/bin/bash

# CCP4 Extraction Job Wrapper
# This script is a thin wrapper around run-maintenance-job.sh
# for CCP4 tar extraction and BINARY.setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMMAND="cd /mnt/ccp4data && tar -xf ccp4-9.0.011-shelx-arpwarp-linux64.tar.gz --checkpoint=1000 --checkpoint-action=echo='Extracted %u files...' && echo '✅ Extraction complete! Running BINARY.setup...' && cd /mnt/ccp4data/ccp4-9 && ./BINARY.setup && echo '✅ BINARY.setup complete!'"

exec "$SCRIPT_DIR/run-maintenance-job.sh" "$COMMAND" "CCP4 Extraction & Setup"
