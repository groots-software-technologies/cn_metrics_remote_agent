#!/bin/bash
#######################################################
# Program: CloudNetra Metrics Agent Installation.
# Purpose: 
#  - Monitoring the server health overview.
#  - Can be run interactively for a clean and easy installation experience.
# License:
#  - Distributed in the hope that it will be useful, but under Groots Software Technologies @rights.
#######################################################

# Constants
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

# -----------------------------
# Required tools
# -----------------------------
check_required_tools() {
  local tools=(curl wget cut tar gzip sudo bc netstat)
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      log_message "$RED" "Missing tool: $tool"
      exit 1
    fi
  done
}

# -----------------------------
# OS & ARCH
# -----------------------------
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

# -----------------------------
# OS VERSION → V0 / V1
# -----------------------------
set_binary_version() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release

    OS_ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    OS_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)

    log_message "$BLUE" "Detected OS: $OS_ID $OS_VERSION"

    case "$OS_ID" in
      ubuntu)
        if [[ "$OS_VERSION" == "18" || "$OS_VERSION" == "20" ]]; then
          BIN_VERSION="V0"
        else
          BIN_VERSION="V1"
        fi
        ;;
      rhel)
        [[ "$OS_VERSION" == "8" ]] && BIN_VERSION="V0" || BIN_VERSION="V1"
        ;;
      amzn)
        [[ "$OS_VERSION" == "2" ]] && BIN_VERSION="V0" || BIN_VERSION="V1"
        ;;
      centos)
        [[ "$OS_VERSION" == "7" ]] && BIN_VERSION="V0" || BIN_VERSION="V1"
        ;;
      *)
        log_message "$YELLOW" "Unknown OS → default V1"
        BIN_VERSION="V1"
        ;;
    esac

    log_message "$GREEN" "Selected binary: ${ARCH}${BIN_VERSION}.sh"
  else
    log_message "$RED" "OS detection failed"
    exit 1
  fi
}

# -----------------------------
# URL generator (FIXED)
# -----------------------------
generate_agent_script_url() {
  local action="$1"
  local env="$2"
  local version="$3"

  local file_name

if [[ "$action" == "install" ]]; then
  file_name="${ARCH}${BIN_VERSION}.sh"
else
  file_name="${ARCH}.sh"
fi

  echo "https://raw.githubusercontent.com/groots-software-technologies/cn_metrics_remote_agent/${env}/linux/linux/${action}/${file_name}"
}

# -----------------------------
# Download + Execute
# -----------------------------
download_and_execute_agent_script() {
  local action="$1"
  local digital_key="$2"
  local env="$3"

  local PRIMARY_VERSION="$BIN_VERSION"
  local FALLBACK_VERSION="V1"

  for version in "$PRIMARY_VERSION" "$FALLBACK_VERSION"; do

    local url
    url=$(generate_agent_script_url "$action" "$env")

    log_message "$BLUE" "Downloading: $url"

    curl -f -L --retry 3 --connect-timeout 10 -o agent.sh "$url"

    if [ $? -eq 0 ]; then
      chmod +x agent.sh

      if [ "$action" == "install" ]; then
        log_message "$YELLOW" "Executing install script ($version)"
        ./agent.sh -k "$digital_key" -e "$env"
      else
        log_message "$YELLOW" "Executing uninstall script"
        ./agent.sh
      fi

      rm -f agent.sh
      log_message "$GREEN" "Execution completed"
      return 0
    else
      log_message "$YELLOW" "Download failed for ${version}, trying fallback..."
    fi
  done

  log_message "$RED" "All download attempts failed"
  exit 1
}

# -----------------------------
# MAIN
# -----------------------------
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
  set_binary_version

  download_and_execute_agent_script "$ACTION" "$DIGITAL_KEY" "$ENV"
}

main "$@"
