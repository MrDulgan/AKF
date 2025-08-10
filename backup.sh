#!/bin/bash

# AK Server Backup Script
# Developer: Dulgan

RED='\e[0;31m'
GREEN='\e[1;32m'
BLUE='\e[0;36m'
YELLOW='\e[1;33m'
NC='\e[0m'

INSTALL_DIR="/root/hxsy"
BACKUP_DIR="/root/ak_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
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
            error_exit "Database password not found in $config_path"
        fi
    else
        error_exit "Configuration file not found: $config_path"
    fi
}

create_backup_directory() {
    echo -e "${BLUE}>> Creating backup directory...${NC}"
    mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory"
    echo -e "${GREEN}>> Backup directory ready: $BACKUP_DIR${NC}"
}

backup_databases() {
    echo -e "${BLUE}>> Backing up databases...${NC}"
    local databases=("FFAccount" "FFDB1" "FFMember")
    
    for db in "${databases[@]}"; do
        echo -e "${BLUE}   - Backing up $db...${NC}"
        PGPASSWORD="$DB_PASS" pg_dump -U "$DB_USER" -h localhost "$db" > "$BACKUP_DIR/${db}_${TIMESTAMP}.sql" || error_exit "Failed to backup $db"
        echo -e "${GREEN}   - $db backed up successfully${NC}"
    done
}

backup_server_files() {
    echo -e "${BLUE}>> Backing up server files...${NC}"
    
    # Create tar archive excluding logs and backups
    tar -czf "$BACKUP_DIR/server_files_${TIMESTAMP}.tar.gz" \
        --exclude="$INSTALL_DIR/Logs" \
        --exclude="$INSTALL_DIR/*.log*" \
        -C "$(dirname "$INSTALL_DIR")" \
        "$(basename "$INSTALL_DIR")" || error_exit "Failed to backup server files"
    
    echo -e "${GREEN}>> Server files backed up successfully${NC}"
}

backup_configurations() {
    echo -e "${BLUE}>> Backing up configurations...${NC}"
    
    local config_backup_dir="$BACKUP_DIR/configs_${TIMESTAMP}"
    mkdir -p "$config_backup_dir"
    
    # Backup important config files
    cp "$INSTALL_DIR/setup.ini" "$config_backup_dir/" 2>/dev/null
    cp "$INSTALL_DIR/GatewayServer/setup.ini" "$config_backup_dir/gateway_setup.ini" 2>/dev/null
    
    # Backup systemd service if exists
    if [[ -f "/etc/systemd/system/aurakingdom.service" ]]; then
        cp "/etc/systemd/system/aurakingdom.service" "$config_backup_dir/"
    fi
    
    echo -e "${GREEN}>> Configurations backed up successfully${NC}"
}

cleanup_old_backups() {
    echo -e "${BLUE}>> Cleaning up old backups (keeping last 5)...${NC}"
    
    # Keep only last 5 database backups for each database
    for db in "FFAccount" "FFDB1" "FFMember"; do
        ls -t "$BACKUP_DIR"/${db}_*.sql 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
    done
    
    # Keep only last 5 server file backups
    ls -t "$BACKUP_DIR"/server_files_*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
    
    # Keep only last 5 config backups
    ls -td "$BACKUP_DIR"/configs_* 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null
    
    echo -e "${GREEN}>> Old backups cleaned up${NC}"
}

show_backup_info() {
    echo -e "${GREEN}
==================================================
           Backup Complete!
==================================================${NC}"
    echo -e "Backup Location: ${GREEN}$BACKUP_DIR${NC}"
    echo -e "Timestamp: ${GREEN}$TIMESTAMP${NC}"
    echo -e "Backup Size: ${GREEN}$(du -sh "$BACKUP_DIR" | cut -f1)${NC}"
    echo -e "\nBackup Contents:"
    ls -la "$BACKUP_DIR"/*"$TIMESTAMP"* 2>/dev/null | while read line; do
        echo -e "  ${BLUE}$line${NC}"
    done
}

# Main execution
echo -e "${BLUE}
==================================================
           AK Server Backup Script
           Developer: Dulgan
==================================================${NC}"

# Check if server directory exists
if [[ ! -d "$INSTALL_DIR" ]]; then
    error_exit "Server installation directory not found: $INSTALL_DIR"
fi

# Check dependencies
for cmd in pg_dump tar; do
    if ! command -v "$cmd" &> /dev/null; then
        error_exit "Required command not found: $cmd"
    fi
done

read_db_password
create_backup_directory
backup_databases
backup_server_files
backup_configurations
cleanup_old_backups
show_backup_info

echo -e "\n${GREEN}Backup process completed successfully!${NC}"
