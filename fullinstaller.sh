#!/bin/bash

# Color definitions
RED='\e[0;31m'
GREEN='\e[1;32m'
BLUE='\e[0;36m'
YELLOW='\e[1;33m'
RC='\e[0m'

# Initial message
INSTALLER_MSG="${BLUE}
==================================================
             AK Installer Script
              Developer: Dulgan
==================================================${RC}"
echo -e "$INSTALLER_MSG"

# Display recommended OS notice
display_recommendation() {
    echo -e "${YELLOW}
[Notice] The recommended operating system for this installation is Debian 11.
         The server may not function correctly on other systems.
${RC}"
}
display_recommendation

# Variables
DB_VERSION=13
DB_USER='postgres'
DB_PASS=''
INSTALL_DIR='/root/hxsy'
DOWNLOAD_URL='https://mega.nz/file/T75VTTqC#S8Ou186bqyNeIQKlUm4MV5gS7A_YBbz_wauCEY7sLOs'

# Operation status variables
declare -A STATUS=(
    [postgresql_installed]=false
    [config_success]=false
    [db_creation_success]=false
    [sql_import_success]=false
    [download_success]=false
    [patch_success]=false
    [admin_creation_success]=false
    [grub_configured]=false
)

# Exit on error with a message
error_exit() {
    echo -e "${RED}[ERROR] $1${RC}"
    exit 1
}

