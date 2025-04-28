#!/bin/bash

RED='\e[0;31m'
GREEN='\e[1;32m'
BLUE='\e[0;36m'
YELLOW='\e[1;33m'
NC='\e[0m'

DB_VERSION=13
DB_USER='postgres'
DB_PASS=''
INSTALL_DIR='/root/hxsy'
DOWNLOAD_URL='https://mega.nz/file/z6AyGIaA#1OXGc4amedlwtNvknc-KC9im_B9nh0FeXO1Ns51Fvr0'
LOG_FILE="/tmp/ak_installer.log"

declare -A STATUS=(
    [ssh_service_checked]=false
    [postgresql_installed]=false
    [config_success]=false
    [db_creation_success]=false
    [sql_import_success]=false
    [download_success]=false
    [patch_success]=false
    [admin_creation_success]=false
    [grub_configured]=false
)

echo "Installation started at $(date)" > "$LOG_FILE"

log_message() {
    echo "[INFO] $(date): $1" >> "$LOG_FILE"
}

trap 'error_exit "An unexpected error occurred. Please check ${LOG_FILE} for details."' ERR

error_exit() {
    echo -e "\n${RED}[✗] ERROR: $1${NC}" | tee -a "$LOG_FILE"

    if [[ "$1" == *"apt-get update failed"* ]] || [[ "$1" == *"Failed to update package lists"* ]]; then
        echo -e "${YELLOW}[*] DEBUG: Checking relevant apt source files...${NC}" | tee -a "$LOG_FILE"
        if [ -d /etc/apt/sources.list.d ]; then
            echo -e "${YELLOW}--- Contents of /etc/apt/sources.list.d/ ---${NC}" | tee -a "$LOG_FILE"
            ls -l /etc/apt/sources.list.d/ >> "$LOG_FILE"
            grep -rE '^[[:space:]]*deb' /etc/apt/sources.list.d/ >> "$LOG_FILE" 2>&1
            grep -rE --color=never '^[[:space:]]*deb' /etc/apt/sources.list.d/
        fi
         if [ -f /etc/apt/sources.list ]; then
            echo -e "${YELLOW}--- Relevant lines from /etc/apt/sources.list ---${NC}" | tee -a "$LOG_FILE"
            grep -E '^[[:space:]]*deb' /etc/apt/sources.list >> "$LOG_FILE" 2>&1
            grep -E --color=never '^[[:space:]]*deb' /etc/apt/sources.list
        fi
    fi
    if [[ "$1" == *"Failed to modify SSH config"* ]] || [[ "$1" == *"Failed to restart SSH service"* ]]; then
         local ssh_config_file="/etc/ssh/sshd_config"
         if [ -f "$ssh_config_file" ]; then
             echo -e "${YELLOW}[*] DEBUG: Checking relevant lines from $ssh_config_file...${NC}" | tee -a "$LOG_FILE"
             grep -Ei --color=never '^\s*(PermitRootLogin|PasswordAuthentication)' "$ssh_config_file" | tee -a "$LOG_FILE"
         fi
    fi
    if [[ "$1" == *"Database import failed"* ]] || [[ "$1" == *"Failed to import SQL file"* ]]; then
        echo -e "${YELLOW}[*] DEBUG: Checking PostgreSQL connection and databases...${NC}" | tee -a "$LOG_FILE"
        if command -v psql &>/dev/null && [ -n "$DB_USER" ]; then
             sudo -H -u "$DB_USER" psql -l >> "$LOG_FILE" 2>&1
             echo -e "${YELLOW}--- List of databases (from psql -l): ---${NC}" | tee -a "$LOG_FILE"
             sudo -H -u "$DB_USER" psql -l | grep -E '^\s*(FFAccount|FFDB1|FFMember|postgres)'
        fi
    fi
    exit 1
}

retry_command() {
    local n=0
    local max=3
    local delay=5
    local cmd_output
    local return_code
    local command_str="$*"

    until [ $n -ge $max ]
    do
        echo -e "${BLUE}>> Attempting: $command_str (Attempt $((n+1))/$max)...${NC}"
        cmd_output=$("$@" 2>&1)
        return_code=$?

        log_message "Retry Attempt $((n+1))/$max: Command: '$command_str' | RC: $return_code | Output: $cmd_output"

        if [ $return_code -eq 0 ]; then
            echo -e "${GREEN}[✓] Command successful.${NC}"
            return 0
        fi

        n=$((n+1))
        echo -e "${YELLOW}[!] Notice: Command failed with exit code $return_code. Output below:${NC}"
        echo "$cmd_output"
        log_message "Command failed on attempt $n."

        if [ $n -lt $max ]; then
            echo -e "${YELLOW}[*] Retrying in $delay seconds...${NC}"
            sleep $delay
            delay=$((delay * 2))
        fi
    done

    echo -e "${RED}[✗] ERROR: Command failed after $max attempts: $command_str${NC}"
    log_message "Command '$command_str' failed definitively after $max attempts."
    return 1
}

check_disk_space() {
    local REQUIRED_SPACE=1048576
    local check_path
    check_path=$(dirname "$INSTALL_DIR")
    if [ ! -d "$check_path" ]; then
        check_path="/"
    fi

    local avail
    avail=$(df -k "$check_path" 2>/dev/null | tail -1 | awk '{print $4}')
    if [ -z "$avail" ]; then
        avail=$(df -k / 2>/dev/null | tail -1 | awk '{print $4}')
    fi

    if [ -z "$avail" ]; then
        error_exit "Could not determine available disk space."
    fi

    if [ "$avail" -lt "$REQUIRED_SPACE" ]; then
        error_exit "Insufficient disk space in '$check_path'. At least 1 GB free space is required (Available: ${avail} KB)."
    fi
    log_message "Disk space check passed: ${avail} KB available in '$check_path'."
}

check_memory() {
    local REQUIRED_MEMORY_KB=4194304
    local REQUIRED_MEMORY_GB=4
    local avail_mem_kb
    avail_mem_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local using_fallback=false
    if [ -z "$avail_mem_kb" ]; then
         avail_mem_kb=$(grep MemFree /proc/meminfo | awk '{print $2}')
         using_fallback=true
         echo -e "${YELLOW}[*] Notice: Could not find MemAvailable in /proc/meminfo, using MemFree as fallback (less accurate).${NC}"
         log_message "Using MemFree as fallback for memory check."
    fi

    local avail_mem_gb=$(awk "BEGIN {printf \"%.2f\", $avail_mem_kb / 1024 / 1024}")

    if [ "$avail_mem_kb" -lt "$REQUIRED_MEMORY_KB" ]; then
        echo -e "\n${YELLOW}[!] WARNING: Insufficient Memory Detected!${NC}"
        echo -e "         At least ${REQUIRED_MEMORY_GB} GB of available memory (RAM) is recommended for installation."
        if [ "$using_fallback" = true ]; then
             echo -e "         Your system currently reports approximately ${avail_mem_gb} GB free memory (estimated using MemFree)."
        else
             echo -e "         Your system currently has approximately ${avail_mem_gb} GB available memory (MemAvailable)."
        fi
        echo -e "         Continuing with low memory might lead to performance issues or installation failure."
        log_message "Warning: Insufficient memory detected. Required: ${REQUIRED_MEMORY_GB} GB, Available: ${avail_mem_gb} GB (Fallback: $using_fallback)."

        local continue_choice
        read -p "Do you want to continue anyway? [y/N]: " continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            error_exit "Installation aborted due to insufficient memory."
        else
            echo -e "${YELLOW}[*] Continuing despite low memory warning...${NC}"
            log_message "User chose to continue despite low memory warning."
        fi
    else
         echo -e "${GREEN}[✓] Memory check passed: ${avail_mem_gb} GB available (Required: ${REQUIRED_MEMORY_GB} GB).${NC}"
         log_message "Memory check passed: ${avail_mem_kb} KB available."
    fi
}

echo -e "${BLUE}
==================================================
          AK Installer Script
          Developer: Dulgan
==================================================${NC}"
log_message "Installer started."

display_recommendation() {
    echo -e "${YELLOW}
[*] Notice: It is highly recommended to run this installation on Debian 11 (Bullseye).
            Running on other systems (especially newer kernels like 6.x)
            may lead to compatibility issues or require manual adjustments (like GRUB).
${NC}"
    log_message "Displayed OS recommendation."
}

detect_os() {
    echo -e "${BLUE}>> Detecting operating system...${NC}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        OS_CODENAME=$(lsb_release -cs 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2)

        if [[ "$ID" == "ubuntu" ]]; then
            OS="Ubuntu"
            PKG_MANAGER="apt-get"
            SSH_PKG="openssh-server"
            SSH_CONFIG_FILE="/etc/ssh/sshd_config"
        elif [[ "$ID" == "debian" ]]; then
            OS="Debian"
            PKG_MANAGER="apt-get"
            SSH_PKG="openssh-server"
            SSH_CONFIG_FILE="/etc/ssh/sshd_config"
        elif [[ "$ID" == "centos" ]] || [[ "$ID_LIKE" == *"rhel"* ]] || [[ "$ID_LIKE" == *"fedora"* ]]; then
            if grep -q "Stream" /etc/os-release; then
                 OS="CentOS Stream"
            else
                 OS="CentOS/RHEL"
            fi
            if command -v dnf &> /dev/null; then
                PKG_MANAGER="dnf"
            elif command -v yum &> /dev/null; then
                PKG_MANAGER="yum"
            else
                error_exit "Cannot find 'dnf' or 'yum' package manager on this $OS system."
            fi
            SSH_PKG="openssh-server"
            SSH_CONFIG_FILE="/etc/ssh/sshd_config"
        else
            error_exit "Unsupported operating system ID: '$ID'. Supported families: Debian, Ubuntu, CentOS/RHEL."
        fi
        echo -e "${GREEN}[✓] Detected OS: $OS_NAME $OS_VERSION ($OS_CODENAME) - Using $PKG_MANAGER${NC}"
        log_message "OS detected: $OS ($OS_NAME $OS_VERSION / $OS_CODENAME) with package manager $PKG_MANAGER."
    else
        error_exit "Cannot detect operating system (missing /etc/os-release)."
    fi
}

check_sudo_command() {
    echo -e "${BLUE}>> Checking for 'sudo' command and privileges...${NC}"
    if ! command -v sudo &> /dev/null; then
        error_exit "'sudo' command not found. Please install sudo and ensure the current user has sudo privileges, then re-run the script."
    else
        if sudo -n true 2>/dev/null; then
             echo -e "${GREEN}[✓] 'sudo' is available and passwordless access seems configured.${NC}"
        else
            echo -e "${YELLOW}[*] Notice: 'sudo' is available but may require a password for subsequent commands.${NC}"
            if ! sudo -v; then
               error_exit "Failed to validate sudo privileges. Please check your sudo configuration or run the script with sudo."
            fi
            echo -e "${GREEN}[✓] Sudo access verified (password may be required once).${NC}"
        fi
        log_message "'sudo' command is available."
    fi
}

