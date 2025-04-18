#!/bin/bash

# =========================
# 🎨 Define Colors
# =========================

# Text Colors (Foreground)
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Bright Text Colors
BRIGHT_BLACK='\033[1;30m'
BRIGHT_RED='\033[1;31m'
BRIGHT_GREEN='\033[1;32m'
BRIGHT_YELLOW='\033[1;33m'
BRIGHT_BLUE='\033[1;34m'
BRIGHT_MAGENTA='\033[1;35m'
BRIGHT_CYAN='\033[1;36m'
BRIGHT_WHITE='\033[1;37m'

# Background Colors
BG_BLACK='\033[40m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_MAGENTA='\033[45m'
BG_CYAN='\033[46m'
BG_WHITE='\033[47m'

# Bright Background Colors
BG_BRIGHT_BLACK='\033[100m'
BG_BRIGHT_RED='\033[101m'
BG_BRIGHT_GREEN='\033[102m'
BG_BRIGHT_YELLOW='\033[103m'
BG_BRIGHT_BLUE='\033[104m'
BG_BRIGHT_MAGENTA='\033[105m'
BG_BRIGHT_CYAN='\033[106m'
BG_BRIGHT_WHITE='\033[107m'

# =========================
# ✨ Text Styles
# =========================
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
BLINK='\033[5m'         # May not work on all terminals
REVERSE='\033[7m'
HIDDEN='\033[8m'        # Invisible (good for password prompts)

# =========================
# 🚫 Reset
# =========================
NC='\033[0m'            # No Color / Reset all styles
RESET='\033[0m'

# =========================
# 🎨 End of Define Colors
# =========================

# Function to check PostgreSQL connection to a specific database
check_postgres_connection() {
    local db_name="$1"
    
    # Attempt to connect to the specified database using psql
    if ! sudo -u postgres psql -d "$db_name" -c "SELECT 1;" &>/dev/null; then
        echo -e "${BRIGHT_RED}${BLINK}❌ Error:${NC}${BRIGHT_RED} Connection to PostgreSQL Database Failed. \nPlease Check if the Database is Setup Correctly and Running.${NC}"
        return 1  # Return failure
    fi
    return 0  # Success
}

# Clear the screen before showing the menu
    clear
	
while true; do
    # Main Menu
    echo -e ""
    echo -e "${CYAN}╔══════════════════════════╗${NC}"
    echo -e "${CYAN}║  Account Creation Tool   ║${NC}"
    echo -e "${CYAN}╠══════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}${YELLOW} 1.${NC} Create a New Account  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${YELLOW} 2.${NC} Exit                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════╝${NC}"
    echo -e ""
    read -p "$(echo -e "${CYAN}Choose an option (${YELLOW}1${NC}${CYAN} or ${YELLOW}2${NC}${CYAN}): ${NC}")" choice

    case "$choice" in
        1)
            # Prompt for account name
            read -p "$(echo -e "${CYAN}Enter Account Name: ${NC}")" account_name
			
			# Check if empty
			if [ -z "$account_name" ]; then
			echo -e "${BRIGHT_RED}${BLINK}❌ Error:${NC}${BRIGHT_RED} Account Name cannot be Empty. Try Again.${NC}"
			continue
			fi

            # Prompt for password (visible)
            read -p "$(echo -e "${CYAN}Enter Password: ${NC}")" password
			if [ -z "$password" ]; then
			echo -e "${BRIGHT_RED}${BLINK}❌ Error:${NC}${BRIGHT_RED} Password cannot be Empty. Try Again.${NC}"
			continue
			fi
            read -p "$(echo -e "${CYAN}Confirm Password: ${NC}")" password_confirm
			if [ -z "$password_confirm" ]; then
			echo -e "${BRIGHT_RED}${BLINK}❌ Error:${NC}${BRIGHT_RED} Confirm Password cannot be Empty. Try Again.${NC}"
			continue
			fi

            # Check if passwords match
            if [ "$password" != "$password_confirm" ]; then
                echo -e "${BRIGHT_RED}${BLINK}❌ Error:${NC}${BRIGHT_RED} Passwords do not Match. Try Again.${NC}"
                continue
            fi

            # =========================
            # Check Database Connections
            # =========================
            # Check connectivity to both FFMember and FFAccount databases
            check_postgres_connection "FFMember"
            if [ $? -ne 0 ]; then
                # If FFMember is not connected, retry the connection check
                echo -e "${BRIGHT_RED}${BLINK}⚠️ Database FFMember Not Found. ${NC}${BRIGHT_RED}Please Resolve the connection issue and Try Again.${NC}"
                sleep 2
                continue
            fi

            check_postgres_connection "FFAccount"
            if [ $? -ne 0 ]; then
                # If FFAccount is not connected, retry the connection check
                echo -e "${BRIGHT_RED}${BLINK}⚠️ Database FFAccount Not Found. ${NC}${BRIGHT_RED}Please Resolve the connection issue and Try Again.${NC}"
                sleep 2
                continue
            fi

            # If both databases are connected, proceed with insertions
            # =========================

            # Insert into FFMember
            echo -e "${MAGENTA}➤ Creating account in FFMember...${NC}"
            insert_result=$(sudo -u postgres psql -d FFMember -c \
            "INSERT INTO tb_user (mid, password, pwd) VALUES ('$account_name', '$password', '$(echo -n $password | md5sum | cut -d ' ' -f 1)');" 2>&1)

            # Check if insert failed
            if echo "$insert_result" | grep -q "ERROR"; then
                echo -e "${BRIGHT_RED}${BLINK}❌ Error:${NC}${BRIGHT_RED} Database error during FFMember insert:${NC}"
                echo "$insert_result"
                continue
            fi

            # Get user ID
            user_id=$(sudo -u postgres psql -At -d FFMember -c \
            "SELECT idnum FROM tb_user WHERE mid = '$account_name'")

            if [ -z "$user_id" ]; then
                echo -e "${BRIGHT_RED}${BLINK}❌ Error:${NC}${BRIGHT_RED} Failed to retrieve user ID from FFMember.${NC}"
                continue
            fi

            # Insert into FFAccount
            echo -e "${MAGENTA}➤ Creating account in FFAccount...${NC}"
            insert_result=$(sudo -u postgres psql -d FFAccount -c \
            "INSERT INTO accounts (id, username, password) VALUES ('$user_id', '$account_name', '$password');" 2>&1)

            if echo "$insert_result" | grep -q "ERROR"; then
                echo -e "${BRIGHT_RED}${BLINK}❌ Error:${NC}${BRIGHT_RED} Database error during FFAccount insert:${NC}"
                echo "$insert_result"
                continue
            fi

            echo -e "${GREEN}✅ Account '$account_name' Created Successfully.${NC}"
            echo
            ;;
        2)
            echo -e "${YELLOW}👋 Exiting. Have a Great Day.${NC}"
            exit 0
            ;;
        *)
            echo -e "${BRIGHT_RED}${BLINK}⚠️ Invalid Choice.${NC}${BRIGHT_RED} Please Enter 1 or 2.${NC}"
            ;;
    esac
done