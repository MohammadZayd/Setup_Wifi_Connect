#!/bin/bash                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     
# Improved WiFi Connect Installation Script with error handling and logging

# Set up logging
LOG_FILE="/var/log/wifi-connect-install.log"

# Ensure log file exists and is writable
if [ ! -f "$LOG_FILE" ]; then
    sudo touch "$LOG_FILE" || {
        echo "Failed to create log file at $LOG_FILE. Creating log in current directory instead."
        LOG_FILE="./wifi-connect-install.log"
        touch "$LOG_FILE" || {
            echo "Failed to create log file. Continuing without logging to file."
            LOG_FILE="/dev/null"
        }
    }
fi

# Ensure log file is writable
if [ -f "$LOG_FILE" ] && [ ! -w "$LOG_FILE" ] && [ "$LOG_FILE" != "/dev/null" ]; then
    sudo chmod 644 "$LOG_FILE" || {
        echo "Failed to make log file writable. Creating log in current directory instead."
        LOG_FILE="./wifi-connect-install.log"
        touch "$LOG_FILE" || {
            echo "Failed to create log file. Continuing without logging to file."
            LOG_FILE="/dev/null"
        }
    }
fi

# Set up logging with tee
exec > >(tee -a "$LOG_FILE") 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting WiFi Connect installation"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Log file: $LOG_FILE"

# Function for error handling
handle_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >&2
    exit 1
}

# Function to check if a service exists and is installed
check_service_exists() {
    systemctl list-unit-files | grep -q "$1"
    return $?
}

# Function to check if a service is active
check_service_active() {
    systemctl is-active --quiet "$1"
    return $?
}

# Update package lists
echo "$(date '+%Y-%m-%d %H:%M:%S') - Updating package lists"
sudo apt update -y || handle_error "Failed to update package lists"

# Check if dnsmasq is already installed
if dpkg -l | grep -q "^ii.*dnsmasq "; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - dnsmasq is already installed"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Installing dnsmasq"
    sudo apt install -y dnsmasq || handle_error "Failed to install dnsmasq"
fi

# Configure dnsmasq if port isn't already set
if grep -q "^$#$\?port=" /etc/dnsmasq.conf; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - dnsmasq port is already configured"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuring dnsmasq"
    sudo sed -i 's/^#\s*port=5353/port=53/' /etc/dnsmasq.conf || handle_error "Failed to configure dnsmasq port"
fi

# Check if dnsmasq service exists
if check_service_exists "dnsmasq.service"; then
    # Restart dnsmasq service only if it's active
    if check_service_active "dnsmasq.service"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Restarting dnsmasq service"
        sudo systemctl restart dnsmasq.service || handle_error "Failed to restart dnsmasq service"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - dnsmasq service is not active, no need to restart"
    fi

    # Stop dnsmasq service
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Stopping dnsmasq service"
    sudo systemctl stop dnsmasq.service || handle_error "Failed to stop dnsmasq service"

    # Disable dnsmasq service
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Disabling dnsmasq service"
    sudo systemctl disable dnsmasq.service || handle_error "Failed to disable dnsmasq service"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - dnsmasq service is not installed"
fi

# Check if systemd-resolved service exists
if check_service_exists "systemd-resolved.service"; then
    # Start systemd-resolved service
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting systemd-resolved service"
    sudo systemctl start systemd-resolved.service || handle_error "Failed to start systemd-resolved service"

    # Enable systemd-resolved service
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Enabling systemd-resolved service"
    sudo systemctl enable systemd-resolved.service || handle_error "Failed to enable systemd-resolved service"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: systemd-resolved service is not installed on this system"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - You may need to configure DNS resolution manually"
fi

# Create NetworkManager directory if it doesn't exist
echo "$(date '+%Y-%m-%d %H:%M:%S') - Creating NetworkManager configuration directory"
sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d || handle_error "Failed to create NetworkManager directory"