check_and_manage_ssh() {
    echo -e "${BLUE}>> Checking SSH service status and availability...${NC}"
    local ssh_service_name=""
    local ssh_installed=false

    if systemctl list-unit-files | grep -q "^sshd.service"; then
        ssh_service_name="sshd"
        ssh_installed=true
    elif systemctl list-unit-files | grep -q "^ssh.service"; then
        ssh_service_name="ssh"
        ssh_installed=true
    fi

    if [ "$ssh_installed" = false ]; then
        echo -e "\n${YELLOW}[!] Notice: SSH Server (sshd or ssh service) not found.${NC}"
        echo -e "         An SSH server is required to connect to this machine remotely using"
        echo -e "         tools like Putty, WinSCP, FileZilla, or terminal commands."
        log_message "SSH service not found."
        local install_ssh_choice
        read -p "Do you want to install the SSH server package ($SSH_PKG)? [Y/n]: " install_ssh_choice

        if [[ "$install_ssh_choice" =~ ^[Yy]$ ]] || [ -z "$install_ssh_choice" ]; then
            echo -e "${BLUE}>> Attempting to install $SSH_PKG...${NC}"
            if [ "$PKG_MANAGER" = 'apt-get' ]; then
                 retry_command sudo apt-get -qq update || echo -e "${YELLOW}[!] Warning: Failed to update package lists before SSH install attempt.${NC}"
            fi
            if retry_command sudo "$PKG_MANAGER" -y -qq install "$SSH_PKG"; then
                echo -e "${GREEN}[✓] Successfully installed $SSH_PKG.${NC}"
                log_message "Installed $SSH_PKG successfully."
                if systemctl list-unit-files | grep -q "^sshd.service"; then
                    ssh_service_name="sshd"
                    ssh_installed=true
                elif systemctl list-unit-files | grep -q "^ssh.service"; then
                    ssh_service_name="ssh"
                    ssh_installed=true
                else
                     echo -e "${RED}[✗] ERROR: Installed $SSH_PKG, but could not find sshd.service or ssh.service afterwards.${NC}"
                     log_message "Error: Installed $SSH_PKG but service file not found."
                     STATUS[ssh_service_checked]=false
                     return
                fi
            else
                echo -e "${RED}[✗] ERROR: Failed to install SSH server package ($SSH_PKG). SSH access might not be available.${NC}"
                log_message "Error: Failed to install SSH package $SSH_PKG."
                STATUS[ssh_service_checked]=false
                return
            fi
        else
            echo -e "${YELLOW}[!] Warning: Skipping SSH server installation as requested. Remote access via SSH might not be possible.${NC}"
            log_message "User skipped SSH server installation."
            STATUS[ssh_service_checked]=false
            return
        fi
    fi

    echo -e "${BLUE}>> Managing SSH service: ${ssh_service_name}...${NC}"
    local needs_action=false
    if ! systemctl is-active --quiet "$ssh_service_name"; then
        echo -e "${YELLOW}[*] Notice: SSH service ($ssh_service_name) is not active.${NC}"
        needs_action=true
    fi
    if ! systemctl is-enabled --quiet "$ssh_service_name"; then
        echo -e "${YELLOW}[*] Notice: SSH service ($ssh_service_name) is not enabled to start on boot.${NC}"
        needs_action=true
    fi

    if [ "$needs_action" = true ]; then
        echo -e "${BLUE}>> Attempting to enable and start SSH service ($ssh_service_name)...${NC}"
        if ! sudo systemctl enable "$ssh_service_name"; then
            echo -e "${YELLOW}[!] Warning: Failed to enable SSH service $ssh_service_name.${NC}"
        else
             echo -e "${GREEN}[✓] SSH service $ssh_service_name enabled.${NC}"
        fi
        if ! sudo systemctl start "$ssh_service_name"; then
            echo -e "${RED}[✗] ERROR: Failed to start SSH service $ssh_service_name. Check SSH configuration and logs ('sudo journalctl -u $ssh_service_name').${NC}"
            log_message "Failed to start SSH service $ssh_service_name."
            STATUS[ssh_service_checked]=false
            return
        else
             echo -e "${GREEN}[✓] SSH service $ssh_service_name started/activated.${NC}"
        fi
        log_message "Enabled and started SSH service $ssh_service_name."
    else
        echo -e "${GREEN}[✓] SSH service ($ssh_service_name) is active and enabled.${NC}"
        log_message "SSH service $ssh_service_name is active and enabled."
    fi

    echo -e "${BLUE}>> Checking SSH configuration for root login with password...${NC}"
    if [ ! -f "$SSH_CONFIG_FILE" ]; then
        echo -e "${YELLOW}[!] Warning: SSH config file ($SSH_CONFIG_FILE) not found. Cannot check/configure root login.${NC}"
        log_message "Warning: SSH config file $SSH_CONFIG_FILE not found."
        STATUS[ssh_service_checked]=true
        return
    fi

    local permit_root_ok=false
    local password_auth_ok=false
    local config_needs_change=false

    if grep -qE "^\s*PermitRootLogin\s+yes\s*$" "$SSH_CONFIG_FILE"; then
        permit_root_ok=true
    fi
    if grep -qE "^\s*PasswordAuthentication\s+yes\s*$" "$SSH_CONFIG_FILE"; then
        password_auth_ok=true
    fi

    if [ "$permit_root_ok" = true ] && [ "$password_auth_ok" = true ]; then
        echo -e "${GREEN}[✓] SSH configuration already allows root login with password.${NC}"
        log_message "SSH config already allows root login with password."
    else
        echo -e "${YELLOW}[*] Notice: SSH configuration needs adjustment for root login with password.${NC}"
        config_needs_change=true
    fi

    if [ "$config_needs_change" = true ]; then
        echo -e "${BLUE}>> Attempting to modify $SSH_CONFIG_FILE to allow root login with password...${NC}"
        local backup_ts
        backup_ts=$(date +%F_%T)
        sudo cp "$SSH_CONFIG_FILE" "$SSH_CONFIG_FILE.bak.$backup_ts" || error_exit "Failed to backup $SSH_CONFIG_FILE."
        log_message "Backed up $SSH_CONFIG_FILE to $SSH_CONFIG_FILE.bak.$backup_ts"

        if ! $permit_root_ok; then
            echo -e "${BLUE}   - Setting PermitRootLogin to yes...${NC}"
            sudo sed -i -E '/^\s*#?\s*PermitRootLogin\s+/d' "$SSH_CONFIG_FILE" || error_exit "Failed to remove existing PermitRootLogin lines."
            echo "PermitRootLogin yes" | sudo tee -a "$SSH_CONFIG_FILE" > /dev/null || error_exit "Failed to add PermitRootLogin yes."
            log_message "Set PermitRootLogin yes in $SSH_CONFIG_FILE."
        fi

        if ! $password_auth_ok; then
             echo -e "${BLUE}   - Setting PasswordAuthentication to yes...${NC}"
             sudo sed -i -E '/^\s*#?\s*PasswordAuthentication\s+/d' "$SSH_CONFIG_FILE" || error_exit "Failed to remove existing PasswordAuthentication lines."
             echo "PasswordAuthentication yes" | sudo tee -a "$SSH_CONFIG_FILE" > /dev/null || error_exit "Failed to add PasswordAuthentication yes."
             log_message "Set PasswordAuthentication yes in $SSH_CONFIG_FILE."
        fi

        echo -e "${BLUE}>> Restarting SSH service ($ssh_service_name) to apply configuration changes...${NC}"
        if ! sudo systemctl restart "$ssh_service_name"; then
            echo -e "${RED}[✗] ERROR: Failed to restart SSH service ($ssh_service_name) after config change. Check logs ('sudo journalctl -u $ssh_service_name').${NC}"
            echo -e "${YELLOW}[!] Warning: Configuration changes were made, but service restart failed. Manual check required.${NC}"
            log_message "Error: Failed to restart SSH service $ssh_service_name after config change."
            STATUS[ssh_service_checked]=false
            return
        else
            echo -e "${GREEN}[✓] SSH service restarted successfully.${NC}"
            log_message "SSH service $ssh_service_name restarted after config change."
        fi
    fi

    STATUS[ssh_service_checked]=true
    echo -e "${GREEN}[✓] SSH service check and configuration complete.${NC}"
}


check_disk_space
check_memory

configure_locales() {
    echo -e "${BLUE}>> Configuring system locales to en_US.UTF-8...${NC}"
    log_message "Starting locale configuration."
    local REQUIRED_LOCALES=("en_US.UTF-8 UTF-8" "C.UTF-8 UTF-8")
    local DEFAULT_LOCALE="en_US.UTF-8"

    if [ "$OS" = 'Debian' ] || [ "$OS" = 'Ubuntu' ]; then
        if ! dpkg -l | grep -qw locales; then
            echo -e "${BLUE}>> Installing 'locales' package...${NC}"
            retry_command sudo apt-get -qq install -y locales || error_exit "Failed to install 'locales' package."
        else
            echo -e "${GREEN}[✓] 'locales' package is already installed.${NC}"
        fi

        sudo cp /etc/locale.gen /etc/locale.gen.bak.$(date +%F_%T) || echo -e "${YELLOW}[!] Warning: Could not backup /etc/locale.gen.${NC}"

        local locales_changed=false
        for locale_line in "${REQUIRED_LOCALES[@]}"; do
            local locale_name=$(echo "$locale_line" | awk '{print $1}')
            if grep -q "^\s*#\?\s*${locale_name}" /etc/locale.gen; then
                 if grep -q "^\s*#\s*${locale_name}" /etc/locale.gen; then
                     echo -e "${BLUE}>> Enabling locale $locale_name in /etc/locale.gen...${NC}"
                     sudo sed -i -E "s/^\s*#\s*(${locale_name}\s+.*)/\1/g" /etc/locale.gen || error_exit "Failed to enable locale $locale_name in /etc/locale.gen."
                     locales_changed=true
                 else
                     echo -e "${GREEN}[✓] Locale $locale_name already enabled in /etc/locale.gen.${NC}"
                 fi
            else
                 echo -e "${BLUE}>> Adding and enabling locale $locale_line to /etc/locale.gen...${NC}"
                 echo "$locale_line" | sudo tee -a /etc/locale.gen > /dev/null || error_exit "Failed to add locale $locale_line to /etc/locale.gen."
                 locales_changed=true
            fi
        done

        if [ "$locales_changed" = true ]; then
            echo -e "${BLUE}>> Generating locales...${NC}"
            sudo locale-gen || error_exit "Locale generation failed (locale-gen)."
            log_message "Regenerated locales."
        else
            echo -e "${GREEN}[✓] Locales already configured in /etc/locale.gen, no regeneration needed.${NC}"
        fi

        echo -e "${BLUE}>> Setting default system locale to $DEFAULT_LOCALE...${NC}"
        sudo update-locale LANG="$DEFAULT_LOCALE" LC_ALL="$DEFAULT_LOCALE" || error_exit "Failed to set default locale using update-locale."
        export LANG="$DEFAULT_LOCALE"
        export LC_ALL="$DEFAULT_LOCALE"

    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "RHEL"* ]]; then
         echo -e "${BLUE}>> Checking/Installing 'glibc-langpack-en' on $OS...${NC}"
         if ! rpm -q glibc-langpack-en &>/dev/null; then
             retry_command sudo "$PKG_MANAGER" -y -q install glibc-langpack-en || error_exit "Failed to install glibc-langpack-en."
         else
             echo -e "${GREEN}[✓] 'glibc-langpack-en' is installed.${NC}"
         fi

         if ! locale -a | grep -q -i "en_US.utf8"; then
             echo -e "${YELLOW}[!] Warning: en_US.UTF-8 locale not found after installing langpack. Manual check might be needed.${NC}"
             log_message "Warning: en_US.UTF-8 locale not found after installing langpack."
         else
             echo -e "${GREEN}[✓] Locale en_US.UTF-8 is available.${NC}"
         fi

         echo -e "${BLUE}>> Setting default system locale to $DEFAULT_LOCALE using localectl...${NC}"
         sudo localectl set-locale LANG="$DEFAULT_LOCALE" || error_exit "Failed to set default locale using localectl."
         export LANG="$DEFAULT_LOCALE"
         export LC_ALL="$DEFAULT_LOCALE"
    fi

    echo -e "${BLUE}>> Verifying current locale settings:${NC}"
    locale
    log_message "Locale configuration completed. Current LANG=${LANG}, LC_ALL=${LC_ALL}"
    echo -e "${GREEN}[✓] Locale configuration completed.${NC}"
}


install_ubuntu_dependencies() {
    echo -e "${BLUE}>> Installing 32-bit compatibility libraries for Debian/Ubuntu...${NC}"
    if ! dpkg --print-foreign-architectures | grep -q i386; then
        echo -e "${BLUE}>> Adding i386 architecture...${NC}"
        sudo dpkg --add-architecture i386 || error_exit "Failed to add i386 architecture."
        echo -e "${BLUE}>> Running apt-get update after adding architecture...${NC}"
        retry_command sudo apt-get -qq update || error_exit "Failed to update package list after adding i386 architecture."
    fi
    retry_command sudo apt-get -qq install -y libc6:i386 lib32gcc-s1 lib32stdc++6 || error_exit "Failed to install 32-bit compatibility libraries (libc6:i386 lib32gcc-s1 lib32stdc++6)."
    echo -e "${GREEN}[✓] 32-bit compatibility libraries installed.${NC}"
    log_message "32-bit compatibility libraries installed for Debian/Ubuntu."
}

install_centos_dependencies() {
    echo -e "${BLUE}>> Installing 32-bit compatibility libraries for CentOS/RHEL...${NC}"
    local core_libs_installed=true
    retry_command sudo "$PKG_MANAGER" -y -q install glibc.i686 libstdc++.i686 || {
        echo -e "${RED}[✗] ERROR: Failed to install core 32-bit compatibility libraries (glibc.i686, libstdc++.i686). This might cause issues.${NC}"
        core_libs_installed=false
        log_message "ERROR: Failed to install core 32-bit libs (glibc.i686, libstdc++.i686)."
    }

    if [ "$core_libs_installed" = true ]; then
         echo -e "${GREEN}[✓] Core 32-bit compatibility libraries (glibc.i686, libstdc++.i686) installed.${NC}"
         log_message "Core 32-bit compatibility libraries installed for CentOS/RHEL."
    fi

    echo -e "${BLUE}>> Attempting to install optional 'compat-libstdc++-33.i686'...${NC}"
    if ! sudo "$PKG_MANAGER" -y -q install compat-libstdc++-33.i686; then
        echo -e "${YELLOW}[*] Notice: Optional package 'compat-libstdc++-33.i686' not found or failed to install. This is often expected on newer systems (RHEL/CentOS 8+) and may not be required.${NC}"
        log_message "Optional package compat-libstdc++-33.i686 not installed (likely not available)."
    else
        echo -e "${GREEN}[✓] Optional package 'compat-libstdc++-33.i686' installed.${NC}"
        log_message "Optional package compat-libstdc++-33.i686 installed."
    fi

    echo -e "${GREEN}[✓] 32-bit compatibility libraries installation process finished.${NC}"
}