# Detect the operating system and set the package manager
detect_os() {
    if [ -f /etc/debian_version ]; then
        OS='Debian'
        PKG_MANAGER='apt-get'
    elif [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
        OS='CentOS'
        PKG_MANAGER='yum'
    else
        error_exit "Unsupported operating system. This script supports Debian and CentOS."
    fi
}

# Select IP address function
select_ip() {
    echo -e "${BLUE}>> Please select an IP address to use:${RC}"
    ips=($(hostname -I))
    for i in "${!ips[@]}"; do
        echo "   [$((i + 1))] ${ips[$i]}"
    done
    read -p "Enter the number of the IP address: " ip_choice
    IP=${ips[$((ip_choice - 1))]}
    if [[ -z "$IP" ]]; then
        error_exit "Invalid IP selection."
    fi
    echo -e "${GREEN}>> Selected IP: $IP${RC}"
}

# Check the kernel version
check_kernel_version() {
    KERNEL_VERSION=$(uname -r | cut -d'.' -f1)
    if [ "$KERNEL_VERSION" -ge 6 ]; then
        echo -e "${YELLOW}[Warning] Your kernel version is 6.x or higher."
        echo -e "For compatibility with the server binaries, it is recommended to use kernel 5.x."
        echo -e "Consider downgrading your kernel version, for example by using Debian 11.${RC}"
        read -p "Press Enter to continue at your own risk or Ctrl+C to cancel..." dummy
    fi
}

# Update package lists
update_packages() {
    echo -e "${BLUE}>> Updating package lists...${RC}"
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        sudo apt-get -qq update || error_exit "Failed to update package lists."
    elif [ "$PKG_MANAGER" = 'yum' ]; then
        sudo yum -q -y update || error_exit "Failed to update package lists."
    fi
}

# Install necessary packages
install_packages() {
    echo -e "${BLUE}>> Installing necessary packages...${RC}"
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        sudo apt-get -qq install -y wget pwgen gnupg unzip megatools || error_exit "Failed to install necessary packages."
    elif [ "$PKG_MANAGER" = 'yum' ]; then
        echo -e "${BLUE}>> Adding the Raven repository...${RC}"
        sudo dnf install -y https://pkgs.dyn.su/el9/base/x86_64/raven-release.el9.noarch.rpm || error_exit "Failed to add Raven repository."
        sudo dnf install -y wget pwgen gnupg2 unzip megatools vim-common || error_exit "Failed to install necessary packages."
    fi
}

# Check and install xxd if not present
check_and_install_xxd() {
    echo -e "${BLUE}>> Checking for xxd...${RC}"
    if ! command -v xxd &> /dev/null; then
        echo -e "${YELLOW}[Notice] xxd is not installed. Installing...${RC}"
        if [ "$PKG_MANAGER" = 'apt-get' ]; then
            sudo apt-get -qq install -y xxd || error_exit "Failed to install xxd."
        elif [ "$PKG_MANAGER" = 'yum' ]; then
            sudo dnf install -y vim-common || error_exit "Failed to install xxd (vim-common)."
        fi
    else
        echo -e "${GREEN}>> xxd is already installed.${RC}"
    fi
}

# PostgreSQL version check
check_postgresql_version() {
    if command -v psql &> /dev/null; then
        INSTALLED_VERSION=$(psql --version | awk '{print $3}' | cut -d '.' -f1)
        if [ "$INSTALLED_VERSION" != "$DB_VERSION" ]; then
            echo -e "${YELLOW}[Notice] PostgreSQL version $INSTALLED_VERSION is installed. This script requires version $DB_VERSION.${RC}"
            read -p "Do you want to remove the current version and install PostgreSQL $DB_VERSION? [y/N]: " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                if [ "$PKG_MANAGER" = 'apt-get' ]; then
                    sudo apt-get -qq remove --purge postgresql || error_exit "Failed to remove PostgreSQL."
                    sudo apt-get -qq autoremove || error_exit "Failed to clean up PostgreSQL removal."
                elif [ "$PKG_MANAGER" = 'yum' ]; then
                    sudo yum -q -y remove postgresql || error_exit "Failed to remove PostgreSQL."
                    sudo yum -q -y autoremove || error_exit "Failed to clean up PostgreSQL removal."
                fi
                install_postgresql
            else
                error_exit "Aborted. PostgreSQL version is not $DB_VERSION."
            fi
        else
            echo -e "${GREEN}>> PostgreSQL version $DB_VERSION is already installed. No need to reinstall.${RC}"
            STATUS[postgresql_installed]=true
        fi
    else
        echo -e "${BLUE}>> PostgreSQL is not installed. Proceeding with installation...${RC}"
        install_postgresql
    fi
}

# Install PostgreSQL (only if not already installed)
install_postgresql() {
    if command -v psql &> /dev/null; then
        echo -e "${GREEN}>> PostgreSQL is already installed. Skipping installation.${RC}"
        STATUS[postgresql_installed]=true
        return
    fi

    echo -e "${BLUE}>> Installing PostgreSQL $DB_VERSION...${RC}"

    if [ "$OS" = 'Debian' ]; then
        wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - || error_exit "Failed to add PostgreSQL GPG key."
        echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
        sudo apt-get -qq update || error_exit "Failed to update package lists."
        sudo apt-get -qq install -y "postgresql-$DB_VERSION" || error_exit "Failed to install PostgreSQL."

    elif [ "$OS" = 'CentOS' ]; then
        echo -e "${BLUE}>> Adding PostgreSQL repository...${RC}"
        sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm || error_exit "Failed to add PostgreSQL repository."
        echo -e "${BLUE}>> Installing PostgreSQL $DB_VERSION...${RC}"
        sudo dnf install -y "postgresql$DB_VERSION-server" "postgresql$DB_VERSION-contrib" || error_exit "Failed to install PostgreSQL packages."
        sudo "/usr/pgsql-$DB_VERSION/bin/postgresql-$DB_VERSION-setup" initdb || error_exit "Failed to initialize PostgreSQL database."
        sudo systemctl enable "postgresql-$DB_VERSION"
        sudo systemctl start "postgresql-$DB_VERSION"
    fi

    if command -v psql &> /dev/null; then
        STATUS[postgresql_installed]=true
        echo -e "${GREEN}>> PostgreSQL $DB_VERSION installed successfully.${RC}"
    else
        error_exit "PostgreSQL installation failed."
    fi
}

# Configure PostgreSQL
configure_postgresql() {
    echo -e "${BLUE}>> Configuring PostgreSQL...${RC}"

    if [ "$OS" = 'Debian' ]; then
        PG_CONF="/etc/postgresql/$DB_VERSION/main/postgresql.conf"
        PG_HBA="/etc/postgresql/$DB_VERSION/main/pg_hba.conf"
        SERVICE_NAME="postgresql"
    elif [ "$OS" = 'CentOS' ]; then
        PG_CONF="/var/lib/pgsql/$DB_VERSION/data/postgresql.conf"
        PG_HBA="/var/lib/pgsql/$DB_VERSION/data/pg_hba.conf"
        SERVICE_NAME="postgresql-$DB_VERSION"
    fi

    sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" "$PG_CONF" || error_exit "Failed to update postgresql.conf."

    if ! grep -q "host    all             all             0.0.0.0/0            md5" "$PG_HBA"; then
        echo "host    all             all             0.0.0.0/0            md5" | sudo tee -a "$PG_HBA" || error_exit "Failed to update pg_hba.conf."
    fi

    sudo systemctl restart "$SERVICE_NAME" || error_exit "Failed to restart PostgreSQL service."

    STATUS[config_success]=true
    echo -e "${GREEN}>> PostgreSQL configuration completed.${RC}"
}

# Secure PostgreSQL
secure_postgresql() {
    echo -e "${BLUE}>> Securing PostgreSQL...${RC}"
    DB_PASS=$(pwgen -s 32 1)
    cd /tmp
    sudo -H -u "$DB_USER" psql -q -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" >/dev/null || error_exit "Failed to set PostgreSQL password."
    echo -e "${GREEN}>> Password set for PostgreSQL user '$DB_USER'.${RC}"
}

# Set up firewall rules
setup_firewall_rules() {
    echo -e "${BLUE}>> Configuring firewall rules...${RC}"
    PORTS=("5567" "5568" "6543" "7654" "7777" "7878" "10021" "10022")
    if [ -x "$(command -v ufw)" ]; then
        echo -e "${GREEN}>> Configuring UFW firewall...${RC}"
        sudo ufw allow ssh >/dev/null 2>&1
        for port in "${PORTS[@]}"; do
            if sudo ufw status | grep -qw "$port"; then
                echo -e "${BLUE}   - Port $port is already allowed in UFW.${RC}"
            else
                sudo ufw allow "$port"/tcp || error_exit "Failed to allow port $port in UFW."
                echo -e "${GREEN}   - Port $port allowed in UFW.${RC}"
            fi
        done
        sudo ufw reload || error_exit "Failed to reload UFW."
    elif [ -x "$(command -v firewall-cmd)" ]; then
        echo -e "${GREEN}>> Configuring Firewalld firewall...${RC}"
        sudo firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
        for port in "${PORTS[@]}"; do
            if sudo firewall-cmd --list-ports | grep -qw "$port/tcp"; then
                echo -e "${BLUE}   - Port $port is already allowed in Firewalld.${RC}"
            else
                sudo firewall-cmd --permanent --add-port="$port"/tcp || error_exit "Failed to allow port $port in Firewalld."
                echo -e "${GREEN}   - Port $port allowed in Firewalld.${RC}"
            fi
        done
        sudo firewall-cmd --reload || error_exit "Failed to reload Firewalld."
    else
        echo -e "${YELLOW}[Notice] No supported firewall detected. Please configure your firewall manually.${RC}"
    fi
    echo -e "${GREEN}>> Firewall rules set successfully.${RC}"
}

# Handle existing INSTALL_DIR
handle_existing_install_dir() {
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}[Notice] The directory $INSTALL_DIR already exists.${RC}"
        echo -e "What would you like to do?"
        echo -e "   [1] Delete the existing directory and proceed."
        echo -e "   [2] Rename the existing directory by appending '-old' and proceed."
        read -p "Enter your choice [1/2]: " dir_choice
        if [ "$dir_choice" = "1" ]; then
            echo -e "${BLUE}>> Deleting existing directory $INSTALL_DIR...${RC}"
            rm -rf "$INSTALL_DIR" || error_exit "Failed to delete $INSTALL_DIR."
            echo -e "${GREEN}>> Directory deleted.${RC}"
        elif [ "$dir_choice" = "2" ]; then
            timestamp=$(date +%Y%m%d%H%M%S)
            new_dir="${INSTALL_DIR}-old-$timestamp"
            echo -e "${BLUE}>> Renaming $INSTALL_DIR to $new_dir...${RC}"
            mv "$INSTALL_DIR" "$new_dir" || error_exit "Failed to rename $INSTALL_DIR."
            echo -e "${GREEN}>> Directory renamed to $new_dir.${RC}"
        else
            error_exit "Invalid choice. Please run the script again and select a valid option."
        fi
    fi
}

