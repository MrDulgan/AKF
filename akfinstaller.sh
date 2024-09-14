#!/bin/bash

# Define colors
RED='\e[0;31m'
GREEN='\e[1;32m'
RC='\e[0m'

# Installer message
INSTALLER_MSG="${GREEN}--------------------------------------------------\nInstaller made by Dulgan\n--------------------------------------------------${RC}"

# Display installer message at the start
echo -e "$INSTALLER_MSG"

# Variables to track the installation process
POSTGRESQL_INSTALLED=false
CONFIG_SUCCESS=false
DB_CREATION_SUCCESS=true
SQL_IMPORT_SUCCESS=true
DOWNLOAD_SUCCESS=false
PATCH_SUCCESS=false
ADMIN_CREATION_SUCCESS=false

# Function to check if a package is installed
is_installed() {
    if [ -x "$(command -v apt-get)" ]; then
        dpkg -s "$1" &> /dev/null
    elif [ -x "$(command -v yum)" ]; then
        rpm -q "$1" &> /dev/null
    fi
}

# Function to install a package only if it's not already installed
install_package() {
    PACKAGE=$1
    if is_installed "$PACKAGE"; then
        echo -e "${GREEN}Package '$PACKAGE' is already installed.${RC}"
    else
        echo -e "${GREEN}Installing package '$PACKAGE'...${RC}"
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get -qq install "$PACKAGE" -y
        elif [ -x "$(command -v yum)" ]; then
            sudo yum -q -y install "$PACKAGE"
        fi
    fi
}

# Make sure lists are up to date for both apt (Debian/Ubuntu) and yum (CentOS)
if [ -x "$(command -v apt-get)" ]; then
    sudo apt-get -qq update
elif [ -x "$(command -v yum)" ]; then
    sudo yum -q -y update
fi

# Install necessary packages (sudo, wget, unzip, psmisc, postgresql, pwgen)
install_package sudo
install_package wget
install_package unzip
install_package psmisc
install_package pwgen

# Install PostgreSQL (using version 13 as default for now)
if [ -x "$(command -v apt-get)" ]; then
    install_package postgresql
elif [ -x "$(command -v yum)" ]; then
    install_package postgresql-server
    install_package postgresql-contrib
    sudo postgresql-setup initdb
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
fi

# Check if PostgreSQL was installed successfully
if command -v psql &> /dev/null; then
    POSTGRESQL_INSTALLED=true
else
    echo -e "${RED}Error: PostgreSQL installation failed.${RC}"
fi

# Configure PostgreSQL to listen on all IPs
if $POSTGRESQL_INSTALLED; then
    POSTGRESQLVERSION=$(psql --version | grep -oP '\d+' | head -1)
    if [ -d "/etc/postgresql/$POSTGRESQLVERSION/main" ]; then
        cd "/etc/postgresql/$POSTGRESQLVERSION/main"
        sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" postgresql.conf
        sudo sed -i "s+host    all             all             127.0.0.1/32            md5+host    all             all             0.0.0.0/0            md5+g" pg_hba.conf
        sudo systemctl restart postgresql
        CONFIG_SUCCESS=true
    else
        echo -e "${RED}Error: PostgreSQL configuration directory not found for version $POSTGRESQLVERSION.${RC}"
    fi
fi

# Generate a random database password
if $CONFIG_SUCCESS; then
    DBPASS=$(pwgen -s 32 1)

    # Change the postgres user password
    sudo -u postgres psql -c "ALTER user postgres WITH password '$DBPASS';" || { echo -e "${RED}Error: Failed to set the PostgreSQL password.${RC}"; exit 1; }
fi

# Get IP address information
IP=$(ip a | grep -Eo 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '127.0.0.1')

# Let the user select or input their IP address
if [ "$IP" != "" ] ; then
    echo -e "Select your IP:\n1) IP: $IP\n2) Input other IP"
    read INVAR
else
    INVAR="2"
fi

