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
    *) log_message "$RED" "Unsupported architecture"; exit 1 ;;
  esac
}

# -----------------------------
# OS VERSION -> AGENT VERSION
# -----------------------------
set_binary_version() {

  if [ ! -f /etc/os-release ]; then
    log_message "$RED" "Unable to detect operating system."
    exit 1
  fi

  . /etc/os-release

  OS_ID=$(echo "${ID:-unknown}" | tr '[:upper:]' '[:lower:]')
  OS_VERSION="${VERSION_ID:-0}"
  OS_MAJOR_VERSION="${OS_VERSION%%.*}"

  ID_LIKE_VALUE=$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')

  log_message "$BLUE" "Detected OS: ${NAME:-$OS_ID}"
  log_message "$BLUE" "OS ID: $OS_ID"
  log_message "$BLUE" "OS Version: $OS_VERSION"
  log_message "$BLUE" "OS Major Version: $OS_MAJOR_VERSION"

  # --------------------------------------------------
  # Legacy systems that require V0
  # --------------------------------------------------
  case "$OS_ID" in

    ubuntu)
      if [ "$OS_MAJOR_VERSION" -le 20 ]; then
        BIN_VERSION="V0"
      else
        BIN_VERSION="V1"
      fi
      ;;

    rhel)
      if [ "$OS_MAJOR_VERSION" -eq 8 ]; then
        BIN_VERSION="V0"
      else
        BIN_VERSION="V1"
      fi
      ;;

    centos)
      if [ "$OS_MAJOR_VERSION" -eq 7 ]; then
        BIN_VERSION="V0"
      else
        BIN_VERSION="V1"
      fi
      ;;

    amzn)
      if [ "$OS_MAJOR_VERSION" -eq 2 ]; then
        BIN_VERSION="V0"
      else
        BIN_VERSION="V1"
      fi
      ;;

    *)
      # --------------------------------------------------
      # All new / unknown OS versions use V1
      # --------------------------------------------------
      BIN_VERSION="V1"
      ;;

  esac

  log_message "$GREEN" "Selected CloudNetra installer: ${ARCH}${BIN_VERSION}.sh"
}

# -----------------------------
# URL generator
# -----------------------------
generate_agent_script_url() {
  local action="$1"
  local env="$2"
  local version="$3"

  local file_name

  if [[ "$action" == "install" ]]; then
    file_name="${ARCH}${version}.sh"
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

  local primary_version="$BIN_VERSION"
  local fallback_version="V1"

  local versions=("$primary_version")

  # Only use V1 as fallback when primary is not already V1
  if [ "$primary_version" != "V1" ]; then
    versions+=("$fallback_version")
  fi

  for version in "${versions[@]}"; do

    local url
    url=$(generate_agent_script_url "$action" "$env" "$version")

    log_message "$BLUE" "Checking installer: ${ARCH}${version}.sh"
    log_message "$BLUE" "URL: $url"

    rm -f agent.sh

    if ! curl -fL \
      --retry 3 \
      --connect-timeout 10 \
      --max-time 120 \
      -o agent.sh \
      "$url"; then

      log_message "$YELLOW" \
        "Installer ${ARCH}${version}.sh is not available."

      continue
    fi

    if [ ! -s agent.sh ]; then
      log_message "$YELLOW" \
        "Installer ${ARCH}${version}.sh downloaded but is empty."

      rm -f agent.sh
      continue
    fi

    chmod +x agent.sh

    # ------------------------------------------------
    # Validate shell script before execution
    # ------------------------------------------------
    if ! bash -n agent.sh; then
      log_message "$RED" \
        "Installer ${ARCH}${version}.sh contains Bash syntax errors."

      rm -f agent.sh
      exit 1
    fi

    local runtime_env="$env"

    if [ "$env" == "main" ]; then
      runtime_env="prod"
    fi

    log_message "$GREEN" \
      "Installer ${ARCH}${version}.sh downloaded successfully."

    log_message "$BLUE" \
      "Passing ENV to agent: $runtime_env"

    if [ "$action" == "install" ]; then

      log_message "$YELLOW" \
        "Executing CloudNetra installer ${ARCH}${version}.sh..."

      if ./agent.sh -k "$digital_key" -e "$runtime_env"; then
        rm -f agent.sh

        log_message "$GREEN" \
          "CloudNetra agent installed successfully."

        return 0
      fi

      # Do NOT automatically switch installer after execution failure
      log_message "$RED" \
        "CloudNetra installer ${ARCH}${version}.sh failed during execution."

      log_message "$RED" \
        "Please check the installer logs before retrying."

      rm -f agent.sh
      exit 1

    else

      log_message "$YELLOW" \
        "Executing CloudNetra uninstall script..."

      if ./agent.sh; then
        rm -f agent.sh

        log_message "$GREEN" \
          "CloudNetra agent uninstalled successfully."

        return 0
      fi

      log_message "$RED" \
        "CloudNetra uninstall failed."

      rm -f agent.sh
      exit 1
    fi

  done

  log_message "$RED" \
    "No compatible CloudNetra installer was available."

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
    log_message "$RED" "Digital key required"
    exit 1
  fi

  check_required_tools
  check_os_architecture
  set_binary_version

  download_and_execute_agent_script "$ACTION" "$DIGITAL_KEY" "$ENV"
}

main "$@"
