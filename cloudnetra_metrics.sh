#!/bin/bash

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
      log_message "$RED" "Missing tool: $tool"
      exit 1
    fi
  done
}

check_os_architecture() {
  case "$(uname)" in
    Linux) OS="linux" ;;
    Darwin) OS="darwin" ;;
    *) log_message "$RED" "Unsupported OS"; exit 1 ;;
  esac

  case "$(uname -m)" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l|armv6l) ARCH="armv7" ;;
    *) log_message "$RED" "Unsupported architecture"; exit 1 ;;
  esac
}

# Normalize monitor input (linux, linux1, linux_v1 → version)
get_version() {
  local input="$1"

  if [[ "$input" =~ ^linux[_-]?([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "0"
  fi
}

generate_agent_script_url() {
  local action="$1"
  local monitor_type="$2"
  local env="$3"

  local version=$(get_version "$monitor_type")

  local file_name="${ARCH}V${version}.sh"

  if [[ "$action" == "uninstall" ]]; then
    file_name="${ARCH}.sh"
  fi

  # ✅ FIXED: folder is always linux (NOT linux1)
  local url="https://raw.githubusercontent.com/groots-software-technologies/cn_metrics_remote_agent/${env}/${OS}/linux/${action}/${file_name}"

  echo "$url"
}

download_and_execute_agent_script() {
  local action="$1"
  local monitor_type="$2"
  local digital_key="$3"
  local env="$4"

  local script_url
  script_url=$(generate_agent_script_url "$action" "$monitor_type" "$env")

  log_message "$BLUE" "Downloading: $script_url"

  curl -f -LO "$script_url"

  if [ $? -ne 0 ]; then
    log_message "$RED" "Download failed. Check URL or repo path."
    exit 1
  fi

  local file="${script_url##*/}"

  if [ ! -f "$file" ]; then
    log_message "$RED" "File not found after download"
    exit 1
  fi

  chmod +x "$file"

  if [ "$action" == "install" ]; then
    log_message "$YELLOW" "Running install script"
    ./$file -k "$digital_key" -e "$env"
  else
    log_message "$YELLOW" "Running uninstall script"
    ./$file
  fi

  rm -f "$file"
  log_message "$GREEN" "Execution completed"
}

main() {
  while getopts "m:a:k:e:" opt; do
    case $opt in
      m) MONITOR_TYPE="$OPTARG" ;;
      a) ACTION="$OPTARG" ;;
      k) DIGITAL_KEY="$OPTARG" ;;
      e) ENV="$OPTARG" ;;
      *) log_message "$RED" "Invalid argument"; exit 1 ;;
    esac
  done

  [ -z "$ENV" ] && ENV="main"

  if [ -z "$MONITOR_TYPE" ] || [ -z "$ACTION" ]; then
    log_message "$RED" "Missing required parameters"
    exit 1
  fi

  if [ "$ACTION" == "install" ] && [ -z "$DIGITAL_KEY" ]; then
    log_message "$RED" "Digital key required for install"
    exit 1
  fi

  check_required_tools
  check_os_architecture

  download_and_execute_agent_script "$ACTION" "$MONITOR_TYPE" "$DIGITAL_KEY" "$ENV"
}

main "$@"
