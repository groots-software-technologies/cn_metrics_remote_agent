#!/bin/bash

###############################################################################
# CloudNetra Metrics Agent Installer
#
# Purpose:
#   Install or uninstall CloudNetra monitoring agents.
#
# Features:
#   - Auto detects OS and Architecture
#   - Auto selects compatible binary version (V0 / V1)
#   - Supports Linux, Apache, MySQL, Nginx and other monitor types
#   - Supports Install and Uninstall actions
#   - Automatic fallback to V1 binary if V0 download fails
#
# Usage:
#   ./cloudnetra_metrics.sh -m linux -a install -k DIGITAL_KEY
#   ./cloudnetra_metrics.sh -m linux -a uninstall
#
# Maintainer:
#   Groots Software Technologies
###############################################################################

###############################################################################
# Script Constants
###############################################################################

SCRIPTNAME=$(basename "$0")

###############################################################################
# Color Definitions
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

###############################################################################
# Logging Configuration
###############################################################################

LOGDIR="/var/log/cn_metrics"
LOGFILE="$LOGDIR/${SCRIPTNAME}.log"

###############################################################################
# Default Variables
###############################################################################

ENV="main"
OS=""
ARCH=""
BIN_VERSION=""

###############################################################################
# Create Log Directory
###############################################################################

initialize_logging() {

	mkdir -p "$LOGDIR"

	if [ ! -f "$LOGFILE" ]; then
		touch "$LOGFILE"
	fi
}

###############################################################################
# Log Message Helper
###############################################################################

log_message() {

	local color="$1"
	local message="$2"

	local timestamp
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')

	local formatted_message="[$timestamp] : $message"

	echo -e "${color}${formatted_message}${RESET}"
	echo "$formatted_message" >>"$LOGFILE"
}

###############################################################################
# Display Help
###############################################################################

show_help() {

	cat <<EOF

CloudNetra Metrics Agent Installer

Usage:
  $SCRIPTNAME -m <monitor_type> -a <action> [options]

Options:

  -m    Monitor Type
        Example:
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

    $SCRIPTNAME -m linux -a install -k XXXXX

  Install Apache Agent

    $SCRIPTNAME -m apache -a install -k XXXXX

  Uninstall Agent

    $SCRIPTNAME -m linux -a uninstall

EOF
}

###############################################################################
# Verify Required Packages
###############################################################################

check_required_tools() {

	local tools=(
		curl
		wget
		cut
		tar
		gzip
		sudo
		bc
		netstat
	)

	for tool in "${tools[@]}"; do

		if ! command -v "$tool" >/dev/null 2>&1; then

			log_message "$RED" \
				"Required package not found: $tool"

			exit 1
		fi
	done
}

###############################################################################
# Detect Operating System
###############################################################################

check_os_architecture() {

	case "$(uname)" in

	Linux)
		OS="linux"
		;;

	Darwin)
		OS="darwin"
		;;

	*)
		log_message "$RED" \
			"Unsupported operating system."

		exit 1
		;;
	esac

	case "$(uname -m)" in

	x86_64)
		ARCH="amd64"
		;;

	aarch64 | arm64)
		ARCH="arm64"
		;;

	armv7l | armv6l)
		ARCH="armv7"
		;;

	*)
		log_message "$RED" \
			"Unsupported architecture: $(uname -m)"

		exit 1
		;;
	esac

	log_message "$GREEN" "Detected OS: $OS"
	log_message "$GREEN" "Detected Architecture: $ARCH"
}

###############################################################################
# Determine Binary Version
#
# V0:
#   Ubuntu 18 / 20
#   RHEL 8
#   Amazon Linux 2
#   CentOS 7
#
# V1:
#   Everything else
###############################################################################

set_binary_version() {

	if [ ! -f /etc/os-release ]; then

		log_message "$RED" \
			"Unable to determine OS version."

		exit 1
	fi

	. /etc/os-release

	local os_id
	local os_version

	os_id=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
	os_version=$(echo "$VERSION_ID" | cut -d '.' -f1)

	log_message "$BLUE" \
		"Detected Distribution: ${os_id} ${os_version}"

	case "$os_id" in

	ubuntu)

		if [[ "$os_version" == "18" || "$os_version" == "20" ]]; then
			BIN_VERSION="V0"
		else
			BIN_VERSION="V1"
		fi
		;;

	rhel)

		if [[ "$os_version" == "8" ]]; then
			BIN_VERSION="V0"
		else
			BIN_VERSION="V1"
		fi
		;;

	amzn)

		if [[ "$os_version" == "2" ]]; then
			BIN_VERSION="V0"
		else
			BIN_VERSION="V1"
		fi
		;;

	centos)

		if [[ "$os_version" == "7" ]]; then
			BIN_VERSION="V0"
		else
			BIN_VERSION="V1"
		fi
		;;

	*)
		BIN_VERSION="V1"
		;;
	esac

	log_message "$GREEN" \
		"Selected Binary Version: ${BIN_VERSION}"
}