install_packages() {
    echo -e "${BLUE}>> Installing necessary base packages...${NC}"
    local packages_to_install=()
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        packages_to_install=("wget" "pwgen" "gnupg" "unzip" "ca-certificates")
    elif [ "$PKG_MANAGER" = 'dnf' ] || [ "$PKG_MANAGER" = 'yum' ]; then
        packages_to_install=("wget" "pwgen" "gnupg2" "unzip")
    fi

    local missing_packages=()
    for pkg in "${packages_to_install[@]}"; do
        if [ "$PKG_MANAGER" = 'apt-get' ]; then
            if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
                missing_packages+=("$pkg")
            fi
        elif [ "$PKG_MANAGER" = 'dnf' ] || [ "$PKG_MANAGER" = 'yum' ]; then
             if ! rpm -q "$pkg" &>/dev/null; then
                 if [[ "$pkg" == "gnupg2" ]] && rpm -q gnupg &>/dev/null; then
                     echo -e "${GREEN}[✓] Package 'gnupg' found instead of 'gnupg2', assuming sufficient.${NC}"
                 else
                    missing_packages+=("$pkg")
                 fi
            fi
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo -e "${BLUE}>> Installing missing base packages: ${missing_packages[*]}...${NC}"
        retry_command sudo "$PKG_MANAGER" -y -qq install "${missing_packages[@]}" || error_exit "Failed to install required base packages."
        log_message "Installed base packages: ${missing_packages[*]}"
    else
        echo -e "${GREEN}[✓] All required base packages are already installed.${NC}"
    fi
}


check_and_install_megatools() {
    echo -e "${BLUE}>> Checking/Installing 'megatools'...${NC}"
    if command -v megadl &> /dev/null; then
        echo -e "${GREEN}[✓] 'megatools' (megadl command) is already installed.${NC}"
        log_message "megatools already installed."
        return 0
    fi

    echo -e "${BLUE}>> Attempting to install 'megatools'...${NC}"
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        retry_command sudo "$PKG_MANAGER" -y -qq install megatools || error_exit "Failed to install megatools using apt-get."
    elif [ "$PKG_MANAGER" = 'dnf' ] || [ "$PKG_MANAGER" = 'yum' ]; then
        echo -e "${BLUE}>> Trying to install 'megatools' using $PKG_MANAGER. May require EPEL or Raven repository.${NC}"
        if ! sudo "$PKG_MANAGER" -y -q install megatools; then
             echo -e "${YELLOW}[*] Notice: Direct installation failed. Checking EPEL/Raven...${NC}"
             if ! rpm -q epel-release &>/dev/null && [[ "$OS" == "CentOS"* || "$OS" == "RHEL"* ]]; then
                 echo -e "${BLUE}>> Installing EPEL repository...${NC}"
                 retry_command sudo "$PKG_MANAGER" -y -q install epel-release || echo -e "${YELLOW}[!] Warning: Failed to install EPEL repository. megatools might not be available.${NC}"
             fi
             if ! rpm -q raven-release &>/dev/null && [[ "$OS_VERSION" == "9" ]]; then
                 echo -e "${BLUE}>> Installing Raven repository for EL9...${NC}"
                 local install_cmd="yum"
                 if command -v dnf &> /dev/null; then install_cmd="dnf"; fi
                 retry_command sudo $install_cmd install -y https://pkgs.dyn.su/el9/base/x86_64/raven-release.el9.noarch.rpm || echo -e "${YELLOW}[!] Warning: Failed to install Raven repository. megatools might not be available.${NC}"
             fi
             echo -e "${BLUE}>> Retrying 'megatools' installation after checking repositories...${NC}"
             retry_command sudo "$PKG_MANAGER" -y -qq install megatools || error_exit "Failed to install megatools even after checking EPEL/Raven repositories."
        fi
    fi

    if ! command -v megadl &> /dev/null; then
        error_exit "megatools installation failed or 'megadl' command not found."
    fi
    echo -e "${GREEN}[✓] 'megatools' installed successfully.${NC}"
    log_message "megatools installed."
}


check_and_install_xxd() {
    echo -e "${BLUE}>> Checking/Installing 'xxd'...${NC}"
    if command -v xxd &> /dev/null; then
        echo -e "${GREEN}[✓] 'xxd' command is already installed.${NC}"
        log_message "'xxd' command verified."
        return 0
    fi

    echo -e "${BLUE}>> 'xxd' not found. Attempting to install...${NC}"
    local xxd_package=""
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        if apt-cache show xxd &>/dev/null; then
             xxd_package="xxd"
        else
             xxd_package="vim-common"
        fi
    elif [ "$PKG_MANAGER" = 'dnf' ] || [ "$PKG_MANAGER" = 'yum' ]; then
        xxd_package="vim-common"
    fi

    if [ -n "$xxd_package" ]; then
        echo -e "${BLUE}>> Installing package '$xxd_package' to provide 'xxd'...${NC}"
        retry_command sudo "$PKG_MANAGER" -y -qq install "$xxd_package" || error_exit "Failed to install '$xxd_package' (for xxd)."
    else
        error_exit "Could not determine package providing 'xxd' for this OS."
    fi

    if ! command -v xxd &> /dev/null; then
        error_exit "'xxd' installation failed or command still not found."
    fi
    echo -e "${GREEN}[✓] 'xxd' installed successfully.${NC}"
    log_message "'xxd' command installed via $xxd_package."
}

verify_essential_commands() {
    echo -e "${BLUE}>> Verifying essential commands are present...${NC}"
    local ESSENTIAL_COMMANDS=("wget" "pwgen" "gpg" "unzip" "megadl" "xxd" "psql" "createdb")
    local ALL_FOUND=true
    for cmd in "${ESSENTIAL_COMMANDS[@]}"; do
        if [[ "$cmd" == "gpg" ]] && ! command -v gpg &>/dev/null && command -v gpg2 &>/dev/null; then
             echo -e "${GREEN}  [✓] Command 'gpg2' found (sufficient for gpg).${NC}"
             continue
        fi
        if [[ "$cmd" == "megadl" ]] && ! command -v megadl &>/dev/null; then
            echo -e "${RED}  [✗] Command '$cmd' is MISSING.${NC}"
            ALL_FOUND=false
        elif ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}  [✗] Command '$cmd' is MISSING.${NC}"
            ALL_FOUND=false
        else
             echo -e "${GREEN}  [✓] Command '$cmd' is available.${NC}"
        fi
    done

    if [ "$ALL_FOUND" = false ]; then
        error_exit "One or more essential commands are missing after installation attempts. Check logs."
    else
        echo -e "${GREEN}[✓] All essential commands verified.${NC}"
        log_message "Essential commands verified."
    fi
}


check_postgresql_version() {
    echo -e "${BLUE}>> Checking PostgreSQL installation...${NC}"
    if command -v psql &> /dev/null; then
        local INSTALLED_VERSION_FULL
        INSTALLED_VERSION_FULL=$(psql -V | awk '{print $3}')
        local INSTALLED_VERSION_MAJOR
        INSTALLED_VERSION_MAJOR=$(echo "$INSTALLED_VERSION_FULL" | cut -d '.' -f1)

        echo -e "${BLUE}>> Detected PostgreSQL version: $INSTALLED_VERSION_FULL${NC}"
        log_message "Detected PostgreSQL version: $INSTALLED_VERSION_FULL"

        if [ "$INSTALLED_VERSION_MAJOR" != "$DB_VERSION" ]; then
            echo -e "${YELLOW}[!] Notice: Installed PostgreSQL major version ($INSTALLED_VERSION_MAJOR) does not match required version ($DB_VERSION).${NC}"
            local choice
            read -p "Do you want to attempt removing version $INSTALLED_VERSION_FULL and install version $DB_VERSION? [y/N]: " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}>> Attempting to remove existing PostgreSQL installation...${NC}"
                if [ "$PKG_MANAGER" = 'apt-get' ]; then
                    sudo systemctl stop postgresql || echo -e "${YELLOW}[!] Warning: Failed to stop postgresql service (maybe not running?).${NC}"
                    retry_command sudo apt-get -qq remove --purge "postgresql-$INSTALLED_VERSION_MAJOR" postgresql-client-common postgresql-common || error_exit "Failed to remove PostgreSQL packages."
                    retry_command sudo apt-get -qq autoremove --purge || echo -e "${YELLOW}[!] Warning: Autoremove after PostgreSQL removal failed or did nothing.${NC}"
                    sudo rm -rf "/etc/postgresql/$INSTALLED_VERSION_MAJOR/"
                    sudo rm -rf "/var/lib/postgresql/$INSTALLED_VERSION_MAJOR/"
                    echo -e "${GREEN}[✓] Existing PostgreSQL version removed.${NC}"
                elif [ "$PKG_MANAGER" = 'dnf' ] || [ "$PKG_MANAGER" = 'yum' ]; then
                    sudo systemctl stop "postgresql-$INSTALLED_VERSION_MAJOR" || echo -e "${YELLOW}[!] Warning: Failed to stop postgresql-$INSTALLED_VERSION_MAJOR service.${NC}"
                    retry_command sudo "$PKG_MANAGER" -y -q remove "postgresql$INSTALLED_VERSION_MAJOR*" || error_exit "Failed to remove PostgreSQL packages."
                    retry_command sudo "$PKG_MANAGER" -y -q autoremove || echo -e "${YELLOW}[!] Warning: Autoremove after PostgreSQL removal failed or did nothing.${NC}"
                    sudo rm -rf "/var/lib/pgsql/$INSTALLED_VERSION_MAJOR/"
                    echo -e "${GREEN}[✓] Existing PostgreSQL version removed.${NC}"
                fi
                log_message "Removed existing PostgreSQL version $INSTALLED_VERSION_FULL."
                install_postgresql
            else
                error_exit "Aborted: PostgreSQL version mismatch. Required: $DB_VERSION, Found: $INSTALLED_VERSION_MAJOR."
            fi
        else
            echo -e "${GREEN}[✓] Correct PostgreSQL major version ($DB_VERSION) is already installed.${NC}"
            STATUS[postgresql_installed]=true
        fi
    else
        echo -e "${BLUE}>> PostgreSQL does not appear to be installed. Proceeding with installation...${NC}"
        install_postgresql
    fi
    log_message "PostgreSQL version check completed."
}


