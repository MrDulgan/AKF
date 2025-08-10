#!/bin/bash

# ------------------------- Global Variables -------------------------
# Color definitions
RED='\e[0;31m'
GREEN='\e[1;32m'
BLUE='\e[0;36m'
YELLOW='\e[1;33m'
NC='\e[0m'  # No Color

# Default configuration values
DB_VERSION=13
DB_USER='postgres'
DB_PASS=''
INSTALL_DIR='/root/hxsy'
DOWNLOAD_URL='https://mega.nz/file/z6AyGIaA#1OXGc4amedlwtNvknc-KC9im_B9nh0FeXO1Ns51Fvr0'
LOG_FILE="/tmp/ak_installer.log"

# Operation status variables for final reporting
declare -A STATUS=(
    [postgresql_installed]=false
    [config_success]=false
    [db_creation_success]=false
    [sql_import_success]=false
    [download_success]=false
    [patch_success]=false
    [admin_creation_success]=false
    [grub_configured]=false
    [ssh_configured]=false
    [compatibility_configured]=false
)

# ---------------------- Logging and Error Handling --------------------
echo "Installation started at $(date)" > "$LOG_FILE"

log_message() {
    echo "[INFO] $(date): $1" >> "$LOG_FILE"
}

trap 'error_exit "An unexpected error occurred. Please check ${LOG_FILE} for details."' ERR

error_exit() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "[ERROR] $(date): $1" >> "$LOG_FILE"
    exit 1
}

# ---------------------- Retry Logic Function --------------------------
retry_command() {
    local n=0
    local max=3
    local delay=2
    until [ $n -ge $max ]
    do
       "$@" && break
       n=$((n+1))
       echo -e "${YELLOW}[NOTICE] Command failed. Retrying in $delay seconds...${NC}"
       sleep $delay
       delay=$((delay * 2))
    done
    if [ $n -ge $max ]; then
       return 1
    fi
    return 0
}

# -------------------- Resource Checks ---------------------------
# Check available disk space (requires at least 1 GB free)
check_disk_space() {
    REQUIRED_SPACE=1048576  # in KB (1 GB)
    avail=$(df "$INSTALL_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
    if [ -z "$avail" ]; then
        avail=$(df / 2>/dev/null | tail -1 | awk '{print $4}')
    fi
    if [ "$avail" -lt "$REQUIRED_SPACE" ]; then
        error_exit "Insufficient disk space. At least 1 GB free space is required."
    fi
    log_message "Disk space check passed: ${avail} KB available."
}

# Check available memory (requires at least 4 GB free)
check_memory() {
    REQUIRED_MEMORY=4194304  # in KB (4 GB)
    avail_mem=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    if [ "$avail_mem" -lt "$REQUIRED_MEMORY" ]; then
         error_exit "Insufficient available memory. At least 4 GB is required."
    fi
    log_message "Memory check passed: ${avail_mem} KB available."
}

# ------------------- Initial Display & OS Detection --------------------
echo -e "${BLUE}
==================================================
           AK Installer Script
           Developer: Dulgan
==================================================${NC}"
log_message "Installer started."

display_recommendation() {
    echo -e "${YELLOW}
[NOTICE] It is highly recommended to run this installation on Debian 11.
         Running on other systems may lead to compatibility issues.
${NC}"
    log_message "Displayed OS recommendation."
}
display_recommendation

detect_os() {
    echo -e "${BLUE}>> Detecting operating system...${NC}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            OS="Ubuntu"
            PKG_MANAGER="apt-get"
        elif [[ "$ID" == "debian" ]]; then
            OS="Debian"
            PKG_MANAGER="apt-get"
        elif [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
            OS="CentOS"
            PKG_MANAGER="yum"
        else
            error_exit "Unsupported operating system. Supported: Debian, Ubuntu, and CentOS."
        fi
        log_message "OS detected: $OS with package manager $PKG_MANAGER."
    else
        error_exit "Cannot detect operating system (missing /etc/os-release)."
    fi
}

check_sudo_command() {
    echo -e "${BLUE}>> Checking for 'sudo' command...${NC}"
    if ! command -v sudo &> /dev/null; then
        error_exit "'sudo' command not found. Please install sudo and re-run the script."
    else
        echo -e "${GREEN}>> 'sudo' is available.${NC}"
        log_message "'sudo' command is available."
    fi
}

# ---------------------- SSH Configuration Functions -------------------
check_ssh_service() {
    echo -e "${BLUE}>> Checking SSH service status...${NC}"
    
    # Check if SSH service exists and is running
    if systemctl list-units --type=service | grep -q "ssh\|sshd"; then
        SSH_SERVICE="ssh"
        if systemctl list-units --type=service | grep -q "sshd"; then
            SSH_SERVICE="sshd"
        fi
        
        if systemctl is-active --quiet "$SSH_SERVICE"; then
            echo -e "${GREEN}>> SSH service ($SSH_SERVICE) is running.${NC}"
            log_message "SSH service is running."
            return 0
        else
            echo -e "${YELLOW}[NOTICE] SSH service ($SSH_SERVICE) is installed but not running.${NC}"
            log_message "SSH service is installed but not running."
            return 1
        fi
    else
        echo -e "${YELLOW}[NOTICE] SSH service is not installed.${NC}"
        log_message "SSH service is not installed."
        return 2
    fi
}

install_ssh_server() {
    echo -e "${BLUE}>> Installing SSH server...${NC}"
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        sudo apt-get -qq update || error_exit "Failed to update package lists."
        sudo apt-get -qq install -y openssh-server || error_exit "Failed to install OpenSSH server."
        SSH_SERVICE="ssh"
    elif [ "$PKG_MANAGER" = 'yum' ]; then
        sudo yum -q -y install openssh-server || error_exit "Failed to install OpenSSH server."
        SSH_SERVICE="sshd"
    fi
    echo -e "${GREEN}>> SSH server installed successfully.${NC}"
    log_message "SSH server installed."
}

configure_ssh() {
    echo -e "${BLUE}>> Configuring SSH settings...${NC}"
    local ssh_config="/etc/ssh/sshd_config"
    
    # Backup original config
    if [ ! -f "${ssh_config}.bak" ]; then
        sudo cp "$ssh_config" "${ssh_config}.bak" || error_exit "Failed to backup SSH config."
        log_message "SSH config backed up."
    fi
    
    # Configure SSH settings for better security and compatibility
    echo -e "${BLUE}   - Configuring SSH parameters...${NC}"
    
    # Enable SSH and set port (default 22)
    sudo sed -i 's/#Port 22/Port 22/' "$ssh_config"
    sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' "$ssh_config"
    sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' "$ssh_config"
    sudo sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' "$ssh_config"
    
    # Add some security settings
    if ! grep -q "MaxAuthTries" "$ssh_config"; then
        echo "MaxAuthTries 3" | sudo tee -a "$ssh_config" > /dev/null
    fi
    
    if ! grep -q "ClientAliveInterval" "$ssh_config"; then
        echo "ClientAliveInterval 300" | sudo tee -a "$ssh_config" > /dev/null
        echo "ClientAliveCountMax 2" | sudo tee -a "$ssh_config" > /dev/null
    fi
    
    echo -e "${GREEN}   - SSH configuration updated.${NC}"
    log_message "SSH configuration updated."
}

start_ssh_service() {
    echo -e "${BLUE}>> Starting and enabling SSH service...${NC}"
    
    # Start SSH service
    sudo systemctl start "$SSH_SERVICE" || error_exit "Failed to start SSH service."
    
    # Enable SSH service to start on boot
    sudo systemctl enable "$SSH_SERVICE" || error_exit "Failed to enable SSH service."
    
    # Check if service is running
    if systemctl is-active --quiet "$SSH_SERVICE"; then
        echo -e "${GREEN}>> SSH service started and enabled successfully.${NC}"
        log_message "SSH service started and enabled."
        STATUS[ssh_configured]=true
    else
        error_exit "SSH service failed to start."
    fi
}

setup_ssh() {
    echo -e "${BLUE}
==================================================
           SSH Configuration Setup
==================================================${NC}"
    
    # Check SSH service status
    check_ssh_service
    ssh_status=$?
    
    case $ssh_status in
        0)
            echo -e "${GREEN}>> SSH is already running.${NC}"
            read -p "Do you want to reconfigure SSH settings? [y/N]: " reconfigure_ssh
            if [[ "$reconfigure_ssh" =~ ^[Yy]$ ]]; then
                configure_ssh
                sudo systemctl restart "$SSH_SERVICE" || error_exit "Failed to restart SSH service."
                echo -e "${GREEN}>> SSH reconfigured successfully.${NC}"
            fi
            STATUS[ssh_configured]=true
            ;;
        1)
            echo -e "${YELLOW}[NOTICE] SSH is installed but not running.${NC}"
            read -p "Do you want to start and configure SSH? [Y/n]: " start_ssh
            if [[ ! "$start_ssh" =~ ^[Nn]$ ]]; then
                configure_ssh
                start_ssh_service
            fi
            ;;
        2)
            echo -e "${YELLOW}[NOTICE] SSH server is not installed.${NC}"
            read -p "Do you want to install and configure SSH server for remote access? [Y/n]: " install_ssh
            if [[ ! "$install_ssh" =~ ^[Nn]$ ]]; then
                install_ssh_server
                configure_ssh
                start_ssh_service
                
                # Show connection information
                echo -e "${GREEN}
