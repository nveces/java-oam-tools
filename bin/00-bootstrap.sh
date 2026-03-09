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

FINAL_JAVA_HOME=""
# Default output directory
OUTDIR=~/HD
PID=""
pidname=""
destdir=""

function bootstrap_oam_jcmd(){

# Step 2 - Parser Input Parameters
while [ $# -gt 0 ]
do
    case $1 in
        -p | --pname )  shift
                        pidname=$1
                        ;;
        -o | --out )    shift
                        destdir=$1
                        ;;
        -j | --javahome ) shift
                        javahome=$1
                        ;;
        -h | --help )   usage
                        exit
                        ;;
        * )             usage $1
                        exit 1
    esac
    shift
done

if [ -z "$pidname" ] ; then
    err "The <pid> is necessary for to continue."
    usage
    exit 1
fi

# Step 4 - Get java PID using ps -ef
PID=$(ps -ef | grep -i "${pidname}" | grep java | grep -v grep | awk '{print $2}' | head -n 1)

#PID=`${JPS} -l | grep "${pidname}" | awk '{print $1}' | head -n 1`
#PID=$(${JCMD} | grep -i "${pidname}" | awk '{print $1}' | head -n 1)

if [ -z ${PID} ]; then
  err "There is not a ${pidname} java process running in the system."
  exit 1
fi

msg "Process Java ID: '${PID}' for process name: '${pidname}'"

# Step 5 - Resolve JAVA_HOME, populate FINAL_JAVA_HOME variable.
resolve_java_home "$PID" "$javahome"
if [[ $? -ne 0 ]]; then
    err "Could not find a valid JAVA_HOME. Please check your process or -j | --javahome parameter."
    exit 1
fi

JCMD="$FINAL_JAVA_HOME/bin/jcmd"
JMAP="$FINAL_JAVA_HOME/bin/jmap"
JSTAT="$FINAL_JAVA_HOME/bin/jstat"
JSTACK="$FINAL_JAVA_HOME/bin/jstack"
JPS="$FINAL_JAVA_HOME/bin/jps"

msg "Using JAVA_HOME -: '${FINAL_JAVA_HOME}'"
msg "Using jcmd ------: '${JCMD}'"
msg "Using jmap ------: '${JMAP}'"
msg "Using jstat -----: '${JSTAT}'"
msg "Using jstack ----: '${JSTACK}'"
msg "Using jps -------: '${JPS}'"

# Step 6 - Check if jcmd tool is available in the resolved FINAL_JAVA_HOME
if ! check_tool "$FINAL_JAVA_HOME" "jcmd"; then
    err "Tool 'jcmd' not found or not executable at: ${JCMD}"
    exit 1
fi

if ! check_tool "$FINAL_JAVA_HOME" "jstat"; then
    err "Tool 'jstat' not found or not executable at: ${JSTAT}"
    exit 1
fi

if ! check_tool "$FINAL_JAVA_HOME" "jstack"; then
    err "Tool 'jstack' not found or not executable at: ${JSTACK}"
    exit 1
fi

# Step 7 - If is provided as parameter, we create the output directory.
if [ -n "$destdir" ] ; then
    OUTDIR="$destdir"
fi

}

# EOF