install_postgresql() {
    if [ "${STATUS[postgresql_installed]}" = true ]; then
         echo -e "${GREEN}[✓] PostgreSQL version $DB_VERSION already marked as installed; skipping installation steps.${NC}"
         return 0
    fi
    if command -v psql &> /dev/null; then
         local INSTALLED_VERSION_MAJOR
         INSTALLED_VERSION_MAJOR=$(psql -V | awk '{print $3}' | cut -d '.' -f1)
         if [ "$INSTALLED_VERSION_MAJOR" == "$DB_VERSION" ]; then
              echo -e "${GREEN}[✓] PostgreSQL version $DB_VERSION found; skipping installation.${NC}"
              STATUS[postgresql_installed]=true
              local SERVICE_NAME
              if [ "$OS" = 'Debian' ] || [ "$OS" = 'Ubuntu' ]; then SERVICE_NAME="postgresql"; else SERVICE_NAME="postgresql-$DB_VERSION"; fi
              sudo systemctl enable "$SERVICE_NAME" --now || echo -e "${YELLOW}[!] Warning: Could not enable/start existing PostgreSQL service $SERVICE_NAME.${NC}"
              return 0
         fi
    fi

    echo -e "${BLUE}>> Installing PostgreSQL $DB_VERSION...${NC}"
    if [ "$OS" = 'Debian' ] || [ "$OS" = 'Ubuntu' ]; then
        local PGDG_LIST_FILE="/etc/apt/sources.list.d/pgdg.list"
        local PGDG_GPG_KEY_FILE="/etc/apt/trusted.gpg.d/postgresql.gpg"

        if [ -f "$PGDG_LIST_FILE" ]; then
            echo -e "${YELLOW}[*] Notice: Removing existing PostgreSQL source list file ($PGDG_LIST_FILE) to ensure clean setup.${NC}"
            sudo rm -f "$PGDG_LIST_FILE" || error_exit "Failed to remove existing $PGDG_LIST_FILE file."
            log_message "Removed existing $PGDG_LIST_FILE"
        fi
        if [ -f "$PGDG_GPG_KEY_FILE" ]; then
            echo -e "${YELLOW}[*] Notice: Removing existing PostgreSQL GPG key file ($PGDG_GPG_KEY_FILE).${NC}"
            sudo rm -f "$PGDG_GPG_KEY_FILE" || error_exit "Failed to remove existing PostgreSQL GPG key."
            log_message "Removed existing PostgreSQL GPG key file."
        fi
        sudo apt-key del ACCC4CF8 >/dev/null 2>&1 || true

        echo -e "${BLUE}>> Adding PostgreSQL GPG key...${NC}"
        wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o "$PGDG_GPG_KEY_FILE" || error_exit "Failed to add PostgreSQL GPG key using gpg."
        log_message "Added PostgreSQL GPG key to $PGDG_GPG_KEY_FILE."

        echo -e "${BLUE}>> Adding PostgreSQL repository source list...${NC}"
        local codename
        codename=$(lsb_release -cs 2>/dev/null)
        if [ -z "$codename" ]; then
             echo -e "${YELLOW}[!] Warning: 'lsb_release -cs' failed. Trying to get codename from /etc/os-release.${NC}"
             codename=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2)
             if [ -z "$codename" ]; then
                 error_exit "Could not determine OS codename automatically. Cannot add PostgreSQL repository."
             fi
             echo -e "${BLUE}>> Using codename '$codename' from /etc/os-release.${NC}"
        fi
        echo "deb [signed-by=$PGDG_GPG_KEY_FILE] http://apt.postgresql.org/pub/repos/apt/ ${codename}-pgdg main" | sudo tee "$PGDG_LIST_FILE" > /dev/null || error_exit "Failed to create PostgreSQL source list file ($PGDG_LIST_FILE)."
        log_message "Created $PGDG_LIST_FILE with content: deb [signed-by=$PGDG_GPG_KEY_FILE] http://apt.postgresql.org/pub/repos/apt/ ${codename}-pgdg main"

        echo -e "${BLUE}>> Updating package lists after adding PostgreSQL repo...${NC}"
        if ! retry_command sudo apt-get -qq update; then
             echo -e "${RED}[✗] DEBUG: apt-get update failed. Contents of $PGDG_LIST_FILE:${NC}"
             sudo cat "$PGDG_LIST_FILE"
             echo -e "${RED}[✗] DEBUG: Listing files in /etc/apt/sources.list.d/:${NC}"
             ls -la /etc/apt/sources.list.d/
             error_exit "Failed to update package lists after adding PostgreSQL repository (see logs and output above)."
        fi
        log_message "Package lists updated successfully after adding PostgreSQL repo."

        echo -e "${BLUE}>> Installing postgresql-$DB_VERSION packages...${NC}"
        retry_command sudo apt-get -qq install -y "postgresql-$DB_VERSION" "postgresql-client-$DB_VERSION" || error_exit "Failed to install PostgreSQL $DB_VERSION packages."
        log_message "Installed postgresql-$DB_VERSION and postgresql-client-$DB_VERSION."

        echo -e "${BLUE}>> Enabling and starting PostgreSQL service...${NC}"
        sudo systemctl enable postgresql || echo -e "${YELLOW}[!] Warning: Failed to enable PostgreSQL service.${NC}"
        sudo systemctl start postgresql || error_exit "Failed to start PostgreSQL service."
        log_message "Enabled and started PostgreSQL service."


    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "RHEL"* ]]; then
        echo -e "${BLUE}>> Adding PostgreSQL repository for $OS...${NC}"
        local el_version
        el_version=$(rpm -E %{rhel})
        if [ -z "$el_version" ]; then
             error_exit "Could not determine RHEL/CentOS major version."
        fi
        local pg_repo_url="https://download.postgresql.org/pub/repos/yum/reporpms/EL-${el_version}-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
        echo -e "${BLUE}>> Using repository RPM: $pg_repo_url${NC}"
        retry_command sudo "$PKG_MANAGER" install -y -q "$pg_repo_url" || error_exit "Failed to add PostgreSQL repository RPM."
        log_message "Added PostgreSQL YUM/DNF repository."

        if command -v dnf &> /dev/null; then
            echo -e "${BLUE}>> Disabling built-in PostgreSQL module (if exists)...${NC}"
            sudo dnf -q module disable postgresql -y || echo -e "${YELLOW}[*] Notice: Failed to disable PostgreSQL module or module not found (may be okay).${NC}"
            log_message "Attempted to disable built-in PostgreSQL DNF module."
        fi

        echo -e "${BLUE}>> Installing PostgreSQL $DB_VERSION server and contrib packages...${NC}"
        retry_command sudo "$PKG_MANAGER" install -y -q "postgresql$DB_VERSION-server" "postgresql$DB_VERSION-contrib" || error_exit "Failed to install PostgreSQL $DB_VERSION packages."
        log_message "Installed postgresql$DB_VERSION-server and postgresql$DB_VERSION-contrib."

        local PGDATA_DIR="/var/lib/pgsql/$DB_VERSION/data"
        if [ ! -f "$PGDATA_DIR/PG_VERSION" ]; then
             echo -e "${BLUE}>> Initializing PostgreSQL database cluster...${NC}"
             sudo "/usr/pgsql-$DB_VERSION/bin/postgresql-$DB_VERSION-setup" initdb || error_exit "Failed to initialize PostgreSQL database cluster."
             log_message "Initialized PostgreSQL database cluster."
        else
             echo -e "${GREEN}[✓] PostgreSQL database cluster already initialized.${NC}"
        fi

        local SERVICE_NAME="postgresql-$DB_VERSION"
        echo -e "${BLUE}>> Enabling and starting $SERVICE_NAME service...${NC}"
        sudo systemctl enable "$SERVICE_NAME" || echo -e "${YELLOW}[!] Warning: Failed to enable $SERVICE_NAME service.${NC}"
        sudo systemctl start "$SERVICE_NAME" || error_exit "Failed to start $SERVICE_NAME service."
        log_message "Enabled and started $SERVICE_NAME service."
    fi

    if command -v psql &> /dev/null; then
        local INSTALLED_VERSION_MAJOR
        INSTALLED_VERSION_MAJOR=$(psql -V | awk '{print $3}' | cut -d '.' -f1)
        if [ "$INSTALLED_VERSION_MAJOR" == "$DB_VERSION" ]; then
            STATUS[postgresql_installed]=true
            echo -e "${GREEN}[✓] PostgreSQL $DB_VERSION installed and verified successfully.${NC}"
        else
             error_exit "PostgreSQL installation completed, but the installed version ($INSTALLED_VERSION_MAJOR) does not match the required version ($DB_VERSION)."
        fi
    else
        error_exit "PostgreSQL installation command finished, but 'psql' command is still not found. Installation likely failed."
    fi
    log_message "PostgreSQL installation completed and verified."
}


configure_postgresql() {
    if [ "${STATUS[postgresql_installed]}" = false ]; then
        error_exit "Cannot configure PostgreSQL because installation status is false."
    fi

    echo -e "${BLUE}>> Configuring PostgreSQL settings (listen_addresses and pg_hba.conf)...${NC}"
    local PG_CONF=""
    local PG_HBA=""
    local SERVICE_NAME=""
    local PG_DATA_DIR=""

    if [ "$OS" = 'Debian' ] || [ "$OS" = 'Ubuntu' ]; then
        PG_CONF="/etc/postgresql/$DB_VERSION/main/postgresql.conf"
        PG_HBA="/etc/postgresql/$DB_VERSION/main/pg_hba.conf"
        PG_DATA_DIR="/var/lib/postgresql/$DB_VERSION/main"
        SERVICE_NAME="postgresql"
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "RHEL"* ]]; then
        PG_DATA_DIR="/var/lib/pgsql/$DB_VERSION/data"
        PG_CONF="$PG_DATA_DIR/postgresql.conf"
        PG_HBA="$PG_DATA_DIR/pg_hba.conf"
        SERVICE_NAME="postgresql-$DB_VERSION"
    else
         error_exit "Cannot determine PostgreSQL config paths for OS: $OS"
    fi

    if [ ! -f "$PG_CONF" ]; then error_exit "PostgreSQL config file not found: $PG_CONF"; fi
    if [ ! -f "$PG_HBA" ]; then error_exit "PostgreSQL HBA file not found: $PG_HBA"; fi

    local config_changed=false

    if ! grep -q "^\s*listen_addresses\s*=\s*'\*'" "$PG_CONF"; then
        echo -e "${BLUE}>> Setting listen_addresses = '*' in $PG_CONF...${NC}"
        sudo sed -i -E "s/^\s*(#\s*)?listen_addresses\s*=.*/listen_addresses = '*'/" "$PG_CONF" || error_exit "Failed to set listen_addresses = '*'."
        if ! grep -q "^\s*listen_addresses\s*=\s*'\*'" "$PG_CONF"; then
             echo "listen_addresses = '*'" | sudo tee -a "$PG_CONF" > /dev/null
        fi
        config_changed=true
        log_message "Set listen_addresses = '*' in $PG_CONF."
    else
        echo -e "${GREEN}[✓] listen_addresses already set to '*' in $PG_CONF.${NC}"
    fi

    local hba_entry="host    all             all             0.0.0.0/0               md5"
    local hba_marker="# Added by AK Installer for remote access"
    if ! grep -qF "$hba_marker" "$PG_HBA"; then
        echo -e "${BLUE}>> Adding rule for md5 access from all IPs in $PG_HBA...${NC}"
        echo -e "\n$hba_marker\n$hba_entry" | sudo tee -a "$PG_HBA" > /dev/null || error_exit "Failed to update $PG_HBA."
        config_changed=true
        log_message "Added host all all 0.0.0.0/0 md5 rule to $PG_HBA."
    else
        echo -e "${GREEN}[✓] Remote access rule already present in $PG_HBA (marked by installer).${NC}"
    fi

    if [ "$config_changed" = true ]; then
        echo -e "${BLUE}>> Restarting PostgreSQL service ($SERVICE_NAME) to apply changes...${NC}"
        if sudo systemctl reload "$SERVICE_NAME"; then
            echo -e "${GREEN}[✓] PostgreSQL service reloaded successfully.${NC}"
            log_message "Reloaded PostgreSQL service $SERVICE_NAME."
        else
            echo -e "${YELLOW}[*] Notice: Reload failed, attempting full restart of $SERVICE_NAME...${NC}"
            if ! sudo systemctl restart "$SERVICE_NAME"; then
                 sudo systemctl status "$SERVICE_NAME" --no-pager -l
                 error_exit "Failed to restart PostgreSQL service ($SERVICE_NAME) after configuration changes."
            fi
             echo -e "${GREEN}[✓] PostgreSQL service restarted successfully.${NC}"
             log_message "Restarted PostgreSQL service $SERVICE_NAME."
        fi
    else
        echo -e "${GREEN}[✓] No configuration changes detected; PostgreSQL restart not required.${NC}"
    fi

    sleep 5
    if ! sudo -u "$DB_USER" psql -c '\q' > /dev/null 2>&1; then
         echo -e "${YELLOW}[!] Warning: Could not connect to PostgreSQL as user '$DB_USER' after configuration. Check service status and logs.${NC}"
         log_message "Warning: Post-configuration connection check failed."
    else
         echo -e "${GREEN}[✓] Basic connection test to PostgreSQL successful.${NC}"
    fi

    STATUS[config_success]=true
    echo -e "${GREEN}[✓] PostgreSQL configuration completed.${NC}"
    log_message "PostgreSQL configuration completed."
}


