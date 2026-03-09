#!/bin/bash
#
# ============================================================
#
#
#
# Created-------:
# ============================================================
# Description ---: Memory Activity Script with Delta Analysis
#
# https://docs.oracle.com/en/java/javase/11/tools/jstat.html
# https://docs.oracle.com/en/java/javase/17/docs/specs/man/jstat.html
# https://docs.oracle.com/en/java/javase/21/docs/specs/man/jstat.html
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

DEFAULT_INTERVAL=5
interval="${interval:-$DEFAULT_INTERVAL}"
bootstrap_oam_jcmd "$@"

function capture_mem_usage() {
    # EU, OU, MU en KB
    local pid="$1"
    $JSTAT -gc "$pid" | tail -1 | awk '{print $6, $8, $10}'
}


msg "--- Monitoring Memory Pressure (Interval: ${interval}s) for PID $PID ---"

read eu1 ou1 mu1 <<< $(capture_mem_usage $PID)
wait_seconds "$interval"
read eu2 ou2 mu2 <<< $(capture_mem_usage $PID)

delta_eu_mb=$(echo "scale=2; ($eu2 - $eu1) / 1024" | bc)
delta_ou_mb=$(echo "scale=2; ($ou2 - $ou1) / 1024" | bc)
delta_mu_mb=$(echo "scale=2; ($mu2 - $mu1) / 1024" | bc)

msg "--- Memory Activity Delta Report for PID $PID ($pidname) ---"
LAB_W=25
msg_kv_padding "Interval" "${interval}s" "." $LAB_W
msg_kv_padding "Eden Space Growth" "${delta_eu_mb} MB" "." $LAB_W
msg_kv_padding "Old Gen Growth"    "${delta_ou_mb} MB" "." $LAB_W
msg_kv_padding "Metaspace Growth"  "${delta_mu_mb} MB" "." $LAB_W

msg "--- Diagnostic Verdict ---"
if (( $(echo "$delta_mu_mb > 1" | bc -l) )); then
    warn "Metaspace is growing (+${delta_mu_mb}MB). Potential ClassLoader leak."
fi

# For Old Gen
if (( $(echo "$delta_ou_mb > 10" | bc -l) )); then
    err "Significant Old Gen growth (+${delta_ou_mb}MB) in ${interval}s."
    msg "   [Action]: If this repeats without Full GC recovery, run 21-L2-class-histogram.sh"
elif (( $(echo "$delta_ou_mb < 0" | bc -l) )); then
    ok_msg "Old Gen decreased (${delta_ou_mb#-} MB). Good recovery."
else
    ok_msg "Old Gen is stable."
fi

# Snapshot of Metaspace
# Metaspace:
# Class space: pointers to class metadata (Klass pointers, -XX:+UseCompressedClassPointers)
# Non-Clas Space: for non-class metadata
# Both: Class space + Non-Class space
# --
# Virtual Space (Reserved/Committed)
msg "--- Metaspace Details (Current) ---"
usage_line=$($JCMD "$PID" VM.metaspace | grep "^Total Usage -")
m_loaders=$(echo "$usage_line" | sed -n 's/.*- \([0-9]*\) loaders.*/\1/p')
m_classes=$(echo "$usage_line" | sed -n 's/.*, \([0-9]*\) classes.*/\1/p')
m_shared=$(echo "$usage_line" | sed -n 's/.*(\([0-9]*\) shared).*/\1/p')

# Reporting with padding
msg_kv_padding "Active ClassLoaders"  "${m_loaders:-0}" "." 30
msg_kv_padding "Total Classes Loaded" "${m_classes:-0}" "." 30
msg_kv_padding "Shared Classes (CDS)" "${m_shared:-0}"  "." 30

# Waste in Metaspace (Internal fragmentation, unused reserved space, etc.)
# It must be very low, ideally <5% of the total committed metaspace. If it's high, it can indicate inefficient memory usage or fragmentation in the Metaspace.
m_waste_raw=$($JCMD "$PID" VM.metaspace | grep "\-total-:")
if [[ -n "$m_waste_raw" ]]; then
    # Extract what is after the ':' and remove leading spaces
    # The result will be something like: "831.48 KB ( <1%)"
    #msg_kv_padding "Waste Raw" "$m_waste_raw" "." 30
    m_waste_clean=$(echo $m_waste_raw | cut -d':' -f2)
    m_waste_clean=$(echo ${m_waste_clean#*:})
    msg_kv_padding "Internal Waste" "$m_waste_clean" "." 30
else
    warn "Could not find '-total-' line for Waste metrics."
fi

# Is the -XX:MaxMetaspaceSize parameter low?
# If the Metaspace is growing and close to the MaxMetaspaceSize, it can lead to OutOfMemoryError: Metaspace.
# Now We report the Virtual space (Reserved/Committed) to see if we are close to the limit.
msg "--- Metaspace Virtual Space ---"
m_virtual_space=$($JCMD "$PID" VM.metaspace | grep -A 3 "Virtual space" | tail -n 3) # Get the 3 lines after "Virtual space"

if [[ -n "$m_virtual_space" ]]; then

  while read -r line; do
    key=$(echo "$line" | cut -d':' -f1 | xargs) # Get the part before ':' and trim spaces
    value=$(echo "$line" | cut -d':' -f2 | xargs) # Get the part after ':' and trim spaces
    value_clean=$(echo "$value" | sed 's/,[[:space:]]*[0-9]* nodes.*//') # Remove the ", 0 nodes" part if it exists
    msg_kv_padding "$key" "$value_clean" "." 30

  done < <(echo "${m_virtual_space}" )

else
    warn "Could not find 'Virtual space' line in VM.metaspace output."
fi


exit 0

# EOF