# Configure NetworkManager if not already configured
if [ -f "/etc/NetworkManager/dnsmasq-shared.d/disable.conf" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - NetworkManager already configured"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuring NetworkManager"
    echo -e "[main]\ndns=none\n\nport=0" | sudo tee /etc/NetworkManager/dnsmasq-shared.d/disable.conf || handle_error "Failed to configure NetworkManager"
fi

# Check if NetworkManager service exists before restarting
if check_service_exists "NetworkManager.service"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Restarting NetworkManager service"
    sudo systemctl restart NetworkManager.service || handle_error "Failed to restart NetworkManager service"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: NetworkManager service not found"
fi

# --- WiFi Connect Installation ---
WIFI_CONNECT_BIN="/usr/local/sbin/wifi-connect"
WIFI_CONNECT_UI_DIR="/usr/local/share/wifi-connect/ui"
WIFI_CONNECT_VERSION_TO_INSTALL="v4.11.83" # Define the version to install

WIFI_CONNECT_INSTALLED=false
UI_INSTALLED=false
TEMP_DIR=""
TEMP_UI_EXTRACT_DIR=""
PACKAGE="" # Initialize package variable

# Check if wifi-connect binary is already installed
if [ -f "$WIFI_CONNECT_BIN" ] && [ -x "$WIFI_CONNECT_BIN" ]; then
    INSTALLED_VERSION=$($WIFI_CONNECT_BIN --version 2>/dev/null || echo "unknown")
    echo "$(date '+%Y-%m-%d %H:%M:%S') - wifi-connect binary found at $WIFI_CONNECT_BIN (Version: $INSTALLED_VERSION)"
    # Add version comparison if you want to upgrade:
    # if [ "$INSTALLED_VERSION" == "$WIFI_CONNECT_VERSION_TO_INSTALL" ]; then
    WIFI_CONNECT_INSTALLED=true
    # else
    #   echo "$(date '+%Y-%m-%d %H:%M:%S') - Different version found. Will reinstall/upgrade."
    # fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - wifi-connect binary not found at $WIFI_CONNECT_BIN"
fi

# Check if wifi-connect UI is already installed
if [ -d "$WIFI_CONNECT_UI_DIR" ] && [ -n "$(ls -A "$WIFI_CONNECT_UI_DIR" 2>/dev/null)" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - wifi-connect UI found at $WIFI_CONNECT_UI_DIR"
    UI_INSTALLED=true
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - wifi-connect UI not found or directory is empty at $WIFI_CONNECT_UI_DIR"
fi

# If both are installed (and optionally version matches), exit
if $WIFI_CONNECT_INSTALLED && $UI_INSTALLED; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - wifi-connect and its UI are already installed and up-to-date."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation check completed."
    echo "You can now run '$WIFI_CONNECT_BIN' to set up your wireless connection."
    exit 0
fi

# Install wifi-connect binary if not installed (or version mismatch if implemented)
if ! $WIFI_CONNECT_INSTALLED; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Proceeding with wifi-connect binary installation."
    ARCH=$(uname -m)
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Detected architecture: $ARCH"

    if [ "$ARCH" = "x86_64" ]; then
        PACKAGE="wifi-connect-x86_64-unknown-linux-gnu.tar.gz"
    elif [ "$ARCH" = "aarch64" ]; then
        PACKAGE="wifi-connect-aarch64-unknown-linux-gnu.tar.gz"
    elif [ "$ARCH" = "armv7l" ]; then
        # Note: Please verify the exact package name for armv7l from Balena's releases.
        # This is an example, it could be -gnueabihf or similar.
        PACKAGE="wifi-connect-armv7-unknown-linux-gnueabihf.tar.gz"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Selected armv7 package: $PACKAGE. Ensure this matches your device."
    else
        handle_error "Unsupported architecture: $ARCH for wifi-connect binary"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WIFI_CONNECT_VERSION_TO_INSTALL: $WIFI_CONNECT_VERSION_TO_INSTALL"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - PACKAGE: $PACKAGE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Downloading wifi-connect package: $PACKAGE (version $WIFI_CONNECT_VERSION_TO_INSTALL)"
    sudo wget --progress=bar:force:noscroll -O "/tmp/$PACKAGE" -o "$LOG_FILE" "https://github.com/balena-os/wifi-connect/releases/download/$WIFI_CONNECT_VERSION_TO_INSTALL/$PACKAGE" || handle_error "Failed to download wifi-connect package"

    TEMP_DIR=$(mktemp -d)
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Extracting wifi-connect package to temporary directory $TEMP_DIR"
    # Assuming the tarball contains a top-level directory with the same name as the tarball (minus .tar.gz)
    # and wifi-connect is inside it. Or wifi-connect is at the root.
    # Use --strip-components=1 if wifi-connect is inside a single top-level folder in the archive.
    # Check the archive structure; for Balena's wifi-connect, it's usually directly in the archive or in a folder like 'wifi-connect'.
    # If 'wifi-connect' binary is at the root of the tar:
    # sudo tar -xzf "/tmp/$PACKAGE" -C "$TEMP_DIR" wifi-connect || handle_error "Failed to extract wifi-connect binary from package"
    # If it's inside a folder (e.g. wifi-connect-armv7-unknown-linux-gnueabihf/wifi-connect):
    sudo tar -xzf "/tmp/$PACKAGE" -C "$TEMP_DIR"  || handle_error "Failed to extract wifi-connect package (check --strip-components)"


    echo "$(date '+%Y-%m-%d %H:%M:%S') - Installing wifi-connect binary to $WIFI_CONNECT_BIN"
    sudo cp "$TEMP_DIR/wifi-connect" "$WIFI_CONNECT_BIN" || handle_error "Failed to install wifi-connect binary (is 'wifi-connect' directly in $TEMP_DIR after extraction?)"
    sudo chmod +x "$WIFI_CONNECT_BIN" || handle_error "Failed to set executable permissions for wifi-connect binary"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Cleaning up temporary files for wifi-connect binary"
    sudo rm -f "/tmp/$PACKAGE"
    sudo rm -rf "$TEMP_DIR"
    TEMP_DIR="" # Reset TEMP_DIR

    echo "$(date '+%Y-%m-%d %H:%M:%S') - wifi-connect binary installation finished."
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Skipping wifi-connect binary installation as it is already present (or version matches)."
fi

# Install wifi-connect UI if not installed
if ! $UI_INSTALLED; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Proceeding with wifi-connect UI installation."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Ensuring UI directory exists: $WIFI_CONNECT_UI_DIR"
    sudo mkdir -p "$WIFI_CONNECT_UI_DIR" || handle_error "Failed to create UI directory"

    UI_PACKAGE_FILENAME="wifi-connect-ui.tar.gz"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Downloading wifi-connect UI (version $WIFI_CONNECT_VERSION_TO_INSTALL)"
    sudo wget --progress=bar:force:noscroll -O "/tmp/$UI_PACKAGE_FILENAME" -o "$LOG_FILE" "https://github.com/balena-os/wifi-connect/releases/download/$WIFI_CONNECT_VERSION_TO_INSTALL/$UI_PACKAGE_FILENAME" || handle_error "Failed to download wifi-connect UI"

    TEMP_UI_EXTRACT_DIR=$(mktemp -d)
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Extracting UI files to $TEMP_UI_EXTRACT_DIR"
    sudo tar -xzf "/tmp/$UI_PACKAGE_FILENAME" -C "$TEMP_UI_EXTRACT_DIR" || handle_error "Failed to extract UI files"

    # The UI tarball usually extracts its content into a 'ui' subdirectory.
    # Copy the *contents* of this 'ui' subdirectory.
    if [ -d "$TEMP_UI_EXTRACT_DIR/ui" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Copying contents from extracted 'ui' subfolder to $WIFI_CONNECT_UI_DIR"
        sudo cp -r "$TEMP_UI_EXTRACT_DIR/ui/." "$WIFI_CONNECT_UI_DIR/" || handle_error "Failed to copy UI files to final destination"
    elif [ -f "$TEMP_UI_EXTRACT_DIR/index.html" ]; then # Fallback if files are at the root of tar
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Copying extracted files directly to $WIFI_CONNECT_UI_DIR"
        sudo cp -r "$TEMP_UI_EXTRACT_DIR/." "$WIFI_CONNECT_UI_DIR/" || handle_error "Failed to copy UI files to final destination (root)"
    else
        handle_error "Extracted UI content not found in expected structure ('ui' subfolder or root index.html)"
    fi


    echo "$(date '+%Y-%m-%d %H:%M:%S') - Cleaning up temporary UI files"
    sudo rm -f "/tmp/$UI_PACKAGE_FILENAME"
    sudo rm -rf "$TEMP_UI_EXTRACT_DIR"
    TEMP_UI_EXTRACT_DIR=""

    echo "$(date '+%Y-%m-%d %H:%M:%S') - wifi-connect UI installation finished."
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Skipping wifi-connect UI installation as it is already present."
fi


# Final verification
echo "$(date '+%Y-%m-%d %H:%M:%S') - Verifying wifi-connect installation"
if ! [ -x "$WIFI_CONNECT_BIN" ]; then
    handle_error "wifi-connect binary at $WIFI_CONNECT_BIN not found or not executable after installation process."
else
     echo "$(date '+%Y-%m-%d %H:%M:%S') - wifi-connect binary is available at $WIFI_CONNECT_BIN."
fi

if [ ! -d "$WIFI_CONNECT_UI_DIR" ] || [ -z "$(ls -A "$WIFI_CONNECT_UI_DIR" 2>/dev/null)" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: wifi-connect UI directory ($WIFI_CONNECT_UI_DIR) is missing or empty after installation process."
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - wifi-connect UI directory is present and appears populated."
fi


echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation process completed."
echo "You can now run '$WIFI_CONNECT_BIN' (or 'wifi-connect' if /usr/local/sbin is in your PATH) to set up your wireless connection."

exit 0