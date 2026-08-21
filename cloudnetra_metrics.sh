#!/bin/bash
###############################################################################
# CloudNetra Metrics Agent Installer
#
# Description:
#   Downloads and executes CloudNetra monitoring agent installers.
#
# Features:
#   - OS auto-detection
#   - Architecture auto-detection
#   - Automatic Linux V0/V1 binary selection
#   - V0 -> V1 fallback when download/validation fails
#   - Install and Uninstall support
#   - Supports Bash scripts and ELF binaries
#   - ELF architecture validation
#   - Installer validation before execution
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
#   Install:
#     ./cloudnetra_metrics.sh -m linux -a install -k DIGITAL_KEY
#
#   Uninstall:
#     ./cloudnetra_metrics.sh -m linux -a uninstall
#
#   Environment:
#     -e main
#     -e dev
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
OS_ID=""
OS_VERSION=""
OS_MAJOR_VERSION=""
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
    if [[ -n "${TEMP_SCRIPT}" && -f "${TEMP_SCRIPT}" ]]; then
        rm -f "${TEMP_SCRIPT}"
    fi
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
# Root Validation
###############################################################################
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo -e "${RED}This script must be executed as root.${RESET}"
        echo
        echo "Please run:"
        echo "  sudo ${SCRIPT_NAME} ..."
        exit 1
    fi
}
###############################################################################
# Help
###############################################################################
show_help() {
cat << EOF
CloudNetra Metrics Agent Installer
Usage:
    ${SCRIPT_NAME} -m <monitor_type> -a <action> [options]
Required Options:
    -m    Monitor Type
          linux
          docker
          apache
          nginx
          mysql
          postgresql
          redis
          jenkins
          kubernetes
    -a    Action
          install
          uninstall
Optional Options:
    -k    CloudNetra Digital Key
          Required for install
    -e    Environment
          main (default)
          dev
    -h    Show this help
Examples:
    Install Linux Agent:
        ${SCRIPT_NAME} -m linux -a install -k XXXXX
    Install Linux Agent in DEV:
        ${SCRIPT_NAME} -m linux -a install -k XXXXX -e dev
    Uninstall Linux Agent:
        ${SCRIPT_NAME} -m linux -a uninstall
    Install MySQL Agent:
        ${SCRIPT_NAME} -m mysql -a install -k XXXXX
    Uninstall MySQL Agent:
        ${SCRIPT_NAME} -m mysql -a uninstall
EOF
}
###############################################################################
# Dependency Validation
###############################################################################
check_required_tools() {
    local tools=(
        curl
        chmod
        mktemp
        file
    )
    local missing_tools=()
    for tool in "${tools[@]}"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            missing_tools+=("${tool}")
        fi
    done
    if [[ "${#missing_tools[@]}" -gt 0 ]]; then
        log_message "${RED}" \
            "Required tool(s) not found: ${missing_tools[*]}"
        log_message "${YELLOW}" \
            "Please install the missing package(s) and try again."
        exit 1
    fi
}
###############################################################################
# OS Detection
###############################################################################
detect_os() {
    case "$(uname -s)" in
        Linux)
            OS="linux"
            ;;
        Darwin)
            OS="darwin"
            ;;
        *)
            log_message "${RED}" \
                "Unsupported operating system: $(uname -s)"
            exit 1
            ;;
    esac
    log_message "${GREEN}" \
        "Detected OS: ${OS}"
}
###############################################################################
# Linux Distribution Detection
###############################################################################
detect_linux_distribution() {
    if [[ "${OS}" != "linux" ]]; then
        return 0
    fi
    if [[ ! -f /etc/os-release ]]; then
        log_message "${RED}" \
            "Unable to determine Linux distribution."
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID,,}"
    OS_VERSION="${VERSION_ID:-unknown}"
    OS_MAJOR_VERSION="${OS_VERSION%%.*}"
    log_message "${BLUE}" \
        "OS ID: ${OS_ID}"
    log_message "${BLUE}" \
        "OS Version: ${OS_VERSION}"
    log_message "${BLUE}" \
        "OS Major Version: ${OS_MAJOR_VERSION}"
}
###############################################################################
# Architecture Detection
###############################################################################
detect_architecture() {
    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l|armv7*)
            ARCH="armv7"
            ;;
        armv6l|armv6*)
            ARCH="armv7"
            ;;
        *)
            log_message "${RED}" \
                "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    log_message "${GREEN}" \
        "Detected Architecture: ${ARCH}"
}
###############################################################################
# Linux Binary Version Detection
#
# V0:
#   Ubuntu 18
#   Ubuntu 20
#   RHEL 8
#   Amazon Linux 2
#   CentOS 7
#
# V1:
#   All other supported distributions
###############################################################################
set_binary_version() {
    if [[ "${OS}" != "linux" ]]; then
        BIN_VERSION="V1"
        return 0
    fi
    case "${OS_ID}" in
        ubuntu)
            if [[ "${OS_MAJOR_VERSION}" =~ ^(18|20)$ ]]; then
                BIN_VERSION="V0"
            else
                BIN_VERSION="V1"
            fi
            ;;
        rhel)
            if [[ "${OS_MAJOR_VERSION}" == "8" ]]; then
                BIN_VERSION="V0"
            else
                BIN_VERSION="V1"
            fi
            ;;
        amzn)
            if [[ "${OS_MAJOR_VERSION}" == "2" ]]; then
                BIN_VERSION="V0"
            else
                BIN_VERSION="V1"
            fi
            ;;
        centos)
            if [[ "${OS_MAJOR_VERSION}" == "7" ]]; then
                BIN_VERSION="V0"
            else
                BIN_VERSION="V1"
            fi
            ;;
        *)
            BIN_VERSION="V1"
            ;;
    esac
    log_message "${GREEN}" \
        "Selected CloudNetra Binary Version: ${BIN_VERSION}"
}
###############################################################################
# Monitor Validation
###############################################################################
validate_monitor_type() {
    local monitor_found="false"
    for monitor in "${SUPPORTED_MONITORS[@]}"; do
        if [[ "${MONITOR_TYPE}" == "${monitor}" ]]; then
            monitor_found="true"
            break
        fi
    done
    if [[ "${monitor_found}" != "true" ]]; then
        log_message "${RED}" \
            "Unsupported monitor type: ${MONITOR_TYPE}"
        log_message "${YELLOW}" \
            "Supported monitor types: ${SUPPORTED_MONITORS[*]}"
        exit 1
    fi
}
###############################################################################
# Environment Validation
###############################################################################
validate_environment() {
    case "${ENVIRONMENT}" in
        main|dev)
            ;;
        *)
            log_message "${RED}" \
                "Invalid environment: ${ENVIRONMENT}"
            log_message "${YELLOW}" \
                "Valid environments: main, dev"
            exit 1
            ;;
    esac
}
###############################################################################
# Input Validation
###############################################################################
validate_inputs() {
    if [[ -z "${MONITOR_TYPE}" ]]; then
        log_message "${RED}" \
            "Monitor type is required."
        exit 1
    fi
    if [[ -z "${ACTION}" ]]; then
        log_message "${RED}" \
            "Action is required."
        exit 1
    fi
    if [[ "${ACTION}" != "install" &&
          "${ACTION}" != "uninstall" ]]; then
        log_message "${RED}" \
            "Action must be install or uninstall."
        exit 1
    fi
    if [[ "${ACTION}" == "install" &&
          -z "${DIGITAL_KEY}" ]]; then
        log_message "${RED}" \
            "Digital key is required for installation."
        exit 1
    fi
    validate_monitor_type
    validate_environment
}
###############################################################################
# Generate Download URL
###############################################################################
generate_agent_script_url() {
    local action="$1"
    local monitor="$2"
    local environment="$3"
    local version="$4"
    local filename=""
    #
    # Linux INSTALL
    #
    # Example:
    #   amd64V0.sh
    #   amd64V1.sh
    #   arm64V0.sh
    #   arm64V1.sh
    #
    if [[ "${monitor}" == "linux" &&
          "${action}" == "install" ]]; then
        filename="${ARCH}${version}.sh"
    #
    # Linux UNINSTALL
    #
    # Example:
    #   amd64.sh
    #   arm64.sh
    #   armv7.sh
    #
    elif [[ "${monitor}" == "linux" &&
            "${action}" == "uninstall" ]]; then
        filename="${ARCH}.sh"
    #
    # Other monitor types
    #
    else
        filename="${ARCH}.sh"
    fi
    echo "https://raw.githubusercontent.com/groots-software-technologies/cn_metrics_remote_agent/${environment}/${OS}/${monitor}/${action}/${filename}"
}
###############################################################################
# Validate ELF Architecture
###############################################################################
validate_elf_architecture() {
    local installer="$1"
    local file_type
    file_type=$(file -b "${installer}")
    case "${ARCH}" in
        amd64)
            if [[ "${file_type}" != *"x86-64"* ]]; then
                log_message "${RED}" \
                    "Architecture mismatch."
                log_message "${RED}" \
                    "Expected: x86-64"
                log_message "${RED}" \
                    "Downloaded: ${file_type}"
                return 1
            fi
            ;;
        arm64)
            if [[ "${file_type}" != *"ARM aarch64"* &&
                  "${file_type}" != *"ARM64"* ]]; then
                log_message "${RED}" \
                    "Architecture mismatch."
                log_message "${RED}" \
                    "Expected: ARM64 / aarch64"
                log_message "${RED}" \
                    "Downloaded: ${file_type}"
                return 1
            fi
            ;;
        armv7)
            if [[ "${file_type}" != *"ARM"* ]]; then
                log_message "${RED}" \
                    "Architecture mismatch."
                log_message "${RED}" \
                    "Expected: ARM 32-bit"
                log_message "${RED}" \
                    "Downloaded: ${file_type}"
                return 1
            fi
            ;;
        *)
            log_message "${RED}" \
                "Unsupported architecture validation: ${ARCH}"
            return 1
            ;;
    esac
    return 0
}
###############################################################################
# Validate Downloaded Installer
#
# Supported installer types:
#
#   1. Bash script
#   2. POSIX shell script
#   3. ELF executable
#
###############################################################################
validate_installer() {
    local installer="$1"
    local file_type
    file_type=$(file -b "${installer}")
    log_message "${BLUE}" \
        "Downloaded installer type: ${file_type}"
    ###########################################################################
    # Shell Script
    ###########################################################################
    if [[ "${file_type}" == *"shell script"* ]]; then
        log_message "${GREEN}" \
            "Installer validation successful: Shell script."
        return 0
    fi
    ###########################################################################
    # ELF Binary
    ###########################################################################
    if [[ "${file_type}" == *"ELF"* ]]; then
        log_message "${BLUE}" \
            "ELF executable detected."
        if ! validate_elf_architecture "${installer}"; then
            return 1
        fi
        chmod +x "${installer}"
        log_message "${GREEN}" \
            "Installer validation successful: ELF binary."
        return 0
    fi
    ###########################################################################
    # Invalid Installer
    ###########################################################################
    log_message "${RED}" \
        "Downloaded file is not a supported installer."
    log_message "${RED}" \
        "File type: ${file_type}"
    return 1
}
###############################################################################
# Execute Installer
###############################################################################
execute_installer() {
    local installer="$1"
    local action="$2"
    local digital_key="$3"
    local runtime_environment="$4"
    local file_type
    file_type=$(file -b "${installer}")
    ###########################################################################
    # Shell Script Installer
    ###########################################################################
    if [[ "${file_type}" == *"shell script"* ]]; then
        log_message "${BLUE}" \
            "Executing shell installer..."
        if [[ "${action}" == "install" ]]; then
            bash "${installer}" \
                -k "${digital_key}" \
                -e "${runtime_environment}"
        else
            bash "${installer}"
        fi
        return 0
    fi
    ###########################################################################
    # ELF Installer
    ###########################################################################
    if [[ "${file_type}" == *"ELF"* ]]; then
        log_message "${BLUE}" \
            "Executing ELF installer..."
        chmod +x "${installer}"
        if [[ "${action}" == "install" ]]; then
            "${installer}" \
                -k "${digital_key}" \
                -e "${runtime_environment}"
        else
            "${installer}"
        fi
        return 0
    fi
    log_message "${RED}" \
        "Cannot execute unsupported installer type: ${file_type}"
    return 1
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
    #
    # Repository branch:
    #   main -> runtime environment prod
    #
    if [[ "${environment}" == "main" ]]; then
        runtime_environment="prod"
    fi
    ###########################################################################
    # Version Selection
    ###########################################################################
    local versions=()
    if [[ "${monitor}" == "linux" &&
          "${action}" == "install" ]]; then
        #
        # First try the OS-selected version.
        #
        versions+=("${BIN_VERSION}")
        #
        # If V0 fails validation/download, automatically try V1.
        #
        if [[ "${BIN_VERSION}" != "V1" ]]; then
            versions+=("V1")
        fi
    else
        #
        # Linux uninstall and all other monitors:
        # no V0/V1 suffix.
        #
        versions+=("")
    fi
    ###########################################################################
    # Download Attempts
    ###########################################################################
    for version in "${versions[@]}"; do
        #######################################################################
        # Cleanup Previous Temporary File
        #######################################################################
        if [[ -n "${TEMP_SCRIPT}" &&
              -f "${TEMP_SCRIPT}" ]]; then
            rm -f "${TEMP_SCRIPT}"
            TEMP_SCRIPT=""
        fi
        #######################################################################
        # Generate URL
        #######################################################################
        local script_url
        script_url=$(
            generate_agent_script_url \
                "${action}" \
                "${monitor}" \
                "${environment}" \
                "${version}"
        )
        local filename
        if [[ "${monitor}" == "linux" &&
              "${action}" == "install" ]]; then
            filename="${ARCH}${version}.sh"
        else
            filename="${ARCH}.sh"
        fi
        log_message "${BLUE}" \
            "Checking installer: ${filename}"
        log_message "${BLUE}" \
            "URL: ${script_url}"
        #######################################################################
        # Create Temporary File
        #######################################################################
        TEMP_SCRIPT=$(mktemp)
        #######################################################################
        # Download
        #######################################################################
        if ! curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --retry 3 \
            --retry-delay 2 \
            --connect-timeout 10 \
            --max-time 120 \
            --output "${TEMP_SCRIPT}" \
            "${script_url}"; then
            log_message "${YELLOW}" \
                "Download failed for ${filename}"
            rm -f "${TEMP_SCRIPT}"
            TEMP_SCRIPT=""
            continue
        fi
        #######################################################################
        # Check Empty File
        #######################################################################
        if [[ ! -s "${TEMP_SCRIPT}" ]]; then
            log_message "${YELLOW}" \
                "Downloaded installer is empty: ${filename}"
            rm -f "${TEMP_SCRIPT}"
            TEMP_SCRIPT=""
            continue
        fi
        #######################################################################
        # Validate Installer
        #######################################################################
        if ! validate_installer "${TEMP_SCRIPT}"; then
            log_message "${YELLOW}" \
                "Installer validation failed: ${filename}"
            rm -f "${TEMP_SCRIPT}"
            TEMP_SCRIPT=""
            continue
        fi
        #######################################################################
        # Execute Installer
        #######################################################################
        if ! execute_installer \
            "${TEMP_SCRIPT}" \
            "${action}" \
            "${digital_key}" \
            "${runtime_environment}"; then
            log_message "${RED}" \
                "Installer execution failed: ${filename}"
            exit 1
        fi
        #######################################################################
        # Successful Execution
        #######################################################################
        log_message "${GREEN}" \
            "CloudNetra ${monitor} ${action} completed successfully."
        return 0
    done
    ###########################################################################
    # All Attempts Failed
    ###########################################################################
    log_message "${RED}" \
        "All CloudNetra installer download/validation attempts failed."
    exit 1
}
###############################################################################
# Main
###############################################################################
main() {
    ###########################################################################
    # Initialize
    ###########################################################################
    initialize_logging
    ###########################################################################
    # Help
    ###########################################################################
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    ###########################################################################
    # Parse Arguments
    ###########################################################################
    while getopts "m:a:k:e:h" opt; do
        case "${opt}" in
            m)
                MONITOR_TYPE="${OPTARG}"
                ;;
            a)
                ACTION="${OPTARG}"
                ;;
            k)
                DIGITAL_KEY="${OPTARG}"
                ;;
            e)
                ENVIRONMENT="${OPTARG}"
                ;;
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
    ###########################################################################
    # Root Check
    ###########################################################################
    check_root
    ###########################################################################
    # Input Validation
    ###########################################################################
    validate_inputs
    ###########################################################################
    # Dependency Check
    ###########################################################################
    check_required_tools
    ###########################################################################
    # Detect OS
    ###########################################################################
    detect_os
    ###########################################################################
    # Detect Linux Distribution
    ###########################################################################
    detect_linux_distribution
    ###########################################################################
    # Detect Architecture
    ###########################################################################
    detect_architecture
    ###########################################################################
    # Linux Binary Version
    #
    # Only required for Linux INSTALL.
    #
    ###########################################################################
    if [[ "${MONITOR_TYPE}" == "linux" &&
          "${ACTION}" == "install" ]]; then
        set_binary_version
    fi
    ###########################################################################
    # Download and Execute
    ###########################################################################
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
