#!/bin/bash

# Color definitions
RED='\e[0;31m'
GREEN='\e[1;32m'
BLUE='\e[0;36m'
RC='\e[0m'

# Initial message
INSTALLER_MSG="${BLUE}--------------------------------------------------\nAK Installer Script made by Dulgan\n--------------------------------------------------${RC}"
echo -e "$INSTALLER_MSG"

# Variables
DB_VERSION=13
DB_USER='postgres'
DB_PASS=''
INSTALL_DIR='/root/hxsy'
DOWNLOAD_URL='https://mega.nz/file/zuRHyBia#fD-_B-XXc20mt2T1ErD0b_YWqXHO8KDpqCEvmz7Xfy4'

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
    echo -e "${RED}$1${RC}"
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
        error_exit "Unsupported operating system. This script supports Ubuntu, Debian, and CentOS."
    fi
}

# Check the kernel version
check_kernel_version() {
    KERNEL_VERSION=$(uname -r | cut -d'.' -f1)
    if [ "$KERNEL_VERSION" -ge 6 ]; then
        echo -e "${RED}Warning: Your kernel version is 6.x or higher.${RC}"
        echo -e "${RED}For compatibility with the server binaries, it is recommended to use kernel 5.x.${RC}"
        echo -e "${RED}Consider downgrading your kernel version, for example by using Debian 11.${RC}"
        read -p "Press Enter to continue at your own risk or Ctrl+C to cancel..." dummy
    fi
}

# Update package lists
update_packages() {
    echo -e "${BLUE}Updating package lists...${RC}"
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        sudo apt-get -qq update || error_exit "Failed to update package lists."
    elif [ "$PKG_MANAGER" = 'yum' ]; then
        sudo yum -q -y update || error_exit "Failed to update package lists."
    fi
}

# Install necessary packages
install_packages() {
    echo -e "${BLUE}Installing necessary packages...${RC}"
    if [ "$PKG_MANAGER" = 'apt-get' ]; then
        sudo apt-get -qq install -y wget pwgen gnupg unzip megatools || error_exit "Failed to install necessary packages."
    elif [ "$PKG_MANAGER" = 'yum' ]; then
        # Add the Raven repository for megatools
        echo -e "${BLUE}Adding the Raven repository...${RC}"
        sudo dnf install -y https://pkgs.dyn.su/el9/base/x86_64/raven-release.el9.noarch.rpm || error_exit "Failed to add Raven repository."

        # Install necessary packages including megatools
        sudo dnf install -y wget pwgen gnupg2 unzip megatools || error_exit "Failed to install necessary packages."
    fi
}

# Install PostgreSQL (only if not already installed)
install_postgresql() {
    # Check if PostgreSQL is already installed
    if command -v psql &> /dev/null; then
        echo -e "${GREEN}PostgreSQL is already installed. Skipping installation.${RC}"
        STATUS[postgresql_installed]=true
        return
    fi
    
    echo -e "${BLUE}Installing PostgreSQL $DB_VERSION...${RC}"
    
    if [ "$OS" = 'Debian' ]; then
        wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - || error_exit "Failed to add PostgreSQL GPG key."
        echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
        sudo apt-get -qq update || error_exit "Failed to update package lists."
        sudo apt-get -qq install -y "postgresql-$DB_VERSION" || error_exit "Failed to install PostgreSQL."
    
    elif [ "$OS" = 'CentOS' ]; then
        # Add the PostgreSQL repository for CentOS 9 Stream
        echo -e "${BLUE}Adding PostgreSQL repository...${RC}"
        sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm || error_exit "Failed to add PostgreSQL repository."

        # Install PostgreSQL
        echo -e "${BLUE}Installing PostgreSQL $DB_VERSION...${RC}"
        sudo dnf install -y "postgresql$DB_VERSION-server" "postgresql$DB_VERSION-contrib" || error_exit "Failed to install PostgreSQL packages."
        
        # Initialize PostgreSQL database
        sudo "/usr/pgsql-$DB_VERSION/bin/postgresql-$DB_VERSION-setup" initdb || error_exit "Failed to initialize PostgreSQL database."
        
        # Enable and start PostgreSQL service
        sudo systemctl enable "postgresql-$DB_VERSION"
        sudo systemctl start "postgresql-$DB_VERSION"
    fi

    # Final check if PostgreSQL is installed
    if command -v psql &> /dev/null; then
        STATUS[postgresql_installed]=true
        echo -e "${GREEN}PostgreSQL $DB_VERSION installed successfully.${RC}"
    else
        error_exit "PostgreSQL installation failed."
    fi
}

