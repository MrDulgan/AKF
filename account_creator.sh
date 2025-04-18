#!/bin/bash

RED='\e[0;31m'
GREEN='\e[1;32m'
BLUE='\e[0;36m'
YELLOW='\e[1;33m'
NC='\e[0m'

DEFAULT_INSTALL_DIR='/root/hxsy'
DB_USER='postgres'
DB_NAME_MEMBER='FFMember'
DB_NAME_ACCOUNT='FFAccount'
DB_CONFIG_FILENAME='db_config.ini'
DEFAULT_PVALUES=0

error_exit() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

check_dependencies() {
    echo -e "${BLUE}>> Checking required commands...${NC}"
    local missing=0
    for cmd in psql md5sum sudo; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}- Command '$cmd' not found. Please install it.${NC}" >&2
            missing=1
        else
             echo -e "${GREEN}- Command '$cmd' is available.${NC}"
        fi
    done
    if [ "$missing" -eq 1 ]; then
        error_exit "Missing required commands. Cannot continue."
    fi
}

read_db_password() {
    local config_path="$1"
    if [[ -f "$config_path" ]]; then
        DB_PASS=$(grep '^DB_PASS=' "$config_path" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$DB_PASS" ]]; then
             echo -e "${YELLOW}[WARNING] DB_PASS not found or empty in '$config_path'.${NC}" >&2
             return 1
        else
            echo -e "${GREEN}>> Database password read successfully from '$config_path'.${NC}"
            return 0
        fi
    else
        echo -e "${YELLOW}[INFO] Configuration file '$config_path' not found.${NC}" >&2
        return 1
    fi
}

create_game_account() {
    local db_password=$1

    echo -e "\n${BLUE}--- Create New Game Account ---${NC}"

    local username
    while true; do
        read -p "Username (3-16 chars, lowercase letters and numbers only): " username
        if [[ "$username" =~ ^[a-z0-9]{3,16}$ ]]; then
            local check_user_sql="SELECT 1 FROM tb_user WHERE mid = '$username';"
            local existing_user
            existing_user=$(PGPASSWORD="$db_password" sudo -H -u "$DB_USER" psql -qtA -d "$DB_NAME_MEMBER" -c "$check_user_sql")
            local psql_exit_code=$?

            if [[ $psql_exit_code -ne 0 ]]; then
                 echo -e "${YELLOW}[WARNING] Database error while checking username. See errors above. Proceeding cautiously.${NC}" >&2
                 break
            elif [[ "$existing_user" == "1" ]]; then
                 echo -e "${YELLOW}[WARNING] Username '$username' already exists. Please choose another.${NC}" >&2
            else
                 break
            fi
        else
            echo -e "${RED}[ERROR] Invalid username format. Must be 3-16 chars, lowercase letters (a-z), and numbers (0-9).${NC}" >&2
        fi
    done

    local password password_confirm
    while true; do
        read -s -p "Password (min 6 characters): " password
        echo ""
        read -s -p "Confirm Password: " password_confirm
        echo ""

        if [[ ${#password} -lt 6 ]]; then
            echo -e "${RED}[ERROR] Password must be at least 6 characters long.${NC}" >&2
        elif [[ "$password" != "$password_confirm" ]]; then
            echo -e "${RED}[ERROR] Passwords do not match. Please try again.${NC}" >&2
        else
            break
        fi
    done

    local password_hash
    password_hash=$(echo -n "$password" | md5sum | cut -d ' ' -f1)

    local pvalues_to_set=$DEFAULT_PVALUES
    local set_pvalues_choice
    read -p "Set custom pvalues? (Default is ${DEFAULT_PVALUES}) [y/N]: " set_pvalues_choice
    if [[ "$set_pvalues_choice" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Enter numeric pvalues: " pvalues_input
            if [[ "$pvalues_input" =~ ^[0-9]+$ ]]; then
                pvalues_to_set=$pvalues_input
                echo -e "${BLUE}>> Using custom pvalues: $pvalues_to_set${NC}"
                break
            else
                echo -e "${RED}[ERROR] Invalid input. Please enter only numbers.${NC}" >&2
            fi
        done
    else
        echo -e "${BLUE}>> Using default pvalues: $pvalues_to_set${NC}"
    fi

    echo -e "${BLUE}>> Adding account '$username' to the database...${NC}"

    local insert_member_sql="INSERT INTO tb_user (mid, password, pwd, pvalues) VALUES ('$username', '$password', '$password_hash', $pvalues_to_set) RETURNING idnum;"
    local user_id
    user_id=$(PGPASSWORD="$db_password" sudo -H -u "$DB_USER" psql -qtA -d "$DB_NAME_MEMBER" -c "$insert_member_sql")
    local psql_exit_code=$?

    if [[ $psql_exit_code -ne 0 || -z "$user_id" ]]; then
        echo -e "${RED}[ERROR] Failed to add account to '$DB_NAME_MEMBER'! Username might already exist or another DB issue occurred.${NC}" >&2
        echo -e "${RED}>> Please check any psql error messages above.${NC}" >&2
        return 1
    else
        echo -e "${GREEN}>> Account added to '$DB_NAME_MEMBER' successfully (ID: $user_id).${NC}"
    fi

    local insert_account_sql="INSERT INTO accounts (id, username, password) VALUES ($user_id, '$username', '$password');"
    PGPASSWORD="$db_password" sudo -H -u "$DB_USER" psql -q -d "$DB_NAME_ACCOUNT" -c "$insert_account_sql"
    psql_exit_code=$?

    if [[ $psql_exit_code -ne 0 ]]; then
        echo -e "${RED}[ERROR] Failed to add account to '$DB_NAME_ACCOUNT'!${NC}" >&2
        echo -e "${RED}>> Please check any psql error messages above.${NC}" >&2
        echo -e "${YELLOW}[WARNING] Account was added to '$DB_NAME_MEMBER' but failed in '$DB_NAME_ACCOUNT'. Database might be inconsistent!${NC}" >&2
        return 1
    else
        echo -e "${GREEN}>> Account added to '$DB_NAME_ACCOUNT' successfully.${NC}"
    fi

    echo -e "${GREEN}--- Account '$username' created successfully! (pvalues: $pvalues_to_set) ---${NC}"
    return 0
}


echo -e "${BLUE}
==================================================
        Game Account Creation Tool
==================================================${NC}"

check_dependencies

INSTALL_DIR="$DEFAULT_INSTALL_DIR"

if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}[WARNING] Default installation directory not found: ${INSTALL_DIR}${NC}" >&2
    echo -e "${BLUE}The script needs the installation directory to find the database configuration file (${DB_CONFIG_FILENAME}).${NC}"
    read -p "Please enter the correct installation directory path: " user_install_dir

    if [[ -z "$user_install_dir" ]]; then
         error_exit "No installation directory provided. Exiting."
    fi

    INSTALL_DIR="$user_install_dir"

    if [[ ! -d "$INSTALL_DIR" ]]; then
        error_exit "Provided installation directory also not found: ${INSTALL_DIR}"
    else
         echo -e "${BLUE}>> Using installation directory: ${INSTALL_DIR}${NC}"
    fi
else
     echo -e "${BLUE}>> Using default installation directory: ${INSTALL_DIR}${NC}"
fi

CONFIG_FILE_PATH="${INSTALL_DIR}/${DB_CONFIG_FILENAME}"

DB_PASS=""
if ! read_db_password "$CONFIG_FILE_PATH"; then
    echo -e "${YELLOW}Could not read database password from configuration file ('$CONFIG_FILE_PATH').${NC}"
    echo -e "${BLUE}Please enter the database password for user '$DB_USER':${NC}"
    read -s -p "Database Password: " DB_PASS
    echo "" # New line
    if [[ -z "$DB_PASS" ]]; then
        error_exit "Database password not provided."
    fi
fi

while true; do
    create_game_account "$DB_PASS"

    echo ""
    read -p "Create another account? [Y/n]: " continue_choice
    if [[ "$continue_choice" =~ ^[Nn]$ ]]; then
        break
    fi
done

echo -e "\n${GREEN}Account creation process finished.${NC}"
exit 0