###############################################################################
# Build Agent Download URL
###############################################################################

generate_agent_script_url() {
	local action="$1"
	local monitor_type="$2"
	local env="$3"
	local version="$4"

	local file_name

	if [ "$monitor_type" = "linux" ]; then
		if [ "$action" = "install" ]; then
			file_name="${ARCH}${version}.sh"
		else
			file_name="${ARCH}.sh"
		fi
	else
		file_name="${ARCH}.sh"
	fi

	echo "https://raw.githubusercontent.com/groots-software-technologies/cn_metrics_remote_agent/${env}/${OS}/${monitor_type}/${action}/${file_name}"
}

###############################################################################
# Download and Execute Agent
###############################################################################

download_and_execute_agent_script() {

	local action="$1"
	local monitor_type="$2"
	local digital_key="$3"
	local env="$4"

	local runtime_env="$env"

	if [ "$env" = "main" ]; then
		runtime_env="prod"
	fi

	local versions

	if [ "$monitor_type" = "linux" ]; then
		versions=("$BIN_VERSION")

		if [ "$BIN_VERSION" != "V1" ]; then
			versions+=("V1")
		fi
	else
		versions=("")
	fi

	for version in "${versions[@]}"; do

		local script_url

		script_url=$(
			generate_agent_script_url \
				"$action" \
				"$monitor_type" \
				"$env" \
				"$version"
		)

		log_message "$BLUE" \
			"Downloading: $script_url"

		if curl \
			-f \
			-L \
			--retry 3 \
			--connect-timeout 10 \
			-o agent.sh \
			"$script_url"; then

			chmod +x agent.sh

			if [ "$action" = "install" ]; then

				log_message "$YELLOW" \
					"Executing installation script"

				./agent.sh \
					-k "$digital_key" \
					-e "$runtime_env"

			else

				log_message "$YELLOW" \
					"Executing uninstall script"

				./agent.sh
			fi

			rm -f agent.sh

			log_message "$GREEN" \
				"Execution completed successfully."

			return 0
		fi

		if [ "$monitor_type" = "linux" ]; then
			log_message "$YELLOW" \
				"Download failed for ${ARCH}${version}.sh"
		else
			log_message "$YELLOW" \
				"Download failed for ${ARCH}.sh"
		fi
	done

	log_message "$RED" \
		"All download attempts failed."

	exit 1
}

###############################################################################
# Validate User Input
###############################################################################

validate_inputs() {

	if [ -z "$MONITOR_TYPE" ]; then
		log_message "$RED" "Monitor type is required."
		exit 1
	fi

	if [ -z "$ACTION" ]; then
		log_message "$RED" "Action is required."
		exit 1
	fi

	if [ "$ACTION" != "install" ] &&
		[ "$ACTION" != "uninstall" ]; then

		log_message "$RED" \
			"Action must be install or uninstall."

		exit 1
	fi

	if [ "$ACTION" = "install" ] &&
		[ -z "$DIGITAL_KEY" ]; then

		log_message "$RED" \
			"Digital key is required for installation."

		exit 1
	fi
}

###############################################################################
# Main
###############################################################################

main() {

	initialize_logging

	if [ $# -eq 0 ]; then
		show_help
		exit 0
	fi

	while getopts "m:a:k:e:h" opt; do
		case "$opt" in

		m) MONITOR_TYPE="$OPTARG" ;;
		a) ACTION="$OPTARG" ;;
		k) DIGITAL_KEY="$OPTARG" ;;
		e) ENV="$OPTARG" ;;
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
	check_os_architecture
	set_binary_version

	download_and_execute_agent_script \
		"$ACTION" \
		"$MONITOR_TYPE" \
		"$DIGITAL_KEY" \
		"$ENV"
}

###############################################################################
# Entry Point
###############################################################################

main "$@"