>> SSH server has been installed and configured.
>> You can now connect remotely using:
>>   - IP Address: $(hostname -I | awk '{print $1}')
>>   - Port: 22
>>   - Username: root (or your current user)
>>   
>> For PuTTY connection:
>>   - Host: $(hostname -I | awk '{print $1}')
>>   - Port: 22
>>   - Connection Type: SSH${NC}"
                
                log_message "SSH server installed and configured for remote access."
            else
                echo -e "${YELLOW}[NOTICE] SSH installation skipped.${NC}"
                log_message "SSH installation skipped by user."
            fi
            ;;
    esac
    
    # Show current SSH status
    if systemctl is-active --quiet "$SSH_SERVICE" 2>/dev/null; then
        echo -e "${GREEN}>> SSH Status: Running${NC}"
        echo -e "${GREEN}>> SSH Port: $(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}' || echo "22")${NC}"
        echo -e "${GREEN}>> Server IP: $(hostname -I | awk '{print $1}')${NC}"
    fi
    
    echo -e "${BLUE}
>> SSH configuration completed.
==================================================${NC}"
}

# --------------------- System & Resource Checks -----------------------
check_disk_space
check_memory

# -------------------- Locale and Dependencies Setup -------------------
configure_locales() {
    echo -e "${BLUE}>> Configuring locales...${NC}"
    log_message "Starting locale configuration."
    REQUIRED_LOCALES=("en_US.UTF-8" "POSIX" "C")
    
    if [ "$OS" = 'Debian' ] || [ "$OS" = 'Ubuntu' ]; then
        if ! dpkg -l | grep -qw locales; then
            echo -e "${BLUE}>> Installing 'locales' package...${NC}"
            sudo apt-get -qq install -y locales || error_exit "Failed to install 'locales'."
        else
            echo -e "${GREEN}>> 'locales' package is installed.${NC}"
        fi
        sudo cp /etc/locale.gen /etc/locale.gen.bak || error_exit "Could not backup /etc/locale.gen."
        for locale in "${REQUIRED_LOCALES[@]}"; do
            if grep -q "^$locale" /etc/locale.gen; then
                echo -e "${GREEN}>> Locale $locale is enabled.${NC}"
            else
                echo -e "${BLUE}>> Enabling locale $locale...${NC}"
                sudo sed -i "s/^# *\($locale\)/\1/" /etc/locale.gen || error_exit "Failed to enable locale $locale."
            fi
        done
        echo -e "${BLUE}>> Generating locales...${NC}"
        sudo locale-gen || error_exit "Locale generation failed."
    elif [ "$OS" = 'CentOS' ]; then
        if ! rpm -qa | grep -qw glibc-langpack-en; then
            echo -e "${BLUE}>> Installing 'glibc-langpack-en'...${NC}"
            sudo yum -q -y install glibc-langpack-en || error_exit "Failed to install glibc-langpack-en."
        else
            echo -e "${GREEN}>> 'glibc-langpack-en' is installed.${NC}"
        fi
        if ! locale -a | grep -qw "en_US.utf8"; then
            echo -e "${BLUE}>> Generating en_US.UTF-8 locale...${NC}"
            sudo localedef -i en_US -f UTF-8 en_US.UTF-8 || error_exit "Failed to generate en_US.UTF-8 locale."
        else
            echo -e "${GREEN}>> Locale en_US.UTF-8 exists.${NC}"
        fi
    fi
    echo -e "${GREEN}>> Locale configuration completed.${NC}"
    log_message "Locale configuration completed."
}

install_ubuntu_dependencies() {
    echo -e "${BLUE}>> Installing Ubuntu compatibility libraries...${NC}"
    sudo apt-get -qq install -y libc6-i386 lib32gcc-s1 lib32stdc++6 || error_exit "Failed to install Ubuntu compatibility libraries."
    echo -e "${GREEN}>> Ubuntu compatibility libraries installed.${NC}"
    log_message "Ubuntu compatibility libraries installed."
}

install_centos_dependencies() {
    echo -e "${BLUE}>> Installing CentOS compatibility libraries...${NC}"
    if command -v dnf &> /dev/null; then
         sudo dnf install -y glibc.i686 libstdc++.i686 compat-libstdc++-33 || error_exit "Failed to install CentOS compatibility libraries."
    else
         sudo yum -q -y install glibc.i686 libstdc++.i686 compat-libstdc++-33 || error_exit "Failed to install CentOS compatibility libraries."
    fi
    echo -e "${GREEN}>> CentOS compatibility libraries installed.${NC}"
    log_message "CentOS compatibility libraries installed."
}

install_packages() {
    echo -e "${BLUE}>> Installing necessary packages...${NC}"
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        sudo apt-get -qq install -y wget pwgen gnupg unzip megatools || error_exit "Failed to install required packages."
    elif [ "$PKG_MANAGER" = 'yum' ]; then
        echo -e "${BLUE}>> Adding additional repository for required packages...${NC}"
        sudo dnf install -y https://pkgs.dyn.su/el9/base/x86_64/raven-release.el9.noarch.rpm || error_exit "Failed to add repository."
        sudo dnf install -y wget pwgen gnupg2 unzip megatools vim-common || error_exit "Failed to install required packages."
    fi
    log_message "Necessary packages installed."
}

check_and_install_xxd() {
    echo -e "${BLUE}>> Checking for xxd command...${NC}"
    if ! command -v xxd &> /dev/null; then
        echo -e "${YELLOW}[NOTICE] xxd missing. Installing...${NC}"
        if [ "$PKG_MANAGER" = 'apt-get' ]; then
            sudo apt-get -qq install -y xxd || error_exit "Failed to install xxd."
        elif [ "$PKG_MANAGER" = 'yum' ]; then
            sudo yum -q -y install vim-common || error_exit "Failed to install xxd (vim-common)."
        fi
    else
        echo -e "${GREEN}>> xxd is installed.${NC}"
    fi
    log_message "xxd command verified."
}

