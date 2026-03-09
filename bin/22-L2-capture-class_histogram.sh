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

function tips(){
    msg "---------------------------------------------------------------------------"
    msg "--- Quick Interpretation Guide ---"
    msg " - High instances + Business class: Possible leak/bottleneck."
    msg " - [B = Byte Array (Payloads/Files), [C = Char Array (Strings/XML)."
    msg " - Primitive [B (Bytes) or [C (Chars): Large size = Big payloads or Buffers."
    msg " - High Bytes / Low Instances -> Huge individual objects (Big files/maps)."
    msg " - Millions of Instances -> Likely Object creation out of control."
    msg "---------------------------------------------------------------------------"

}

# Step 1: Set current DIR and default variables:
V_ADMIN_DIR=$(dirname $0)
source ${V_ADMIN_DIR}/_functions.sh
source ${V_ADMIN_DIR}/00-bootstrap.sh

FINAL_JAVA_HOME=""
# Default output directory
OUTDIR=~/HD
DEFAULT_OUTDIR=~/HD
OUTDIR=$DEFAULT_OUTDIR
PID=""
pidname=""
FORCE="false"

# Step 2 - Auto-discover the FINAL_JAVA_HOME, jcmd, jmap and jps tools and check other parameters
bootstrap_oam_jcmd "$@"

msg "--- [L2] Thread Dump Execution ---"
warn "Impact: MEDIUM. This might pause the JVM briefly for PID $PID (${pidname})."

# Step 4 - We create the output directory to heapdump.
# By default, it will be created in ~/HD, but if the user provides a different one, we will create it there.
mkdir -p ${OUTDIR}

# Step 5 - Create the Heap Dump
class_histogram="${OUTDIR}/${pidname}_$(date_dump_01)_${PID}.histo"
msg "Creating Class Histogram: '${class_histogram}'"
num_results=20
# Options
opt_all="-all=true" # [optional] Inspect all objects, including unreachable objects (BOOLEAN, false)
#opt_all=""
# [optional] Number of parallel threads to use for heap inspection. 0 (the default) means let the VM determine the number of threads to use.
# 1 means use one thread (disable parallelism).
# For any other value the VM will try to use the specified number of threads, but might use fewer. (INT, 0)
parallel="-parallel=0"
options="${opt_all} ${parallel} "
$JCMD $PID GC.class_histogram ${options} > "${class_histogram}"
if [ $? -eq 0 ]; then
  msg "--- Top $num_results Memory Consumers (by Bytes) ---"

  head_limit=$((num_results + 2))
  cat "${class_histogram}" | tail -n +2 | head -n ${head_limit}
  echo ""
  tips
else
  err "Failed to capture histogram."
fi

exit 0

# EOF