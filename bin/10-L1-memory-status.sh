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

# Step 2: Report OS Memory
mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
mem_free=$(grep MemFree /proc/meminfo | awk '{print $2}')
mem_avail=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
mem_cached=$(grep Cached /proc/meminfo | awk '{print $2}')
shared=$(grep Shmem /proc/meminfo | awk '{print $2}')
swap_cached=$(grep SwapCached /proc/meminfo | awk '{print $2}')
swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
swap_free=$(grep SwapFree /proc/meminfo | awk '{print $2}')

# Calculate MB
total_mb=$(( mem_total / 1024 ))
avail_mb=$(( mem_avail / 1024 ))
free_mb=$(( mem_free / 1024 ))
swap_total_mb=$(( swap_total / 1024 ))
swap_used_mb=$(( (swap_total - swap_free) / 1024 ))

msg "--- [Section 1] Global OS Memory Status ---"
msg_kv_padding "Physical RAM Total" "$total_mb MB" "." 30
msg_kv_padding "RAM Available" "$avail_mb MB" "." 30
msg_kv_padding "RAM Free" "$free_mb MB" "." 30
msg_kv_padding "System Cache/Buffer" "$(( ($(grep -E '^(Buffers|Cached|SReclaimable)' /proc/meminfo | awk '{sum+=$2} END {print sum}')) / 1024 )) MB" "." 30
msg_kv_padding "Swap Total" "$swap_total_mb MB" "." 30
msg_kv_padding "Swap in Use" "$swap_used_mb MB" "." 30

if [ "$swap_used_mb" -gt 100 ]; then
    warn "Swap activity detected! This will degrade JVM performance."
fi

# Step 3: Process Memory Representation
msg "--- [Section 2] Process Memory Representation ($PID) ---"
# Report RSS % and Swap % for the process
m1_rss_kb=$(grep VmRSS /proc/$PID/status | awk '{print $2}')
m1_swap_kb=$(grep VmSwap /proc/$PID/status | awk '{print $2}')
if [[ -n "$m1_rss_kb" ]]; then
    m1_rss_mb=$(( m1_rss_kb / 1024 ))
    m1_swap_mb=$(( m1_swap_kb / 1024 ))
    msg_kv_padding "M1 Process RSS" "$m1_rss_mb MB" "." 30
    msg_kv_padding "M1 Process Swap using /proc" "$m1_swap_mb MB" "." 30
else
    warn "Could not retrieve RSS or Swap info for PID $PID from /proc."
fi

m2_info=$(ps -o rss=,pmem= -p "$PID")
m2_rss_kb=$(echo "$m2_info" | awk '{print $1}')
m2_pmem=$(echo "$m2_info" | awk '{print $2}')
m2_rss_mb=$(( m2_rss_kb / 1024 ))
msg_kv_padding "M2 RSS (Physical RAM)" "$m2_rss_mb MB" "." 30
msg_kv_padding "M2 System RAM Usage" "$m2_pmem %" "." 30

if [[ -n "$m1_rss_kb" && -n "$m2_rss_kb" ]]; then
    diff=$(( m1_rss_kb - m2_rss_kb ))
    if [ ${diff#-} -gt 1024 ]; then
        warn "Minor discrepancy detected between /proc and ps sources."
    fi
fi

msg "--- [Section 2.1] JVM Internal Perspective (jcmd) ---"
jcmd_output=$($JCMD "$PID" GC.heap_info 2>/dev/null)
meta_line=$(echo "$jcmd_output" | grep "Metaspace")
m_used=$(echo "$meta_line" | awk '{print $3}')
m_com=$(echo "$meta_line" | awk '{print $7}')

# Extrat the Heap total (Sum of generations)
heap_total_kb=$(echo "$jcmd_output" | grep -E "Eden|Old|space" | awk '{sum+=$3} END {print sum}')
msg_kv_padding "  JVM Reported Heap Used" "$((heap_total_kb / 1024)) MB" "." 30
msg_kv_padding "  JVM Metaspace Committed" "$(( ${m_com//[^0-9]/} / 1024 )) MB" "." 30

msg "--- [Section 3] Global Java Footprint (All instances) ---"
java_metrics=$(ps -C java -o rss=,pmem= 2>/dev/null)

total_metrics=$(echo "$java_metrics" | awk '{rss+=$1; pmem+=$2} END {print rss, pmem}')
all_java_rss_kb=$(echo "$total_metrics" | awk '{print $1}')
all_java_pmem=$(echo "$total_metrics" | awk '{print $2}')
all_java_rss_mb=$(( all_java_rss_kb / 1024 ))

if [ "$all_java_rss_mb" -gt 0 ]; then
    percentage=$(( (m2_rss_mb * 100) / all_java_rss_mb ))
else
    percentage=0
fi

msg_kv_padding "Total Java Processes" "$(ps -C java --no-headers | wc -l)" "." 30
msg_kv_padding "Cumulative Java RSS" "$all_java_rss_mb MB" "." 30
msg_kv_padding "Our PID Relative Weight" "$percentage % of all Java" "." 30

if [ "$all_java_rss_mb" -gt $(( m1_total_mb * 80 / 100 )) ]; then
    warn "Java processes are consuming >80% of total system RAM."
fi

all_java_rss_kb=0
all_java_swp_kb=0
java_count=0
java_pids=$(pgrep -x java)
#
if [[ -n "$java_pids" ]]; then
    while read -r p_pid; do
        # 1. Sum RSS from /proc/pid/status (more reliable than ps output for memory metrics)
        p_rss=$(grep VmRSS "/proc/$p_pid/status" 2>/dev/null | awk '{print $2}')
        # 2. Sum Swap from /proc/pid/status
        p_swp=$(grep VmSwap "/proc/$p_pid/status" 2>/dev/null | awk '{print $2}')
        all_java_rss_kb=$(( all_java_rss_kb + ${p_rss:-0} ))
        all_java_swp_kb=$(( all_java_swp_kb + ${p_swp:-0} ))
        ((java_count++))
    done <<< "$java_pids"
else
    warn "No java processes found running in the system."
fi

# Convert to MB
all_java_rss_mb=$(( all_java_rss_kb / 1024 ))
all_java_swp_mb=$(( all_java_swp_kb / 1024 ))

msg "--- [Section 3.1] Total Java Porcesses ---"
# Reporting
msg_kv_padding "Total Java Processes" "$java_count" "." 30
msg_kv_padding "Cumulative Java RSS" "$all_java_rss_mb MB" "." 30
msg_kv_padding "Cumulative Java Swap" "$all_java_swp_mb MB" "." 30

# Cálculo de peso relativo de nuestro PID ($rss_mb de la Sección 2)
if [ "$all_java_rss_mb" -gt 0 ]; then
    percentage=$(( (m1_rss_mb * 100) / all_java_rss_mb ))
    msg_kv_padding "Our PID Relative Weight" "$percentage % of all Java" "." 30
fi


# EOF
