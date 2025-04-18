#!/bin/bash

DB_MEMBER="FFMember"
DB_ACCOUNT="FFAccount"
DB_USER="postgres"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_error() {
    echo -e "${RED}❌ Error: $1${NC}" >&2
}
log_success() {
    echo -e "${GREEN}✅ Success: $1${NC}"
}
log_info() {
    echo -e "${YELLOW}ℹ️ $1${NC}"
}

prompt_password() {
    local prompt="$1"
    local password_var="$2"
    local password=""
    local password_confirm=""
    while true; do
        read -sp "$(echo -e "${CYAN}${prompt}: ${NC}")" password; echo
        if [ -z "$password" ]; then log_error "Password cannot be empty."; continue; fi
        read -sp "$(echo -e "${CYAN}Confirm ${prompt}: ${NC}")" password_confirm; echo
        if [ "$password" == "$password_confirm" ]; then break; else log_error "Passwords do not match. Please try again."; fi
    done
    printf -v "$password_var" '%s' "$password"
}
prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local value=""
    while true; do
        read -p "$(echo -e "${CYAN}${prompt}: ${NC}")" value
        if [ -n "$value" ]; then break; else log_error "Input cannot be empty."; fi
    done
    printf -v "$var_name" '%s' "$value"
}

run_psql() {
    local db_name="$1"; shift
    local sql_command="$1"; shift
    local psql_output=""
    local psql_exit_code=0
    local psql_vars=()
    while [ "$#" -gt 0 ]; do psql_vars+=("-v" "$1"); shift; done

    psql_output=$(sudo -u "$DB_USER" psql -q -v ON_ERROR_STOP=1 -At -d "$db_name" "${psql_vars[@]}" -c "$sql_command" 2>&1)
    psql_exit_code=$?

    if [ $psql_exit_code -ne 0 ]; then
        log_error "Database operation failed in '$db_name'."
        echo "Details: $psql_output" >&2
        return 1
    fi
    echo "$psql_output"
    return 0
}

check_db_access() {
    local db_name="$1"
    log_info "Checking connection to database '$db_name'..."
    run_psql "$db_name" "SELECT 1;" > /dev/null
    if [ $? -ne 0 ]; then
        log_error "Cannot connect to database '$db_name'. Please check server status and configuration."
        return 1
    fi
    log_info "Connection to '$db_name' successful."
    return 0
}

clear
while true; do
    echo -e "\n${CYAN}┌──────────────────────────┐${NC}"
    echo -e "${CYAN}│ Account Creation Tool    │${NC}"
    echo -e "${CYAN}├──────────────────────────┤${NC}"
    echo -e "${CYAN}│ ${YELLOW}1.${NC} Create New Account   ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${YELLOW}2.${NC} Exit                 ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────┘${NC}"
    read -p "$(echo -e "${CYAN}Choose an option (1 or 2): ${NC}")" choice

    case "$choice" in
        1)
            if ! check_db_access "$DB_MEMBER" || ! check_db_access "$DB_ACCOUNT"; then
                log_info "Please resolve database connection issues before proceeding."
                sleep 2
                continue
            fi

            prompt_input "Enter Account Name" account_name

            log_info "Validating username format..."
            if [[ ! "$account_name" =~ ^[[:ascii:]]+$ ]]; then
                log_error "Username must contain only ASCII characters. Please try again."
                continue
            fi
            if [[ "$account_name" =~ [[:upper:]] ]]; then
                log_error "Username cannot contain uppercase letters. Please try again."
                continue
            fi
            log_info "Username format is valid."

            log_info "Checking if username '$account_name' already exists in '$DB_MEMBER'..."
            exists_output=$(run_psql "$DB_MEMBER" "SELECT 1 FROM tb_user WHERE mid = :account_name LIMIT 1;" "account_name=$account_name")
            db_check_status=$?
            if [ $db_check_status -ne 0 ]; then
                log_error "Database error while checking username. Cannot proceed."
                continue
            fi
            if [ -n "$exists_output" ]; then
                log_error "Username '$account_name' already exists. Please choose a different one."
                continue
            fi
            log_info "Username '$account_name' is available."

            prompt_password "Password" user_password

            log_info "Generating MD5 password hash..."
            hashed_password=$(echo -n "$user_password" | md5sum | cut -d ' ' -f 1)
            if [ -z "$hashed_password" ]; then
                 log_error "Failed to generate MD5 hash."
                 continue
            fi

            log_info "Attempting to create account in '$DB_MEMBER'..."
            user_id=$(run_psql "$DB_MEMBER" \
                "INSERT INTO tb_user (mid, password, pwd) VALUES (:account_name, :plain_password, :hashed_pwd) RETURNING idnum;" \
                "account_name=$account_name" \
                "plain_password=$user_password" \
                "hashed_pwd=$hashed_password"
            )
            if [ $? -ne 0 ]; then continue; fi
            if [ -z "$user_id" ]; then log_error "Failed to retrieve user ID from '$DB_MEMBER'."; continue; fi

            log_info "Account created in '$DB_MEMBER' (User ID: $user_id). Attempting insert into '$DB_ACCOUNT'..."
            run_psql "$DB_ACCOUNT" \
                "INSERT INTO accounts (id, username, password) VALUES (:user_id, :account_name, :plain_password);" \
                "user_id=$user_id" \
                "account_name=$account_name" \
                "plain_password=$user_password"
            if [ $? -ne 0 ]; then
                log_error "Account partially created. Insert OK in '$DB_MEMBER' but FAILED in '$DB_ACCOUNT'. Manual check required."
                continue
            fi

            log_info "Account created in both databases. Now setting Item Mall Currency..."

            while true; do
                prompt_input "Enter Item Mall Currency (pvalues - numeric only)" pvalues_value
                if [[ "$pvalues_value" =~ ^[0-9]+$ ]]; then
                    break
                else
                    log_error "Invalid input. Item Mall Currency must be a number. Please try again."
                fi
            done

            log_info "Updating Item Mall Currency (pvalues) in '$DB_MEMBER'..."
            run_psql "$DB_MEMBER" \
                "UPDATE tb_user SET pvalues = :pvalues_value WHERE mid = :account_name;" \
                "pvalues_value=$pvalues_value" \
                "account_name=$account_name"
            if [ $? -ne 0 ]; then
                log_error "Failed to update Item Mall Currency, but the account exists."
                continue
            fi

            log_success "Account '$account_name' created and Item Mall Currency set successfully."
            echo
            ;;
        2)
            log_info "Exiting. Have a great day!"
            exit 0
            ;;
        *)
            log_error "Invalid Choice. Please enter 1 or 2."
            ;;
    esac
done