if [ "$INVAR" = "2" ]; then
    echo "Please enter IP:"
    read IP
fi

# Select server version
echo -e "Select the version you want to install.\n1) Yokohiro - V15"
read AKVERSION

# Download hxsy.zip from Google Drive and extract it
HXSY_URL="https://drive.google.com/uc?export=download&id=1foqvndDuHwEgixOokU_2rITu1AG-dSv_"
wget --no-check-certificate -q -O /root/hxsy.zip "$HXSY_URL" && unzip -q /root/hxsy.zip -d /root/ && rm /root/hxsy.zip && DOWNLOAD_SUCCESS=true || { echo -e "${RED}Error: Failed to download or extract hxsy.zip.${RC}"; exit 1; }

# Prepare IP for hex patch
PATCHIP=$(printf '\\x%02x\\x%02x\\x%02x' $(echo "$IP" | tr '.' ' '))

# Set version name
VERSIONNAME="NONE"

# Patch files for Yokohiro - V15
if [ "$AKVERSION" = 1 ] && $DOWNLOAD_SUCCESS; then
    cd "/root/hxsy" || { echo -e "${RED}Error: Failed to change directory to /root/hxsy.${RC}"; exit 1; }

    # Patch config files
    sed -i "s/xxxxxxxx/$DBPASS/g" "setup.ini" && \
    sed -i "s/xxxxxxxx/$DBPASS/g" "GatewayServer/setup.ini" && \
    sed -i "s/\x44\x24\x0c\x28\x62\x34/\x44\x24\x0c\x08\x49\x40/g" "MissionServer/MissionServer" && \
    sed -i "s/\x3d\xc0\xa8\x64/\x3d$PATCHIP/g" "WorldServer/WorldServer" && \
    sed -i "s/\x3d\xc0\xa8\x64/\x3d$PATCHIP/g" "ZoneServer/ZoneServer" && PATCH_SUCCESS=true || PATCH_SUCCESS=false

    if $PATCH_SUCCESS; then
        sudo -u postgres psql -d FFAccount -c "UPDATE worlds SET ip = '$IP';" || { echo -e "${RED}Error: Failed to update worlds table in FFAccount database.${RC}"; PATCH_SUCCESS=false; }
        sudo -u postgres psql -d FFDB1 -c "UPDATE serverstatus SET ext_address = '$IP' WHERE ext_address <> '127.0.0.1';" || { echo -e "${RED}Error: Failed to update ext_address in FFDB1 database.${RC}"; PATCH_SUCCESS=false; }
        sudo -u postgres psql -d FFDB1 -c "UPDATE serverstatus SET int_address = '$IP' WHERE int_address <> '127.0.0.1';" || { echo -e "${RED}Error: Failed to update int_address in FFDB1 database.${RC}"; PATCH_SUCCESS=false; }	
    fi

    VERSIONNAME="Yokohiro - V15.001.01.16"
    CREDITS="Horo"
    THREADLINK="https://forum.ragezone.com/members/yokohiro.311139/"
fi

# Function to create databases and import SQL files
create_and_import_db() {
    DB_NAME=$1
    SQL_FILE=$2

    # Create the database
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;" || { echo -e "${RED}Error: Failed to create $DB_NAME database.${RC}"; DB_CREATION_SUCCESS=false; }

    # Import the SQL file
    sudo -u postgres psql -d $DB_NAME -f "/root/hxsy/SQL/$SQL_FILE" || { echo -e "${RED}Error: Failed to import $SQL_FILE into $DB_NAME database.${RC}"; SQL_IMPORT_SUCCESS=false; }
}

# Create FFAccount, FFDB1, and FFMember databases and import SQL files if PostgreSQL is installed
if $POSTGRESQL_INSTALLED; then
    create_and_import_db "FFAccount" "FFAccount.sql"
    create_and_import_db "FFDB1" "FFDB1.sql"
    create_and_import_db "FFMember" "FFMember.sql"
fi

