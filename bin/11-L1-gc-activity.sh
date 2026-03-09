#!/bin/bash
#
# ============================================================
#
#
#
# Created-------:
# ============================================================
# Description ---: GC Activity Monitoring Script
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


bootstrap_oam_jcmd "$@"

# 1. See GC activity using `jstat` command:
#read fgc fgct ygc ygct <<< $($JSTAT -gc "$PID" | tail -1 | awk '{print $15, $16, $1, $2}')
read fgc fgct ygc ygct <<< $($JSTAT -gc "$PID" | sed '1d' | awk '{print $15, $16, $1, $2}')

# 2. Get uptime of the process in seconds to estimate the FGC rate per hour
uptime_seconds=$($JCMD "$PID" VM.uptime | tail -1 | grep -oE "[0-9]+\.[0-9]+" | cut -d. -f1)

# 3. Calculate the estimated Full GC rate per hour
if [ "$uptime_seconds" -gt 0 ]; then
    # Full GC per hour (estimated)
    fgc_per_hour=$(echo "scale=2; ($fgc * 3600) / $uptime_seconds" | bc)
else
    fgc_per_hour=0
fi

msg "--- GC Health Report for PID $PID ($pidname) ---"
msg_kv_padding "Uptime" "${uptime_seconds}s ($((uptime_seconds / 3600))h $(( (uptime_seconds % 3600) / 60 ))m)" "-" "19"
msg_kv_padding "Young GC" "$ygc events (Total time: ${ygct}s)" "-" "19"
msg_kv_padding "Full GC" "$fgc events (Total time: ${fgct}s)" "-" "19"
msg_kv_padding "Estimated FGC Rate" "$fgc_per_hour per hour" "-" "19"

# 4. Alert Logic for Operations (Triage)
if [ "$fgc" -gt 0 ]; then
    # Average time per Full GC
    avg_fgc_time=$(echo "scale=2; $fgct / $fgc" | bc)
    msg "Average Full GC Duration: ${avg_fgc_time}s"

    if (( $(echo "$fgc_per_hour > 10" | bc -l) )); then
        msg "CRITICAL: High FGC rate detected! Check memory leak."
    elif (( $(echo "$fgc_per_hour > 2" | bc -l) )); then
        msg "WARNING: Moderate FGC activity. Monitor Old Gen."
    else
        msg "STATUS: FGC activity is within normal operational limits."
    fi
else
    msg "STATUS: Perfect. No Full GC events recorded yet."
fi

# EOF