# Configure PostgreSQL
configure_postgresql() {
    echo -e "${BLUE}Configuring PostgreSQL...${RC}"
    
    if [ "$OS" = 'Debian' ]; then
        PG_CONF="/etc/postgresql/$DB_VERSION/main/postgresql.conf"
        PG_HBA="/etc/postgresql/$DB_VERSION/main/pg_hba.conf"
        SERVICE_NAME="postgresql"
    elif [ "$OS" = 'CentOS' ]; then
        PG_CONF="/var/lib/pgsql/$DB_VERSION/data/postgresql.conf"
        PG_HBA="/var/lib/pgsql/$DB_VERSION/data/pg_hba.conf"
        SERVICE_NAME="postgresql-$DB_VERSION"
    fi

    # Modify postgresql.conf and pg_hba.conf as needed
    sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" "$PG_CONF" || error_exit "Failed to update postgresql.conf."
    
    if ! grep -q "host    all             all             0.0.0.0/0            md5" "$PG_HBA"; then
        echo "host    all             all             0.0.0.0/0            md5" | sudo tee -a "$PG_HBA" || error_exit "Failed to update pg_hba.conf."
    fi
    
    # Restart PostgreSQL service
    sudo systemctl restart "$SERVICE_NAME" || error_exit "Failed to restart PostgreSQL service."
    
    STATUS[config_success]=true
    echo -e "${GREEN}PostgreSQL configuration completed.${RC}"
}

# Secure PostgreSQL
secure_postgresql() {
    echo -e "${BLUE}Securing PostgreSQL...${RC}"
    DB_PASS=$(pwgen -s 32 1)
    cd /tmp
    sudo -H -u "$DB_USER" psql -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" || error_exit "Failed to set PostgreSQL password."
    echo -e "${GREEN}Password set for PostgreSQL user '$DB_USER'.${RC}"
}

# Set up firewall rules
setup_firewall_rules() {
    echo -e "${BLUE}Setting up firewall rules...${RC}"
    PORTS=("6543" "5567" "5568" "10021" "10022")
    if [ -x "$(command -v ufw)" ]; then
        echo -e "${GREEN}Configuring UFW firewall...${RC}"
        sudo ufw allow ssh >/dev/null 2>&1
        for port in "${PORTS[@]}"; do
            if sudo ufw status | grep -qw "$port"; then
                echo -e "${BLUE}Port $port is already allowed in UFW.${RC}"
            else
                sudo ufw allow "$port"/tcp || error_exit "Failed to allow port $port in UFW."
                echo -e "${GREEN}Port $port allowed in UFW.${RC}"
            fi
        done
        sudo ufw reload || error_exit "Failed to reload UFW."
    elif [ -x "$(command -v firewall-cmd)" ]; then
        echo -e "${GREEN}Configuring Firewalld firewall...${RC}"
        sudo firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
        for port in "${PORTS[@]}"; do
            if sudo firewall-cmd --list-ports | grep -qw "$port/tcp"; then
                echo -e "${BLUE}Port $port is already allowed in Firewalld.${RC}"
            else
                sudo firewall-cmd --permanent --add-port="$port"/tcp || error_exit "Failed to allow port $port in Firewalld."
                echo -e "${GREEN}Port $port allowed in Firewalld.${RC}"
            fi
        done
        sudo firewall-cmd --reload || error_exit "Failed to reload Firewalld."
    else
        echo -e "${RED}No supported firewall detected. Please configure your firewall manually.${RC}"
    fi
    echo -e "${GREEN}Firewall rules set successfully.${RC}"
}

# Download server files
download_server_files() {
    echo -e "${BLUE}Downloading server files...${RC}"
    megadl "$DOWNLOAD_URL" --path "/root/hxsy.zip" || error_exit "Failed to download hxsy.zip."
    if [ -f "/root/hxsy.zip" ]; then
        STATUS[download_success]=true
        echo -e "${GREEN}Server files downloaded.${RC}"
    else
        error_exit "Failed to download hxsy.zip."
    fi
}