# Download server files
download_server_files() {
    echo -e "${BLUE}>> Downloading server files...${RC}"
    megadl "$DOWNLOAD_URL" --path "/root/hxsy.zip" || error_exit "Failed to download hxsy.zip."
    if [ -f "/root/hxsy.zip" ]; then
        STATUS[download_success]=true
        echo -e "${GREEN}>> Server files downloaded.${RC}"
    else
        error_exit "Failed to download hxsy.zip."
    fi
}

# Extract server files
extract_server_files() {
    echo -e "${BLUE}>> Extracting server files...${RC}"
    unzip -qo "/root/hxsy.zip" -d "/root" || error_exit "Failed to extract hxsy.zip."
    chmod -R 755 "$INSTALL_DIR"
    rm "/root/hxsy.zip"
    echo -e "${GREEN}>> Server files extracted.${RC}"
}

# Download start and stop scripts
download_start_stop_scripts() {
    echo -e "${BLUE}>> Downloading start and stop scripts...${RC}"
    cd "$INSTALL_DIR" || error_exit "Failed to change directory to $INSTALL_DIR."
    wget -q -O start "https://raw.githubusercontent.com/MrDulgan/AKF/main/start" || error_exit "Failed to download start script."
    wget -q -O stop "https://raw.githubusercontent.com/MrDulgan/AKF/main/stop" || error_exit "Failed to download stop script."
    chmod +x start stop || error_exit "Failed to make start and stop scripts executable."
    echo -e "${GREEN}>> Start and stop scripts downloaded and made executable.${RC}"
}

