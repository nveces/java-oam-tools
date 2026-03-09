#!/bin/bash
#
# ============================================================
#
#
#
# Created-------:
# ============================================================
# Description ---: GC Activity Monitoring Script with Delta Analysis
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

msg "--- Starting Delta Monitor (Interval: ${interval}s) for PID $PID ---"

# fgc1 : Full GC count at T1
# fgct1: Full GC time at T1
# ou1  : Old Gen Used at T1
read fgc1 fgct1 ou1 <<< $(capture_gc_metrics)

msg "Wait... capturing second sample in ${interval} seconds..."
wait_seconds "$interval"

read fgc2 fgct2 ou2 <<< $(capture_gc_metrics)

delta_fgc=$(( fgc2 - fgc1 ))
delta_fgct=$(echo "scale=3; $fgct2 - $fgct1" | bc)
delta_ou_kb=$(echo "$ou2 - $ou1" | bc)
delta_ou_mb=$(echo "scale=2; $delta_ou_kb / 1024" | bc)

msg "--- GC Activity Delta Report for PID $PID ($pidname) ---"
msg_kv_padding "Interval" "${interval}s" "." 30
msg_kv_padding "Full GC Events" "$delta_fgc" "." 30
msg_kv_padding "Full GC Time"   "${delta_fgct}s" "." 30
msg_kv_padding "Old Gen Growth" "${delta_ou_mb} MB" "." 30
uptime_raw=$(get_jvm_uptime_seconds "$PID")
uptime_h=$(( uptime_raw / 3600 ))
uptime_m=$(( (uptime_raw % 3600) / 60 ))
total_fgc_history=$fgc2
total_fgc_time=$fgct2
msg_kv_padding "JVM Uptime"       "${uptime_h}h ${uptime_m}m" "." 30
msg_kv_padding "Total FGC Events" "$total_fgc_history" "." 30
msg_kv_padding "Total FGC Time"   "${total_fgc_time}s" "." 30


if [ "$delta_fgc" -gt 0 ]; then
    warn "Activity detected in Old Gen. Memory is not being fully released. There is pressure in the Old Gen and it is likely that a Full GC was triggered during the interval."
elif (( $(echo "$delta_ou_mb > 0" | bc -l) )); then
    msg "STATUS: Memory is increasing (+${delta_ou_mb} MB) but no Full GC triggered yet."
else
    ok_msg "Memory Recovered: ${delta_ou_mb#-} MB released from Old Gen."
    msg "STATUS: Stable. No significant growth in Old Gen."
fi

if [ "$delta_fgc" -eq 0 ] && (( $(echo "$delta_ou_mb == 0" | bc -l) )); then
    # Stable: No Full GC events and no growth in Old Gen
    ok_msg "Stable: No memory growth or GC pauses in the last ${interval}s."
elif (( $(echo "$delta_ou_mb > 0" | bc -l) )); then
    # Trending Up: Memory is growing but no Full GC events yet
    warn "Memory Growing: +${delta_ou_mb} MB. Monitor if this trend continues."
fi

# This is a simple heuristic to give an overall health score based on the observed GC activity and memory growth during the interval of 60sec.
# It can be further refined with more complex logic or additional metrics.
if [ "$delta_fgc" -eq 0 ]; then
    ok_msg "Health Score: 100% - No Full GC interruptions."
elif [ "$delta_fgc" -le 1 ]; then
    ok_msg "Health Score: 90% - Single Full GC (Normal maintenance)."

elif [ "$delta_fgc" -le 3 ]; then
    warn "Health Score: 60% - Multiple Full GCs detected ($delta_fgc)."
    msg "[Action Required]: High memory pressure. Run Class Histogram (L2)."
else
    err "Health Score: 20% - CRITICAL: $delta_fgc Full GCs in ${interval}s!"
    #
    if [ "$uptime_h" -gt 0 ]; then
        fgc_avg_hour=$(echo "scale=1; $total_fgc_history / $uptime_h" | bc)
        msg_kv_padding "  Historical Average" "${fgc_avg_hour} FGC/hour" "." 30
    fi
    if [ "$uptime_raw" -lt 3600 ]; then
        msg "   [Diagnosis]: Early Life Stress. Check -Xmx (Likely Heap too small for load)."
    else
        msg "   [Diagnosis]: Potential Memory Leak or Peak Load. Inspect your application: '${pidname}'."
    fi
fi


exit 0

# EOF