# Extract server files
extract_server_files() {
    echo -e "${BLUE}Extracting server files...${RC}"
    unzip -qo "/root/hxsy.zip" -d "/root" || error_exit "Failed to extract hxsy.zip."
    chmod -R 755 "$INSTALL_DIR"
    rm "/root/hxsy.zip"
    echo -e "${GREEN}Server files extracted.${RC}"
}

# Create and import databases
import_databases() {
    echo -e "${BLUE}Creating and importing databases...${RC}"
    DATABASES=("FFAccount" "FFDB1" "FFMember")

    cd /tmp

    for DB in "${DATABASES[@]}"; do
        sudo -H -u "$DB_USER" psql -c "DROP DATABASE IF EXISTS \"$DB\";" || error_exit "Failed to drop database $DB."
        sudo -H -u "$DB_USER" createdb -T template0 "$DB" || error_exit "Failed to create database $DB."
    done
    STATUS[db_creation_success]=true

    # Import SQL files
    for DB in "${DATABASES[@]}"; do
        SQL_FILE="$INSTALL_DIR/SQL/$DB.bak"
        if [ -f "$SQL_FILE" ]; then
            sudo -H -u "$DB_USER" psql "$DB" < "$SQL_FILE" || error_exit "Failed to import $DB.bak."
        else
            error_exit "SQL file $SQL_FILE not found."
        fi
    done
    STATUS[sql_import_success]=true
    echo -e "${GREEN}Databases imported successfully.${RC}"
}

# Patch server files
patch_server_files() {
    echo -e "${BLUE}Patching server files...${RC}"
    
    # Convert IP address to hex format and use the first 3 bytes
    IFS='.' read -r -a IP_ARRAY <<< "$IP"
    PATCHIP=$(printf '\\x%02X\\x%02X\\x%02X' "${IP_ARRAY[0]}" "${IP_ARRAY[1]}" "${IP_ARRAY[2]}")
    
    # Replace password placeholders in setup.ini files
    sed -i "s/xxxxxxxx/$DBPASS/g" "$INSTALL_DIR/setup.ini" || error_exit "Failed to patch setup.ini."
    sed -i "s/xxxxxxxx/$DBPASS/g" "$INSTALL_DIR/GatewayServer/setup.ini" || error_exit "Failed to patch GatewayServer/setup.ini."
    
    # Patch MissionServer binary file
    sed -i "s/\x44\x24\x0c\x28\x62\x34/\x44\x24\x0c\x08\x49\x40/g" "$INSTALL_DIR/MissionServer/MissionServer" || error_exit "Failed to patch MissionServer."
    
    # Replace IP address bytes in the binaries (adjust if necessary)
    ORIGINAL_IP_BYTES='\x3d\xc0\xa8\x64'  # Example placeholder (192.168.100)
    
    # Patch WorldServer binary
    sed -i "s/$ORIGINAL_IP_BYTES/\x3d$PATCHIP/g" "$INSTALL_DIR/WorldServer/WorldServer" || error_exit "Failed to patch WorldServer."
    
    # Patch ZoneServer binary
    sed -i "s/$ORIGINAL_IP_BYTES/\x3d$PATCHIP/g" "$INSTALL_DIR/ZoneServer/ZoneServer" || error_exit "Failed to patch ZoneServer."
    
    # Update IP addresses in PostgreSQL database
    sudo -u postgres psql -d FFAccount -c "UPDATE worlds SET ip = '$IP';" || error_exit "Failed to update IP in FFAccount database."
    sudo -u postgres psql -d FFDB1 -c "UPDATE serverstatus SET ext_address = '$IP' WHERE ext_address <> '127.0.0.1';" || error_exit "Failed to update external IP in FFDB1 database."
    sudo -u postgres psql -d FFDB1 -c "UPDATE serverstatus SET int_address = '$IP' WHERE int_address <> '127.0.0.1';" || error_exit "Failed to update internal IP in FFDB1 database."

    STATUS[patch_success]=true
    echo -e "${GREEN}Server files patched successfully.${RC}"
}

