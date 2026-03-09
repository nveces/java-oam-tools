#!/bin/bash
#
# ============================================================
#
#
#
# Created-------:
# ============================================================
# Description ---:
#
# ============================================================
#
# ============================================================
# Pre Steps---:
# chmod 774 *.sh
# ============================================================
#
#
# EOH

#set -euo pipefail
set -o pipefail

# Step 1: Set current DIR and default variables:
V_ADMIN_DIR=$(dirname $0)
source ${V_ADMIN_DIR}/_functions.sh
source ${V_ADMIN_DIR}/00-bootstrap.sh


function usage(){
    echo "Usage: $0"
    echo "Ex: $0"
    exit 1
}

DEFAULT_DUMP_FILE="/home/aarjona/HD/quark_20260309_191502_255170.hprof"
#DUMP_FILE="$1"
DUMP_FILE=${DEFAULT_DUMP_FILE}
MAT_PATH="${MAT_PATH:-/nvme1n1p1/devspace/mat/mat-1.16.1.20250109/ParseHeapDump.sh}"

msg "--- [Section 50-L3] MAT Automated Analysis ---"

# 1. Check hprof file
if [[ -z "$DUMP_FILE" ]]; then
    err "Usage: $0 <path_to_heap_dump.hprof>"
    exit 1
fi

if [[ ! -f "$DUMP_FILE" ]]; then
    err "File not found: $DUMP_FILE"
    exit 1
fi

# 2.
if [[ ! -x "$MAT_PATH" ]]; then
    err "Eclipse MAT executable not found or not executable at: $MAT_PATH"
    msg "Please go to Settings to verify MAT installation."
    exit 1
fi


msg "Starting MAT Analysis for: $(basename "$DUMP_FILE")"
msg "This may take several minutes depending on the dump size..."

options="org.eclipse.mat.api:suspects"

# Ejecutamos el reporte de Leak Suspects (el más valioso para OAM)
"$MAT_PATH" "$DUMP_FILE" $options -vmargs -Xmx4g

if [ $? -eq 0 ]; then
    ok_msg "Analysis complete."
    # MAT genera un archivo ZIP con el reporte HTML
    report_zip="${DUMP_FILE%.*}_Leak_Suspects.zip"
    msg "Report generated: $report_zip"
    msg "Transfer this ZIP to your workstation to view the HTML report."
else
    err "MAT Analysis failed."
fi


# EOF