secure_postgresql() {
    if [ "${STATUS[config_success]}" = false ]; then
        error_exit "Cannot secure PostgreSQL because configuration status is false."
    fi

    echo -e "${BLUE}>> Setting password for PostgreSQL user '$DB_USER'...${NC}"
    DB_PASS=$(pwgen -s -B -N 1 32)
    if [ -z "$DB_PASS" ]; then
        error_exit "Failed to generate PostgreSQL password using pwgen."
    fi
    log_message "Generated PostgreSQL password for user $DB_USER."

    local DB_PASS_SQL_ESCAPED=${DB_PASS//\'/\'\'}
    local sql_command="ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS_SQL_ESCAPED}';"

    echo -e "${BLUE}>> Applying password change...${NC}"
    if ! sudo -u "$DB_USER" psql -q -c "$sql_command"; then
        error_exit "Failed to set password for PostgreSQL user '$DB_USER'. Command attempted: psql -c \"$sql_command\""
    fi

    log_message "Successfully set password for PostgreSQL user '$DB_USER'. Password: [REDACTED]"
    echo -e "${GREEN}[✓] Password for PostgreSQL user '$DB_USER' set successfully.${NC}"
    echo -e "${YELLOW}[!] IMPORTANT: The generated PostgreSQL password is: $DB_PASS${NC}"
    echo -e "${YELLOW}             Please save this password securely! It will be needed for configuration files.${NC}"
}


setup_firewall_rules() {
    echo -e "${BLUE}>> Configuring firewall rules...${NC}"
    local PORTS=("5567" "5568" "6543" "7654" "7777" "7878" "10021" "10022")
    local PG_PORT="5432"
    local SSH_PORT="22"
    local firewall_configured=false

    if command -v ufw &> /dev/null; then
        echo -e "${BLUE}>> Detected UFW firewall.${NC}"
        if ! sudo ufw status | grep -qw active; then
            echo -e "${YELLOW}[*] Notice: UFW is inactive. Enabling UFW...${NC}"
            sudo ufw allow "$SSH_PORT"/tcp >/dev/null 2>&1
            sudo ufw --force enable || error_exit "Failed to enable UFW."
            log_message "Enabled UFW firewall."
        fi

        if ! sudo ufw status | grep -qw "$SSH_PORT/tcp"; then
             echo -e "${BLUE}  >> Allowing SSH port $SSH_PORT/tcp...${NC}"
             sudo ufw allow "$SSH_PORT"/tcp >/dev/null 2>&1 || error_exit "Failed to allow port $SSH_PORT via UFW."
             echo -e "${GREEN}  [✓] Port $SSH_PORT/tcp allowed.${NC}"
        else
             echo -e "${GREEN}  [✓] Port $SSH_PORT/tcp already allowed.${NC}"
        fi

        if ! sudo ufw status | grep -qw "$PG_PORT/tcp"; then
            echo -e "${BLUE}  >> Allowing PostgreSQL port $PG_PORT/tcp...${NC}"
            sudo ufw allow "$PG_PORT"/tcp >/dev/null 2>&1 || error_exit "Failed to allow port $PG_PORT via UFW."
            echo -e "${GREEN}  [✓] Port $PG_PORT/tcp allowed.${NC}"
        else
            echo -e "${GREEN}  [✓] Port $PG_PORT/tcp already allowed.${NC}"
        fi

        for port in "${PORTS[@]}"; do
            if ! sudo ufw status | grep -qw "$port/tcp"; then
                echo -e "${BLUE}  >> Allowing game server port $port/tcp...${NC}"
                sudo ufw allow "$port"/tcp >/dev/null 2>&1 || error_exit "Failed to allow port $port via UFW."
                 echo -e "${GREEN}  [✓] Port $port/tcp allowed.${NC}"
            else
                echo -e "${GREEN}  [✓] Port $port/tcp already allowed.${NC}"
            fi
        done
        echo -e "${GREEN}[✓] UFW rules configured.${NC}"
        log_message "UFW rules configured for SSH ($SSH_PORT), PostgreSQL ($PG_PORT), and game ports."
        firewall_configured=true

    elif command -v firewall-cmd &> /dev/null; then
        echo -e "${BLUE}>> Detected Firewalld.${NC}"
        if ! sudo systemctl is-active --quiet firewalld; then
             echo -e "${YELLOW}[*] Notice: Firewalld is not active. Starting and enabling Firewalld...${NC}"
             sudo systemctl enable firewalld --now || error_exit "Failed to start or enable Firewalld."
             log_message "Started and enabled Firewalld."
             sleep 3
        fi

        if ! sudo firewall-cmd --permanent --query-service=ssh >/dev/null 2>&1; then
             echo -e "${BLUE}  >> Adding SSH service permanently...${NC}"
             sudo firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || error_exit "Failed to allow SSH service via Firewalld."
             echo -e "${GREEN}  [✓] SSH service added.${NC}"
        else
            echo -e "${GREEN}  [✓] SSH service already allowed permanently.${NC}"
        fi

        if ! sudo firewall-cmd --permanent --query-port="$PG_PORT/tcp" >/dev/null 2>&1; then
            echo -e "${BLUE}  >> Allowing PostgreSQL port $PG_PORT/tcp permanently...${NC}"
            sudo firewall-cmd --permanent --add-port="$PG_PORT"/tcp >/dev/null 2>&1 || error_exit "Failed to allow port $PG_PORT via Firewalld."
            echo -e "${GREEN}  [✓] Port $PG_PORT/tcp added.${NC}"
        else
            echo -e "${GREEN}  [✓] Port $PG_PORT/tcp already allowed permanently.${NC}"
        fi

        for port in "${PORTS[@]}"; do
             if ! sudo firewall-cmd --permanent --query-port="$port/tcp" >/dev/null 2>&1; then
                echo -e "${BLUE}  >> Allowing game server port $port/tcp permanently...${NC}"
                sudo firewall-cmd --permanent --add-port="$port"/tcp >/dev/null 2>&1 || error_exit "Failed to allow port $port via Firewalld."
                echo -e "${GREEN}  [✓] Port $port/tcp added.${NC}"
            else
                echo -e "${GREEN}  [✓] Port $port/tcp already allowed permanently.${NC}"
            fi
        done

        echo -e "${BLUE}>> Reloading Firewalld to apply changes...${NC}"
        sudo firewall-cmd --reload >/dev/null 2>&1 || error_exit "Failed to reload Firewalld."
        echo -e "${GREEN}[✓] Firewalld rules configured and reloaded.${NC}"
        log_message "Firewalld rules configured for SSH service, PostgreSQL ($PG_PORT), and game ports."
        firewall_configured=true
    fi

    if [ "$firewall_configured" = false ]; then
        echo -e "${YELLOW}[!] Warning: No supported firewall (UFW or Firewalld) detected or managed.${NC}"
        echo -e "${YELLOW}           Please ensure ports ${SSH_PORT}/tcp, ${PG_PORT}/tcp and ${PORTS[*]}/tcp are allowed manually if a firewall is active.${NC}"
        log_message "No supported firewall detected or configured."
    fi
}


handle_existing_install_dir() {
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}[!] WARNING: Installation directory '$INSTALL_DIR' already exists.${NC}"
        echo -e "${BLUE}Choose an action:${NC}"
        echo -e "${BLUE}  [1] Delete the existing directory and continue (ALL DATA INSIDE WILL BE LOST).${NC}"
        echo -e "${BLUE}  [2] Rename the existing directory (append '-old-TIMESTAMP') and continue.${NC}"
        echo -e "${BLUE}  [3] Abort installation.${NC}"
        local dir_choice
        read -p "Enter your choice [1/2/3]: " dir_choice

        case "$dir_choice" in
            1)
                echo -e "${RED}>> Deleting existing directory: $INSTALL_DIR...${NC}"
                if [[ "$INSTALL_DIR" == "/root/hxsy" ]]; then
                     local confirm_delete
                     read -p "$(echo -e ${RED}ARE YOU SURE you want to delete $INSTALL_DIR? This cannot be undone. [y/N]: ${NC})" confirm_delete
                     if [[ ! "$confirm_delete" =~ ^[Yy]$ ]]; then
                         error_exit "Aborted deletion of $INSTALL_DIR."
                     fi
                fi
                rm -rf "$INSTALL_DIR" || error_exit "Failed to delete $INSTALL_DIR. Check permissions."
                echo -e "${GREEN}[✓] Directory '$INSTALL_DIR' deleted.${NC}"
                log_message "Deleted existing installation directory: $INSTALL_DIR."
                mkdir -p "$INSTALL_DIR" || error_exit "Failed to recreate installation directory: $INSTALL_DIR."
                chmod 755 "$INSTALL_DIR"
                ;;
            2)
                local timestamp
                timestamp=$(date +%Y%m%d_%H%M%S)
                local new_dir="${INSTALL_DIR}-old-${timestamp}"
                echo -e "${BLUE}>> Renaming '$INSTALL_DIR' to '$new_dir'...${NC}"
                mv "$INSTALL_DIR" "$new_dir" || error_exit "Failed to rename '$INSTALL_DIR' to '$new_dir'. Check permissions or if it's in use."
                echo -e "${GREEN}[✓] Directory renamed to '$new_dir'.${NC}"
                log_message "Renamed existing installation directory '$INSTALL_DIR' to '$new_dir'."
                mkdir -p "$INSTALL_DIR" || error_exit "Failed to create installation directory: $INSTALL_DIR."
                 chmod 755 "$INSTALL_DIR"
                ;;
            3)
                error_exit "Aborted installation due to existing directory."
                ;;
            *)
                error_exit "Invalid choice. Please run the script again."
                ;;
        esac
    else
         echo -e "${BLUE}>> Creating installation directory: $INSTALL_DIR...${NC}"
         mkdir -p "$INSTALL_DIR" || error_exit "Failed to create installation directory: $INSTALL_DIR."
         chmod 755 "$INSTALL_DIR"
         log_message "Created installation directory: $INSTALL_DIR."
    fi
}


download_server_files() {
    echo -e "${BLUE}>> Downloading server files from MEGA...${NC}"
    local download_path="/root/hxsy.zip"
    mkdir -p "$(dirname "$download_path")"

    echo -e "${BLUE}>> Starting download (this may take some time)...${NC}"
    if ! retry_command megadl "$DOWNLOAD_URL" --path "$download_path"; then
        error_exit "Failed to download '$DOWNLOAD_URL' after multiple attempts. Check network or URL."
    fi

    if [ -f "$download_path" ] && [ -s "$download_path" ]; then
        STATUS[download_success]=true
        local file_size
        file_size=$(du -sh "$download_path" | cut -f1)
        echo -e "${GREEN}[✓] Server files downloaded successfully (${file_size}) to $download_path.${NC}"
        log_message "Server files downloaded successfully to $download_path (${file_size})."
    else
        rm -f "$download_path"
        error_exit "Download of '$download_path' failed or resulted in an empty file."
    fi
}

extract_server_files() {
    local download_path="/root/hxsy.zip"
    echo -e "${BLUE}>> Extracting server files from $download_path to $INSTALL_DIR...${NC}"

    if [ ! -f "$download_path" ]; then
        error_exit "Cannot extract: Downloaded file '$download_path' not found."
    fi
    if [ ! -d "$INSTALL_DIR" ]; then
        error_exit "Cannot extract: Installation directory '$INSTALL_DIR' not found."
    fi

    unzip -qo "$download_path" -d "$INSTALL_DIR"
    local unzip_rc=$?

    if [ $unzip_rc -ne 0 ]; then
        echo -e "${RED}[✗] ERROR: Unzip command failed with return code $unzip_rc.${NC}"
        if ! unzip -tq "$download_path"; then
             error_exit "Extraction failed. The downloaded file '$download_path' might be corrupted."
        else
             error_exit "Extraction failed. Check permissions for '$INSTALL_DIR' or disk space."
        fi
    fi

    echo -e "${BLUE}>> Setting permissions (755) for extracted files in $INSTALL_DIR...${NC}"
    chmod -R 755 "$INSTALL_DIR" || error_exit "Failed to set permissions on extracted files in '$INSTALL_DIR'."

    echo -e "${BLUE}>> Removing downloaded archive $download_path...${NC}"
    rm -f "$download_path" || echo -e "${YELLOW}[!] Warning: Failed to remove downloaded archive '$download_path'.${NC}"

    echo -e "${GREEN}[✓] Server files extracted and permissions set.${NC}"
    log_message "Server files extracted to $INSTALL_DIR and permissions set."
}


download_start_stop_scripts() {
    echo -e "${BLUE}>> Downloading start/stop scripts from GitHub...${NC}"
    local start_script_url="https://raw.githubusercontent.com/MrDulgan/AKF/main/start"
    local stop_script_url="https://raw.githubusercontent.com/MrDulgan/AKF/main/stop"
    local start_script_path="$INSTALL_DIR/start"
    local stop_script_path="$INSTALL_DIR/stop"

    if [ ! -d "$INSTALL_DIR" ]; then
        error_exit "Cannot download scripts: Installation directory '$INSTALL_DIR' not found."
    fi

    echo -e "${BLUE}>> Downloading 'start' script...${NC}"
    if ! retry_command wget -q -O "$start_script_path" "$start_script_url"; then
        error_exit "Failed to download start script from '$start_script_url' after multiple attempts."
    fi

    echo -e "${BLUE}>> Downloading 'stop' script...${NC}"
    if ! retry_command wget -q -O "$stop_script_path" "$stop_script_url"; then
        error_exit "Failed to download stop script from '$stop_script_url' after multiple attempts."
    fi

    echo -e "${BLUE}>> Setting execute permissions for start/stop scripts...${NC}"
    chmod +x "$start_script_path" "$stop_script_path" || error_exit "Failed to set execute permissions on start/stop scripts."

    echo -e "${GREEN}[✓] Start and stop scripts downloaded and configured.${NC}"
    log_message "Start/stop scripts downloaded and made executable in $INSTALL_DIR."
}


import_databases() {
    if [ "${STATUS[config_success]}" = false ] || [ -z "$DB_PASS" ]; then
        error_exit "Cannot import databases: PostgreSQL not configured or password not set."
    fi

    echo -e "${BLUE}>> Creating and importing databases...${NC}"
    local DATABASES=("FFAccount" "FFDB1" "FFMember")
    local SQL_DIR="$INSTALL_DIR/SQL"

    if [ ! -d "$SQL_DIR" ]; then
        error_exit "Database import failed: SQL directory '$SQL_DIR' not found."
    fi

    export PGPASSWORD="$DB_PASS"

    echo -e "${BLUE}>> Creating databases: ${DATABASES[*]}...${NC}"
    local db_creation_failed=false
    for DB in "${DATABASES[@]}"; do
        echo -e "${BLUE}   >> Preparing database '$DB'...${NC}"
        log_message "Preparing database $DB (dropping if exists, then creating)."
        if sudo -H -u "$DB_USER" psql -lqt | cut -d \| -f 1 | grep -qw "$DB"; then
            echo -e "${YELLOW}     [*] Database '$DB' exists. Dropping...${NC}"
            if dropdb --version > /dev/null 2>&1; then
                 sudo -H -u "$DB_USER" dropdb "$DB" || error_exit "Failed to drop existing database '$DB' using dropdb."
            else
                 sudo -H -u "$DB_USER" psql -q -c "DROP DATABASE \"$DB\";" || error_exit "Failed to drop existing database '$DB' using psql."
            fi
             log_message "Dropped existing database '$DB'."
        else
             echo -e "${GREEN}     [✓] Database '$DB' does not exist. Skipping drop.${NC}"
        fi

        echo -e "${BLUE}   >> Creating database '$DB'...${NC}"
        if ! sudo -H -u "$DB_USER" createdb -O "$DB_USER" -T template0 "$DB"; then
            echo -e "${RED}[✗] ERROR: Failed to create database '$DB'.${NC}"
            db_creation_failed=true
            break
        fi
        echo -e "${GREEN}   [✓] Database '$DB' created successfully.${NC}"
        log_message "Database '$DB' created successfully."
    done

    if [ "$db_creation_failed" = true ]; then
        unset PGPASSWORD
        error_exit "Database creation failed. Check PostgreSQL logs and permissions."
    fi
    STATUS[db_creation_success]=true
    log_message "Databases created: ${DATABASES[*]}"

    echo -e "${BLUE}>> Importing data into databases...${NC}"
    local sql_import_failed=false
    for DB in "${DATABASES[@]}"; do
        local SQL_FILE="$SQL_DIR/$DB.bak"
        if [ ! -f "$SQL_FILE" ]; then
            echo -e "${RED}[✗] ERROR: SQL file '$SQL_FILE' for database '$DB' not found. Skipping import for this DB.${NC}"
            log_message "Error: SQL file '$SQL_FILE' not found. Skipping import for $DB."
            sql_import_failed=true
            continue
        fi
        local file_size_human
        file_size_human=$(du -sh "$SQL_FILE" | cut -f1)

        echo -e "${BLUE}   >> Importing '$SQL_FILE' (${file_size_human}) into database '$DB'... (This might take a while)${NC}"
        log_message "Importing '$SQL_FILE' into database '$DB'."
        if ! sudo -H -u "$DB_USER" psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$SQL_FILE" >> "$LOG_FILE" 2>&1; then
            echo -e "${RED}[✗] ERROR: Failed to import SQL file '$SQL_FILE' into database '$DB'. Check $LOG_FILE for details.${NC}"
            log_message "Error: Failed to import '$SQL_FILE' into database '$DB'."
            sql_import_failed=true
        else
            echo -e "${GREEN}   [✓] Successfully imported data into '$DB'.${NC}"
            log_message "Successfully imported data into '$DB'."
        fi
    done

    unset PGPASSWORD

    if [ "$sql_import_failed" = true ]; then
        echo -e "${YELLOW}[!] Warning: One or more SQL imports failed or were skipped due to missing files. Check logs.${NC}"
        log_message "Warning: One or more SQL imports failed or were skipped."
        STATUS[sql_import_success]=false
    else
        STATUS[sql_import_success]=true
        echo -e "${GREEN}[✓] Databases created and imported successfully.${NC}"
        log_message "Databases imported successfully."
    fi
}