# Configure GRUB for vsyscall
configure_grub() {
    KERNEL_VERSION=$(uname -r | cut -d'.' -f1)
    
    # Only run this function if kernel version is 6 or higher
    if [ "$KERNEL_VERSION" -lt 6 ]; then
        echo -e "${GREEN}Kernel version is less than 6. No need to configure GRUB for vsyscall support.${RC}"
        return
    fi
    
    echo -e "${BLUE}Configuring GRUB for vsyscall support...${RC}"
    
    if [ -f /etc/default/grub ]; then
        # Check if vsyscall=emulate is already set in either GRUB_CMDLINE_LINUX_DEFAULT or GRUB_CMDLINE_LINUX
        if grep -q "vsyscall=emulate" /etc/default/grub; then
            echo -e "${GREEN}vsyscall=emulate is already set in GRUB configuration.${RC}"
            STATUS[grub_configured]=false
        else
            if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
                # Append vsyscall=emulate to GRUB_CMDLINE_LINUX_DEFAULT
                sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 vsyscall=emulate"/' /etc/default/grub || error_exit "Failed to update GRUB_CMDLINE_LINUX_DEFAULT."
                echo -e "${GREEN}vsyscall=emulate added to GRUB_CMDLINE_LINUX_DEFAULT.${RC}"
            elif grep -q "^GRUB_CMDLINE_LINUX=" /etc/default/grub; then
                # Append vsyscall=emulate to GRUB_CMDLINE_LINUX
                sudo sed -i 's/\(GRUB_CMDLINE_LINUX="[^"]*\)"/\1 vsyscall=emulate"/' /etc/default/grub || error_exit "Failed to update GRUB_CMDLINE_LINUX."
                echo -e "${GREEN}vsyscall=emulate added to GRUB_CMDLINE_LINUX.${RC}"
            else
                # Neither found, so create GRUB_CMDLINE_LINUX and add vsyscall=emulate
                echo 'GRUB_CMDLINE_LINUX="vsyscall=emulate"' | sudo tee -a /etc/default/grub || error_exit "Failed to add GRUB_CMDLINE_LINUX."
                echo -e "${GREEN}GRUB_CMDLINE_LINUX created with vsyscall=emulate.${RC}"
            fi
            
            # Run update-grub and notify the user
            sudo update-grub || error_exit "Failed to update GRUB."
            STATUS[grub_configured]=true
            echo -e "${GREEN}GRUB configuration updated. A system reboot is required for changes to take effect.${RC}"
        fi
    else
        echo -e "${RED}/etc/default/grub not found. Skipping GRUB configuration.${RC}"
    fi
}

# Update database IP addresses
update_database_ips() {
    echo -e "${BLUE}Updating database IP addresses...${RC}"
    cd /tmp
    sudo -H -u "$DB_USER" psql -d "FFAccount" -c "UPDATE worlds SET ip = '$IP';" || error_exit "Failed to update IP in FFAccount database."
    sudo -H -u "$DB_USER" psql -d "FFDB1" -c "UPDATE serverstatus SET ext_address = '$IP' WHERE ext_address <> '127.0.0.1';" || error_exit "Failed to update ext_address in FFDB1 database."
    sudo -H -u "$DB_USER" psql -d "FFDB1" -c "UPDATE serverstatus SET int_address = '$IP' WHERE int_address <> '127.0.0.1';" || error_exit "Failed to update int_address in FFDB1 database."
    echo -e "${GREEN}Database IP addresses updated successfully.${RC}"
}

