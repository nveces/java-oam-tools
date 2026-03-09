#!/bin/bash
#
# ============================================================
#
#
# Created-------:
# ============================================================
# Description--: Common Functions
#
# ============================================================
#
# ============================================================
# Pre Steps---:
# chmod 774 *.sh
# ============================================================
#
#
#### LOG VERBOSITY
# 0 - NONE--: No registry any message
# 1 - ERROR-: Regitry only error messages
# 2 - WARN--: Registry only warn and error messages
# 3 - INFO--: Registry only warn, error and informative messages
# 4 - DEBUG-: Registry warn, error, informative, and debug messages
#
# EOH

# Default 3
LOG_LEVEL=3
SCREEN_ONLY=""

# colors
# Black       0;30     Dark Gray     1;30
# Blue        0;34     Light Blue    1;34
# Green       0;32     Light Green   1;32
# Cyan        0;36     Light Cyan    1;36
# Red         0;31     Light Red     1;31
# Purple      0;35     Light Purple  1;35
# Brown       0;33     Yellow        1;33
# Light Gray  0;37     White         1;37

black='\e[0;30m'
blue='\e[0;34m'
green='\e[0;32m'
cyan='\e[0;36m'
red='\e[0;31m'
brown='\e[0;33m'
lgray='\e[0;37m'
#
reset='\e[0m'
bold='\e[1m'
#
col_dbg='\e[0;34m'
col_msg='\e[0;32m'
col_warn='\e[0;33m'
col_err='\e[0;31m'
#
col_success='\033[1;32m'

LINE_PADDING=''
CHAR_CAPTION="."
LINE_PAD_LENGTH=30
for ((i=0; i<$LINE_PAD_LENGTH; i++)); do
    LINE_PADDING+=$CHAR_CAPTION
done
LINE_PADDING+=":"


function date_logf() {
    #date "+%a %d %b %Y %T"
    date "+[%F %T]"
}

function date_gc() {
    date "+%F"
}

function date_dump() {
    date "+%F_%H-%M-%S"
}

function date_dump_01() {
    date "+%Y%m%d_%H%M%S"
}

function _log(){
    if [ $LOG_LEVEL -gt $1 ]; then
        printf "%b%s %s: ${bold}%s${reset} %b%s${reset}\n" $5 "$(date_logf)" "$2" "$4"  $5 "$3"
    fi
}

function err() {
    _log 0 "[ERROR]" "$1" "✘" ${col_err}
}

function warn() {
    _log 1 "[WARN]" "$1" "⚠" ${col_warn}
}

function msg() {
    _log 2 "[INFO]" "$1" "[OK]" ${col_msg}
}

function dbg() {
    _log 3 "[DEBUG]" "$1" "[--]" ${col_dbg}
}

function ok_msg() {
    _log 2 "[SUCCESS]" "$1" "✔" ${col_success}
}

function parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}


function usage_info(){

  cat <<@EndOfUsage
Usage: $0 [OPTIONS]
    [ -e | --environment ] - Environment code. Examples: lab, dev, qua, int, pre, pro,
    [ -o | -operation ]    - Operation number associated to the CLI script

Examples:
    ${0} -e lab -o 10

@EndOfUsage

  if [ -n "$1" ]
  then
    err "$@"
    exit 1
  else
    exit 0
  fi
}

function usage_info_manage(){

  cat <<@EndOfUsage
Usage: $0 [OPTIONS]
    [ -i | --init ]   - Init: remove link & file
    [ -c | --create ] - Create: mv file & create link

Examples:
    ${0} -i
    ${0} -c

@EndOfUsage

  if [ -n "$1" ]
  then
    err "$@"
    exit 1
  else
    exit 0
  fi
}

# printf "%${padding_length}s" ""
# printf "%${padding_length}s" "."
# printf "%-${padding_length}s" ":"
function get_padding(){
    local char="$1"
    local max_length="$2"
    local current_length="$3"
    local padding_length=$((max_length - current_length))

    if [[ $padding_length -lt 1 ]]; then
        padding_length=1
    fi
    printf "%${padding_length}s" | tr ' ' "$char"
}

