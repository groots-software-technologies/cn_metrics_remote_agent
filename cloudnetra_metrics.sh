#!/bin/bash
###############################################################################
# CloudNetra Metrics Agent Installer
#
# Description:
#   Downloads and executes CloudNetra monitoring agent installers.
#
# Features:
#   - OS and Architecture auto-detection
#   - Automatic V0/V1 binary selection
#   - Install and Uninstall support
#   - Automatic V1 fallback when V0 download fails
#   - Execution logging
#   - Safe temporary file handling
#
# Supported Monitor Types:
#   - linux
#   - docker
#   - apache
#   - nginx
#   - mysql
#   - postgresql
#   - redis
#   - jenkins
#   - kubernetes
#
# Usage:
#   ./cloudnetra_metrics.sh -m linux -a install -k DIGITAL_KEY
#   ./cloudnetra_metrics.sh -m linux -a uninstall
#
# Maintainer:
#   Groots Software Technologies
###############################################################################
set -euo pipefail
###############################################################################
# Constants
###############################################################################
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_DIR="/var/log/cn_metrics"
###############################################################################
# Colors
###############################################################################
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly RESET='\033[0m'
###############################################################################
# Global Variables
###############################################################################
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
MONITOR_TYPE=""
ACTION=""
DIGITAL_KEY=""
ENVIRONMENT="main"
OS=""
ARCH=""
BIN_VERSION=""
TEMP_SCRIPT=""
SUPPORTED_MONITORS=(
    "linux"
    "docker"
    "apache"
    "nginx"
    "mysql"
    "postgresql"
    "redis"
    "jenkins"
    "kubernetes"
)
###############################################################################
# Cleanup
###############################################################################
cleanup() {
    [[ -n "${TEMP_SCRIPT}" ]] && rm -f "${TEMP_SCRIPT}"
}
trap cleanup EXIT
###############################################################################
# Logging Functions
###############################################################################
initialize_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${LOG_FILE}"
}
log_message() {
    local color="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local formatted
    formatted="[${timestamp}] : ${message}"
    echo -e "${color}${formatted}${RESET}"
    echo "${formatted}" >> "${LOG_FILE}"
}
###############################################################################
# Help
###############################################################################
show_help() {
cat << EOF
CloudNetra Metrics Agent Installer
Usage:
    ${SCRIPT_NAME} -m <monitor_type> -a <action> [options]
Options:
    -m    Monitor Type
          linux
          apache
          nginx
          mysql
    -a    Action
          install
          uninstall
    -k    CloudNetra Digital Key
          Required only for install
    -e    Environment
          main (default)
          dev
Examples:
    Install Linux Agent
    ${SCRIPT_NAME} -m linux -a install -k XXXXX
    Install Apache Agent
    ${SCRIPT_NAME} -m apache -a install -k XXXXX
    Uninstall Agent
    ${SCRIPT_NAME} -m linux -a uninstall
EOF
}
###############################################################################
# Dependency Validation
###############################################################################
check_required_tools() {
    local tools=(
        curl
        cut
        chmod
        mktemp
    )
    for tool in "${tools[@]}"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            log_message "${RED}" "Required tool not found: ${tool}"
            exit 1
        fi
    done
}
###############################################################################
# OS & Architecture Detection
###############################################################################
detect_os_architecture() {
    case "$(uname)" in
        Linux)
            OS="linux"
            ;;
        Darwin)
            OS="darwin"
            ;;
        *)
            log_message "${RED}" "Unsupported operating system."
            exit 1
            ;;
    esac
    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l|armv6l)
            ARCH="armv7"
            ;;
        *)
            log_message "${RED}" \
                "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    log_message "${GREEN}" "Detected OS: ${OS}"
    log_message "${GREEN}" "Detected Architecture: ${ARCH}"
}
###############################################################################
# Binary Version Detection
#
# V0:
#   Ubuntu 18 / 20
#   RHEL 8
#   Amazon Linux 2
#   CentOS 7
#
# V1:
#   All other distributions
###############################################################################
set_binary_version() {
    if [[ ! -f /etc/os-release ]]; then
        log_message "${RED}" \
            "Unable to determine operating system version."
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    local os_id
    local os_version
    os_id=$(echo "${ID}" | tr '[:upper:]' '[:lower:]')
    os_version=$(echo "${VERSION_ID}" | cut -d '.' -f1)
    log_message "${BLUE}" \
        "Detected Distribution: ${os_id} ${os_version}"
    case "${os_id}" in
        ubuntu)
            [[ "${os_version}" =~ ^(18|20)$ ]] \
                && BIN_VERSION="V0" \
                || BIN_VERSION="V1"
            ;;
        rhel)
            [[ "${os_version}" == "8" ]] \
                && BIN_VERSION="V0" \
                || BIN_VERSION="V1"
            ;;
        amzn)
            [[ "${os_version}" == "2" ]] \
                && BIN_VERSION="V0" \
                || BIN_VERSION="V1"
            ;;
        centos)
            [[ "${os_version}" == "7" ]] \
                && BIN_VERSION="V0" \
                || BIN_VERSION="V1"
            ;;
        *)
            BIN_VERSION="V1"
            ;;
    esac
    log_message "${GREEN}" \
        "Selected Binary Version: ${BIN_VERSION}"
}
###############################################################################
# Generate Download URL
###############################################################################
generate_agent_script_url() {
    local action="$1"
    local monitor="$2"
    local environment="$3"
    local version="$4"
    local filename
    if [[ "${monitor}" == "linux" && "${action}" == "install" ]]; then
        filename="${ARCH}${version}.sh"
    else
        filename="${ARCH}.sh"
    fi
    echo "https://raw.githubusercontent.com/groots-software-technologies/cn_metrics_remote_agent/${environment}/${OS}/${monitor}/${action}/${filename}"
}
###############################################################################
# Download and Execute Agent
###############################################################################
download_and_execute_agent_script() {
    local action="$1"
    local monitor="$2"
    local digital_key="$3"
    local environment="$4"
    local runtime_environment="${environment}"
    [[ "${environment}" == "main" ]] && runtime_environment="prod"
    local versions=()
    if [[ "${monitor}" == "linux" && "${action}" == "install" ]]; then
        versions+=("${BIN_VERSION}")
        if [[ "${BIN_VERSION}" != "V1" ]]; then
            versions+=("V1")
        fi
    else
        versions+=("")
    fi
    for version in "${versions[@]}"; do
        local script_url
        script_url=$(
            generate_agent_script_url \
                "${action}" \
                "${monitor}" \
                "${environment}" \
                "${version}"
        )
        log_message "${BLUE}" "Downloading: ${script_url}"
        TEMP_SCRIPT=$(mktemp)
        if curl \
            --fail \
            --location \
            --retry 3 \
            --connect-timeout 10 \
            --output "${TEMP_SCRIPT}" \
            "${script_url}"
        then
            chmod +x "${TEMP_SCRIPT}"
            if [[ "${action}" == "install" ]]; then
                "${TEMP_SCRIPT}" \
                    -k "${digital_key}" \
                    -e "${runtime_environment}"
            else
                "${TEMP_SCRIPT}"
            fi
            log_message "${GREEN}" \
                "Execution completed successfully."
            return 0
        fi
        if [[ "${monitor}" == "linux" && "${action}" == "install" ]]; then
            log_message "${YELLOW}" \
                "Download failed for ${ARCH}${version}.sh"
        else
            log_message "${YELLOW}" \
                "Download failed for ${ARCH}.sh"
        fi
    done
    log_message "${RED}" "All download attempts failed."
    exit 1
}
###############################################################################
# Input Validation
###############################################################################
validate_environment() {
    case "${ENVIRONMENT}" in
        main|dev)
            ;;
        *)
            log_message "${RED}" \
                "Invalid environment: ${ENVIRONMENT}"
            exit 1
            ;;
    esac
}
validate_inputs() {
    [[ -z "${MONITOR_TYPE}" ]] && {
        log_message "${RED}" "Monitor type is required."
        exit 1
    }
    [[ -z "${ACTION}" ]] && {
        log_message "${RED}" "Action is required."
        exit 1
    }
    if [[ "${ACTION}" != "install" && "${ACTION}" != "uninstall" ]]; then
        log_message "${RED}" \
            "Action must be install or uninstall."
        exit 1
    fi
    if [[ "${ACTION}" == "install" && -z "${DIGITAL_KEY}" ]]; then
        log_message "${RED}" \
            "Digital key is required for installation."
        exit 1
    fi
    validate_environment
}
###############################################################################
# Main
###############################################################################
main() {
    initialize_logging
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    while getopts "m:a:k:e:h" opt; do
        case "${opt}" in
            m) MONITOR_TYPE="${OPTARG}" ;;
            a) ACTION="${OPTARG}" ;;
            k) DIGITAL_KEY="${OPTARG}" ;;
            e) ENVIRONMENT="${OPTARG}" ;;
            h)
                show_help
                exit 0
                ;;
            *)
                show_help
                exit 1
                ;;
        esac
    done
    validate_inputs
    check_required_tools
    detect_os_architecture
    if [[ "${MONITOR_TYPE}" == "linux" &&
          "${ACTION}" == "install" ]]; then
        set_binary_version
    fi
    download_and_execute_agent_script \
        "${ACTION}" \
        "${MONITOR_TYPE}" \
        "${DIGITAL_KEY}" \
        "${ENVIRONMENT}"
}
###############################################################################
# Entry Point
###############################################################################
main "$@"
