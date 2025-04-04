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

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Logfile
LOGDIR="/var/log/cn_metrics/"
LOGFILE="$LOGDIR/$SCRIPTNAME.log"

# Create log directory and file
if [ ! -d "$LOGDIR" ]; then
    mkdir -p "$LOGDIR"
fi
if [ ! -f "$LOGFILE" ]; then
    touch "$LOGFILE"
fi

# Function to log messages with colors and timestamp
log_message() {
  local color="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')  # Get the current timestamp

  # Format the log message
  local formatted_message="[$timestamp] : $message"

  # Print the formatted message to the terminal with color
  echo -e "${color}${formatted_message}${RESET}"

  # Log the formatted message with timestamp to the log file
  echo "$formatted_message" >> $LOGFILE
}



# Default environment (main)
ENV="main"

# Check if required tools are installed
check_required_tools() {
  local tools=(curl wget cut tar gzip sudo bc netstat)
  for tool in "${tools[@]}"; do
    if ! command -v $tool &>/dev/null; then
      log_message "$RED" "Error: Required tool $tool is not installed. Please install it and retry."
      exit 1
    fi
  done
}

# Function to check for environment
set_environment() {
    # Check if the environment is set via -e flag
    if [ "$ENV" == "dev" ]; then
        API_URL="https://dev-app.cloudnetra.io"
    elif [ "$ENV" == "main" ]; then
        API_URL="https://app.cloudnetra.io"
    elif [ "$ENV" == "local" ]; then
        API_URL="http://localhost:3004"
    else
        echo "Error: Invalid environment specified. Please use 'dev' or 'main'."
        exit 1
    fi
}

# Fetch Machine ID
get_machine_id() {
  if [ -f /etc/machine-id ]; then
    MACHINE_ID=$(cat /etc/machine-id)
  elif [ -f /var/lib/dbus/machine-id ]; then
    MACHINE_ID=$(cat /var/lib/dbus/machine-id)
  elif command -v hostnamectl &>/dev/null; then
    MACHINE_ID=$(hostnamectl | grep "Machine ID" | awk '{print $3}')
  else
    log_message "$RED" "Error: Could not retrieve Machine ID."
    exit 1
  fi

  if [ -z "$MACHINE_ID" ]; then
    log_message "$RED" "Error: Machine ID is empty."
    exit 1
  fi
}

# Determine OS and architecture
check_os_architecture() {
  if [ "$(uname)" == "Linux" ]; then
    OS="linux"
  elif [ "$(uname)" == "Darwin" ]; then
    OS="darwin"
  else
    echo "This operating system is not supported. The supported operating systems are Linux and Darwin"
    exit 1
  fi

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
      log_message "$RED" "Error: Unsupported architecture $(uname -m). Supported architectures: x86_64, aarch64, armv7."
      exit 1
      ;;
  esac
}


# Function to generate the agent script URL
generate_agent_script_url() {
    local action="$1"
    local monitor_type="$2"
    local url
    local env="$3"
    
    if [ "$action" == "install" ]; then
        # URL for installation script
        url="https://github.com/groots-software-technologies/cn_metrics_remote_agent/raw/refs/heads/${env}/${OS}/${monitor_type}/install/${ARCH}.sh"
    elif [ "$action" == "uninstall" ]; then
        # URL for uninstallation script
        url="https://github.com/groots-software-technologies/cn_metrics_remote_agent/raw/refs/heads/${env}/${OS}/${monitor_type}/uninstall/${ARCH}.sh"
    else
        echo "Invalid action specified. Please use 'install' or 'uninstall'."
        exit 1
    fi
    
    echo "$url"
}
# Function to download and install or uninstall the agent
download_and_execute_agent_script() {
    local action="$1"
    local monitor_type="$2"
    local digital_key="$3"
    local env="$4"

    local environment="$env"
    if [ "$env" == "main" ]; then
        environment="prod"
    fi

    # Generate the URL for the script (development or production)
    local script_url
    script_url=$(generate_agent_script_url "$action" "$monitor_type" "$env")

    log_message "$BLUE" "Downloading script from $script_url"

    # Show progress bar during download using curl
    curl -LO --progress-bar "$script_url" | while read -r line; do
        # Handle the progress output if needed (you can add logging if necessary)
        log_message "$BLUE" "Downloading in progress..." # Optional progress message
    done

    # Check if the file downloaded correctly
    if [ ! -f "${script_url##*/}" ]; then
        log_message "$RED" "Error: Failed to download the script. The file does not exist."
        exit 1
    fi

    # Make the script executable
    chmod +x "${script_url##*/}"

    # Run the downloaded script
    if [ "$action" == "install" ]; then
        log_message "$YELLOW" "Running the installation script"
        ./"${script_url##*/}" -k "$digital_key" -e "$environment"
    elif [ "$action" == "uninstall" ]; then
        log_message "$YELLOW" "Running the uninstallation script"
        ./"${script_url##*/}"
    fi

    # Cleanup: Remove the downloaded agent script file
    rm -f "${script_url##*/}"
    log_message "$GREEN" "Script executed and removed."
}

# Main function to execute the script logic
main() {

    # Show help if arguments are incorrect or if help is explicitly requested
    if [ "${1}" = "--help" -o "${#}" -lt 4 ]; then
        log_message "$YELLOW" "Usage: $SCRIPTNAME -m [monitor_type] -a [install/uninstall] -k [DIGITAL_KEY]

        OPTION                               DESCRIPTION
        -----------------------------------------------------
        --help                               Help
        -m [monitor_type]                    Type of monitor to install (linux, apache, other)
        -a [install/uninstall]               Action to perform (install or uninstall)
        -k [DIGITAL_KEY]                     CloudNetra Metrics Digital Key (required for install action)
        -----------------------------------------------------"
        exit 0
    fi

    # Parse command-line arguments
    while getopts "m:a:k:e:" OPT; do
        case $OPT in
            m) MONITOR_TYPE="$OPTARG" ;;
            a) ACTION="$OPTARG" ;;
            k) DIGITAL_KEY="$OPTARG" ;;
            e) ENV="$OPTARG" ;;
            *)
                log_message "$RED" "Invalid argument. Please use -h for help."
                exit 3
                ;;
        esac
    done

    # If no environment is set, default to 'main'
    if [ -z "$ENV" ]; then
        ENV="main"
    fi

    # Set the environment and URLs
    set_environment

    # Validate the parameters
    if [ -z "$MONITOR_TYPE" ] || [ -z "$ACTION" ]; then
        log_message "$RED" "Error: Missing required parameters."
        exit 1
    fi

    # If the action is 'uninstall', skip the -k validation
    if [ "$ACTION" = "install" ] && [ -z "$DIGITAL_KEY" ]; then
        log_message "$RED" "Error: Missing required parameter -k (DIGITAL_KEY)."
        exit 1
    fi

    # Validate the action parameter
    if [ "$ACTION" != "install" ] && [ "$ACTION" != "uninstall" ]; then
        log_message "$RED" "Error: Invalid action specified. Please use 'install' or 'uninstall'."
        exit 1
    fi

    # Check if required tools are installed
    check_required_tools

    # Determine the OS and architecture
    check_os_architecture

    # Perform the chosen action (install or uninstall)
    download_and_execute_agent_script "$ACTION" "$MONITOR_TYPE" "$DIGITAL_KEY" "$ENV"
}

# Call the main function to execute the script
main "$@"