check_and_install_commands() {
    REQUIRED_COMMANDS=("wget" "pwgen" "gnupg" "unzip" "megatools" "xxd")
    MISSING_COMMANDS=()

    echo -e "${BLUE}>> Verifying required commands...${NC}"
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${YELLOW}   - Command '$cmd' is missing.${NC}"
            MISSING_COMMANDS+=("$cmd")
        else
            echo -e "${GREEN}   - Command '$cmd' is available.${NC}"
        fi
    done

    if [ "${#MISSING_COMMANDS[@]}" -ne 0 ]; then
        echo -e "${BLUE}>> Installing missing commands...${NC}"
        if [ "$PKG_MANAGER" = 'apt-get' ]; then
            sudo apt-get -qq update || error_exit "Failed to update package lists."
            for cmd in "${MISSING_COMMANDS[@]}"; do
                if [ "$cmd" = "xxd" ]; then
                    sudo apt-get -qq install -y xxd || error_exit "Failed to install xxd."
                else
                    sudo apt-get -qq install -y "$cmd" || error_exit "Failed to install $cmd."
                fi
            done
        elif [ "$PKG_MANAGER" = 'yum' ]; then
            sudo yum -q -y update || error_exit "Failed to update package lists."
            for cmd in "${MISSING_COMMANDS[@]}"; do
                if [ "$cmd" = "xxd" ]; then
                    sudo yum -q -y install vim-common || error_exit "Failed to install xxd (vim-common)."
                else
                    sudo yum -q -y install "$cmd" || error_exit "Failed to install $cmd."
                fi
            done
        fi
    else
        echo -e "${GREEN}>> All required commands are installed.${NC}"
    fi
    log_message "Required commands verified."
}

# ---------------------- PostgreSQL Setup ------------------------------
check_postgresql_version() {
    echo -e "${BLUE}>> Checking PostgreSQL installation...${NC}"
    if command -v psql &> /dev/null; then
        INSTALLED_VERSION=$(psql --version | awk '{print $3}' | cut -d '.' -f1)
        if [ "$INSTALLED_VERSION" != "$DB_VERSION" ]; then
            echo -e "${YELLOW}[NOTICE] PostgreSQL version $INSTALLED_VERSION detected, but version $DB_VERSION is required.${NC}"
            read -p "Do you want to remove the current version and install PostgreSQL $DB_VERSION? [y/N]: " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                if [ "$PKG_MANAGER" = 'apt-get' ]; then
                    sudo apt-get -qq remove --purge postgresql || error_exit "Failed to remove PostgreSQL."
                    sudo apt-get -qq autoremove || error_exit "Cleanup after PostgreSQL removal failed."
                elif [ "$PKG_MANAGER" = 'yum' ]; then
                    sudo yum -q -y remove postgresql || error_exit "Failed to remove PostgreSQL."
                    sudo yum -q -y autoremove || error_exit "Cleanup after PostgreSQL removal failed."
                fi
                install_postgresql
            else
                error_exit "Aborted: PostgreSQL version mismatch."
            fi
        else
            echo -e "${GREEN}>> PostgreSQL version $DB_VERSION is installed.${NC}"
            STATUS[postgresql_installed]=true
        fi
    else
        echo -e "${BLUE}>> PostgreSQL is not installed. Proceeding with installation...${NC}"
        install_postgresql
    fi
    log_message "PostgreSQL version check completed."
}

install_postgresql() {
    if command -v psql &> /dev/null; then
        echo -e "${GREEN}>> PostgreSQL is already installed; skipping installation.${NC}"
        STATUS[postgresql_installed]=true
        return
    fi

    echo -e "${BLUE}>> Installing PostgreSQL $DB_VERSION...${NC}"
    if [ "$OS" = 'Debian' ] || [ "$OS" = 'Ubuntu' ]; then
        wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - || error_exit "Failed to add PostgreSQL GPG key."
        echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
        sudo apt-get -qq update || error_exit "Failed to update package lists."
        sudo apt-get -qq install -y "postgresql-$DB_VERSION" || error_exit "Failed to install PostgreSQL $DB_VERSION."
    elif [ "$OS" = 'CentOS' ]; then
        echo -e "${BLUE}>> Adding PostgreSQL repository...${NC}"
        sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm || error_exit "Failed to add PostgreSQL repository."
        echo -e "${BLUE}>> Installing PostgreSQL $DB_VERSION...${NC}"
        sudo dnf install -y "postgresql$DB_VERSION-server" "postgresql$DB_VERSION-contrib" || error_exit "Failed to install PostgreSQL packages."
        sudo "/usr/pgsql-$DB_VERSION/bin/postgresql-$DB_VERSION-setup" initdb || error_exit "Failed to initialize PostgreSQL."
        sudo systemctl enable "postgresql-$DB_VERSION"
        sudo systemctl start "postgresql-$DB_VERSION"
    fi

    if command -v psql &> /dev/null; then
        STATUS[postgresql_installed]=true
        echo -e "${GREEN}>> PostgreSQL $DB_VERSION installed successfully.${NC}"
    else
        error_exit "PostgreSQL installation failed."
    fi
    log_message "PostgreSQL installation completed."
}

configure_postgresql() {
    echo -e "${BLUE}>> Configuring PostgreSQL settings...${NC}"
    if [ "$OS" = 'Debian' ] || [ "$OS" = 'Ubuntu' ]; then
        PG_CONF="/etc/postgresql/$DB_VERSION/main/postgresql.conf"
        PG_HBA="/etc/postgresql/$DB_VERSION/main/pg_hba.conf"
        SERVICE_NAME="postgresql"
    elif [ "$OS" = 'CentOS' ]; then
        PG_CONF="/var/lib/pgsql/$DB_VERSION/data/postgresql.conf"
        PG_HBA="/var/lib/pgsql/$DB_VERSION/data/pg_hba.conf"
        SERVICE_NAME="postgresql-$DB_VERSION"
    fi

    # Backup original configurations
    sudo cp "$PG_CONF" "$PG_CONF.backup" || error_exit "Failed to backup postgresql.conf"
    sudo cp "$PG_HBA" "$PG_HBA.backup" || error_exit "Failed to backup pg_hba.conf"

    # Enhanced PostgreSQL security configuration
    sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" "$PG_CONF" || error_exit "Failed to update postgresql.conf."
    
    # Add security-focused settings
    sudo tee -a "$PG_CONF" > /dev/null <<EOF

# AK Installer Enhanced Security Settings
log_connections = on
log_disconnections = on
log_checkpoints = on
log_lock_waits = on
log_temp_files = 0
log_statement = 'mod'
log_min_duration_statement = 1000
max_connections = 50
password_encryption = 'md5'
ssl = off
shared_preload_libraries = ''
EOF

    # Enhanced pg_hba.conf security
    if ! grep -q "host    all             all             127.0.0.1/32         md5" "$PG_HBA"; then
        echo "host    all             all             127.0.0.1/32         md5" | sudo tee -a "$PG_HBA" || error_exit "Failed to update pg_hba.conf."
    fi
    if ! grep -q "host    all             all             0.0.0.0/0            md5" "$PG_HBA"; then
        echo "host    all             all             0.0.0.0/0            md5" | sudo tee -a "$PG_HBA" || error_exit "Failed to update pg_hba.conf."
    fi

    sudo systemctl restart "$SERVICE_NAME" || error_exit "Failed to restart PostgreSQL service."
    
    # Verify PostgreSQL is running
    sleep 3
    if ! sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        error_exit "PostgreSQL failed to start after configuration"
    fi
    
    STATUS[config_success]=true
    echo -e "${GREEN}>> Enhanced PostgreSQL configuration completed.${NC}"
    log_message "Enhanced PostgreSQL configured."
}