# Create admin account
create_admin_account() {
    echo -e "\n${BLUE}Admin Account Creation${RC}"
    read -p "Username: " ADMIN_USERNAME
    read -s -p "Password: " ADMIN_PASSWORD
    echo ""
    echo -e "${GREEN}Creating admin account...${RC}"
    ADMIN_PWD_HASH=$(echo -n "$ADMIN_PASSWORD" | md5sum | cut -d ' ' -f1)
    cd /tmp
    sudo -H -u "$DB_USER" psql -d "FFMember" -c "INSERT INTO tb_user (mid, password, pwd) VALUES ('$ADMIN_USERNAME', '$ADMIN_PASSWORD', '$ADMIN_PWD_HASH');" || error_exit "Failed to insert into FFMember database."
    USER_ID=$(sudo -H -u "$DB_USER" psql -At -d "FFMember" -c "SELECT idnum FROM tb_user WHERE mid = '$ADMIN_USERNAME';")
    sudo -H -u "$DB_USER" psql -d "FFAccount" -c "INSERT INTO accounts (id, username, password) VALUES ('$USER_ID', '$ADMIN_USERNAME', '$ADMIN_PASSWORD');" || error_exit "Failed to insert into FFAccount database."
    sudo -H -u "$DB_USER" psql -d "FFMember" -c "UPDATE tb_user SET pvalues = 999999 WHERE mid = '$ADMIN_USERNAME';" || error_exit "Failed to update pvalues in FFMember database."
    sudo -H -u "$DB_USER" psql -d "FFAccount" -c "INSERT INTO gm_tool_accounts (id, account_name, password, privilege) VALUES ('$USER_ID', '$ADMIN_USERNAME', '$ADMIN_PASSWORD', 5);" || error_exit "Failed to insert into gm_tool_accounts."
    STATUS[admin_creation_success]=true
    echo -e "${GREEN}Admin account '$ADMIN_USERNAME' created successfully.${RC}"
}

# Main flow

# Detect operating system
detect_os

# Check kernel version
check_kernel_version

# Update package lists
update_packages

# Install all necessary packages
install_packages

# Install PostgreSQL
install_postgresql

# Configure PostgreSQL
configure_postgresql

# Secure PostgreSQL
secure_postgresql

# Set up firewall rules
setup_firewall_rules

# Get IP address
IP=$(hostname -I | awk '{print $1}')

# Download server files
download_server_files

# Extract server files
extract_server_files

# Create and import databases
import_databases

# Patch server files
patch_server_files

# Configure GRUB for vsyscall
configure_grub

# Update database IP addresses
update_database_ips

# Create admin account
create_admin_account

# Set permissions on server directory
chmod -R 755 "$INSTALL_DIR"

# Installation result message
if [ "${STATUS[postgresql_installed]}" = true ] && [ "${STATUS[config_success]}" = true ] && \
   [ "${STATUS[db_creation_success]}" = true ] && [ "${STATUS[sql_import_success]}" = true ] && \
   [ "${STATUS[download_success]}" = true ] && [ "${STATUS[patch_success]}" = true ] && \
   [ "${STATUS[admin_creation_success]}" = true ]; then
    echo -e "${GREEN}--------------------------------------------------"
    echo -e "Installation complete!"
    echo -e "--------------------------------------------------"
    echo -e "Server IP: $IP"
    echo -e "PostgreSQL Version: $DB_VERSION"
    echo -e "Database User: $DB_USER"
    echo -e "Database Password: $DB_PASS"
    echo -e "Server Directory: $INSTALL_DIR/"
    echo -e "To start the server: $INSTALL_DIR/start"
    echo -e "To stop the server: $INSTALL_DIR/stop"
    if [ "${STATUS[grub_configured]}" = true ]; then
        echo -e "\n${RED}IMPORTANT:${RC} A system reboot is required for the GRUB configuration changes to take effect."
        echo -e "Please reboot your system before starting the server."
    fi
    echo -e "${RC}"
else
    echo -e "${RED}--------------------------------------------------"
    echo -e "Installation failed!"
    echo -e "--------------------------------------------------"
    echo -e "Possible reasons:"
    [ "${STATUS[postgresql_installed]}" = false ] && echo -e "- PostgreSQL installation failed."
    [ "${STATUS[config_success]}" = false ] && echo -e "- PostgreSQL configuration failed."
    [ "${STATUS[download_success]}" = false ] && echo -e "- Server files could not be downloaded or extracted."
    [ "${STATUS[db_creation_success]}" = false ] && echo -e "- Failed to create databases."
    [ "${STATUS[sql_import_success]}" = false ] && echo -e "- Failed to import SQL files into databases."
    [ "${STATUS[patch_success]}" = false ] && echo -e "- File patching failed."
    [ "${STATUS[admin_creation_success]}" = false ] && echo -e "- Failed to create admin account."
    echo -e "Please check the error messages above.${RC}"
fi
