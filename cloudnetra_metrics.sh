#!/bin/bash
#######################################################
# Program: CloudNetra Metrics Agent Installation.
#######################################################
 
SCRIPTNAME=$(basename "$0")
 
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'
 
# Log
LOGDIR="/var/log/cn_metrics/"
LOGFILE="$LOGDIR/$SCRIPTNAME.log"
 
mkdir -p "$LOGDIR"
touch "$LOGFILE"
 
log_message() {
  local color="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local formatted_message="[$timestamp] : $message"
 
  echo -e "${color}${formatted_message}${RESET}"
  echo "$formatted_message" >> "$LOGFILE"
}
 
ENV="main"
 
check_required_tools() {
  local tools=(curl wget cut tar gzip sudo bc netstat)
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      log_message "$RED" "Error: Required tool $tool is not installed."
      exit 1
    fi
  done
}
 
set_environment() {
  case "$ENV" in
    dev) API_URL="https://dev-app.cloudnetra.io" ;;
    main) API_URL="https://app.cloudnetra.io" ;;
    local) API_URL="http://localhost:3004" ;;
    *)
      log_message "$RED" "Invalid environment"
      exit 1
      ;;
  esac
}
 
check_os_architecture() {
  case "$(uname)" in
    Linux) OS="linux" ;;
    Darwin) OS="darwin" ;;
    *)
      log_message "$RED" "Unsupported OS"
      exit 1
      ;;
  esac
 
  case "$(uname -m)" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l|armv6l) ARCH="armv7" ;;
    *)
      log_message "$RED" "Unsupported architecture"
      exit 1
      ;;
  esac
}
 
generate_agent_script_url() {
    local action="$1"
    local monitor_type="$2"
    local env="$3"
    local file_name="${ARCH}.sh"
 
    # ✅ FIX: support linux_v1, linux1, etc.
    if [[ "$action" == "install" && "$monitor_type" == linux* ]]; then
        if [[ "$monitor_type" =~ ^linux_?v?([0-9]+)$ ]]; then
            version="${BASH_REMATCH[1]}"
        else
            version="0"
        fi
        file_name="${ARCH}V${version}.sh"
    fi
 
    if [[ "$action" == "uninstall" ]]; then
        file_name="${ARCH}.sh"
    fi
 
    if [[ "$action" == "install" ]]; then
        url="https://github.com/groots-software-technologies/cn_metrics_remote_agent/raw/refs/heads/${env}/${OS}…
    elif [[ "$action" == "uninstall" ]]; then
        url="https://github.com/groots-software-technologies/cn_metrics_remote_agent/raw/refs/heads/${env}/${OS}…
    else
        log_message "$RED" "Invalid action"
        exit 1
    fi
 
    echo "$url"
}
 
download_and_execute_agent_script() {
    local action="$1"
    local monitor_type="$2"
    local digital_key="$3"
    local env="$4"
 
    local environment="$env"
    [ "$env" == "main" ] && environment="prod"
 
    local script_url
    script_url=$(generate_agent_script_url "$action" "$monitor_type" "$env")
 
    log_message "$BLUE" "Downloading: $script_url"
 
    curl -fLO "$script_url"
    if [ $? -ne 0 ]; then
        log_message "$RED" "Download failed (Invalid URL or file not found)"
        exit 1
    fi
 
    local file="${script_url##*/}"
 
    if [ ! -f "$file" ]; then
        log_message "$RED" "File not downloaded"
        exit 1
    fi
 
    chmod +x "$file"
 
    if [[ "$action" == "install" ]]; then
        ./"$file" -k "$digital_key" -e "$environment"
    else
        ./"$file"
    fi
 
    rm -f "$file"
    log_message "$GREEN" "Execution completed"
}
 
main() {
 
    if [[ "$1" == "--help" || "$#" -lt 4 ]]; then
        echo "Usage: $SCRIPTNAME -m [monitor_type] -a [install/uninstall] -k [DIGITAL_KEY] -e [env]"
        exit 0
    fi
 
    # ✅ FIX: missing done added
    while getopts "m:a:k:e:" OPT; do
        case $OPT in
            m) MONITOR_TYPE="$OPTARG" ;;
            a) ACTION="$OPTARG" ;;
            k) DIGITAL_KEY="$OPTARG" ;;
            e) ENV="$OPTARG" ;;
            *) exit 1 ;;
        esac
    done
 
    [ -z "$ENV" ] && ENV="main"
 
    set_environment
 
    if [[ -z "$MONITOR_TYPE" || -z "$ACTION" ]]; then
        log_message "$RED" "Missing parameters"
        exit 1
    fi
 
    if [[ "$ACTION" == "install" && -z "$DIGITAL_KEY" ]]; then
        log_message "$RED" "Digital key required"
        exit 1
    fi
 
    check_required_tools
    check_os_architecture
 
    download_and_execute_agent_script "$ACTION" "$MONITOR_TYPE" "$DIGITAL_KEY" "$ENV"
}
 
main "$@"