remove_sql_directory() {
    local sql_dir="$INSTALL_DIR/SQL"
    if [ -d "$sql_dir" ]; then
        echo -e "${BLUE}>> Removing SQL directory '$sql_dir' after import...${NC}"
        rm -rf "$sql_dir" || error_exit "Failed to remove SQL directory '$sql_dir'."
        echo -e "${GREEN}[✓] SQL directory removed.${NC}"
        log_message "SQL directory removed."
    else
        echo -e "${BLUE}>> SQL directory '$sql_dir' not found; skipping removal.${NC}"
        log_message "SQL directory not found, skipping removal."
    fi
}

patch_server_files() {
    echo -e "${BLUE}>> Patching server configuration and binary files...${NC}"

    if [ -z "$IP" ] || [ -z "$DB_PASS" ]; then
        error_exit "Cannot patch files: Server IP or DB Password is not set."
    fi

    echo -e "${BLUE}>> Patching database password in setup.ini files...${NC}"
    local setup_files=("$INSTALL_DIR/setup.ini" "$INSTALL_DIR/GatewayServer/setup.ini")
    local setup_patched=false
    local DBPASS_ESCAPED
    DBPASS_ESCAPED=$(printf '%s' "$DB_PASS" | sed 's:[/\&]:\\&:g')

    for file_path in "${setup_files[@]}"; do
        if [[ -f "$file_path" ]]; then
            if grep -q "xxxxxxxx" "$file_path"; then
                 echo -e "${BLUE}   >> Patching $file_path...${NC}"
                 if command -v perl &> /dev/null; then
                      perl -pi -e "s/xxxxxxxx/$DBPASS_ESCAPED/g" "$file_path"
                 else
                      sed "s/xxxxxxxx/$DBPASS_ESCAPED/g" "$file_path" > "$file_path.tmp" && mv "$file_path.tmp" "$file_path"
                 fi
                 if [ $? -ne 0 ]; then
                     rm -f "$file_path.tmp"
                     error_exit "Failed to patch password in $file_path."
                 fi
                 setup_patched=true
                 echo -e "${GREEN}   [✓] Patched $file_path successfully.${NC}"
            else
                 echo -e "${YELLOW}   [*] Placeholder 'xxxxxxxx' not found in $file_path. Assuming already patched or not needed.${NC}"
            fi
        else
            echo -e "${YELLOW}[*] Notice: File $file_path not found; skipping patch.${NC}"
        fi
    done
    if [ "$setup_patched" = true ]; then log_message "Patched database password in setup.ini files."; fi

    echo -e "${BLUE}>> Patching IP addresses and offsets in binary files...${NC}"

    local IP_ARRAY
    IFS='.' read -r -a IP_ARRAY <<< "$IP"
    if [ ${#IP_ARRAY[@]} -ne 4 ]; then error_exit "Invalid IP address format: $IP"; fi
    local PATCHIP_HEX
    PATCHIP_HEX=$(printf '\\x%02X\\x%02X\\x%02X' "${IP_ARRAY[0]}" "${IP_ARRAY[1]}" "${IP_ARRAY[2]}")
    local ORIGINAL_IP_HEX_PATTERN='\xc0\xa8\x64'
    log_message "Patching binaries: Replacing IP pattern ${ORIGINAL_IP_HEX_PATTERN} with ${PATCHIP_HEX} (derived from $IP)"

    local mission_server_bin="$INSTALL_DIR/MissionServer/MissionServer"
    local mission_offset=2750792
    local mission_original_hex="01346228"
    local mission_new_hex_val="01404908"
    local mission_new_bin_val

    if command -v perl &> /dev/null; then
        mission_new_bin_val=$(perl -e "print pack('H*', '$mission_new_hex_val')")
    else
         mission_new_bin_val=$(echo "$mission_new_hex_val" | sed 's/\(..\)/\\x\1/g')
         if [[ "$mission_new_bin_val" != '\x01\x40\x49\x08' ]]; then
              error_exit "Failed to convert hex '$mission_new_hex_val' to binary using fallback method."
         fi
    fi

    if [[ -f "$mission_server_bin" ]]; then
        echo -e "${BLUE}   >> Checking patch requirement for $mission_server_bin at offset $mission_offset...${NC}"
        local current_hex_val
        current_hex_val=$(xxd -seek "$mission_offset" -l 4 -p "$mission_server_bin" | tr -d '\n')

        if [[ "$current_hex_val" == "$mission_original_hex" ]]; then
            echo -e "${BLUE}   >> Patching $mission_server_bin at offset $mission_offset with hex $mission_new_hex_val...${NC}"
            printf "%b" "$mission_new_bin_val" | dd of="$mission_server_bin" bs=1 seek="$mission_offset" count=4 conv=notrunc status=none
            if [ $? -ne 0 ]; then
                 error_exit "Failed to patch $mission_server_bin at offset $mission_offset using dd."
            fi
            echo -e "${GREEN}   [✓] Patched $mission_server_bin offset successfully.${NC}"
            log_message "Patched $mission_server_bin at offset $mission_offset."
        elif [[ "$current_hex_val" == "$mission_new_hex_val" ]]; then
             echo -e "${GREEN}   [✓] No patch needed for $mission_server_bin offset (already patched).${NC}"
             log_message "Skipped patching $mission_server_bin offset (already done)."
        else
            echo -e "${YELLOW}[!] Warning: Unexpected hex value '$current_hex_val' found at offset $mission_offset in $mission_server_bin. Expected '$mission_original_hex'. Skipping patch.${NC}"
            log_message "Warning: Unexpected hex value '$current_hex_val' at offset $mission_offset in $mission_server_bin. Expected '$mission_original_hex'."
        fi
    else
        echo -e "${YELLOW}[*] Notice: File $mission_server_bin not found; skipping offset patch.${NC}"
    fi

    local mission_server_sed_target="$INSTALL_DIR/MissionServer/MissionServer"
    if [[ -f "$mission_server_sed_target" ]]; then
         echo -e "${BLUE}   >> Applying specific sed patch to $mission_server_sed_target...${NC}"
         cp "$mission_server_sed_target" "$mission_server_sed_target.bak.$$"
         sed -i 's/\x44\x24\x0c\x28\x62\x34/\x44\x24\x0c\x08\x49\x40/g' "$mission_server_sed_target"
         if [ $? -ne 0 ]; then
             mv "$mission_server_sed_target.bak.$$" "$mission_server_sed_target"
             error_exit "Failed to apply sed patch to $mission_server_sed_target."
         fi
         rm "$mission_server_sed_target.bak.$$"
         echo -e "${GREEN}   [✓] Applied sed patch to $mission_server_sed_target.${NC}"
         log_message "Applied sed patch (\x44\x24\x0c\x28\x62\x34 -> \x44\x24\x0c\x08\x49\x40) to $mission_server_sed_target."
    else
         echo -e "${YELLOW}[*] Notice: File $mission_server_sed_target not found; skipping sed patch.${NC}"
    fi

    local world_server_bin="$INSTALL_DIR/WorldServer/WorldServer"
    local zone_server_bin="$INSTALL_DIR/ZoneServer/ZoneServer"
    local ip_patch_applied=false

    for binary_file in "$world_server_bin" "$zone_server_bin"; do
         if [[ -f "$binary_file" ]]; then
             local offset_found=""
             if command -v perl &> /dev/null; then
                 offset_found=$(perl -ne 'print tell if /\Q$ENV{ORIGINAL_IP_HEX_PATTERN}\E/' ORIGINAL_IP_HEX_PATTERN="$ORIGINAL_IP_HEX_PATTERN" "$binary_file" | head -n 1)
             else
                 if grep -qobUP "$ORIGINAL_IP_HEX_PATTERN" "$binary_file"; then offset_found="yes"; fi
             fi

             if [[ -n "$offset_found" ]]; then
                 echo -e "${BLUE}   >> Patching IP in $binary_file (replacing $ORIGINAL_IP_HEX_PATTERN with $PATCHIP_HEX)...${NC}"
                 cp "$binary_file" "$binary_file.bak.$$"
                 if command -v perl &> /dev/null; then
                     perl -pi -e "s/\Q$ORIGINAL_IP_HEX_PATTERN\E/$PATCHIP_HEX/g" "$binary_file"
                 else
                     sed -i "s/$ORIGINAL_IP_HEX_PATTERN/$PATCHIP_HEX/g" "$binary_file"
                 fi

                 if [ $? -ne 0 ]; then
                     mv "$binary_file.bak.$$" "$binary_file"
                     error_exit "Failed to patch IP in $binary_file."
                 fi
                 rm "$binary_file.bak.$$"
                 echo -e "${GREEN}   [✓] Patched IP in $binary_file successfully.${NC}"
                 ip_patch_applied=true
             else
                  echo -e "${YELLOW}   [*] Original IP pattern '$ORIGINAL_IP_HEX_PATTERN' not found in $binary_file. Assuming already patched or not needed.${NC}"
                  local already_patched=""
                   if command -v perl &> /dev/null; then
                       already_patched=$(perl -ne 'print tell if /\Q$ENV{PATCHIP_HEX}\E/' PATCHIP_HEX="$PATCHIP_HEX" "$binary_file" | head -n 1)
                   elif grep -qobUP "$PATCHIP_HEX" "$binary_file"; then
                        already_patched="yes"
                   fi
                  if [[ -n "$already_patched" ]]; then
                       echo -e "${GREEN}   [✓] File $binary_file seems already patched with the correct IP pattern ($PATCHIP_HEX).${NC}"
                  fi
             fi
         else
             echo -e "${YELLOW}[*] Notice: File $binary_file not found; skipping IP patch.${NC}"
         fi
    done
    if [ "$ip_patch_applied" = true ]; then log_message "Patched IP address in WorldServer/ZoneServer binaries."; fi

    STATUS[patch_success]=true
    echo -e "${GREEN}[✓] Server file patching process completed.${NC}"
    log_message "Server file patching process completed."
}


update_database_ips() {
    if [ "${STATUS[sql_import_success]}" = false ] || [ -z "$IP" ] || [ -z "$DB_PASS" ]; then
        error_exit "Cannot update database IPs: SQL import not successful, or IP/DB Password missing."
    fi

    echo -e "${BLUE}>> Updating IP addresses in database tables...${NC}"
    export PGPASSWORD="$DB_PASS"

    local update_failed=false

    echo -e "${BLUE}   >> Updating FFAccount.worlds table...${NC}"
    local sql_cmd_account="UPDATE worlds SET ip = '$IP';"
    if ! sudo -H -u "$DB_USER" psql -q -d "FFAccount" -c "$sql_cmd_account"; then
        echo -e "${RED}[✗] ERROR: Failed to update IP in FFAccount.worlds.${NC}"
        update_failed=true
    else
        log_message "Updated IP in FFAccount.worlds to $IP."
    fi

    echo -e "${BLUE}   >> Updating FFDB1.serverstatus table (excluding MissionServer)...${NC}"
    local sql_cmd_db1_main="UPDATE serverstatus SET ext_address = '$IP', int_address = '$IP' WHERE name != 'MissionServer';"
    if ! sudo -H -u "$DB_USER" psql -q -d "FFDB1" -c "$sql_cmd_db1_main"; then
        echo -e "${RED}[✗] ERROR: Failed to update main IP addresses in FFDB1.serverstatus.${NC}"
        update_failed=true
    else
         log_message "Updated ext_address and int_address in FFDB1.serverstatus to $IP (excluding MissionServer)."
    fi

    echo -e "${BLUE}   >> Updating FFDB1.serverstatus table (MissionServer entry)...${NC}"
    local sql_cmd_db1_mission="UPDATE serverstatus SET ext_address = 'none' WHERE name = 'MissionServer';"
    if ! sudo -H -u "$DB_USER" psql -q -d "FFDB1" -c "$sql_cmd_db1_mission"; then
        echo -e "${RED}[✗] ERROR: Failed to update MissionServer IP in FFDB1.serverstatus.${NC}"
        update_failed=true
    else
        log_message "Updated ext_address to 'none' for MissionServer in FFDB1.serverstatus."
    fi

    unset PGPASSWORD

    if [ "$update_failed" = true ]; then
        error_exit "One or more database IP updates failed. Check PostgreSQL logs and permissions."
    fi

    echo -e "${GREEN}[✓] Database IP addresses updated successfully.${NC}"
    log_message "Database IP addresses updated."
}


configure_grub() {
    echo -e "${BLUE}>> Checking GRUB configuration for vsyscall=emulate...${NC}"
    local grub_config_file="/etc/default/grub"
    local grub_update_cmd=""
    local grub_needs_update=false

    if command -v update-grub &> /dev/null; then
        grub_update_cmd="sudo update-grub"
    elif command -v grub2-mkconfig &> /dev/null; then
        if [ -f /boot/grub2/grub.cfg ]; then
            grub_update_cmd="sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
        elif [ -f /boot/efi/EFI/redhat/grub.cfg ]; then
             grub_update_cmd="sudo grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg"
        elif [ -f /boot/efi/EFI/centos/grub.cfg ]; then
             grub_update_cmd="sudo grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg"
        elif [ -f /boot/efi/EFI/debian/grub.cfg ]; then
             grub_update_cmd="sudo grub2-mkconfig -o /boot/efi/EFI/debian/grub.cfg"
        elif [ -f /boot/efi/EFI/ubuntu/grub.cfg ]; then
             grub_update_cmd="sudo grub2-mkconfig -o /boot/efi/EFI/ubuntu/grub.cfg"
        else
             echo -e "${YELLOW}[!] Warning: Cannot determine GRUB2 config file path for grub2-mkconfig.${NC}"
        fi
    fi

    if [ ! -f "$grub_config_file" ]; then
        echo -e "${YELLOW}[*] Notice: GRUB default config file '$grub_config_file' not found. Skipping vsyscall configuration.${NC}"
        log_message "Skipped GRUB config: $grub_config_file not found."
        STATUS[grub_configured]=false
        return
    fi

    if [ -z "$grub_update_cmd" ]; then
         echo -e "${YELLOW}[!] Warning: Could not find a valid GRUB update command (update-grub or grub2-mkconfig). Skipping vsyscall configuration.${NC}"
         log_message "Skipped GRUB config: No update command found."
         STATUS[grub_configured]=false
         return
    fi

    if grep -qE '^\s*GRUB_CMDLINE_LINUX(_DEFAULT)?\s*=\s*".*vsyscall=emulate.*"' "$grub_config_file"; then
        echo -e "${GREEN}[✓] GRUB already configured with vsyscall=emulate. No changes needed.${NC}"
        log_message "GRUB already has vsyscall=emulate."
        STATUS[grub_configured]=false
    else
        echo -e "${BLUE}>> vsyscall=emulate not found in GRUB config. Adding it...${NC}"
        local backup_ts
        backup_ts=$(date +%F_%T)
        sudo cp "$grub_config_file" "$grub_config_file.bak.$backup_ts" || error_exit "Failed to backup $grub_config_file."

        if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_config_file"; then
            sudo sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)"/\1 vsyscall=emulate"/' "$grub_config_file" || error_exit "Failed to add vsyscall=emulate to GRUB_CMDLINE_LINUX_DEFAULT."
            echo -e "${GREEN}[✓] Added vsyscall=emulate to GRUB_CMDLINE_LINUX_DEFAULT.${NC}"
            grub_needs_update=true
        elif grep -q "^GRUB_CMDLINE_LINUX=" "$grub_config_file"; then
            sudo sed -i -E 's/^(GRUB_CMDLINE_LINUX="[^"]*)"/\1 vsyscall=emulate"/' "$grub_config_file" || error_exit "Failed to add vsyscall=emulate to GRUB_CMDLINE_LINUX."
            echo -e "${GREEN}[✓] Added vsyscall=emulate to GRUB_CMDLINE_LINUX.${NC}"
            grub_needs_update=true
        else
            echo -e "${YELLOW}[!] Warning: Could not find GRUB_CMDLINE_LINUX_DEFAULT or GRUB_CMDLINE_LINUX. Adding GRUB_CMDLINE_LINUX line.${NC}"
            echo '' | sudo tee -a "$grub_config_file" > /dev/null
            echo 'GRUB_CMDLINE_LINUX="vsyscall=emulate"' | sudo tee -a "$grub_config_file" > /dev/null || error_exit "Failed to add GRUB_CMDLINE_LINUX line to $grub_config_file."
            echo -e "${GREEN}[✓] Added GRUB_CMDLINE_LINUX=\"vsyscall=emulate\" line.${NC}"
            grub_needs_update=true
        fi

        if [ "$grub_needs_update" = true ]; then
            echo -e "${BLUE}>> Updating GRUB configuration using: $grub_update_cmd...${NC}"
            if ! $grub_update_cmd > "$LOG_FILE.grub_update" 2>&1; then
                 echo -e "${RED}[✗] ERROR: Failed to update GRUB configuration. Check details below and in $LOG_FILE.grub_update${NC}"
                 cat "$LOG_FILE.grub_update"
                 sudo mv "$grub_config_file.bak.$backup_ts" "$grub_config_file"
                 error_exit "GRUB update failed."
            fi
            STATUS[grub_configured]=true
            echo -e "${GREEN}[✓] GRUB configuration updated successfully.${NC}"
            echo -e "${YELLOW}[!] IMPORTANT: A system reboot is REQUIRED for the GRUB changes (vsyscall=emulate) to take effect.${NC}"
            log_message "GRUB configured for vsyscall=emulate and update command executed."
        fi
    fi
}


admin_info_message() {
    echo -e "${BLUE}
==================================================
        Admin Account Creation Details
==================================================${NC}"
    echo -e "Admin Username: ${GREEN}${ADMIN_USERNAME}${NC}"
    echo -e "\n${YELLOW}[!] IMPORTANT: Post-Installation Steps for Admin:${NC}"
    echo -e "1. Log into the game using the admin account credentials."
    echo -e "2. Create a character for the admin account."
    echo -e "3. Access the PostgreSQL database (e.g., using psql or a GUI tool)."
    echo -e "4. Connect to the ${GREEN}FFDB1${NC} database."
    echo -e "5. Run the following SQL command to grant full GM privileges:"
    echo -e "   ${BLUE}UPDATE player_characters SET privilege = 5 WHERE account_id = (SELECT idnum FROM \"FFMember\".tb_user WHERE mid = '${ADMIN_USERNAME}');${NC}"
    echo -e "   (Replace '${ADMIN_USERNAME}' if you used a different name. Note the schema qualification for FFMember)."
    log_message "Admin creation instructions displayed for user ${ADMIN_USERNAME}."
}

create_admin_account() {
    if [ "${STATUS[sql_import_success]}" = false ] || [ -z "$DB_PASS" ]; then
        error_exit "Cannot create admin account: Database import not successful or DB Password missing."
    fi

    echo -e "\n${BLUE}>> Creating Game Admin Account...${NC}"
    while true; do
        read -p "Enter desired admin username (3-16 lowercase letters/numbers): " ADMIN_USERNAME
        if [[ "$ADMIN_USERNAME" =~ ^[a-z0-9]{3,16}$ ]]; then
            break
        else
            echo -e "${RED}[✗] Invalid username. Must be 3-16 characters, lowercase letters (a-z) and numbers (0-9) only.${NC}"
        fi
    done

    while true; do
         read -s -p "Enter admin password: " ADMIN_PASSWORD
         echo ""
         read -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
         echo ""
         if [ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_CONFIRM" ]; then
              if [ -z "$ADMIN_PASSWORD" ]; then
                  echo -e "${RED}[✗] Password cannot be empty.${NC}"
              else
                   break
              fi
         else
              echo -e "${RED}[✗] Passwords do not match. Please try again.${NC}"
         fi
    done

    echo -e "${BLUE}>> Processing admin account creation for '$ADMIN_USERNAME'...${NC}"
    export PGPASSWORD="$DB_PASS"

    local ADMIN_PWD_HASH
    ADMIN_PWD_HASH=$(echo -n "$ADMIN_PASSWORD" | md5sum | awk '{print $1}')
    if [ -z "$ADMIN_PWD_HASH" ]; then
        unset PGPASSWORD
        error_exit "Failed to generate MD5 hash for the admin password."
    fi

    local creation_failed=false
    local USER_ID=""

    echo -e "${BLUE}   >> Inserting into FFMember.tb_user...${NC}"
    local sql_cmd_member_insert="INSERT INTO tb_user (mid, password, pwd) VALUES ('${ADMIN_USERNAME}', '${ADMIN_PASSWORD}', '${ADMIN_PWD_HASH}');"
    if ! sudo -H -u "$DB_USER" psql -v ON_ERROR_STOP=1 -q -d "FFMember" -c "$sql_cmd_member_insert"; then
        echo -e "${RED}[✗] ERROR: Failed to insert admin account into FFMember.tb_user. Does username already exist? Check logs.${NC}"
        creation_failed=true
    else
        USER_ID=$(sudo -H -u "$DB_USER" psql -v ON_ERROR_STOP=1 -At -d "FFMember" -c "SELECT idnum FROM tb_user WHERE mid = '${ADMIN_USERNAME}';")
        if [ -z "$USER_ID" ]; then
             echo -e "${RED}[✗] ERROR: Failed to retrieve idnum for admin user '$ADMIN_USERNAME' from FFMember.tb_user after insert.${NC}"
             creation_failed=true
        else
            log_message "Inserted admin user '$ADMIN_USERNAME' into FFMember.tb_user with idnum $USER_ID."
        fi
    fi

    if [ "$creation_failed" = false ]; then
        echo -e "${BLUE}   >> Inserting into FFAccount.accounts...${NC}"
        local sql_cmd_account_insert="INSERT INTO accounts (id, username, password) VALUES ('${USER_ID}', '${ADMIN_USERNAME}', '${ADMIN_PASSWORD}');"
        if ! sudo -H -u "$DB_USER" psql -v ON_ERROR_STOP=1 -q -d "FFAccount" -c "$sql_cmd_account_insert"; then
            echo -e "${RED}[✗] ERROR: Failed to insert admin account into FFAccount.accounts. Check logs.${NC}"
            creation_failed=true
        else
             log_message "Inserted admin user '$ADMIN_USERNAME' (ID: $USER_ID) into FFAccount.accounts."
        fi
    fi

    if [ "$creation_failed" = false ]; then
        echo -e "${BLUE}   >> Updating privileges (pvalues) in FFMember.tb_user...${NC}"
        local sql_cmd_member_priv="UPDATE tb_user SET pvalues = 999999 WHERE idnum = '${USER_ID}';"
        if ! sudo -H -u "$DB_USER" psql -v ON_ERROR_STOP=1 -q -d "FFMember" -c "$sql_cmd_member_priv"; then
            echo -e "${RED}[✗] ERROR: Failed to update admin privileges (pvalues) in FFMember.tb_user. Check logs.${NC}"
            creation_failed=true
        else
             log_message "Updated pvalues for admin user '$ADMIN_USERNAME' (ID: $USER_ID) in FFMember.tb_user."
        fi
    fi

    if [ "$creation_failed" = false ]; then
        echo -e "${BLUE}   >> Inserting into FFAccount.gm_tool_accounts...${NC}"
        local sql_cmd_gmtool_insert="INSERT INTO gm_tool_accounts (id, account_name, password, privilege) VALUES ('${USER_ID}', '${ADMIN_USERNAME}', '${ADMIN_PASSWORD}', 5);"
        if ! sudo -H -u "$DB_USER" psql -v ON_ERROR_STOP=1 -q -d "FFAccount" -c "$sql_cmd_gmtool_insert"; then
            echo -e "${RED}[✗] ERROR: Failed to insert admin account into FFAccount.gm_tool_accounts. Check logs.${NC}"
            creation_failed=true
        else
            log_message "Inserted admin user '$ADMIN_USERNAME' (ID: $USER_ID) into FFAccount.gm_tool_accounts with privilege 5."
        fi
    fi

    unset PGPASSWORD

    if [ "$creation_failed" = true ]; then
        error_exit "Admin account creation failed at one of the steps. Check logs and database state. Manual cleanup might be needed."
    fi

    STATUS[admin_creation_success]=true
    echo -e "${GREEN}[✓] Admin account '$ADMIN_USERNAME' created successfully in the database.${NC}"
    log_message "Admin account '$ADMIN_USERNAME' created successfully in database tables."

    admin_info_message
}


prompt_systemd_service() {
    if [ ! -d /run/systemd/system ]; then
        echo -e "${YELLOW}[*] Notice: Systemd not detected as the init system. Skipping systemd service setup.${NC}"
        log_message "Systemd not detected, skipping service setup."
        return
    fi

    echo -e "\n${BLUE}--- Optional: Systemd Service Setup ---${NC}"
    echo -e "You can set up a systemd service to manage the Aura Kingdom server processes."
    echo -e "This allows using commands like:"
    echo -e "  ${GREEN}systemctl start aurakingdom${NC}"
    echo -e "  ${GREEN}systemctl stop aurakingdom${NC}"
    echo -e "  ${GREEN}systemctl restart aurakingdom${NC}"
    echo -e "  ${GREEN}systemctl status aurakingdom${NC}"
    echo -e "The service will also attempt to restart automatically if the server crashes."

    local service_choice
    read -p "Would you like to install the systemd service? [Y/n]: " service_choice

    if [[ "$service_choice" =~ ^[Yy]$ ]] || [ -z "$service_choice" ]; then
        install_systemd_service
    else
        echo -e "${BLUE}>> Skipping systemd service installation.${NC}"
        log_message "User opted not to install systemd service."
    fi
}

install_systemd_service() {
    echo -e "${BLUE}>> Creating systemd service file for Aura Kingdom...${NC}"
    local SERVICE_NAME="aurakingdom"
    local SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    if [ ! -x "$INSTALL_DIR/start" ] || [ ! -x "$INSTALL_DIR/stop" ]; then
        error_exit "Cannot create systemd service: Start/stop scripts not found or not executable in $INSTALL_DIR."
    fi

    local pg_service_dep="postgresql.service"
    if [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "RHEL"* ]]; then
         pg_service_dep="postgresql-$DB_VERSION.service"
    fi

    echo -e "${BLUE}>> Writing systemd service file to $SERVICE_FILE...${NC}"
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Aura Kingdom Server ($INSTALL_DIR)
Requires=network-online.target $pg_service_dep
After=network-online.target $pg_service_dep

[Service]
Type=forking
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start
ExecStop=$INSTALL_DIR/stop
Restart=on-failure
RestartSec=10s
TimeoutStartSec=300s
TimeoutStopSec=60s
User=root

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then error_exit "Failed to write systemd service file to $SERVICE_FILE."; fi
    log_message "Created systemd service file $SERVICE_FILE."

    echo -e "${BLUE}>> Reloading systemd daemon...${NC}"
    sudo systemctl daemon-reload || error_exit "Failed to reload systemd daemon."

    echo -e "${BLUE}>> Enabling $SERVICE_NAME service to start on boot...${NC}"
    sudo systemctl enable "${SERVICE_NAME}.service" || error_exit "Failed to enable $SERVICE_NAME service."

    echo -e "${BLUE}>> Starting $SERVICE_NAME service...${NC}"
    if ! sudo systemctl start "${SERVICE_NAME}.service"; then
         echo -e "${RED}[✗] ERROR: Failed to start $SERVICE_NAME service initially. Check status below:${NC}"
         sudo systemctl status "${SERVICE_NAME}.service" --no-pager -l
         error_exit "Failed to start $SERVICE_NAME service."
    fi

    echo -e "${BLUE}>> Verifying service status...${NC}"
    sleep 5
    if sudo systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        echo -e "${GREEN}[✓] Systemd service '$SERVICE_NAME' installed, enabled, and started successfully.${NC}"
        log_message "Systemd service '$SERVICE_NAME' installed and started."
    else
        echo -e "${RED}[✗] ERROR: Systemd service '$SERVICE_NAME' failed to start or is not active after starting. Check status:${NC}"
        sudo systemctl status "${SERVICE_NAME}.service" --no-pager -l
        error_exit "Systemd service '$SERVICE_NAME' did not remain active after starting."
    fi
}

display_recommendation
detect_os
check_sudo_command
check_and_manage_ssh
configure_locales

echo -e "\n${BLUE}--- Network Configuration ---${NC}"
ips=($(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.'))
if [ ${#ips[@]} -eq 0 ]; then
    ips=($(hostname -I | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -v '^127\.'))
     if [ ${#ips[@]} -eq 0 ]; then
        error_exit "No suitable non-loopback IPv4 addresses found using 'ip addr' or 'hostname -I'. Check network configuration."
     fi
fi

echo -e "${BLUE}>> Please select the primary IP address for the server:${NC}"
select ip_choice in "${ips[@]}" "Enter IP manually" "Abort"; do
    case "$ip_choice" in
        "Enter IP manually")
            read -p "Enter the desired IP address: " IP
            if [[ ! "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                 echo -e "${RED}[✗] Invalid IP format. Please try again.${NC}"
                 continue
            else
                 break
            fi
            ;;
        "Abort")
            error_exit "Installation aborted by user during IP selection."
            ;;
        *)
            if [[ "$REPLY" =~ ^[0-9]+$ ]] && [ "$REPLY" -ge 1 ] && [ "$REPLY" -le ${#ips[@]} ]; then
                 IP="${ips[$((REPLY-1))]}"
                 break
            elif [[ -n "$ip_choice" ]]; then
                 IP="$ip_choice"
                 break
            else
                echo -e "${RED}[✗] Invalid selection. Please choose a number from the list.${NC}"
            fi
            ;;
    esac
done
echo -e "${GREEN}[✓] Using server IP address: $IP${NC}"
log_message "Selected server IP: $IP"

check_kernel_version() {
    local KERNEL_VERSION_MAJOR
    KERNEL_VERSION_MAJOR=$(uname -r | cut -d'.' -f1)
    if [ "$KERNEL_VERSION_MAJOR" -ge 6 ]; then
        echo -e "\n${YELLOW}--- Kernel Version Warning ---${NC}"
        echo -e "${YELLOW}[!] WARNING: Your kernel version is ${KERNEL_VERSION_MAJOR}.x ($(uname -r)).${NC}"
        echo -e "${YELLOW}           This server software was likely designed for older kernels (e.g., 5.x like in Debian 11).${NC}"
        echo -e "${YELLOW}           You *might* encounter compatibility issues, especially related to the 'vsyscall=emulate' GRUB setting.${NC}"
        echo -e "${YELLOW}           If you face problems, consider using Debian 11 (Bullseye).${NC}"
        read -p "Press Enter to acknowledge and continue, or Ctrl+C to cancel..." dummy
        log_message "User acknowledged kernel version warning (Kernel: $(uname -r))."
    fi
}
check_kernel_version

echo -e "\n${BLUE}--- System Preparation ---${NC}"
update_packages() {
    echo -e "${BLUE}>> Updating package lists...${NC}"
    if ! retry_command sudo "$PKG_MANAGER" -y -qq update; then
        if [ "$PKG_MANAGER" = 'apt-get' ]; then
             error_exit "Initial 'apt-get update' failed even after retries. Check network, /etc/apt/sources.list and files in /etc/apt/sources.list.d/."
        else
             error_exit "Initial '$PKG_MANAGER update' failed even after retries. Check network and repository configuration (e.g., /etc/yum.repos.d/)."
        fi
    fi
    log_message "Initial package lists updated successfully."
}
update_packages

if [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ]; then
    install_ubuntu_dependencies
elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "RHEL"* ]]; then
    install_centos_dependencies
fi

install_packages
check_and_install_megatools
check_and_install_xxd

echo -e "\n${BLUE}--- PostgreSQL Setup (Version $DB_VERSION) ---${NC}"
check_postgresql_version
configure_postgresql
secure_postgresql

verify_essential_commands

echo -e "\n${BLUE}--- Firewall Configuration ---${NC}"
setup_firewall_rules

echo -e "\n${BLUE}--- Server Files Installation ---${NC}"
handle_existing_install_dir
download_server_files
extract_server_files
download_start_stop_scripts

echo -e "\n${BLUE}--- Database and File Patching ---${NC}"
import_databases
remove_sql_directory
patch_server_files
update_database_ips

echo -e "\n${BLUE}--- GRUB Configuration (vsyscall) ---${NC}"
configure_grub

echo -e "\n${BLUE}--- Game Admin Account Setup ---${NC}"
create_admin_account

echo -e "\n${BLUE}--- Final Steps ---${NC}"
echo -e "${BLUE}>> Ensuring correct permissions for $INSTALL_DIR...${NC}"
chmod -R 755 "$INSTALL_DIR" || echo -e "${YELLOW}[!] Warning: Failed to set final permissions on $INSTALL_DIR.${NC}"

prompt_systemd_service

echo -e "\n${BLUE}--- Installation Summary ---${NC}"
INSTALL_SUCCESS=true
FAILED_STEPS=()
for status_key in "${!STATUS[@]}"; do
    if [[ "$status_key" == "grub_configured" ]] || [[ "$status_key" == "ssh_service_checked" ]]; then
        continue
    fi
    if [ "${STATUS[$status_key]}" = false ]; then
        FAILED_STEPS+=("$status_key")
        INSTALL_SUCCESS=false
    fi
done

if [ "$INSTALL_SUCCESS" = true ]; then
    echo -e "${GREEN}
==================================================
           Installation Complete!
==================================================${NC}"
    echo -e "Server IP Address      : ${GREEN}$IP${NC}"
    echo -e "Installation Directory : ${GREEN}$INSTALL_DIR${NC}"
    echo -e "PostgreSQL Version     : ${GREEN}$DB_VERSION${NC}"
    echo -e "Database User          : ${GREEN}$DB_USER${NC}"
    echo -e "Database Password      : ${GREEN}$DB_PASS${NC} (SAVE THIS SECURELY!)"
    echo -e "Admin Game Account     : ${GREEN}$ADMIN_USERNAME${NC}"

    echo -e "\n${BLUE}SSH Status:${NC}"
    if [ "${STATUS[ssh_service_checked]}" = true ]; then
        echo -e " - SSH Service         : ${GREEN}Checked/Configured${NC}"
        local ssh_config_file="/etc/ssh/sshd_config"
        if [ -f "$ssh_config_file" ]; then
             if grep -qE "^\s*PermitRootLogin\s+yes\s*$" "$ssh_config_file" && grep -qE "^\s*PasswordAuthentication\s+yes\s*$" "$ssh_config_file"; then
                  echo -e " - Root Login (Password): ${GREEN}Enabled${NC}"
             else
                  if grep -qE "^\s*PermitRootLogin\s+(prohibit-password|without-password)\s*$" "$ssh_config_file"; then
                       echo -e " - Root Login (Password): ${YELLOW}Disabled (Key-based login might be possible)${NC}"
                  elif grep -qE "^\s*PermitRootLogin\s+no\s*$" "$ssh_config_file"; then
                       echo -e " - Root Login (Password): ${RED}Disabled${NC}"
                  else
                       echo -e " - Root Login (Password): ${YELLOW}Check config ($ssh_config_file)${NC}"
                  fi
                  if ! grep -qE "^\s*PasswordAuthentication\s+yes\s*$" "$ssh_config_file"; then
                      echo -e " - Password Auth       : ${YELLOW}Might be disabled${NC}"
                  fi
             fi
        else
             echo -e " - Root Login (Password): ${YELLOW}Config file not found, status unknown${NC}"
        fi
    else
        echo -e " - SSH Service         : ${YELLOW}Not installed or failed to configure${NC}"
    fi


    echo -e "\n${BLUE}To manage the server:${NC}"
    local service_name="aurakingdom"
    if [ -f "/etc/systemd/system/${service_name}.service" ]; then
        echo -e " - Start : ${GREEN}sudo systemctl start ${service_name}${NC}"
        echo -e " - Stop  : ${GREEN}sudo systemctl stop ${service_name}${NC}"
        if systemctl is-active --quiet "${service_name}.service"; then
             echo -e " - Status: ${GREEN}Server is running${NC} (Use 'sudo systemctl status ${service_name}' for details)"
        else
             echo -e " - Status: ${RED}Server is not running${NC} (Use 'sudo systemctl status ${service_name}' for details)"
        fi
    else
        echo -e " - Start : ${GREEN}cd $INSTALL_DIR && ./start${NC}"
        echo -e " - Stop  : ${GREEN}cd $INSTALL_DIR && ./stop${NC}"
        echo -e " - Status: ${YELLOW}Systemd service not installed. Check processes manually.${NC}"
    fi

    if [ "${STATUS[grub_configured]}" = true ]; then
        echo -e "\n${YELLOW}[!] IMPORTANT: A system REBOOT is required for GRUB changes (vsyscall=emulate) to take effect.${NC}"
        echo -e "              The server might not function correctly until after the reboot.${NC}"
    fi
     echo -e "\n${YELLOW}[!] REMINDER: Remember to grant GM privileges to your admin character in the database (see instructions above).${NC}"
    log_message "Installation completed successfully."
    echo -e "\n${GREEN}Log file located at: $LOG_FILE${NC}"
else
    echo -e "${RED}
==================================================
            Installation Failed!
==================================================${NC}"
    echo -e "${RED}One or more steps failed during the installation process.${NC}"
    if [ ${#FAILED_STEPS[@]} -gt 0 ]; then
         echo -e "${RED}Failed steps:${NC}"
         for step in "${FAILED_STEPS[@]}"; do
             echo -e " - ${RED}$step${NC}"
         done
    fi
    echo -e "\nPlease review the error messages above and check the detailed log file:"
    echo -e "${YELLOW}${LOG_FILE}${NC}"
    log_message "Installation failed. Failed steps: ${FAILED_STEPS[*]}"
    exit 1
fi

exit 0