# Prompt user for admin account creation
echo -e "\nAdmin Account Creation"
echo -n "Username: "
read ADMIN_USERNAME
echo -n "Password: "
read -s ADMIN_PASSWORD
echo ""

# Create admin account in FFMember, FFAccount, and gm_tool_accounts
if sudo -u postgres psql -d FFMember -c "INSERT INTO tb_user (mid, password, pwd) VALUES ('$ADMIN_USERNAME', '$ADMIN_PASSWORD', '$(echo -n $ADMIN_PASSWORD | md5sum | cut -d ' ' -f 1)');"; then
    USER_ID=$(sudo -u postgres psql -At -d FFMember -c "SELECT idnum FROM tb_user WHERE mid = '$ADMIN_USERNAME';")
    sudo -u postgres psql -d FFAccount -c "INSERT INTO accounts (id, username, password) VALUES ('$USER_ID', '$ADMIN_USERNAME', '$ADMIN_PASSWORD');"
    sudo -u postgres psql -d FFMember -c "UPDATE tb_user SET pvalues = 999999 WHERE mid = '$ADMIN_USERNAME';"

    # Insert into gm_tool_accounts with $USER_ID
    sudo -u postgres psql -d FFAccount -c "INSERT INTO gm_tool_accounts (id, account_name, password, privilege) VALUES ('$USER_ID', '$ADMIN_USERNAME', '$ADMIN_PASSWORD', 5);"

    ADMIN_CREATION_SUCCESS=true
    echo -e "${GREEN}Admin account '$ADMIN_USERNAME' created successfully.${RC}"
else
    echo -e "${RED}Error: Failed to create admin account.${RC}"
fi

# Display info message for setting admin privileges in FFDB1
if $ADMIN_CREATION_SUCCESS; then
    echo -e "\n${GREEN}Admin account created successfully!${RC}"
    echo -e "${GREEN}To grant full admin privileges, after creating a character, please update the 'privilege' column to '5' in the 'player_characters' table of the FFDB1 database.${RC}"
fi

# Display final installation message with specific checks
if [ "$VERSIONNAME" = "NONE" ]; then
    echo -e "${RED}--------------------------------------------------"
    echo -e "Installation failed!"
    echo -e "--------------------------------------------------"
    echo -e "Possible reasons:"
    if ! $POSTGRESQL_INSTALLED; then
        echo -e "- PostgreSQL installation failed."
    fi
    if ! $CONFIG_SUCCESS; then
        echo -e "- PostgreSQL configuration failed."
    fi
    if ! $DOWNLOAD_SUCCESS; then
        echo -e "- hxsy.zip could not be downloaded or extracted."
    fi
    if ! $PATCH_SUCCESS; then
        echo -e "- File patching failed."
    fi
    if ! $DB_CREATION_SUCCESS; then
        echo -e "- Failed to create one or more databases."
    fi
    if ! $SQL_IMPORT_SUCCESS; then
        echo -e "- Failed to import one or more SQL files into databases."
    fi
    echo -e "Please check the error messages above for more details.${RC}"
else
    echo -e "$INSTALLER_MSG"
    echo -e "${GREEN}--------------------------------------------------"
    echo -e "Installation complete!"
    echo -e "--------------------------------------------------"
    echo -e "Server Version: $VERSIONNAME"
    echo -e "Server IP: $IP"
    echo -e "PostgreSQL Version: $POSTGRESQLVERSION"
    echo -e "Database User: postgres"
    echo -e "Database Password: $DBPASS"
    echo -e "Server Path: /root/hxsy/"
    echo -e "PostgreSQL Configuration Path: /etc/postgresql/$POSTGRESQLVERSION/main/"
    echo -e "Release Info / Client Download: $THREADLINK"
    echo -e "\nMake sure to thank $CREDITS!"
    echo -e "\nTo start the server, please use /root/hxsy/start"
    echo -e "To stop the server, please use /root/hxsy/stop${RC}"
fi