secure_postgresql() {
    echo -e "${BLUE}>> Securing PostgreSQL access...${NC}"
    DB_PASS=$(pwgen -s 32 1)
    cd /tmp
    sudo -H -u "$DB_USER" psql -q -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" >/dev/null || error_exit "Failed to secure PostgreSQL user."
    echo -e "${GREEN}>> PostgreSQL user '$DB_USER' password set.${NC}"
    log_message "PostgreSQL secured."
}

# ---------------------- Firewall and Directory ------------------------
setup_firewall_rules() {
    echo -e "${BLUE}>> Configuring firewall rules...${NC}"
    PORTS=("5567" "5568" "6543" "7654" "7777" "7878" "10021" "10022")
    if [ -x "$(command -v ufw)" ]; then
        echo -e "${GREEN}>> Configuring UFW...${NC}"
        sudo ufw allow ssh >/dev/null 2>&1
        for port in "${PORTS[@]}"; do
            if sudo ufw status | grep -qw "$port"; then
                echo -e "${BLUE}   - Port $port already allowed in UFW.${NC}"
            else
                sudo ufw allow "$port"/tcp >/dev/null 2>&1 || error_exit "Failed to allow port $port via UFW."
                echo -e "${GREEN}   - Port $port allowed in UFW.${NC}"
            fi
        done
        sudo ufw reload >/dev/null 2>&1 || error_exit "Failed to reload UFW."
    elif [ -x "$(command -v firewall-cmd)" ]; then
        echo -e "${GREEN}>> Configuring Firewalld...${NC}"
        sudo firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
        for port in "${PORTS[@]}"; do
            if sudo firewall-cmd --list-ports | grep -qw "$port/tcp"; then
                echo -e "${BLUE}   - Port $port already allowed in Firewalld.${NC}"
            else
                sudo firewall-cmd --permanent --add-port="$port"/tcp >/dev/null 2>&1 || error_exit "Failed to allow port $port via Firewalld."
                echo -e "${GREEN}   - Port $port allowed in Firewalld.${NC}"
            fi
        done
        sudo firewall-cmd --reload >/dev/null 2>&1 || error_exit "Failed to reload Firewalld."
    else
        echo -e "${YELLOW}[NOTICE] No supported firewall detected; please configure manually.${NC}"
    fi
    echo -e "${GREEN}>> Firewall rules configured.${NC}"
    log_message "Firewall rules set."
}

handle_existing_install_dir() {
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${BLUE}[NOTICE] Installation directory $INSTALL_DIR exists.${NC}"
        echo -e "${BLUE}Choose an action:${NC}"
        echo -e "${BLUE}   [1] Delete it and continue.${NC}"
        echo -e "${BLUE}   [2] Rename it (append '-old') and continue.${NC}"
        read -p "$(echo -e ${BLUE}Enter your choice [1/2]: ${NC})" dir_choice
        if [ "$dir_choice" = "1" ]; then
            echo -e "${BLUE}>> Deleting $INSTALL_DIR...${NC}"
            rm -rf "$INSTALL_DIR" || error_exit "Failed to delete $INSTALL_DIR."
            echo -e "${GREEN}>> Directory deleted.${NC}"
        elif [ "$dir_choice" = "2" ]; then
            timestamp=$(date +%Y%m%d%H%M%S)
            new_dir="${INSTALL_DIR}-old-$timestamp"
            echo -e "${BLUE}>> Renaming $INSTALL_DIR to $new_dir...${NC}"
            mv "$INSTALL_DIR" "$new_dir" || error_exit "Failed to rename $INSTALL_DIR."
            echo -e "${GREEN}>> Directory renamed to $new_dir.${NC}"
        else
            error_exit "Invalid option. Please run the script again."
        fi
        log_message "Handled existing installation directory."
    fi
}

# -------------------- File Downloads and Extraction -------------------
download_server_files() {
    echo -e "${BLUE}>> Downloading server files...${NC}"
    
    # Enhanced download with progress and verification
    local download_path="/root/hxsy.zip"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "${BLUE}   - Attempt $attempt/$max_attempts...${NC}"
        
        if megadl "$DOWNLOAD_URL" --path "$download_path" > /dev/null 2>&1; then
            # Verify download completed and file exists
            if [ -f "$download_path" ] && [ -s "$download_path" ]; then
                local file_size=$(stat -c%s "$download_path" 2>/dev/null)
                if [ "$file_size" -gt 1048576 ]; then  # At least 1MB
                    echo -e "${GREEN}>> Server files downloaded successfully (${file_size} bytes).${NC}"
                    STATUS[download_success]=true
                    log_message "Server files downloaded successfully"
                    return 0
                else
                    echo -e "${YELLOW}[WARNING] Downloaded file seems too small, retrying...${NC}"
                    rm -f "$download_path"
                fi
            else
                echo -e "${YELLOW}[WARNING] Download failed or file is empty, retrying...${NC}"
                rm -f "$download_path"
            fi
        else
            echo -e "${YELLOW}[WARNING] Download command failed, retrying...${NC}"
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            echo -e "${BLUE}   - Waiting 5 seconds before retry...${NC}"
            sleep 5
        fi
    done
    
    error_exit "Failed to download hxsy.zip after $max_attempts attempts."
}

extract_server_files() {
    echo -e "${BLUE}>> Extracting server files...${NC}"
    local zip_file="/root/hxsy.zip"
    
    # Verify zip file integrity before extraction
    if ! unzip -t "$zip_file" > /dev/null 2>&1; then
        error_exit "Downloaded zip file is corrupted."
    fi
    
    # Extract with verification
    if unzip -qo "$zip_file" -d "/root"; then
        # Verify extraction was successful
        if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/setup.ini" ]; then
            chmod -R 755 "$INSTALL_DIR"
            rm -f "$zip_file"
            echo -e "${GREEN}>> Server files extracted and permissions set.${NC}"
            log_message "Server files extracted successfully."
        else
            error_exit "Extraction completed but required files are missing."
        fi
    else
        error_exit "Failed to extract hxsy.zip."
    fi
}

download_management_scripts() {
    echo -e "${BLUE}>> Downloading management scripts...${NC}"
    cd "$INSTALL_DIR" || error_exit "Failed to change directory to $INSTALL_DIR."
    
    local scripts=("start" "stop" "backup.sh" "restore.sh" "monitor.sh")
    local base_url="https://raw.githubusercontent.com/MrDulgan/AKF/main"
    
    for script in "${scripts[@]}"; do
        echo -e "${BLUE}   - Downloading $script...${NC}"
        if retry_command wget -q -O "$script" "$base_url/$script"; then
            chmod +x "$script" || error_exit "Failed to set execute permissions on $script."
            echo -e "${GREEN}   - $script downloaded and configured.${NC}"
        else
            echo -e "${YELLOW}[WARNING] Failed to download $script, skipping...${NC}"
            log_message "Warning: Failed to download $script"
        fi
    done
    
    echo -e "${GREEN}>> Management scripts download completed.${NC}"
    log_message "Management scripts downloaded."
}

import_databases() {
    echo -e "${BLUE}>> Creating and importing databases...${NC}"
    DATABASES=("FFAccount" "FFDB1" "FFMember")
    cd /tmp
    for DB in "${DATABASES[@]}"; do
        sudo -H -u "$DB_USER" psql -q -c "DROP DATABASE IF EXISTS \"$DB\";" >/dev/null || error_exit "Failed to drop database $DB."
        sudo -H -u "$DB_USER" createdb -T template0 "$DB" >/dev/null || error_exit "Failed to create database $DB."
    done
    STATUS[db_creation_success]=true

    for DB in "${DATABASES[@]}"; do
        SQL_FILE="$INSTALL_DIR/SQL/$DB.bak"
        if [ -f "$SQL_FILE" ]; then
            sudo -H -u "$DB_USER" psql -q "$DB" < "$SQL_FILE" >/dev/null || error_exit "Failed to import SQL file for $DB."
        else
            error_exit "SQL file $SQL_FILE not found."
        fi
    done
    STATUS[sql_import_success]=true
    echo -e "${GREEN}>> Databases created and imported successfully.${NC}"
    log_message "Databases imported."
}

