#!/bin/bash

# AK Server Restore Script
# Developer: Dulgan

RED='\e[0;31m'
GREEN='\e[1;32m'
BLUE='\e[0;36m'
YELLOW='\e[1;33m'
NC='\e[0m'

INSTALL_DIR="/root/hxsy"
BACKUP_DIR="/root/ak_backups"
DB_USER="postgres"

error_exit() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

read_db_password() {
    local config_path="$INSTALL_DIR/setup.ini"
    if [[ -f "$config_path" ]]; then
        DB_PASS=$(grep "^AccountDBPW=" "$config_path" | head -n 1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$DB_PASS" ]]; then
            echo -e "${YELLOW}[WARNING] Could not read DB password from config${NC}"
            read -s -p "Enter PostgreSQL password for user '$DB_USER': " DB_PASS
            echo ""
        fi
    else
        read -s -p "Enter PostgreSQL password for user '$DB_USER': " DB_PASS
        echo ""
    fi
}

list_available_backups() {
    echo -e "${BLUE}>> Available backups:${NC}"
    echo ""
    
    # List database backups
    echo -e "${YELLOW}Database Backups:${NC}"
    local db_backups=($(ls "$BACKUP_DIR"/FFAccount_*.sql 2>/dev/null | sort -r))
    for i in "${!db_backups[@]}"; do
        local timestamp=$(basename "${db_backups[$i]}" | sed 's/FFAccount_\(.*\)\.sql/\1/')
        echo -e "  [$((i+1))] ${timestamp}"
    done
    
    echo ""
    echo -e "${YELLOW}Server File Backups:${NC}"
    local file_backups=($(ls "$BACKUP_DIR"/server_files_*.tar.gz 2>/dev/null | sort -r))
    for i in "${!file_backups[@]}"; do
        local timestamp=$(basename "${file_backups[$i]}" | sed 's/server_files_\(.*\)\.tar\.gz/\1/')
        echo -e "  [$((i+1))] ${timestamp}"
    done
    echo ""
}

select_backup_timestamp() {
    local backup_type="$1"
    local backups=()
    
    if [[ "$backup_type" == "database" ]]; then
        backups=($(ls "$BACKUP_DIR"/FFAccount_*.sql 2>/dev/null | sort -r))
    else
        backups=($(ls "$BACKUP_DIR"/server_files_*.tar.gz 2>/dev/null | sort -r))
    fi
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        error_exit "No $backup_type backups found in $BACKUP_DIR"
    fi
    
    echo -e "${BLUE}Select $backup_type backup to restore:${NC}"
    for i in "${!backups[@]}"; do
        local file=$(basename "${backups[$i]}")
        if [[ "$backup_type" == "database" ]]; then
            local timestamp=$(echo "$file" | sed 's/FFAccount_\(.*\)\.sql/\1/')
        else
            local timestamp=$(echo "$file" | sed 's/server_files_\(.*\)\.tar\.gz/\1/')
        fi
        echo -e "  [$((i+1))] ${timestamp} ($(du -sh "${backups[$i]}" | cut -f1))"
    done
    
    read -p "Enter selection (1-${#backups[@]}): " selection
    
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#backups[@]} ]]; then
        error_exit "Invalid selection"
    fi
    
    selected_backup="${backups[$((selection-1))]}"
    if [[ "$backup_type" == "database" ]]; then
        SELECTED_TIMESTAMP=$(basename "$selected_backup" | sed 's/FFAccount_\(.*\)\.sql/\1/')
    else
        SELECTED_TIMESTAMP=$(basename "$selected_backup" | sed 's/server_files_\(.*\)\.tar\.gz/\1/')
    fi
}

stop_server() {
    echo -e "${BLUE}>> Stopping AK server...${NC}"
    if [[ -f "$INSTALL_DIR/stop" ]]; then
        "$INSTALL_DIR/stop"
    else
        # Manual stop
        for srv in ZoneServer WorldServer MissionServer LoginServer GatewayServer TicketServer; do
            pkill -f "$srv" 2>/dev/null
        done
    fi
    sleep 5
    echo -e "${GREEN}>> Server stopped${NC}"
}

restore_databases() {
    echo -e "${BLUE}>> Restoring databases...${NC}"
    local databases=("FFAccount" "FFDB1" "FFMember")
    
    for db in "${databases[@]}"; do
        local backup_file="$BACKUP_DIR/${db}_${SELECTED_TIMESTAMP}.sql"
        
        if [[ ! -f "$backup_file" ]]; then
            error_exit "Backup file not found: $backup_file"
        fi
        
        echo -e "${BLUE}   - Restoring $db...${NC}"
        
        # Drop and recreate database
        PGPASSWORD="$DB_PASS" dropdb -U "$DB_USER" -h localhost "$db" 2>/dev/null
        PGPASSWORD="$DB_PASS" createdb -U "$DB_USER" -h localhost "$db" || error_exit "Failed to create database $db"
        
        # Restore from backup
        PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -h localhost "$db" < "$backup_file" || error_exit "Failed to restore database $db"
        
        echo -e "${GREEN}   - $db restored successfully${NC}"
    done
}

restore_server_files() {
    echo -e "${BLUE}>> Restoring server files...${NC}"
    local backup_file="$BACKUP_DIR/server_files_${SELECTED_TIMESTAMP}.tar.gz"
    
    if [[ ! -f "$backup_file" ]]; then
        error_exit "Server backup file not found: $backup_file"
    fi
    
    # Backup current installation if it exists
    if [[ -d "$INSTALL_DIR" ]]; then
        local current_backup="$INSTALL_DIR.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}>> Backing up current installation to $current_backup${NC}"
        mv "$INSTALL_DIR" "$current_backup"
    fi
    
    # Extract backup
    echo -e "${BLUE}>> Extracting server files...${NC}"
    tar -xzf "$backup_file" -C "$(dirname "$INSTALL_DIR")" || error_exit "Failed to extract server files"
    
    # Set permissions
    chmod -R 755 "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/start" "$INSTALL_DIR/stop" 2>/dev/null
    
    echo -e "${GREEN}>> Server files restored successfully${NC}"
}

restore_configurations() {
    echo -e "${BLUE}>> Restoring configurations...${NC}"
    local config_backup_dir="$BACKUP_DIR/configs_${SELECTED_TIMESTAMP}"
    
    if [[ -d "$config_backup_dir" ]]; then
        # Restore systemd service if exists
        if [[ -f "$config_backup_dir/aurakingdom.service" ]]; then
            echo -e "${BLUE}   - Restoring systemd service...${NC}"
            sudo cp "$config_backup_dir/aurakingdom.service" "/etc/systemd/system/"
            sudo systemctl daemon-reload
            echo -e "${GREEN}   - Systemd service restored${NC}"
        fi
        
        echo -e "${GREEN}>> Configurations restored successfully${NC}"
    else
        echo -e "${YELLOW}>> No configuration backup found for this timestamp${NC}"
    fi
}

# Main execution
echo -e "${BLUE}
==================================================
           AK Server Restore Script
           Developer: Dulgan
==================================================${NC}"

# Check if backup directory exists
if [[ ! -d "$BACKUP_DIR" ]]; then
    error_exit "Backup directory not found: $BACKUP_DIR"
fi

list_available_backups

echo -e "${YELLOW}What would you like to restore?${NC}"
echo -e "  [1] Full restore (databases + server files)"
echo -e "  [2] Databases only"
echo -e "  [3] Server files only"
read -p "Enter your choice (1-3): " restore_choice

case $restore_choice in
    1)
        echo -e "${BLUE}>> Full restore selected${NC}"
        select_backup_timestamp "database"
        read_db_password
        stop_server
        restore_databases
        restore_server_files
        restore_configurations
        ;;
    2)
        echo -e "${BLUE}>> Database restore selected${NC}"
        select_backup_timestamp "database"
        read_db_password
        stop_server
        restore_databases
        ;;
    3)
        echo -e "${BLUE}>> Server files restore selected${NC}"
        select_backup_timestamp "server"
        stop_server
        restore_server_files
        restore_configurations
        ;;
    *)
        error_exit "Invalid choice"
        ;;
esac

echo -e "${GREEN}
==================================================
           Restore Complete!
==================================================${NC}"
echo -e "Restored from backup: ${GREEN}${SELECTED_TIMESTAMP}${NC}"
echo -e "\nTo start the server:"
echo -e "  ${BLUE}$INSTALL_DIR/start${NC}"
echo -e "\nOr if using systemd:"
echo -e "  ${BLUE}systemctl start aurakingdom${NC}"
