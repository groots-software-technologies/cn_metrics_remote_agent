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
LOGDIR="/var/log/cn_metrics/"
LOGFILE="$LOGDIR/$SCRIPTNAME.log"
BAR_SIZE=40
BAR_CHAR_DONE="#"
BAR_CHAR_TODO="-"
BAR_PERCENTAGE_SCALE=2

# Default environment (prod)
ENV="prod"

# Function to log messages
log_message() {
    while read -r line; do
        echo -e "\n[$(date +"%Y-%m-%dT%H:%M:%S,%N" | rev | cut -c 7- | rev)] [$SCRIPTNAME]: $line" | tee -a "$LOGFILE" 2>&1
    done
}

# Function to check required tools
check_required_tools() {
    local required_tools=("curl" "wget" "cut" "tar" "gzip" "sudo" "bc" "netstat")

    for tool in "${required_tools[@]}"; do
        type "$tool" &>/dev/null || {
            echo >&2 "This script requires the \"$tool\" package, but it's not installed. Aborting."
            exit 1
        }
    done
}
# Function to check for environment
set_environment() {
    # Check if the environment is set via -e flag
    if [ "$ENV" == "dev" ]; then
        API_URL="https://dev-app.cloudnetra.io"
    elif [ "$ENV" == "prod" ]; then
        API_URL="https://app.cloudnetra.io"
    elif [ "$ENV" == "local" ]; then
        API_URL="http://localhost:3004"
    else
        echo "Error: Invalid environment specified. Please use 'dev' or 'prod'."
        exit 1
    fi
}

# Function to retrieve the Machine ID
get_machine_id() {
    if [ -f /etc/machine-id ]; then
        MACHINE_ID=$(cat /etc/machine-id)
    elif [ -f /var/lib/dbus/machine-id ]; then
        MACHINE_ID=$(cat /var/lib/dbus/machine-id)
    elif command -v hostnamectl &>/dev/null; then
        MACHINE_ID=$(hostnamectl | grep "Machine ID" | awk '{print $3}')
    else
        echo "Error: Could not retrieve machine ID."
        exit 1
    fi

    # Ensure the machine ID is not empty
    if [ -z "$MACHINE_ID" ]; then
        echo "Error: Machine ID is empty. Could not retrieve a valid machine ID."
        exit 1
    fi
}

# Function to determine the OS and architecture
determine_os_and_arch() {
    if [ "$(uname)" == "Linux" ]; then
        OS="linux"
    else
        echo "This operating system is not supported. The supported operating systems are Linux and Darwin."
        exit 1
    fi

    if [ "$(uname -m)" == "x86_64" ]; then
        ARCH="amd64"
    elif [ "$(uname -m)" == "aarch64" ] || [ "$(uname -m)" == "arm64" ]; then
        ARCH="arm64"
    else
        echo "This machine architecture is not supported. The supported architectures are x86_64, aarch64, armv7."
        exit 1
    fi
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
    # Generate the URL for the script (development or production)
    local script_url
    script_url=$(generate_agent_script_url "$action" "$monitor_type" "$env")
    
    log_message <<<"Downloading script from $script_url"

    # Show progress bar during download using curl
    curl -LO --progress-bar "$script_url" | while read -r line; do
        # Handle the progress output if needed
        show_progress 100 100
    done
    
    # Check if the file downloaded correctly
    if [ ! -f "${script_url##*/}" ]; then
        log_message <<<"Error: Failed to download the script. The file does not exist."
        exit 1
    fi

    # Make the script executable
    chmod +x "${script_url##*/}"

    # Run the downloaded script
    if [ "$action" == "install" ]; then
        log_message <<<"Running the installation script"
        ./"${script_url##*/}" -t "$digital_key" -e "$env"
    elif [ "$action" == "uninstall" ]; then
        log_message <<<"Running the uninstallation script"
        ./"${script_url##*/}"
    fi

    # Cleanup: Remove the downloaded agent script file
    rm -f "${script_url##*/}"
    log_message <<<"Script executed and removed."
}

# Main function to execute the script logic
main() {
    # Check if the log directory exists, if not, create it
    if [ ! -d "$LOGDIR" ]; then
        mkdir -p "$LOGDIR"
    elif [ ! -f "$LOGFILE" ]; then
        touch "$LOGFILE"
    fi

    # Show help if arguments are incorrect or if help is explicitly requested
    if [ "${1}" = "--help" -o "${#}" -lt 4 ]; then
        echo -e "Usage: $SCRIPTNAME -m [monitor_type] -a [install/uninstall] -k [DIGITAL_KEY]

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
                echo "Invalid argument. Please use -h for help."
                exit 3
                ;;
        esac
    done

    # If no environment is set, default to 'prod'
    if [ -z "$ENV" ]; then
        ENV="prod"
    fi

    # Set the environment and URLs
    set_environment

    # Validate the parameters
    if [ -z "$MONITOR_TYPE" ] || [ -z "$ACTION" ]; then
        echo "Error: Missing required parameters."
        exit 1
    fi

    # If the action is 'uninstall', skip the -k validation
    if [ "$ACTION" != "uninstall" ] && [ -z "$DIGITAL_KEY" ]; then
        echo "Error: Missing required parameter -k (DIGITAL_KEY)."
        exit 1
    fi

    # Validate the action parameter
    if [ "$ACTION" != "install" ] && [ "$ACTION" != "uninstall" ]; then
        echo "Error: Invalid action specified. Please use 'install' or 'uninstall'."
        exit 1
    fi

    # Check if required tools are installed
    check_required_tools

    # Determine the OS and architecture
    determine_os_and_arch


    # Perform the chosen action (install or uninstall)
    download_and_execute_agent_script "$ACTION" "$MONITOR_TYPE" "$DIGITAL_KEY" "$ENV"

    # Final message
    echo "------------------------------------------------------"
    echo -e "\033[1;32mAgent operation completed successfully!\033[0m"
    echo "------------------------------------------------------"
}

# Call the main function to execute the script
main "$@"