# Create and import databases
import_databases() {
    echo -e "${BLUE}>> Creating and importing databases...${RC}"
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
            sudo -H -u "$DB_USER" psql -q "$DB" < "$SQL_FILE" >/dev/null || error_exit "Failed to import $DB.bak."
        else
            error_exit "SQL file $SQL_FILE not found."
        fi
    done
    STATUS[sql_import_success]=true
    echo -e "${GREEN}>> Databases imported successfully.${RC}"
}

# Remove the SQL directory after importing
remove_sql_directory() {
    if [ -d "$INSTALL_DIR/SQL" ]; then
        echo -e "${BLUE}>> Removing SQL directory...${RC}"
        rm -rf "$INSTALL_DIR/SQL" || error_exit "Failed to remove SQL directory."
        echo -e "${GREEN}>> SQL directory removed successfully.${RC}"
    else
        echo -e "${BLUE}>> SQL directory not found, skipping removal.${RC}"
    fi
}

# Patch server files
patch_server_files() {
    echo -e "${BLUE}>> Patching server files...${RC}"

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
                echo -e "${BLUE}   - Original value found in $binary_file at offset $offset. Patching...${RC}"
                printf "$new_value" | dd of="$binary_file" bs=1 seek=$offset conv=notrunc >/dev/null 2>&1 || error_exit "Failed to patch $binary_file at offset $offset."
                echo -e "${GREEN}   - Patched value at offset $offset in $binary_file.${RC}"
            else
                echo -e "${BLUE}   - Value at offset $offset does not match the original value. No patch needed.${RC}"
            fi
        else
            echo -e "${YELLOW}[Notice] File $binary_file does not exist, skipping.${RC}"
        fi
    }

    offset=2750792
    original_value="01346228"
    new_value="01404908"

    patch_mission_server "$INSTALL_DIR/MissionServer/MissionServer" "$offset" "$original_value" "$new_value"

    echo -e "${BLUE}>> Patching binary IP addresses...${RC}"

    sed -i "s/\x44\x24\x0c\x28\x62\x34/\x44\x24\x0c\x08\x49\x40/g" "$INSTALL_DIR/MissionServer/MissionServer" || error_exit "Failed to patch MissionServer."
    sed -i "s/\x3d\xc0\xa8\x64/\x3d$PATCHIP/g" "$INSTALL_DIR/WorldServer/WorldServer" || error_exit "Failed to patch WorldServer."
    sed -i "s/\x3d\xc0\xa8\x64/\x3d$PATCHIP/g" "$INSTALL_DIR/ZoneServer/ZoneServer" || error_exit "Failed to patch ZoneServer."
    STATUS[patch_success]=true
    echo -e "${GREEN}>> Server files patched successfully.${RC}"
}