remove_sql_directory() {
    if [ -d "$INSTALL_DIR/SQL" ]; then
        echo -e "${BLUE}>> Removing SQL directory...${NC}"
        rm -rf "$INSTALL_DIR/SQL" || error_exit "Failed to remove SQL directory."
        echo -e "${GREEN}>> SQL directory removed.${NC}"
        log_message "SQL directory removed."
    else
        echo -e "${BLUE}>> SQL directory not found; skipping removal.${NC}"
    fi
}

# ---------------------- Patching and Updates --------------------------
patch_server_files() {
    echo -e "${BLUE}>> Patching server files...${NC}"

    IFS='.' read -r -a IP_ARRAY <<< "$IP"
    PATCHIP=$(printf '\\x%02X\\x%02X\\x%02X' "${IP_ARRAY[0]}" "${IP_ARRAY[1]}" "${IP_ARRAY[2]}")

    DBPASS_ESCAPED=$(printf '%s\n' "$DB_PASS" | sed 's/[\/&]/\\&/g')

    if [[ -f "$INSTALL_DIR/setup.ini" ]]; then
        sed -i "s/xxxxxxxx/$DBPASS_ESCAPED/g" "$INSTALL_DIR/setup.ini" || error_exit "Failed to patch setup.ini."
    fi
    if [[ -f "$INSTALL_DIR/GatewayServer/setup.ini" ]]; then
        sed -i "s/xxxxxxxx/$DBPASS_ESCAPED/g" "$INSTALL_DIR/GatewayServer/setup.ini" || error_exit "Failed to patch GatewayServer/setup.ini."
    fi

    patch_mission_server() {
        local binary_file=$1
        local offset=$2
        local original_value=$3
        local new_value=$4
        if [[ -f "$binary_file" ]]; then
            current_value=$(xxd -seek $offset -l 4 -ps "$binary_file")
            if [[ "$current_value" == "$original_value" ]]; then
                echo -e "${BLUE}   - Patching $binary_file at offset $offset...${NC}"
                printf "$new_value" | dd of="$binary_file" bs=1 seek=$offset conv=notrunc >/dev/null 2>&1 || error_exit "Failed to patch $binary_file at offset $offset."
                echo -e "${GREEN}   - Patched $binary_file successfully.${NC}"
            else
                echo -e "${BLUE}   - No patch needed for $binary_file at offset $offset.${NC}"
            fi
        else
            echo -e "${YELLOW}[NOTICE] File $binary_file not found; skipping patch.${NC}"
        fi
    }

    offset=2750792
    original_value="01346228"
    new_value="01404908"
    patch_mission_server "$INSTALL_DIR/MissionServer/MissionServer" "$offset" "$original_value" "$new_value"

    echo -e "${BLUE}>> Patching binary IP addresses...${NC}"
    sed -i "s/\x44\x24\x0c\x28\x62\x34/\x44\x24\x0c\x08\x49\x40/g" "$INSTALL_DIR/MissionServer/MissionServer" || error_exit "Failed to patch MissionServer binary."
    sed -i "s/\x3d\xc0\xa8\x64/\x3d$PATCHIP/g" "$INSTALL_DIR/WorldServer/WorldServer" || error_exit "Failed to patch WorldServer binary."
    sed -i "s/\x3d\xc0\xa8\x64/\x3d$PATCHIP/g" "$INSTALL_DIR/ZoneServer/ZoneServer" || error_exit "Failed to patch ZoneServer binary."
    STATUS[patch_success]=true
    echo -e "${GREEN}>> Server files patched successfully.${NC}"
    log_message "Server files patched."
}

update_database_ips() {
    echo -e "${BLUE}>> Updating database IP addresses...${NC}"
    cd /tmp
    sudo -H -u "$DB_USER" psql -q -d "FFAccount" -c "UPDATE worlds SET ip = '$IP';" >/dev/null || error_exit "Failed to update IP in FFAccount."
    sudo -H -u "$DB_USER" psql -q -d "FFDB1" -c "UPDATE serverstatus SET ext_address = '$IP', int_address = '$IP' WHERE name != 'MissionServer';" >/dev/null || error_exit "Failed to update IP addresses in FFDB1."
    sudo -H -u "$DB_USER" psql -q -d "FFDB1" -c "UPDATE serverstatus SET ext_address = 'none' WHERE name = 'MissionServer';" >/dev/null || error_exit "Failed to update MissionServer IP in FFDB1."
    
    # Ensure base server ports are set correctly in serverstatus
    echo -e "${BLUE}>> Setting base server ports in serverstatus...${NC}"
    sudo -H -u "$DB_USER" psql -q -d "FFDB1" -c "UPDATE serverstatus SET port = 6543 WHERE name = 'LoginServer';" >/dev/null 2>&1
    sudo -H -u "$DB_USER" psql -q -d "FFDB1" -c "UPDATE serverstatus SET port = 7777 WHERE name = 'TicketServer';" >/dev/null 2>&1
    sudo -H -u "$DB_USER" psql -q -d "FFDB1" -c "UPDATE serverstatus SET port = 0 WHERE name IN ('WorldServer', 'ZoneServer');" >/dev/null 2>&1
    
    echo -e "${GREEN}>> Database IP addresses and ports updated.${NC}"
    log_message "Database IP addresses and ports updated."
}

configure_grub() {
    echo -e "${BLUE}>> Configuring GRUB for vsyscall support...${NC}"
    if [ -f /etc/default/grub ]; then
        if grep -q "vsyscall=emulate" /etc/default/grub; then
            echo -e "${GREEN}>> GRUB already configured with vsyscall=emulate; skipping.${NC}"
            STATUS[grub_configured]=false
            log_message "GRUB already configured; no changes made."
            return
        else
            if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
                sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 vsyscall=emulate"/' /etc/default/grub || error_exit "Failed to update GRUB_CMDLINE_LINUX_DEFAULT."
                echo -e "${GREEN}>> vsyscall=emulate added to GRUB_CMDLINE_LINUX_DEFAULT.${NC}"
            elif grep -q "^GRUB_CMDLINE_LINUX=" /etc/default/grub; then
                sudo sed -i 's/\(GRUB_CMDLINE_LINUX="[^"]*\)"/\1 vsyscall=emulate"/' /etc/default/grub || error_exit "Failed to update GRUB_CMDLINE_LINUX."
                echo -e "${GREEN}>> vsyscall=emulate added to GRUB_CMDLINE_LINUX.${NC}"
            else
                echo 'GRUB_CMDLINE_LINUX="vsyscall=emulate"' | sudo tee -a /etc/default/grub || error_exit "Failed to add GRUB_CMDLINE_LINUX."
                echo -e "${GREEN}>> GRUB_CMDLINE_LINUX created with vsyscall=emulate.${NC}"
            fi
            if command -v update-grub &> /dev/null; then
                sudo update-grub > /dev/null 2>&1 || error_exit "Failed to update GRUB."
            elif command -v grub2-mkconfig &> /dev/null; then
                sudo grub2-mkconfig -o /boot/grub2/grub.cfg > /dev/null 2>&1 || error_exit "Failed to update GRUB."
            else
                error_exit "No GRUB update command found."
            fi
            STATUS[grub_configured]=true
            echo -e "${GREEN}>> GRUB configured successfully. A reboot is required for changes to take effect.${NC}"
            log_message "GRUB configured for vsyscall support."
        fi
    else
        echo -e "${YELLOW}[NOTICE] /etc/default/grub not found; skipping GRUB configuration.${NC}"
    fi
}

