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

function usage(){
  cat <<@EndOfUsage
Usage: $0 [OPTIONS]
    [ -p | --pname ] - Name of the Java process to capture the heap dump from (e.g., 'quarkus')
    [ -o | --out ]   - Output directory for the heap dump file (default: ~/HD)
    [ -h | --help ]  - Show this help message and exit

Examples:
    ${0} -output /path/to/output
    ${0} -p quarkus
@EndOfUsage

 if [ -n "$1" ]
  then
    err "$@"
    exit 1
  else
    exit 0
  fi
}

# Step 1: Set current DIR and default variables:
V_ADMIN_DIR=$(dirname $0)
source ${V_ADMIN_DIR}/_functions.sh
source ${V_ADMIN_DIR}/00-bootstrap.sh

FINAL_JAVA_HOME=""
# Default output directory
DEFAULT_OUTDIR=~/HD
OUTDIR=$DEFAULT_OUTDIR
PID=""
pidname=""
FORCE="false"

# Step 2 - Auto-discover the FINAL_JAVA_HOME, jcmd, jmap and jps tools and check other parameters
bootstrap_oam_jcmd "$@"
# Step 3 - Confirm impact of the order to be executed
confirm_impact "$PID"
# Step 4 - We create the output directory to heapdump.
# By default, it will be created in ~/HD, but if the user provides a different one, we will create it there.
mkdir -p ${OUTDIR}

# Step 5 - Create the Heap Dump
heap_dump="${OUTDIR}/${pidname}_$(date_dump_01)_${PID}.hprof"
msg "Creating Heap Dump: '${heap_dump}'"
# -gz=1 Compress the heap dump file using gzip. The resulting file will have a .hprof.gz extension.
#  the heap dump is written in gzipped format using the given compression level
# -all: Si es false, solo vuelca objetos vivos (hace un GC previo). Si es true, vuelca todo.
# Without compression:
compression=""
# With compression:
#compression="-gz=1"

# Get space available in KB in the output directory
avail_kb=$(df -Pk "${OUTDIR}" | tail -1 | awk '{print $4}')
# We estimate that we need at least the same RSS size of process
rss_kb=$(ps -o rss= -p "$PID")
padding_kb=$(( 1024 * 1024 )) # 1024MB of extra margin for safety

if [ "$avail_kb" -lt "$((rss_kb + padding_kb))" ]; then
    err "CRITICAL: Not enough disk space in ${OUTDIR}."
    err "Required: ~$(( (rss_kb + padding_kb) / 1024 )) MB | Available: $((avail_kb / 1024)) MB"
    exit 1
fi

$JCMD $PID GC.heap_dump ${compression} "${heap_dump}"


exit 0

# EOF