# Update database IP addresses
update_database_ips() {
    echo -e "${BLUE}>> Updating database IP addresses...${RC}"
    cd /tmp
    sudo -H -u "$DB_USER" psql -q -d "FFAccount" -c "UPDATE worlds SET ip = '$IP';" >/dev/null || error_exit "Failed to update IP in FFAccount database."
    sudo -H -u "$DB_USER" psql -q -d "FFDB1" -c "UPDATE serverstatus SET ext_address = '$IP', int_address = '$IP' WHERE name != 'MissionServer';" >/dev/null || error_exit "Failed to update external and internal IPs in FFDB1 database."
    sudo -H -u "$DB_USER" psql -q -d "FFDB1" -c "UPDATE serverstatus SET ext_address = 'none' WHERE name = 'MissionServer';" >/dev/null || error_exit "Failed to update MissionServer's external IP to 'none' in FFDB1 database."
    echo -e "${GREEN}>> Database IP addresses updated successfully.${RC}"
}

# Configure GRUB for vsyscall support
configure_grub() {
    echo -e "${BLUE}>> Configuring GRUB for vsyscall support...${RC}"

    if [ -f /etc/default/grub ]; then
        if grep -q "vsyscall=emulate" /etc/default/grub; then
            echo -e "${GREEN}>> vsyscall=emulate is already set in GRUB configuration.${RC}"
            STATUS[grub_configured]=false
        else
            if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
                sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 vsyscall=emulate"/' /etc/default/grub || error_exit "Failed to update GRUB_CMDLINE_LINUX_DEFAULT."
                echo -e "${GREEN}>> vsyscall=emulate added to GRUB_CMDLINE_LINUX_DEFAULT.${RC}"
            elif grep -q "^GRUB_CMDLINE_LINUX=" /etc/default/grub; then
                sudo sed -i 's/\(GRUB_CMDLINE_LINUX="[^"]*\)"/\1 vsyscall=emulate"/' /etc/default/grub || error_exit "Failed to update GRUB_CMDLINE_LINUX."
                echo -e "${GREEN}>> vsyscall=emulate added to GRUB_CMDLINE_LINUX.${RC}"
            else
                echo 'GRUB_CMDLINE_LINUX="vsyscall=emulate"' | sudo tee -a /etc/default/grub || error_exit "Failed to add GRUB_CMDLINE_LINUX."
                echo -e "${GREEN}>> GRUB_CMDLINE_LINUX created with vsyscall=emulate.${RC}"
            fi
        fi

        if command -v update-grub &> /dev/null; then
            sudo update-grub || error_exit "Failed to update GRUB."
        elif command -v grub2-mkconfig &> /dev/null; then
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg || error_exit "Failed to update GRUB."
        else
            error_exit "GRUB update command not found."
        fi

        STATUS[grub_configured]=true
        echo -e "${GREEN}>> GRUB configuration updated. A system reboot is required for changes to take effect.${RC}"
    else
        echo -e "${YELLOW}[Notice] /etc/default/grub not found. Skipping GRUB configuration.${RC}"
    fi
}

# Admin creation information message
admin_info_message() {
    echo -e "${BLUE}
==================================================
       Admin Account Created Successfully
==================================================${RC}"
    echo -e "${YELLOW}[IMPORTANT]${RC} Please log into the game, create a character, and then update the 'privilege' column in the 'player_characters' table to 5 for your character in the FFDB1 database."
}

