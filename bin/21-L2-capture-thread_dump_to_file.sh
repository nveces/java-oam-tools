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
DEFAULT_OUTDIR=~/TD
OUTDIR=$DEFAULT_OUTDIR
PID=""
pidname=""
FORCE="false"

# Step 2 - Auto-discover the FINAL_JAVA_HOME, jcmd, jmap and jps tools and check other parameters
bootstrap_oam_jcmd "$@"

msg "--- [L2] Thread Dump Execution ---"
warn "Impact: MEDIUM. This might pause the JVM briefly for PID $PID (${pidname})."

# Step 4 - We create the output directory to threaddump.
# By default, it will be created in ~/TD, but if the user provides a different one, we will create it there.
mkdir -p ${OUTDIR}

# Step 5 - Create the Thread Dump
thread_dump="${OUTDIR}/${pidname}_$(date_dump_01)_${PID}.tdump"
msg "Creating Thread Dump: '${thread_dump}'"
#overwrite="-overwrite" # [optional] May overwrite existing file (BOOLEAN, false)
format="-format=json" # [optional] Output format ("plain" or "json") (STRING, plain)
overwrite=""
#format="" # plain
options="${overwrite} ${format}"


$JCMD $PID Thread.dump_to_file ${options} "${thread_dump}"

exit 0

# EOF