# -------------------- Enhanced Security Functions ------------------
validate_admin_username() {
    local username="$1"
    
    # Check length (3-16 characters)
    if [[ ${#username} -lt 3 ]] || [[ ${#username} -gt 16 ]]; then
        echo "Username must be 3-16 characters long"
        return 1
    fi
    
    # Check character set (only lowercase letters and numbers)
    if [[ ! "$username" =~ ^[a-z0-9]+$ ]]; then
        echo "Username must contain only lowercase letters and numbers"
        return 1
    fi
    
    # Check for reserved usernames
    local reserved=("admin" "root" "postgres" "system" "guest" "user" "test" "server" "game")
    for reserved_name in "${reserved[@]}"; do
        if [[ "$username" == "$reserved_name" ]]; then
            echo "Username '$username' is reserved and cannot be used"
            return 1
        fi
    done
    
    return 0
}

validate_admin_password() {
    local password="$1"
    
    # Minimum length check
    if [[ ${#password} -lt 8 ]]; then
        echo "Password must be at least 8 characters long"
        return 1
    fi
    
    # Maximum length check
    if [[ ${#password} -gt 64 ]]; then
        echo "Password must be less than 64 characters long"
        return 1
    fi
    
    # Character complexity check
    local has_lower=0
    local has_upper=0
    local has_digit=0
    local has_special=0
    
    if [[ "$password" =~ [a-z] ]]; then has_lower=1; fi
    if [[ "$password" =~ [A-Z] ]]; then has_upper=1; fi
    if [[ "$password" =~ [0-9] ]]; then has_digit=1; fi
    if [[ "$password" =~ [^a-zA-Z0-9] ]]; then has_special=1; fi
    
    local complexity_score=$((has_lower + has_upper + has_digit + has_special))
    
    if [[ $complexity_score -lt 2 ]]; then
        echo "Password must contain at least 2 of: lowercase, uppercase, digit, special character"
        return 1
    fi
    
    return 0
}

# -------------------- Admin Account Creation --------------------------
admin_info_message() {
    echo -e "${BLUE}
==================================================
       Admin Account Created Successfully
==================================================${NC}"
    echo -e "${YELLOW}[IMPORTANT]${NC} After logging into the game, create a character and update the 'privilege' column in the 'player_characters' table (in FFDB1) to 5."
    log_message "Admin creation instructions displayed."
}

create_admin_account() {
    echo -e "\n${BLUE}>> Creating Enhanced Secure Admin Account...${NC}"
    
    local username=""
    local password=""
    local password_confirm=""
    
    # Enhanced username validation loop
    while true; do
        read -p "Admin Username (3-16 chars, a-z, 0-9): " username
        local validation_result
        validation_result=$(validate_admin_username "$username")
        
        if [[ $? -eq 0 ]]; then
            # Check if username already exists
            cd /tmp
            if sudo -H -u "$DB_USER" psql -tAc "SELECT 1 FROM tb_user WHERE mid = '$username';" FFMember 2>/dev/null | grep -q "1"; then
                echo -e "${RED}[ERROR] Username already exists. Please choose another.${NC}"
                continue
            fi
            break
        else
            echo -e "${RED}[ERROR] $validation_result${NC}"
        fi
    done
    
    # Enhanced password validation loop
    while true; do
        read -s -p "Admin Password (min 8 chars, secure): " password
        echo ""
        
        local validation_result
        validation_result=$(validate_admin_password "$password")
        
        if [[ $? -eq 0 ]]; then
            read -s -p "Confirm Password: " password_confirm
            echo ""
            
            if [[ "$password" == "$password_confirm" ]]; then
                break
            else
                echo -e "${RED}[ERROR] Passwords do not match.${NC}"
            fi
        else
            echo -e "${RED}[ERROR] $validation_result${NC}"
        fi
    done

    echo -e "${BLUE}>> Creating secure admin account...${NC}"
    
    # Use MD5 hashing as required by game system
    local admin_pwd_hash=$(echo -n "$password" | md5sum | cut -d ' ' -f1)
    
    cd /tmp
    sudo -H -u "$DB_USER" psql -q -d "FFMember" -c "INSERT INTO tb_user (mid, password, pwd, pvalues) VALUES ('$username', '$password', '$admin_pwd_hash', 999999);" >/dev/null || error_exit "Failed to create admin account in FFMember."
    
    local user_id
    user_id=$(sudo -H -u "$DB_USER" psql -At -d "FFMember" -c "SELECT idnum FROM tb_user WHERE mid = '$username';")
    
    sudo -H -u "$DB_USER" psql -q -d "FFAccount" -c "INSERT INTO accounts (id, username, password) VALUES ('$user_id', '$username', '$password');" >/dev/null || error_exit "Failed to create admin account in FFAccount."
    
    sudo -H -u "$DB_USER" psql -q -d "FFAccount" -c "INSERT INTO gm_tool_accounts (id, account_name, password, privilege) VALUES ('$user_id', '$username', '$password', 5);" >/dev/null || error_exit "Failed to create entry in gm_tool_accounts."
    
    # Log account creation (without sensitive data)
    log_message "Enhanced secure admin account '$username' created with ID $user_id"
    
    STATUS[admin_creation_success]=true
    echo -e "${GREEN}>> Enhanced secure admin account '$username' created successfully.${NC}"
    
    # Secure cleanup
    unset password password_confirm admin_pwd_hash
    ADMIN_USERNAME="$username"
}

# ------------------- Optional Systemd Service Setup -------------------
prompt_systemd_service() {
    echo -e "${YELLOW}
[OPTIONAL] You can install a systemd service for the server. This will allow you to easily manage the server using:
    systemctl start aurakingdom
    systemctl stop aurakingdom
    systemctl restart aurakingdom
and view its status with:
    systemctl status aurakingdom
Would you like to install the systemd service? [Y/n]: ${NC}"
    read -r service_choice
    if [[ "$service_choice" =~ ^[Yy]$ ]] || [ -z "$service_choice" ]; then
        install_systemd_service
    else
        echo -e "${BLUE}>> Skipping systemd service installation.${NC}"
        log_message "User opted not to install systemd service."
    fi
}

install_systemd_service() {
    echo -e "${BLUE}>> Creating systemd service for the server...${NC}"
    SERVICE_FILE="/etc/systemd/system/aurakingdom.service"
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Aura Kingdom Ultimate Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start
ExecStop=$INSTALL_DIR/stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload || error_exit "Failed to reload systemd daemon."
    sudo systemctl enable aurakingdom.service || error_exit "Failed to enable aurakingdom service."
    sudo systemctl start aurakingdom.service || error_exit "Failed to start aurakingdom service."
    echo -e "${GREEN}>> Systemd service 'aurakingdom' installed and started successfully.${NC}"
    log_message "Systemd service 'aurakingdom' installed."
}

# --------------------------- Main Flow ------------------------------
detect_os
check_sudo_command

# SSH Configuration
setup_ssh

configure_locales

# Interactive IP address selection
echo -e "${BLUE}>> Please select an IP address for the server:${NC}"
ips=($(hostname -I))
for i in "${!ips[@]}"; do
    echo -e "${BLUE}   [$((i + 1))] ${ips[$i]}${NC}"
done
read -p "$(echo -e ${BLUE}Enter the number of the desired IP: ${NC})" ip_choice
IP=${ips[$((ip_choice - 1))]}
if [[ -z "$IP" ]]; then
    error_exit "Invalid IP selection."
fi
log_message "Server IP: $IP"

check_kernel_version() {
    echo -e "${BLUE}>> Checking kernel compatibility...${NC}"
    KERNEL_VERSION=$(uname -r | cut -d'.' -f1)
    KERNEL_MINOR=$(uname -r | cut -d'.' -f2)
    FULL_KERNEL=$(uname -r)
    
    echo -e "${BLUE}   - Current kernel: ${FULL_KERNEL}${NC}"
    
    if [ "$KERNEL_VERSION" -ge 6 ]; then
        echo -e "${YELLOW}[WARNING] Your kernel version is 6.x or higher.${NC}"
        echo -e "${YELLOW}For best compatibility, a kernel version of 5.x is recommended. Consider using Debian 11.${NC}"
        echo -e "${YELLOW}The binary files were optimized for Debian 11 (kernel 5.x).${NC}"
        read -p "Press Enter to continue at your own risk or Ctrl+C to cancel..." dummy
        log_message "User acknowledged kernel version warning."
    elif [ "$KERNEL_VERSION" -eq 5 ]; then
        echo -e "${GREEN}>> Kernel version 5.x detected - optimal for binary compatibility.${NC}"
        log_message "Optimal kernel version detected."
    elif [ "$KERNEL_VERSION" -eq 4 ]; then
        echo -e "${YELLOW}[NOTICE] Kernel version 4.x detected - may require additional compatibility libraries.${NC}"
        log_message "Older kernel version detected."
    else
        echo -e "${RED}[WARNING] Very old kernel version detected. Compatibility issues may occur.${NC}"
        read -p "Do you want to continue? [y/N]: " continue_old_kernel
        if [[ ! "$continue_old_kernel" =~ ^[Yy]$ ]]; then
            error_exit "Installation cancelled due to kernel compatibility concerns."
        fi
        log_message "User continued with very old kernel version."
    fi
}

# Enhanced compatibility and optimization functions
configure_kernel_parameters() {
    echo -e "${BLUE}>> Configuring kernel parameters for game server optimization...${NC}"
    
    # Backup existing sysctl.conf
    if [ ! -f /etc/sysctl.conf.bak ]; then
        sudo cp /etc/sysctl.conf /etc/sysctl.conf.bak || error_exit "Failed to backup sysctl.conf."
    fi
    
    # Create optimized sysctl settings for game server
    cat << 'EOF' | sudo tee /etc/sysctl.d/99-gameserver-optimization.conf > /dev/null
# Game Server Optimization Settings
# Network optimizations
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_rmem = 4096 65536 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1

# Memory management
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50

# Process limits
kernel.pid_max = 4194304
fs.file-max = 1000000

# Shared memory (important for older game servers)
kernel.shmmax = 268435456
kernel.shmall = 2097152
EOF
    
    # Apply the settings
    sudo sysctl -p /etc/sysctl.d/99-gameserver-optimization.conf > /dev/null 2>&1 || {
        echo -e "${YELLOW}[WARNING] Some kernel parameters could not be applied.${NC}"
        log_message "Warning: Some kernel parameters failed to apply."
    }
    
    echo -e "${GREEN}>> Kernel parameters optimized for game server.${NC}"
    log_message "Kernel parameters configured."
}

install_legacy_compatibility() {
    echo -e "${BLUE}>> Installing legacy compatibility libraries...${NC}"
    
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        # Debian/Ubuntu compatibility packages
        local packages=(
            "libc6-i386"
            "lib32gcc-s1" 
            "lib32stdc++6"
            "lib32z1"
            "libc6-dev-i386"
            "gcc-multilib"
            "g++-multilib"
        )
        
        # Additional packages for older binary compatibility
        if [ "$KERNEL_VERSION" -ge 5 ]; then
            packages+=("libnss3" "libxss1" "libgconf-2-4" "libxtst6" "libxrandr2" "libasound2" "libpangocairo-1.0-0" "libatk1.0-0" "libcairo-gobject2" "libgtk-3-0" "libgdk-pixbuf2.0-0")
        fi
        
        for package in "${packages[@]}"; do
            if ! dpkg -l | grep -qw "$package" 2>/dev/null; then
                echo -e "${BLUE}   - Installing $package...${NC}"
                sudo apt-get -qq install -y "$package" 2>/dev/null || {
                    echo -e "${YELLOW}[WARNING] Could not install $package, skipping...${NC}"
                    log_message "Warning: Failed to install $package"
                }
            else
                echo -e "${GREEN}   - $package already installed.${NC}"
            fi
        done
        
    elif [ "$PKG_MANAGER" = 'yum' ]; then
        # CentOS/RHEL compatibility packages
        local packages=(
            "glibc.i686"
            "libstdc++.i686"
            "zlib.i686"
            "glibc-devel.i686"
        )
        
        # Check if we have dnf or yum
        local installer="yum"
        if command -v dnf &> /dev/null; then
            installer="dnf"
        fi
        
        for package in "${packages[@]}"; do
            if ! rpm -qa | grep -qw "$package" 2>/dev/null; then
                echo -e "${BLUE}   - Installing $package...${NC}"
                sudo $installer install -y "$package" 2>/dev/null || {
                    echo -e "${YELLOW}[WARNING] Could not install $package, skipping...${NC}"
                    log_message "Warning: Failed to install $package"
                }
            else
                echo -e "${GREEN}   - $package already installed.${NC}"
            fi
        done
    fi
    
    echo -e "${GREEN}>> Legacy compatibility libraries installed.${NC}"
    log_message "Legacy compatibility libraries configured."
}

configure_limits() {
    echo -e "${BLUE}>> Configuring system limits for game server...${NC}"
    
    # Backup existing limits.conf
    if [ ! -f /etc/security/limits.conf.bak ]; then
        sudo cp /etc/security/limits.conf /etc/security/limits.conf.bak || error_exit "Failed to backup limits.conf."
    fi
    
    # Configure limits for game server
    cat << 'EOF' | sudo tee -a /etc/security/limits.conf > /dev/null

# Game Server Limits Configuration
root soft nofile 65536
root hard nofile 65536
root soft nproc 32768
root hard nproc 32768
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
    
    # Configure systemd limits
    sudo mkdir -p /etc/systemd/system.conf.d/
    cat << 'EOF' | sudo tee /etc/systemd/system.conf.d/limits.conf > /dev/null
[Manager]
DefaultLimitNOFILE=65536
DefaultLimitNPROC=32768
EOF
    
    # Reload systemd
    sudo systemctl daemon-reexec 2>/dev/null || true
    
    echo -e "${GREEN}>> System limits configured for optimal performance.${NC}"
    log_message "System limits configured."
    
    # Mark compatibility configuration as complete
    STATUS[compatibility_configured]=true
}

check_cpu_architecture() {
    echo -e "${BLUE}>> Checking CPU architecture compatibility...${NC}"
    
    local arch=$(uname -m)
    echo -e "${BLUE}   - Architecture: $arch${NC}"
    
    case $arch in
        x86_64)
            echo -e "${GREEN}>> x86_64 architecture detected - fully compatible.${NC}"
            # Check for 32-bit compatibility
            if [ -f /lib64/ld-linux-x86-64.so.2 ]; then
                echo -e "${GREEN}   - 64-bit libraries available.${NC}"
            fi
            if [ -f /lib/ld-linux.so.2 ] || [ -f /lib32/ld-linux.so.2 ]; then
                echo -e "${GREEN}   - 32-bit compatibility libraries available.${NC}"
            else
                echo -e "${YELLOW}[WARNING] 32-bit compatibility libraries may be missing.${NC}"
            fi
            ;;
        i386|i686)
            echo -e "${YELLOW}[WARNING] 32-bit architecture detected. Performance may be limited.${NC}"
            ;;
        aarch64|arm64)
            echo -e "${RED}[WARNING] ARM64 architecture detected. Binary compatibility issues likely.${NC}"
            read -p "Do you want to continue at your own risk? [y/N]: " continue_arm
            if [[ ! "$continue_arm" =~ ^[Yy]$ ]]; then
                error_exit "Installation cancelled due to architecture incompatibility."
            fi
            ;;
        *)
            echo -e "${RED}[WARNING] Unsupported architecture: $arch${NC}"
            read -p "Do you want to continue at your own risk? [y/N]: " continue_unknown
            if [[ ! "$continue_unknown" =~ ^[Yy]$ ]]; then
                error_exit "Installation cancelled due to architecture incompatibility."
            fi
            ;;
    esac
    
    log_message "Architecture check completed: $arch"
}

verify_binary_dependencies() {
    echo -e "${BLUE}>> Verifying binary dependencies...${NC}"
    
    # Check for essential libraries that game binaries typically need
    local essential_libs=(
        "/lib/ld-linux.so.2"
        "/lib32/ld-linux.so.2" 
        "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
        "/lib64/ld-linux-x86-64.so.2"
    )
    
    local found_loader=false
    for lib in "${essential_libs[@]}"; do
        if [ -f "$lib" ]; then
            echo -e "${GREEN}   - Found dynamic loader: $lib${NC}"
            found_loader=true
            break
        fi
    done
    
    if [ "$found_loader" = false ]; then
        echo -e "${RED}[ERROR] No compatible dynamic loader found. Binary execution may fail.${NC}"
        log_message "ERROR: No compatible dynamic loader found."
    fi
    
    # Check for pthread library (essential for multi-threaded game servers)
    if ldconfig -p | grep -q "libpthread.so"; then
        echo -e "${GREEN}   - pthread library available.${NC}"
    else
        echo -e "${YELLOW}[WARNING] pthread library may not be available.${NC}"
    fi
    
    # Check for math library
    if ldconfig -p | grep -q "libm.so"; then
        echo -e "${GREEN}   - Math library available.${NC}"
    else
        echo -e "${YELLOW}[WARNING] Math library may not be available.${NC}"
    fi
    
    log_message "Binary dependencies verification completed."
}
check_kernel_version

# Enhanced compatibility checks and optimizations
check_cpu_architecture
verify_binary_dependencies
configure_kernel_parameters
install_legacy_compatibility
configure_limits

update_packages() {
    echo -e "${BLUE}>> Updating package lists...${NC}"
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        sudo apt-get -qq update || error_exit "apt-get update failed."
    elif [ "$PKG_MANAGER" = 'yum' ]; then
        sudo yum -q -y update || error_exit "yum update failed."
    fi
    log_message "Package lists updated."
}
update_packages

install_packages
check_and_install_xxd
check_and_install_commands
check_postgresql_version
install_postgresql
configure_postgresql
secure_postgresql
setup_firewall_rules
handle_existing_install_dir
download_server_files
extract_server_files
download_management_scripts
import_databases
remove_sql_directory
patch_server_files
update_database_ips
configure_grub
create_admin_account
admin_info_message

chmod -R 755 "$INSTALL_DIR"

prompt_systemd_service

# Final installation message
if [ "${STATUS[postgresql_installed]}" = true ] && [ "${STATUS[config_success]}" = true ] && \
   [ "${STATUS[db_creation_success]}" = true ] && [ "${STATUS[sql_import_success]}" = true ] && \
   [ "${STATUS[download_success]}" = true ] && [ "${STATUS[patch_success]}" = true ] && \
   [ "${STATUS[admin_creation_success]}" = true ]; then
    echo -e "${GREEN}
==================================================
           Installation Complete!
==================================================${NC}"
    echo -e "Server IP            : ${GREEN}$IP${NC}"
    echo -e "PostgreSQL Version   : ${GREEN}$DB_VERSION${NC}"
    echo -e "Database User        : ${GREEN}$DB_USER${NC}"
    echo -e "Database Password    : ${GREEN}$DB_PASS${NC}"
    echo -e "Admin Username       : ${GREEN}$ADMIN_USERNAME${NC}"
    echo -e "Server Directory     : ${GREEN}$INSTALL_DIR${NC}"
    
    # SSH Status Display
    if [ "${STATUS[ssh_configured]}" = true ]; then
        echo -e "SSH Status           : ${GREEN}Configured and Running${NC}"
        echo -e "SSH Connection       : ${GREEN}ssh root@$IP${NC}"
        echo -e "PuTTY Settings       : Host: ${GREEN}$IP${NC}, Port: ${GREEN}22${NC}, SSH"
    else
        echo -e "SSH Status           : ${YELLOW}Not Configured${NC}"
    fi
    
    # Compatibility Status Display
    if [ "${STATUS[compatibility_configured]}" = true ]; then
        echo -e "Compatibility        : ${GREEN}Optimized for Binary Execution${NC}"
        echo -e "Kernel Parameters    : ${GREEN}Configured${NC}"
        echo -e "Legacy Libraries     : ${GREEN}Installed${NC}"
    else
        echo -e "Compatibility        : ${YELLOW}Basic Configuration${NC}"
    fi
    
    echo -e "\n${BLUE}Management Commands:${NC}"
    echo -e "  Start server       : ${GREEN}$INSTALL_DIR/start${NC}"
    echo -e "  Stop server        : ${GREEN}$INSTALL_DIR/stop${NC}"
    echo -e "  Monitor server     : ${GREEN}$INSTALL_DIR/monitor.sh${NC}"
    echo -e "  Backup server      : ${GREEN}$INSTALL_DIR/backup.sh${NC}"
    echo -e "  Restore server     : ${GREEN}$INSTALL_DIR/restore.sh${NC}"
    echo -e "  Create accounts    : ${GREEN}./account_creator.sh${NC}"
    if [ "${STATUS[grub_configured]}" = true ]; then
        echo -e "\n${YELLOW}[IMPORTANT] A reboot is required for GRUB changes to take effect.${NC}"
    fi
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo -e "1. Reboot your server if GRUB was configured"
    echo -e "2. Start the server: ${GREEN}$INSTALL_DIR/start${NC}"
    echo -e "3. Monitor status: ${GREEN}$INSTALL_DIR/monitor.sh${NC}"
    echo -e "4. Create game accounts with account_creator.sh"
    if [ "${STATUS[ssh_configured]}" = true ]; then
        echo -e "5. You can now connect remotely via SSH/PuTTY using IP: ${GREEN}$IP${NC}"
    fi
    log_message "Installation completed successfully."
else
    echo -e "${RED}
==================================================
             Installation Failed!
==================================================${NC}"
    echo -e "Possible issues encountered:"
    [ "${STATUS[postgresql_installed]}" = false ] && echo -e " - PostgreSQL installation issue."
    [ "${STATUS[config_success]}" = false ] && echo -e " - PostgreSQL configuration issue."
    [ "${STATUS[download_success]}" = false ] && echo -e " - Server files download/extraction issue."
    [ "${STATUS[db_creation_success]}" = false ] && echo -e " - Database creation issue."
    [ "${STATUS[sql_import_success]}" = false ] && echo -e " - SQL import failed."
    [ "${STATUS[patch_success]}" = false ] && echo -e " - File patching issue."
    [ "${STATUS[admin_creation_success]}" = false ] && echo -e " - Admin account creation failed."
    [ "${STATUS[ssh_configured]}" = false ] && echo -e " - SSH configuration may have failed."
    [ "${STATUS[compatibility_configured]}" = false ] && echo -e " - System compatibility optimization may have failed."
    echo -e "Please check the error messages above and consult ${YELLOW}${LOG_FILE}${NC} for details."
    log_message "Installation failed."
fi