# Create admin account
create_admin_account() {
    echo -e "\n${BLUE}>> Admin Account Creation${RC}"
    read -p "Username: " ADMIN_USERNAME
    read -s -p "Password: " ADMIN_PASSWORD
    echo ""
    echo -e "${GREEN}>> Creating admin account...${RC}"
    ADMIN_PWD_HASH=$(echo -n "$ADMIN_PASSWORD" | md5sum | cut -d ' ' -f1)
    cd /tmp
    sudo -H -u "$DB_USER" psql -q -d "FFMember" -c "INSERT INTO tb_user (mid, password, pwd) VALUES ('$ADMIN_USERNAME', '$ADMIN_PASSWORD', '$ADMIN_PWD_HASH');" >/dev/null || error_exit "Failed to insert into FFMember database."
    USER_ID=$(sudo -H -u "$DB_USER" psql -At -d "FFMember" -c "SELECT idnum FROM tb_user WHERE mid = '$ADMIN_USERNAME';")
    sudo -H -u "$DB_USER" psql -q -d "FFAccount" -c "INSERT INTO accounts (id, username, password) VALUES ('$USER_ID', '$ADMIN_USERNAME', '$ADMIN_PASSWORD');" >/dev/null || error_exit "Failed to insert into FFAccount database."
    sudo -H -u "$DB_USER" psql -q -d "FFMember" -c "UPDATE tb_user SET pvalues = 999999 WHERE mid = '$ADMIN_USERNAME';" >/dev/null || error_exit "Failed to update pvalues in FFMember database."
    sudo -H -u "$DB_USER" psql -q -d "FFAccount" -c "INSERT INTO gm_tool_accounts (id, account_name, password, privilege) VALUES ('$USER_ID', '$ADMIN_USERNAME', '$ADMIN_PASSWORD', 5);" >/dev/null || error_exit "Failed to insert into gm_tool_accounts."
    STATUS[admin_creation_success]=true
    echo -e "${GREEN}>> Admin account '$ADMIN_USERNAME' created successfully.${RC}"
}

# Main flow
detect_os
select_ip
check_kernel_version
update_packages
install_packages
check_and_install_xxd
check_postgresql_version
install_postgresql
configure_postgresql
secure_postgresql
setup_firewall_rules
handle_existing_install_dir
download_server_files
extract_server_files
download_start_stop_scripts
import_databases
remove_sql_directory
patch_server_files
update_database_ips
configure_grub
create_admin_account
admin_info_message
chmod -R 755 "$INSTALL_DIR"

# Installation result message
if [ "${STATUS[postgresql_installed]}" = true ] && [ "${STATUS[config_success]}" = true ] && \
   [ "${STATUS[db_creation_success]}" = true ] && [ "${STATUS[sql_import_success]}" = true ] && \
   [ "${STATUS[download_success]}" = true ] && [ "${STATUS[patch_success]}" = true ] && \
   [ "${STATUS[admin_creation_success]}" = true ]; then
    echo -e "${GREEN}
==================================================
           Installation Complete!
==================================================${RC}"
    echo -e "Server IP            : ${GREEN}$IP${RC}"
    echo -e "PostgreSQL Version   : ${GREEN}$DB_VERSION${RC}"
    echo -e "Database User        : ${GREEN}$DB_USER${RC}"
    echo -e "Database Password    : ${GREEN}$DB_PASS${RC}"
    echo -e "Server Directory     : ${GREEN}$INSTALL_DIR/${RC}"
    echo -e "To start the server  : ${GREEN}$INSTALL_DIR/start${RC}"
    if [ "${STATUS[grub_configured]}" = true ]; then
        echo -e "\n${YELLOW}[IMPORTANT] A system reboot is required for the GRUB configuration changes to take effect."
        echo -e "Please reboot your system before starting the server.${RC}"
    fi
else
    echo -e "${RED}
==================================================
             Installation Failed!
==================================================${RC}"
    echo -e "Possible reasons:"
    [ "${STATUS[postgresql_installed]}" = false ] && echo -e " - PostgreSQL installation failed."
    [ "${STATUS[config_success]}" = false ] && echo -e " - PostgreSQL configuration failed."
    [ "${STATUS[download_success]}" = false ] && echo -e " - Server files could not be downloaded or extracted."
    [ "${STATUS[db_creation_success]}" = false ] && echo -e " - Failed to create databases."
    [ "${STATUS[sql_import_success]}" = false ] && echo -e " - Failed to import SQL files into databases."
    [ "${STATUS[patch_success]}" = false ] && echo -e " - File patching failed."
    [ "${STATUS[admin_creation_success]}" = false ] && echo -e " - Failed to create admin account."
    echo -e "Please check the error messages above and try again."
fi
