#!/bin/bash
#
# ============================================================
#
#
#
# Created-------:
# ============================================================
# Description ---: CodeCache Activity Script, Healthy JIT
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

function codeCacheInfo(){
    local codecache_raw=$1
    # Get the size and used values in KB using regex and text processing
    c_size=$(echo "$codecache_raw" | sed -n 's/.*size=\([0-9]*\)Kb.*/\1/p')
    c_used=$(echo "$codecache_raw" | sed -n 's/.*used=\([0-9]*\)Kb.*/\1/p')
    c_free=$(echo "$codecache_raw" | sed -n 's/.*free=\([0-9]*\)Kb.*/\1/p')

    # Check if we successfully parsed the values
    if [[ -z "$c_size" || -z "$c_used" ]]; then
        err "Failed to parse Code Cache metrics. Check jcmd output format."
        exit 1
    fi

    # Calculate usage percentage (Simple Bash arithmetic)
    percent_used=$(( (c_used * 100) / c_size ))

    # Report visual aligned
    LABEL_W=25
    msg_kv_padding "Total Capacity" "$((c_size / 1024)) MB" "." $LABEL_W
    msg_kv_padding "Used" "$((c_used / 1024)) MB" "." $LABEL_W
    msg_kv_padding "Free" "$((c_free / 1024)) MB" "." $LABEL_W
    msg_kv_padding "Usage Percentage" "${percent_used}%" "." $LABEL_W

    # --- Analsys for OAM Operations ---
    if [ "$percent_used" -gt 90 ]; then
        err "CRITICAL: Code Cache is almost full (>90%)!"
        msg "   [Insight]: JIT compilation might stop. Performance will degrade drastically."
        msg "   [Action]: Recommend increasing -XX:ReservedCodeCacheSize"
    elif [ "$percent_used" -gt 75 ]; then
        warn "Warning: Code Cache usage is high (${percent_used}%)."
        msg "   [Action]: Monitor if this grows after new bundle deployments."
    else
        ok_msg "Code Cache health is good (${percent_used}%)."
    fi
}

DEFAULT_INTERVAL=5
interval="${interval:-$DEFAULT_INTERVAL}"
bootstrap_oam_jcmd "$@"

msg "--- Code Cache Status (L1 Analysis) ---"
# jcmd Compiler.codecache returns a structured, and we capture the CodeCache line:
# CodeCache: size=245760Kb, used=25181Kb, max_used=26916Kb, free=220577Kb
CODE_RAW=$($JCMD "$PID" Compiler.codecache 2>/dev/null | sed '1d' | grep "CodeCache")

if [[ -z "$CODE_RAW" ]]; then
    warn "Compiler.codecache command not supported or failed for PID $PID."
    CODE_RAW=$($JCMD "$PID" VM.info 2>/dev/null  | grep "CodeCache")
fi

if [[ -n "$CODE_RAW" ]]; then
    codeCacheInfo "$CODE_RAW"
else
    err "Could not retrieve Code Cache metrics for PID $PID."
fi


exit 0

# EOF
