#!/bin/bash

# Enhanced AK Account Creator
# Developer: Dulgan

RED='\e[0;31m'
GREEN='\e[1;32m'
BLUE='\e[0;36m'
YELLOW='\e[1;33m'
PURPLE='\e[0;35m'
NC='\e[0m'

DEFAULT_INSTALL_DIR='/root/hxsy'
DB_USER='postgres'
DB_NAME_MEMBER='FFMember'
DB_NAME_ACCOUNT='FFAccount'
DB_CONFIG_FILENAME='setup.ini'
DB_PASSWORD_KEY='AccountDBPW'
DEFAULT_PVALUES=0

error_exit() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

# Enhanced validation functions
validate_username() {
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
    local reserved=("admin" "root" "postgres" "system" "guest" "user" "test" "server" "game" "gm" "master" "owner")
    for reserved_name in "${reserved[@]}"; do
        if [[ "$username" == "$reserved_name" ]]; then
            echo "Username '$username' is reserved and cannot be used"
            return 1
        fi
    done
    
    return 0
}

validate_password() {
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

# SQL injection prevention
escape_sql_string() {
    local input="$1"
    # Replace single quotes with two single quotes for PostgreSQL
    echo "${input//\'/\'\'}"
}

check_dependencies() {
    echo -e "${BLUE}>> Checking required commands...${NC}"
    local missing=0
    for cmd in psql md5sum sudo grep cut sed; do
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
        DB_PASS=$(grep "^${DB_PASSWORD_KEY}=" "$config_path" | head -n 1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [[ -z "$DB_PASS" ]]; then
             echo -e "${YELLOW}[WARNING] Key '${DB_PASSWORD_KEY}' not found or empty in '$config_path'.${NC}" >&2
             return 1
        else
            echo -e "${GREEN}>> Database password read successfully using key '${DB_PASSWORD_KEY}' from '$config_path'.${NC}"
            return 0
        fi
    else
        echo -e "${YELLOW}[INFO] Configuration file '$config_path' not found.${NC}" >&2
        return 1
    fi
}

create_game_account() {
    local db_password=$1

    echo -e "\n${PURPLE}--- Create Enhanced Secure Game Account ---${NC}"

    local username
    while true; do
        read -p "Username (3-16 chars, a-z, 0-9 only): " username
        
        local validation_result
        validation_result=$(validate_username "$username")
        
        if [[ $? -eq 0 ]]; then
            # Escape username for SQL safety
            local safe_username
            safe_username=$(escape_sql_string "$username")
            
            local check_user_sql="SELECT 1 FROM tb_user WHERE mid = '$safe_username';"
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
            echo -e "${RED}[ERROR] $validation_result${NC}" >&2
        fi
    done

    local password password_confirm
    while true; do
        read -s -p "Password (min 8 chars, secure): " password
        echo ""
        
        local validation_result
        validation_result=$(validate_password "$password")
        
        if [[ $? -eq 0 ]]; then
            read -s -p "Confirm Password: " password_confirm
            echo ""
            
            if [[ "$password" == "$password_confirm" ]]; then
                break
            else
                echo -e "${RED}[ERROR] Passwords do not match. Please try again.${NC}" >&2
            fi
        else
            echo -e "${RED}[ERROR] $validation_result${NC}" >&2
        fi
    done

    # Enhanced hashing - Game requires MD5 for compatibility
    local password_hash_md5
    password_hash_md5=$(echo -n "$password" | md5sum | cut -d ' ' -f1)
    
    # Note: Game system requires MD5 hash, cannot be changed to SHA256

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

    echo -e "${BLUE}>> Adding secure account '$username' to the database...${NC}"

    # Use safe, escaped values for SQL queries
    local safe_username safe_password
    safe_username=$(escape_sql_string "$username")
    safe_password=$(escape_sql_string "$password")

    local insert_member_sql="INSERT INTO tb_user (mid, password, pwd, pvalues) VALUES ('$safe_username', '$safe_password', '$password_hash_md5', $pvalues_to_set) RETURNING idnum;"
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

    local insert_account_sql="INSERT INTO accounts (id, username, password) VALUES ($user_id, '$safe_username', '$safe_password');"
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

    # Secure cleanup
    unset password password_confirm password_hash_md5 safe_password

    echo -e "${GREEN}--- Enhanced secure account '$username' created successfully! (pvalues: $pvalues_to_set) ---${NC}"
    echo -e "${BLUE}[INFO] Account uses MD5 hashing as required by game system.${NC}"
    return 0
}

echo -e "${PURPLE}
==================================================
        Enhanced AK Account Creation Tool
        Enhanced Security & Validation
==================================================${NC}"

check_dependencies

INSTALL_DIR="$DEFAULT_INSTALL_DIR"
DB_PASS=""

if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "${BLUE}>> Using default installation directory: ${INSTALL_DIR}${NC}"
    CONFIG_FILE_PATH="${INSTALL_DIR}/${DB_CONFIG_FILENAME}"

    if ! read_db_password "$CONFIG_FILE_PATH"; then
        echo -e "${YELLOW}Could not automatically read database password from '$CONFIG_FILE_PATH' using key '${DB_PASSWORD_KEY}'.${NC}" >&2
        echo -e "${BLUE}Please enter the database password for user '$DB_USER':${NC}"
        read -s -p "Database Password: " DB_PASS_input
        echo ""
        if [[ -z "$DB_PASS_input" ]]; then
            error_exit "Database password not provided."
        fi
        DB_PASS="$DB_PASS_input"
    fi
else
    echo -e "${YELLOW}[WARNING] Default installation directory not found: ${INSTALL_DIR}. Cannot read password automatically.${NC}" >&2
    echo -e "${BLUE}Please enter the database password for user '$DB_USER':${NC}"
    read -s -p "Database Password: " DB_PASS_input
    echo ""
    if [[ -z "$DB_PASS_input" ]]; then
        error_exit "Database password not provided."
    fi
    DB_PASS="$DB_PASS_input"
fi

while true; do
    if [[ -z "$DB_PASS" ]]; then
         error_exit "Database password could not be determined. Exiting."
    fi
    create_game_account "$DB_PASS"

    echo ""
    read -p "Create another account? [Y/n]: " continue_choice
    if [[ "$continue_choice" =~ ^[Nn]$ ]]; then
        break
    fi
done

echo -e "\n${GREEN}Account creation process finished.${NC}"
exit 0