function msg_kv_padding() {
    local key="$1"
    local value="$2"
    local char="${3:-.}"
    local max_len="${4:-25}"
    local pad=$(get_padding "$char" $max_len ${#key})
    msg "${key} ${pad}: ${value}"
}

function check_tool() {
    local jhome=$1
    local tool=$2
    local tool_path="$jhome/bin/$tool"

    # Check if the tool exists in the system PATH
    if command -v "$tool" &> /dev/null; then
        local in_path="$(command -v "$tool")"
        local label="Tool '$tool' found in system PATH at:"
        msg "$(printf "%-39s%s" "$label" "$in_path")"
        #msg "Tool '$tool' found in system PATH at: $in_path"
    else
        msg "Tool '$tool' not found in system PATH."
    fi
    local pad=$(get_padding "." 7 ${#tool})
    # Check if the tool exists in the specified JAVA_HOME/bin directory
    if [[ -n "$jhome" ]] && [[ -x "$tool_path" ]];then
        msg "Tool '$tool' found at ${pad}: $tool_path"
        return 0
    else
        err "Tool '$tool' not found or not executable at ${pad}: $tool_path"
        return 1
    fi
}

function resolve_java_home() {
    local pid="$1"
    local user_home="$2"
    local discovered_home=""

    #
    if [[ -n "$user_home" ]]; then
        if [[ -d "$user_home" ]]; then
            if check_tool "$user_home" "java"; then
                msg "The provided JAVA_HOME is valid. Using: $user_home"
                FINAL_JAVA_HOME="$user_home"
                return 0
            else
                msg "WARN: The provided JAVA_HOME '$user_home' is not a valid JAVA_HOME."
            fi
        else
            msg "WARN: The provided JAVA_HOME '$user_home' is not a valid JAVA_HOME."
        fi
    fi

    # Auto-discover the JAVA_HOME from the running process
    if [[ -d "/proc/$pid" ]]; then
        local java_exe
        java_exe=$(readlink -f /proc/"$pid"/exe 2>/dev/null)
        if [[ -n "$java_exe" ]]; then
            discovered_home="${java_exe%/bin/java}"
            msg "Auto-discovered JAVA_HOME from process $pid: $discovered_home"
            FINAL_JAVA_HOME="$discovered_home"
            return 0
        fi
    fi

    # Fallback: Try to read from the process environment variables
    discovered_home=$(strings /proc/"$pid"/environ 2>/dev/null | grep "^JAVA_HOME=" | cut -d= -f2)
    if [[ -n "$discovered_home" ]]; then
        msg "Found JAVA_HOME in process environment: $discovered_home"
        FINAL_JAVA_HOME="$discovered_home"
        return 0
    fi

    return 1
}

function get_max_heap_mb() {
    local pid="$1"
    local max_bytes

    # Extract the value of MaxHeapSize using jcmd from the PID process.
    # This is more reliable than trying to parse the command line or environment variables,
    # as it reflects the actual runtime configuration of the JVM.

    max_bytes=$($JCMD "$pid" VM.flags 2>/dev/null | grep -oE "XX:MaxHeapSize=[0-9]+" | cut -d= -f2)

    if [[ -n "$max_bytes" ]]; then
        echo $(( max_bytes / 1024 / 1024 )) # Convert bytes to MB
    else
        echo "0" # Fallback if the value cannot be determined
    fi
}

FORCE="false"
# Confirm high-impact operation with the user (Level 3)
function confirm_impact() {
    local pid="$1"
    warn "!!! WARNING: HIGH IMPACT OPERATION !!!"
    warn "This script will freeze the JVM (PID $pid) while writing the dump to disk."

    # Estimated time based on Heap size (conceptual example)
    warn "Estimated Heap Size: $(get_max_heap_mb $pid) MB"

    if [[ "$FORCE" != "true" ]]; then
        read -p "Are you sure you want to proceed? [y/N]: " confirm
        [[ "$confirm" != "y" ]] && msg "Operation cancelled." && exit 0
    fi
}


function capture_gc_metrics() {
    #
    jstat -gc "$PID" | tail -1 | awk '{print $15, $16, $8, $13}'
}

#sleep "$interval"
#coproc read -t $interval && wait "$!" || true
function wait_seconds() {
    local sec="$1"
    msg "Waiting for ${sec} seconds..."
    # If you want to be purist and avoid the fork of sleep:
    read -t "$sec" <> <(:) || true
}

function get_jvm_uptime_seconds() {
    local pid="$1"
    #
    local val=$($JCMD "$pid" VM.uptime 2>/dev/null | sed '1d' | grep -oE "[0-9]+\.[0-9]+" | cut -d. -f1)
    echo "${val:-0}" # Si falla, devuelve 0 para evitar errores vacíos
}

#
# EOF