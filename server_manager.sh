#!/bin/bash

# Enhanced Server Manager for AKF
# Multi-Server & Multi-Channel Management
# Developer: Dulgan

# Color codes
RED='\e[0;31m'
GREEN='\e[1;32m'
BLUE='\e[0;36m'
YELLOW='\e[1;33m'
PURPLE='\e[0;35m'
CYAN='\e[0;96m'
BOLD='\e[1m'
NC='\e[0m'

# Configuration
BASE_DIR="/root"
BASE_NAME="hxsy"
MULTI_SERVER_CONFIG="/root/multi_server.conf"
MULTI_CHANNEL_CONFIG="/root/multi_channel.conf"
DB_USER="postgres"
SETUP_INI="/root/hxsy/setup.ini"

# Server instance tracking
declare -A SERVER_INSTANCES
declare -A SERVER_DATABASES

# Channel configuration
BASE_WORLD_ID=1010
BASE_WORLD_NAME="Aurora"
BASE_PORT=5567
BASE_ZONESERVER_ID=1011

# Auto-detect server IP from existing database
get_server_ip() {
    local server_ip="127.0.0.1"
    
    if [[ -n "$DB_PASSWORD" ]]; then
        # Try to get IP from worlds table in FFAccount
        local detected_ip=$(PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFAccount" -t -c "SELECT ip FROM worlds LIMIT 1;" 2>/dev/null | tr -d ' ' | grep -v '^$')
        
        if [[ -n "$detected_ip" && "$detected_ip" != "" ]]; then
            server_ip="$detected_ip"
            echo -e "${GREEN}>> Auto-detected server IP from database: $server_ip${NC}"
        else
            # Fallback: try from serverstatus table in FFDB1
            detected_ip=$(PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -t -c "SELECT ext_address FROM serverstatus LIMIT 1;" 2>/dev/null | tr -d ' ' | grep -v '^$')
            
            if [[ -n "$detected_ip" && "$detected_ip" != "" ]]; then
                server_ip="$detected_ip"
                echo -e "${GREEN}>> Auto-detected server IP from serverstatus: $server_ip${NC}"
            else
                echo -e "${YELLOW}>> Using default IP: $server_ip${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}>> No database access, using default IP: $server_ip${NC}"
    fi
    
    echo "$server_ip"
}

# Test database connectivity
test_database_connection() {
    echo -e "${BLUE}>> Testing database connection...${NC}"
    
    if [[ -z "$DB_PASSWORD" ]]; then
        echo -e "${RED}   ✗ Database password not available${NC}"
        return 1
    fi
    
    # Test FFAccount database
    if PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFAccount" -c "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}   ✓ FFAccount database connection successful${NC}"
    else
        echo -e "${RED}   ✗ FFAccount database connection failed${NC}"
        return 1
    fi
    
    # Test FFDB1 database
    if PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -c "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}   ✓ FFDB1 database connection successful${NC}"
    else
        echo -e "${RED}   ✗ FFDB1 database connection failed${NC}"
        return 1
    fi
    
    # Test FFMember database
    if PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFMember" -c "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}   ✓ FFMember database connection successful${NC}"
    else
        echo -e "${RED}   ✗ FFMember database connection failed${NC}"
        return 1
    fi
    
    return 0
}

# Initialize script
initialize() {
    echo -e "${PURPLE}
==================================================
          AKF Enhanced Server Manager
         Multi-Server & Multi-Channel Management
               Developer: Dulgan
==================================================${NC}"
    
    # Auto-detect database password
    auto_detect_db_password
    
    # Load configurations
    load_server_config
    load_channel_config
    
    # Detect existing instances
    detect_server_instances
}

# Auto-detect database password from setup.ini
auto_detect_db_password() {
    # First try default setup.ini
    if [[ -f "$SETUP_INI" ]]; then
        DB_PASSWORD=$(grep "^AccountDBPW=" "$SETUP_INI" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$DB_PASSWORD" ]]; then
            echo -e "${GREEN}>> Database password auto-detected from setup.ini${NC}"
            return 0
        fi
    fi
    
    # Try main hxsy directory
    if [[ -f "/root/hxsy/setup.ini" ]]; then
        DB_PASSWORD=$(grep "^AccountDBPW=" "/root/hxsy/setup.ini" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$DB_PASSWORD" ]]; then
            echo -e "${GREEN}>> Database password found from /root/hxsy/setup.ini${NC}"
            return 0
        fi
    fi
    
    # Fallback: try to find from any instance
    for instance_dir in /root/hxsy* /root/*/; do
        if [[ -f "$instance_dir/setup.ini" ]]; then
            DB_PASSWORD=$(grep "^AccountDBPW=" "$instance_dir/setup.ini" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -n "$DB_PASSWORD" ]]; then
                echo -e "${GREEN}>> Database password found from $instance_dir${NC}"
                return 0
            fi
        fi
    done
    
    echo -e "${RED}>> Could not auto-detect database password!${NC}"
    echo -e "${YELLOW}>> Please make sure setup.ini exists with AccountDBPW setting${NC}"
    return 1
}

# Detect all server instances
detect_server_instances() {
    echo -e "${BLUE}>> Detecting server instances...${NC}"
    echo -e "${BLUE}>> Searching in directory: $BASE_DIR${NC}"
    
    # Clear existing detection
    SERVER_INSTANCES=()
    SERVER_DATABASES=()
    
    # Default instance (hxsy)
    echo -e "${BLUE}>> Checking main instance: $BASE_DIR/$BASE_NAME${NC}"
    if [[ -d "$BASE_DIR/$BASE_NAME" ]]; then
        echo -e "${YELLOW}   Directory exists: $BASE_DIR/$BASE_NAME${NC}"
        
        # Check for any server executable and directory structure
        local server_found=false
        echo -e "${BLUE}   Checking for server executables and directories...${NC}"
        
        # Check for essential server directories (modern structure - recommended)
        local dirs_found=0
        for essential_dir in "WorldServer" "ZoneServer" "LoginServer" "TicketServer" "GatewayServer"; do
            if [[ -d "$BASE_DIR/$BASE_NAME/$essential_dir" ]]; then
                echo -e "${CYAN}     ✓ $essential_dir/ directory found${NC}"
                ((dirs_found++))
            fi
        done
        
        # If we have essential directories, consider it a valid server
        if [[ $dirs_found -ge 2 ]]; then
            echo -e "${GREEN}   ✓ Found $dirs_found server directories - modern server structure detected${NC}"
            server_found=true
        fi
        
        # Fallback: Check specific known server names in subdirectories and main directory
        if [[ "$server_found" == "false" ]]; then
            echo -e "${BLUE}   Checking for server executables (legacy mode)...${NC}"
            for server_location in "$BASE_DIR/$BASE_NAME/TicketServer/TicketServer" "$BASE_DIR/$BASE_NAME/LoginServer/LoginServer" "$BASE_DIR/$BASE_NAME/WorldServer/WorldServer" "$BASE_DIR/$BASE_NAME/ZoneServer/ZoneServer" "$BASE_DIR/$BASE_NAME/GatewayServer/GatewayServer" "$BASE_DIR/$BASE_NAME/MissionServer/MissionServer" "$BASE_DIR/$BASE_NAME/TicketServer" "$BASE_DIR/$BASE_NAME/LoginServer"; do
                if [[ -f "$server_location" && -x "$server_location" ]]; then
                    echo -e "${YELLOW}     Found server file: $(basename "$server_location") in $(dirname "$server_location")${NC}"
                    server_found=true
                fi
            done
        fi
        
        # If not found, check all executable files without extensions (including subdirectories)
        if [[ "$server_found" == "false" ]]; then
            echo -e "${BLUE}   Checking all executable files (including subdirectories)...${NC}"
            while IFS= read -r -d '' file; do
                local filename=$(basename "$file")
                if [[ ! "$filename" =~ \.(sh|ini|conf|txt|log)$ ]] && [[ "$filename" != "akutools" ]]; then
                    echo -e "${YELLOW}     Found executable: $filename in $(dirname "$file")${NC}"
                    server_found=true
                fi
            done < <(find "$BASE_DIR/$BASE_NAME/" -maxdepth 2 -type f -executable -print0 2>/dev/null)
        fi
        
        if [[ "$server_found" == "true" ]]; then
            SERVER_INSTANCES["hxsy"]="$BASE_DIR/$BASE_NAME"
            
            # Try to detect database name from setup.ini
            local db_name="FFAccount"
            if [[ -f "$BASE_DIR/$BASE_NAME/setup.ini" ]]; then
                local detected_db=$(grep "^AccountDBName=" "$BASE_DIR/$BASE_NAME/setup.ini" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [[ -n "$detected_db" ]]; then
                    db_name="$detected_db"
                fi
            fi
            
            SERVER_DATABASES["hxsy"]="$db_name"
            echo -e "${GREEN}   • Found main instance: hxsy at $BASE_DIR/$BASE_NAME (DB: $db_name)${NC}"
        else
            echo -e "${YELLOW}   No server executables found in $BASE_DIR/$BASE_NAME${NC}"
        fi
    else
        echo -e "${YELLOW}   Directory not found: $BASE_DIR/$BASE_NAME${NC}"
    fi
    
    # Named instances (hxsy_* and hxsy-*)
    echo -e "${BLUE}>> Scanning for hxsy_* and hxsy-* instances...${NC}"
    for instance_dir in /root/hxsy_* /root/hxsy-*; do
        echo -e "${BLUE}   Checking: $instance_dir${NC}"
        if [[ -d "$instance_dir" ]]; then
            echo -e "${YELLOW}     Directory exists${NC}"
            
            # Check for any server executable and directory structure
            local server_found=false
            echo -e "${BLUE}     Checking for server executables and directories...${NC}"
            
            # Check for essential server directories (modern structure)
            local dirs_found=0
            for essential_dir in "WorldServer" "ZoneServer" "LoginServer" "TicketServer" "GatewayServer"; do
                if [[ -d "$instance_dir/$essential_dir" ]]; then
                    echo -e "${CYAN}       ✓ $essential_dir/ directory found${NC}"
                    ((dirs_found++))
                fi
            done
            
            # If we have essential directories, consider it a valid server
            if [[ $dirs_found -ge 2 ]]; then
                echo -e "${GREEN}     ✓ Found $dirs_found server directories - modern server structure detected${NC}"
                server_found=true
            fi
            
            # Fallback: Check specific known server names (both in main directory and subdirectories)
            if [[ "$server_found" == "false" ]]; then
                echo -e "${BLUE}     Checking for server executables (legacy mode)...${NC}"
                for server_file in TicketServer LoginServer WorldServer ZoneServer GatewayServer MissionServer; do
                    # Check in main directory
                    if [[ -f "$instance_dir/$server_file" && -x "$instance_dir/$server_file" ]]; then
                        echo -e "${YELLOW}       Found server file: $server_file${NC}"
                        server_found=true
                    # Check in subdirectory (e.g., /root/hxsy/WorldServer/WorldServer)
                    elif [[ -f "$instance_dir/$server_file/$server_file" && -x "$instance_dir/$server_file/$server_file" ]]; then
                        echo -e "${YELLOW}       Found server file: $server_file in $instance_dir/$server_file${NC}"
                        server_found=true
                    fi
                done
            fi
            
            # If not found, check all executable files without extensions
            if [[ "$server_found" == "false" ]]; then
                echo -e "${BLUE}     Checking all executable files...${NC}"
                while IFS= read -r -d '' file; do
                    local filename=$(basename "$file")
                    if [[ ! "$filename" =~ \.(sh|ini|conf|txt|log)$ ]] && [[ "$filename" != "akutools" ]]; then
                        echo -e "${YELLOW}       Found executable: $filename${NC}"
                        server_found=true
                    fi
                done < <(find "$instance_dir/" -maxdepth 1 -type f -executable -print0 2>/dev/null)
            fi
            
            if [[ "$server_found" == "true" ]]; then
                local instance_name=$(basename "$instance_dir")
                # Extract suffix after hxsy_ or hxsy-
                local clean_name
                if [[ "$instance_name" == hxsy_* ]]; then
                    clean_name=${instance_name#hxsy_}
                elif [[ "$instance_name" == hxsy-* ]]; then
                    clean_name=${instance_name#hxsy-}
                else
                    clean_name="$instance_name"
                fi
                
                SERVER_INSTANCES["$clean_name"]="$instance_dir"
                
                # Try to detect database name from setup.ini
                local db_name="FFAccount"
                if [[ -f "$instance_dir/setup.ini" ]]; then
                    local detected_db=$(grep "^AccountDBName=" "$instance_dir/setup.ini" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    if [[ -n "$detected_db" ]]; then
                        db_name="$detected_db"
                    fi
                fi
                
                SERVER_DATABASES["$clean_name"]="$db_name"
                echo -e "${GREEN}   • Found instance: $clean_name at $instance_dir (DB: $db_name)${NC}"
            else
                echo -e "${YELLOW}     No server executables found in $instance_dir${NC}"
            fi
        else
            echo -e "${YELLOW}     Not a directory: $instance_dir${NC}"
        fi
    done
    
    # Custom named instances (non-hxsy pattern)
    echo -e "${BLUE}>> Scanning for custom instances...${NC}"
    for custom_dir in /root/*/; do
        local dir_name=$(basename "$custom_dir")
        # Skip known directories and hxsy patterns
        if [[ "$dir_name" != "hxsy" && "$dir_name" != "hxsy_"* && "$dir_name" != "hxsy-"* && "$dir_name" != "AKUTools" && "$dir_name" != "." && "$dir_name" != ".." ]]; then
            echo -e "${BLUE}   Checking custom: $custom_dir${NC}"
            if [[ -f "$custom_dir/TicketServer" ]]; then
                echo -e "${YELLOW}     TicketServer found in custom directory${NC}"
                SERVER_INSTANCES["$dir_name"]="$custom_dir"
                
                # Try to detect database name
                local db_name="FFAccount"
                if [[ -f "$custom_dir/setup.ini" ]]; then
                    local detected_db=$(grep "^AccountDBName=" "$custom_dir/setup.ini" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    if [[ -n "$detected_db" ]]; then
                        db_name="$detected_db"
                    fi
                fi
                
                SERVER_DATABASES["$dir_name"]="$db_name"
                echo -e "${GREEN}   • Found custom instance: $dir_name at $custom_dir (DB: $db_name)${NC}"
            fi
        fi
    done
    
    echo -e "${CYAN}>> Total instances detected: ${#SERVER_INSTANCES[@]}${NC}"
}


# Load server configuration
load_server_config() {
    if [[ -f "$MULTI_SERVER_CONFIG" ]]; then
        source "$MULTI_SERVER_CONFIG" 2>/dev/null || {
            SERVERS=()
            SERVER_PATHS=()
            SERVER_PORTS=()
        }
    else
        SERVERS=()
        SERVER_PATHS=()
        SERVER_PORTS=()
    fi
}

# Load channel configuration  
load_channel_config() {
    if [[ -f "$MULTI_CHANNEL_CONFIG" ]]; then
        source "$MULTI_CHANNEL_CONFIG" 2>/dev/null || {
            CHANNELS=()
            CHANNEL_IDS=()
            CHANNEL_PORTS=()
            CHANNEL_ZONE_IDS=()
        }
    else
        CHANNELS=()
        CHANNEL_IDS=()
        CHANNEL_PORTS=()
        CHANNEL_ZONE_IDS=()
    fi
}

# Save server configuration
save_server_config() {
    cat > "$MULTI_SERVER_CONFIG" << EOF
# Multi-Server Configuration
# Generated by AKF Enhanced Server Manager

SERVERS=($(printf '"%s" ' "${SERVERS[@]}"))
SERVER_PATHS=($(printf '"%s" ' "${SERVER_PATHS[@]}"))
SERVER_PORTS=($(printf '"%s" ' "${SERVER_PORTS[@]}"))
EOF
    echo -e "${GREEN}>> Server configuration saved to $MULTI_SERVER_CONFIG${NC}"
}

# Save channel configuration
save_channel_config() {
    cat > "$MULTI_CHANNEL_CONFIG" << EOF
# Multi-Channel Configuration  
# Generated by AKF Enhanced Server Manager

CHANNELS=($(printf '"%s" ' "${CHANNELS[@]}"))
CHANNEL_IDS=($(printf '"%s" ' "${CHANNEL_IDS[@]}"))
CHANNEL_PORTS=($(printf '"%s" ' "${CHANNEL_PORTS[@]}"))
CHANNEL_ZONE_IDS=($(printf '"%s" ' "${CHANNEL_ZONE_IDS[@]}"))
EOF
    echo -e "${GREEN}>> Channel configuration saved to $MULTI_CHANNEL_CONFIG${NC}"
}

# Calculate ports for server instance
calculate_server_ports() {
    local server_id="$1"
    local port_offset=$((server_id * 100))
    local ports=()
    
    # Base ports + offset
    ports+=($((6543 + port_offset)))  # LoginServer
    ports+=($((7777 + port_offset)))  # TicketServer
    ports+=($((7878 + port_offset)))  # GatewayServer HTTP
    ports+=($((10320 + port_offset))) # ZoneServer GM Tool
    ports+=($((20060 + port_offset))) # ZoneServer CGI
    
    echo "${ports[*]}"
}

# Calculate channel parameters based on instance and channel number
calculate_channel_params() {
    local channel_num="$1"
    local instance_id="$2"
    
    # If instance_id not provided, default to 0 (main instance)
    if [[ -z "$instance_id" ]]; then
        instance_id=0
    fi
    
    # Each instance gets its own range of 100 IDs and ports
    local instance_base=$((1010 + instance_id * 100))
    local world_id=$((instance_base + channel_num))
    local port=$((BASE_PORT + instance_id * 1000 + channel_num))
    # Zone ID calculation: For main instance, ZoneServer starts at 1011
    # For other instances, maintain 1-offset from WorldServer
    local zone_id=$((instance_base + 1 + channel_num))
    
    echo "$world_id $port $zone_id"
}

# Get instance ID from instance name/path
get_instance_id() {
    local instance_name="$1"
    local instance_id=0
    
    # Main instance (hxsy) gets ID 0
    if [[ "$instance_name" == "hxsy" ]]; then
        instance_id=0
    else
        # Named instances get sequential IDs
        local counter=1
        for existing_instance in "${!SERVER_INSTANCES[@]}"; do
            if [[ "$existing_instance" != "hxsy" ]]; then
                if [[ "$existing_instance" == "$instance_name" ]]; then
                    instance_id=$counter
                    break
                fi
                ((counter++))
            fi
        done
    fi
    
    echo "$instance_id"
}

# Create new server instance
create_server_instance() {
    echo -e "${BLUE}
==================================================
         Create New Server Instance
==================================================${NC}"
    
    if [[ -z "$DB_PASSWORD" ]]; then
        echo -e "${RED}>> Database password not available. Cannot create server instance.${NC}"
        return 1
    fi
    
    # Get server name
    read -p "Enter server instance name (e.g., server1, pvp, test): " server_name
    if [[ -z "$server_name" ]]; then
        echo -e "${RED}>> Server name cannot be empty.${NC}"
        return 1
    fi
    
    # Validate server name
    if [[ ! "$server_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}>> Invalid server name. Use only letters, numbers, underscore, and dash.${NC}"
        return 1
    fi
    
    # Check if server already exists
    local server_path="$BASE_DIR/${BASE_NAME}_${server_name}"
    if [[ -d "$server_path" ]]; then
        echo -e "${RED}>> Server instance '$server_name' already exists at $server_path${NC}"
        return 1
    fi
    
    # Check if base server exists
    local base_server_found=false
    echo -e "${BLUE}>> Checking base server files in $BASE_DIR/$BASE_NAME...${NC}"
    if [[ -d "$BASE_DIR/$BASE_NAME" ]]; then
        # List files for debugging
        echo -e "${BLUE}   All files in base directory:${NC}"
        ls -la "$BASE_DIR/$BASE_NAME/" 2>/dev/null
        
        echo -e "${BLUE}   Executable files (without extension):${NC}"
        find "$BASE_DIR/$BASE_NAME/" -maxdepth 1 -type f -executable ! -name "*.sh" ! -name "*.ini" ! -name "akutools" 2>/dev/null | while read file; do
            echo -e "${CYAN}     $(basename "$file")${NC}"
        done
        
        # Check for any server executable
        for server_file in TicketServer LoginServer WorldServer ZoneServer GatewayServer MissionServer; do
            if [[ -f "$BASE_DIR/$BASE_NAME/$server_file" && -x "$BASE_DIR/$BASE_NAME/$server_file" ]]; then
                echo -e "${GREEN}   Found server file: $server_file${NC}"
                base_server_found=true
            fi
        done
        
        # If not found, check all executable files
        if [[ "$base_server_found" == "false" ]]; then
            echo -e "${BLUE}   Checking all executable files...${NC}"
            while IFS= read -r -d '' file; do
                local filename=$(basename "$file")
                if [[ ! "$filename" =~ \.(sh|ini|conf|txt|log)$ ]] && [[ "$filename" != "akutools" ]]; then
                    echo -e "${GREEN}   Found executable: $filename${NC}"
                    base_server_found=true
                fi
            done < <(find "$BASE_DIR/$BASE_NAME/" -maxdepth 1 -type f -executable -print0 2>/dev/null)
        fi
        
        if [[ "$base_server_found" == "false" ]]; then
            echo -e "${RED}>> No server executables found in base directory!${NC}"
            echo -e "${YELLOW}>> Please check if server files are properly installed.${NC}"
            return 1
        fi
    else
        echo -e "${RED}>> Base server directory not found at $BASE_DIR/$BASE_NAME${NC}"
        echo -e "${YELLOW}>> Please run fullinstaller.sh first.${NC}"
        return 1
    fi
    
    local server_id="${#SERVERS[@]}"
    local server_ports=($(calculate_server_ports "$server_id"))
    
    echo -e "${BLUE}>> Server will be created at: $server_path${NC}"
    echo -e "${BLUE}>> Database will be: FFAccount_${server_name}${NC}"
    echo -e "${BLUE}>> Ports: Login:${server_ports[0]}, Ticket:${server_ports[1]}, Gateway:${server_ports[2]}, GM:${server_ports[3]}, CGI:${server_ports[4]}${NC}"
    
    read -p "Continue with server creation? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}>> Server creation cancelled.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}>> Creating server instance '$server_name'...${NC}"
    
    # Copy base server (excluding existing channels)
    echo -e "${BLUE}>> Copying base server files (excluding channels)...${NC}"
    
    # Create target directory
    mkdir -p "$server_path"
    
    # Copy all files and directories except Channel_* folders
    for item in "$BASE_DIR/$BASE_NAME"/*; do
        if [[ -d "$item" ]]; then
            local dirname=$(basename "$item")
            # Skip Channel_* directories
            if [[ ! "$dirname" =~ ^Channel_[0-9]+ ]]; then
                cp -r "$item" "$server_path/"
                echo -e "${GREEN}   ✓ Copied directory: $dirname${NC}"
            else
                echo -e "${YELLOW}   ✗ Skipped channel: $dirname${NC}"
            fi
        else
            # Copy all files
            cp "$item" "$server_path/"
            echo -e "${GREEN}   ✓ Copied file: $(basename "$item")${NC}"
        fi
    done
    
    echo -e "${GREEN}   ✓ Base server files copied successfully (channels excluded)${NC}"
    
    # Database configuration (all instances use same databases)
    echo -e "${BLUE}>> All instances will use shared databases: FFAccount, FFDB1, FFMember${NC}"
    
    # No need to create new databases - using shared ones
    echo -e "${GREEN}   ✓ Using existing shared databases${NC}"
    
    # Add server status entries for new instance to shared FFDB1
    echo -e "${BLUE}>> Adding server status entries to shared FFDB1...${NC}"
    local base_world_id=$((1010 + server_id * 100))
    local base_zone_id=$((1011 + server_id * 100))
    
    # Get real server IP from existing database for client connections
    local server_ip=$(get_server_ip)
    
    # Add WorldServer entry to serverstatus in shared FFDB1
    PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -c "
    INSERT INTO serverstatus (id, name, ext_address, ext_port, int_address, int_port, last_start_time, last_vip_mail_time)
    VALUES ($base_world_id, 'WorldServer', '$server_ip', ${server_ports[0]}, '127.0.0.1', $((${server_ports[0]} + 1)), 0, 0)
    ON CONFLICT (id) DO UPDATE SET 
        ext_address = '$server_ip',
        int_address = '127.0.0.1',
        ext_port = ${server_ports[0]}, 
        int_port = $((${server_ports[0]} + 1));
    " >/dev/null 2>&1
    
    # Add ZoneServer entry to serverstatus in shared FFDB1  
    PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -c "
    INSERT INTO serverstatus (id, name, ext_address, ext_port, int_address, int_port, last_start_time, last_vip_mail_time)
    VALUES ($base_zone_id, 'ZoneServer', '$server_ip', ${server_ports[3]}, '127.0.0.1', $((${server_ports[3]} + 1)), 0, 0)
    ON CONFLICT (id) DO UPDATE SET 
        ext_address = '$server_ip',
        int_address = '127.0.0.1',
        ext_port = ${server_ports[3]}, 
        int_port = $((${server_ports[3]} + 1));
    " >/dev/null 2>&1
    
    echo -e "${GREEN}   ✓ Server status entries added to shared FFDB1${NC}"
    
    # Update configuration files
    echo -e "${BLUE}>> Updating configuration files...${NC}"
    
    # Update setup.ini
    if [[ -f "$server_path/setup.ini" ]]; then
        echo -e "${BLUE}   - Updating main setup.ini...${NC}"
        # Keep shared database configurations (no changes needed)
        # AccountDBName=FFAccount (unchanged)
        # GameDB=FFDB1 (unchanged)
        
        # IP configurations (use localhost for all internal communications)
        sed -i "s/^AccountDBIP=.*/AccountDBIP=127.0.0.1/" "$server_path/setup.ini"
        sed -i "s/^GameDBIP=.*/GameDBIP=127.0.0.1/" "$server_path/setup.ini"
        sed -i "s/^MemberDBIP=.*/MemberDBIP=127.0.0.1/" "$server_path/setup.ini"
        sed -i "s/^BillingGatewayIP=.*/BillingGatewayIP=127.0.0.1/" "$server_path/setup.ini"
        sed -i "s/^TicketServerIP=.*/TicketServerIP=127.0.0.1/" "$server_path/setup.ini"
        sed -i "s/^WorldServerIP=.*/WorldServerIP=127.0.0.1/" "$server_path/setup.ini"
        sed -i "s/^ZoneServerIP=.*/ZoneServerIP=127.0.0.1/" "$server_path/setup.ini"
        sed -i "s/^LoginServerIP=.*/LoginServerIP=127.0.0.1/" "$server_path/setup.ini"
        
        # Port configurations
        sed -i "s/^TicketServerPort=.*/TicketServerPort=${server_ports[1]}/" "$server_path/setup.ini"
        sed -i "s/^BillingGatewayPort=.*/BillingGatewayPort=${server_ports[2]}/" "$server_path/setup.ini"
        sed -i "s/^BillingGatewayPaymentPort=.*/BillingGatewayPaymentPort=${server_ports[2]}/" "$server_path/setup.ini"
        sed -i "s/^BillingGatewayWorldPort=.*/BillingGatewayWorldPort=${server_ports[2]}/" "$server_path/setup.ini"
        
        # World ID configurations (base + offset)
        local world_id_base=$((1010 + server_id * 100))
        sed -i "s/^PlayerRoomWorldID=.*/PlayerRoomWorldID=$world_id_base/" "$server_path/setup.ini"
        sed -i "s/^CrossWorldID=.*/CrossWorldID=$world_id_base/" "$server_path/setup.ini"
        sed -i "s/^TerritoryWorldID=.*/TerritoryWorldID=$world_id_base/" "$server_path/setup.ini"
        sed -i "s/^ColosseumWorldID=.*/ColosseumWorldID=$world_id_base/" "$server_path/setup.ini"
        sed -i "s/^FightZoneWroldID=.*/FightZoneWroldID=$world_id_base/" "$server_path/setup.ini"
        
        echo -e "${GREEN}   ✓ Main setup.ini updated (using shared databases)${NC}"
    fi
    
    # Update server-specific setup.ini files
    echo -e "${BLUE}   - Updating server-specific setup.ini files...${NC}"
    
    # LoginServer setup.ini
    if [[ -f "$server_path/LoginServer/setup.ini" ]]; then
        sed -i "s/^LoginServerPort=.*/LoginServerPort=${server_ports[0]}/" "$server_path/LoginServer/setup.ini"
        sed -i "s/^AccountDBIP=.*/AccountDBIP=127.0.0.1/" "$server_path/LoginServer/setup.ini"
        sed -i "s/^TicketServerIP=.*/TicketServerIP=127.0.0.1/" "$server_path/LoginServer/setup.ini"
        echo -e "${GREEN}   ✓ LoginServer setup.ini updated${NC}"
    fi
    
    # TicketServer setup.ini
    if [[ -f "$server_path/TicketServer/setup.ini" ]]; then
        sed -i "s/^TicketServerPort=.*/TicketServerPort=${server_ports[1]}/" "$server_path/TicketServer/setup.ini"
        sed -i "s/^AccountDBIP=.*/AccountDBIP=127.0.0.1/" "$server_path/TicketServer/setup.ini"
        sed -i "s/^LoginServerIP=.*/LoginServerIP=127.0.0.1/" "$server_path/TicketServer/setup.ini"
        echo -e "${GREEN}   ✓ TicketServer setup.ini updated${NC}"
    fi
    
    # GatewayServer setup.ini (keep shared FFMember database)
    if [[ -f "$server_path/GatewayServer/setup.ini" ]]; then
        # AccountDBName=FFMember (unchanged - shared database)
        sed -i "s/^BillingGatewayPort=.*/BillingGatewayPort=${server_ports[2]}/" "$server_path/GatewayServer/setup.ini"
        sed -i "s/^HttpServerPort=.*/HttpServerPort=${server_ports[2]}/" "$server_path/GatewayServer/setup.ini"
        sed -i "s/^AccountDBIP=.*/AccountDBIP=127.0.0.1/" "$server_path/GatewayServer/setup.ini"
        echo -e "${GREEN}   ✓ GatewayServer setup.ini updated (using shared FFMember)${NC}"
    fi
    
    # WorldServer setup.ini
    if [[ -f "$server_path/WorldServer/setup.ini" ]]; then
        local world_id_base=$((1010 + server_id * 100))
        sed -i "s/^WorldServerID=.*/WorldServerID=$world_id_base/" "$server_path/WorldServer/setup.ini"
        sed -i "s/^GameDBIP=.*/GameDBIP=127.0.0.1/" "$server_path/WorldServer/setup.ini"
        sed -i "s/^ZoneServerIP=.*/ZoneServerIP=127.0.0.1/" "$server_path/WorldServer/setup.ini"
        echo -e "${GREEN}   ✓ WorldServer setup.ini updated${NC}"
    fi
    
    # ZoneServer setup.ini  
    if [[ -f "$server_path/ZoneServer/setup.ini" ]]; then
        local zone_id_base=$((1011 + server_id * 100))
        sed -i "s/^ZoneServerID=.*/ZoneServerID=$zone_id_base/" "$server_path/ZoneServer/setup.ini"
        sed -i "s/^GMToolPort=.*/GMToolPort=${server_ports[3]}/" "$server_path/ZoneServer/setup.ini"
        sed -i "s/^CGIPort=.*/CGIPort=${server_ports[4]}/" "$server_path/ZoneServer/setup.ini"
        sed -i "s/^GameDBIP=.*/GameDBIP=127.0.0.1/" "$server_path/ZoneServer/setup.ini"
        sed -i "s/^WorldServerIP=.*/WorldServerIP=127.0.0.1/" "$server_path/ZoneServer/setup.ini"
        echo -e "${GREEN}   ✓ ZoneServer setup.ini updated${NC}"
    fi
    
    # Update config files for each channel
    echo -e "${BLUE}   - Updating config files...${NC}"
    local world_id_base=$((1010 + server_id * 100))
    
    # Update main config.ini if exists
    if [[ -f "$server_path/config.ini" ]]; then
        # config.ini doesn't usually need World ID changes, it's for feature switches
        echo -e "${GREEN}   ✓ config.ini preserved${NC}"
    fi
    
    # Update configXX.ini files
    for config_file in "$server_path"/config[0-9][0-9].ini; do
        if [[ -f "$config_file" ]]; then
            sed -i "s/^CrossWorldID=.*/CrossWorldID=$world_id_base/" "$config_file"
            sed -i "s/^TerritoryWorldID=.*/TerritoryWorldID=$world_id_base/" "$config_file"
            sed -i "s/^ColosseumWorldID=.*/ColosseumWorldID=$world_id_base/" "$config_file"
            sed -i "s/^WarCampWorldID=.*/WarCampWorldID=$world_id_base/" "$config_file"
            sed -i "s/^FamilyWarWorldID=.*/FamilyWarWorldID=$world_id_base/" "$config_file"
            sed -i "s/^ManorRanchWorldID=.*/ManorRanchWorldID=$world_id_base/" "$config_file"
            sed -i "s/^RaidBattleWorldID=.*/RaidBattleWorldID=$world_id_base/" "$config_file"
            echo -e "${GREEN}   ✓ Updated $(basename "$config_file")${NC}"
        fi
    done
    
    # Add to configuration
    SERVERS+=("$server_name")
    SERVER_PATHS+=("$server_path")
    SERVER_PORTS+=("${server_ports[*]}")
    
    save_server_config
    
    echo -e "${GREEN}
==================================================
      Server Instance Created Successfully!
      
      Instance: $server_name
      Path: $server_path
      Databases: FFAccount, FFDB1, FFMember (shared)
      Ports: ${server_ports[*]}
      
      Use './start' to start all instances
==================================================${NC}"
}

# Create new channel for selected instance
create_channel() {
    echo -e "${BLUE}
==================================================
           Create New Channel
==================================================${NC}"
    
    if [[ -z "$DB_PASSWORD" ]]; then
        echo -e "${RED}>> Database password not available. Cannot create channel.${NC}"
        return 1
    fi
    
    # Select server instance
    if [[ ${#SERVER_INSTANCES[@]} -eq 0 ]]; then
        echo -e "${RED}>> No server instances found.${NC}"
        return 1
    elif [[ ${#SERVER_INSTANCES[@]} -eq 1 ]]; then
        # Only one instance, use it
        for instance in "${!SERVER_INSTANCES[@]}"; do
            selected_instance="$instance"
            selected_path="${SERVER_INSTANCES[$instance]}"
            selected_db="${SERVER_DATABASES[$instance]}"
            break
        done
        echo -e "${GREEN}>> Using instance: $selected_instance${NC}"
    else
        # Multiple instances, let user choose
        echo -e "${BLUE}>> Available server instances:${NC}"
        local -a instance_list=()
        local counter=1
        for instance in "${!SERVER_INSTANCES[@]}"; do
            echo -e "${GREEN}   $counter. $instance (${SERVER_INSTANCES[$instance]})${NC}"
            instance_list+=("$instance")
            ((counter++))
        done
        
        read -p "Select server instance (1-${#instance_list[@]}): " choice
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#instance_list[@]} ]]; then
            echo -e "${RED}>> Invalid selection.${NC}"
            return 1
        fi
        
        selected_instance="${instance_list[$((choice-1))]}"
        selected_path="${SERVER_INSTANCES[$selected_instance]}"
        selected_db="${SERVER_DATABASES[$selected_instance]}"
    fi
    
    echo -e "${BLUE}>> Selected instance: $selected_instance${NC}"
    echo -e "${BLUE}>> Instance path: $selected_path${NC}"
    echo -e "${BLUE}>> Database: $selected_db${NC}"
    
    # Get channel number
    read -p "Enter channel number (e.g., 1, 2, 3): " channel_num
    if [[ ! "$channel_num" =~ ^[0-9]+$ ]] || [[ "$channel_num" -lt 1 ]]; then
        echo -e "${RED}>> Invalid channel number.${NC}"
        return 1
    fi
    
    local channel_name="Channel_$(printf "%02d" $channel_num)"
    local channel_path="$selected_path/$channel_name"
    
    # Check if channel already exists
    if [[ -d "$channel_path" ]]; then
        echo -e "${RED}>> Channel already exists at $channel_path${NC}"
        return 1
    fi
    
    # Calculate channel parameters using instance-specific ID
    local instance_id=$(get_instance_id "$selected_instance")
    local params=($(calculate_channel_params "$channel_num" "$instance_id"))
    local world_id="${params[0]}"
    local port="${params[1]}"
    local zone_id="${params[2]}"
    local world_name="$BASE_WORLD_NAME-${selected_instance}-Ch$(printf "%02d" $channel_num)"
    
    echo -e "${BLUE}>> Channel will have:${NC}"
    echo -e "${BLUE}   - World ID: $world_id${NC}"
    echo -e "${BLUE}   - Port: $port${NC}"
    echo -e "${BLUE}   - Zone Server ID: $zone_id${NC}"
    echo -e "${BLUE}   - Name: $world_name${NC}"
    echo -e "${BLUE}   - Path: $channel_path${NC}"
    
    read -p "Continue with channel creation? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}>> Channel creation cancelled.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}>> Creating channel '$channel_name'...${NC}"
    
    # Create channel directory
    mkdir -p "$channel_path"
    
    # Copy required files and directories with proper structure
    echo -e "${BLUE}>> Copying channel files and directories...${NC}"
    local copy_success=true
    
    # Copy WorldServer directory with all its contents (recommended approach)
    local world_server_copied=false
    if [[ -d "$selected_path/WorldServer" ]]; then
        if cp -r "$selected_path/WorldServer" "$channel_path/" 2>/dev/null; then
            echo -e "${GREEN}   ✓ WorldServer directory copied (including setup.ini, libs, and configs)${NC}"
            world_server_copied=true
        fi
    else
        # Fallback: try copying executable only (legacy mode)
        for ws_location in "$selected_path/WorldServer" "$selected_path/worldserver" "$selected_path/World_Server"; do
            if [[ -f "$ws_location" ]]; then
                if cp "$ws_location" "$channel_path/WorldServer" 2>/dev/null; then
                    echo -e "${GREEN}   ✓ Copied $(basename "$ws_location") from $(dirname "$ws_location") → WorldServer${NC}"
                    world_server_copied=true
                    break
                fi
            fi
        done
    fi
    
    # Copy ZoneServer directory with all its contents (recommended approach)
    local zone_server_copied=false
    if [[ -d "$selected_path/ZoneServer" ]]; then
        if cp -r "$selected_path/ZoneServer" "$channel_path/" 2>/dev/null; then
            echo -e "${GREEN}   ✓ ZoneServer directory copied (including setup.ini and GMCmd.ini)${NC}"
            zone_server_copied=true
        fi
    else
        # Fallback: try copying executable only (legacy mode)
        for zs_location in "$selected_path/ZoneServer" "$selected_path/zoneserver" "$selected_path/Zone_Server"; do
            if [[ -f "$zs_location" ]]; then
                if cp "$zs_location" "$channel_path/ZoneServer" 2>/dev/null; then
                    echo -e "${GREEN}   ✓ Copied $(basename "$zs_location") from $(dirname "$zs_location") → ZoneServer${NC}"
                    zone_server_copied=true
                    break
                fi
            fi
        done
    fi
    
    # Copy config files
    local config_copied=false
    if cp "$selected_path/"*.ini "$channel_path/" 2>/dev/null; then
        echo -e "${GREEN}   ✓ Copied configuration files${NC}"
        config_copied=true
    fi
    
    # Copy library files
    cp "$selected_path/"*.so* "$channel_path/" 2>/dev/null
    
    # Check if essential files were copied
    if [[ "$world_server_copied" == "false" || "$zone_server_copied" == "false" || "$config_copied" == "false" ]]; then
        echo -e "${RED}>> Failed to copy essential channel files!${NC}"
        if [[ "$world_server_copied" == "false" ]]; then
            echo -e "${RED}   Missing: WorldServer${NC}"
        fi
        if [[ "$zone_server_copied" == "false" ]]; then
            echo -e "${RED}   Missing: ZoneServer${NC}"
        fi
        if [[ "$config_copied" == "false" ]]; then
            echo -e "${RED}   Missing: Configuration files${NC}"
        fi
        rm -rf "$channel_path" 2>/dev/null
        return 1
    fi
    
    # Create channel-specific setup.ini
    if [[ -f "$channel_path/setup.ini" ]]; then
        echo -e "${BLUE}   - Updating channel setup.ini...${NC}"
        
        # Ensure IP addresses are set to 127.0.0.1
        sed -i "s/^GameDBIP=.*/GameDBIP=127.0.0.1/" "$channel_path/setup.ini"
        sed -i "s/^AccountDBIP=.*/AccountDBIP=127.0.0.1/" "$channel_path/setup.ini"
        sed -i "s/^TicketServerIP=.*/TicketServerIP=127.0.0.1/" "$channel_path/setup.ini"
        sed -i "s/^BillingGatewayIP=.*/BillingGatewayIP=127.0.0.1/" "$channel_path/setup.ini"
        sed -i "s/^BillingGatewayPaymentIP=.*/BillingGatewayPaymentIP=127.0.0.1/" "$channel_path/setup.ini"
        sed -i "s/^BillingGatewayWorldIP=.*/BillingGatewayWorldIP=127.0.0.1/" "$channel_path/setup.ini"
        
        # World Server port configuration (each channel gets unique port)
        sed -i "s/^TicketServerPort=.*/TicketServerPort=$port/" "$channel_path/setup.ini"
        
        # World ID configurations for this channel
        sed -i "s/^PlayerRoomWorldID=.*/PlayerRoomWorldID=$world_id/" "$channel_path/setup.ini"
        sed -i "s/^CrossWorldID=.*/CrossWorldID=$world_id/" "$channel_path/setup.ini"
        sed -i "s/^TerritoryWorldID=.*/TerritoryWorldID=$world_id/" "$channel_path/setup.ini"
        sed -i "s/^ColosseumWorldID=.*/ColosseumWorldID=$world_id/" "$channel_path/setup.ini"
        sed -i "s/^FightZoneWroldID=.*/FightZoneWroldID=$world_id/" "$channel_path/setup.ini"
        
        # Keep shared database settings (no changes needed)
        # AccountDBName=FFAccount (unchanged)
        # GameDB=FFDB1 (unchanged)
        
        echo -e "${GREEN}   ✓ Channel setup.ini updated (IPs and IDs configured)${NC}"
    fi
    
    # Update WorldServer setup.ini for this channel
    if [[ -f "$channel_path/WorldServer/setup.ini" ]]; then
        sed -i "s/^WorldServerID=.*/WorldServerID=$world_id/" "$channel_path/WorldServer/setup.ini"
        echo -e "${GREEN}   ✓ WorldServer setup.ini updated (ID: $world_id)${NC}"
    fi
    
    # Update ZoneServer setup.ini for this channel
    if [[ -f "$channel_path/ZoneServer/setup.ini" ]]; then
        sed -i "s/^ZoneServerID=.*/ZoneServerID=$zone_id/" "$channel_path/ZoneServer/setup.ini"
        # Update ZoneServer ports (base port + 100 offset for zone server)
        sed -i "s/^GMToolPort=.*/GMToolPort=$((port + 100))/" "$channel_path/ZoneServer/setup.ini"
        sed -i "s/^CGIPort=.*/CGIPort=$((port + 200))/" "$channel_path/ZoneServer/setup.ini"
        echo -e "${GREEN}   ✓ ZoneServer setup.ini updated (ID: $zone_id)${NC}"
    fi
    
    # Update LoginServer setup.ini for this channel
    if [[ -f "$channel_path/LoginServer/setup.ini" ]]; then
        sed -i "s/^LoginServerPort=.*/LoginServerPort=$((port - 1000))/" "$channel_path/LoginServer/setup.ini"
        echo -e "${GREEN}   ✓ LoginServer setup.ini updated${NC}"
    fi
    
    # Update TicketServer setup.ini for this channel
    if [[ -f "$channel_path/TicketServer/setup.ini" ]]; then
        sed -i "s/^TicketServerIP=.*/TicketServerIP=127.0.0.1/" "$channel_path/TicketServer/setup.ini"
        sed -i "s/^TicketServerPort=.*/TicketServerPort=$port/" "$channel_path/TicketServer/setup.ini"
        echo -e "${GREEN}   ✓ TicketServer setup.ini updated${NC}"
    fi
    
    # Update GatewayServer setup.ini for this channel
    if [[ -f "$channel_path/GatewayServer/setup.ini" ]]; then
        sed -i "s/^AccountDBIP=.*/AccountDBIP=127.0.0.1/" "$channel_path/GatewayServer/setup.ini"
        sed -i "s/^HttpServerPort=.*/HttpServerPort=$((port + 300))/" "$channel_path/GatewayServer/setup.ini"
        echo -e "${GREEN}   ✓ GatewayServer setup.ini updated${NC}"
    fi
    
    # Update configXX.ini for this specific channel
    local channel_config_file="$instance_path/config$(printf "%02d" $channel_num).ini"
    if [[ -f "$channel_config_file" ]]; then
        echo -e "${BLUE}   - Updating $channel_config_file...${NC}"
        sed -i "s/^CrossWorldID=.*/CrossWorldID=$world_id/" "$channel_config_file"
        sed -i "s/^TerritoryWorldID=.*/TerritoryWorldID=$world_id/" "$channel_config_file"
        sed -i "s/^ColosseumWorldID=.*/ColosseumWorldID=$world_id/" "$channel_config_file"
        sed -i "s/^WarCampWorldID=.*/WarCampWorldID=$world_id/" "$channel_config_file"
        sed -i "s/^FamilyWarWorldID=.*/FamilyWarWorldID=$world_id/" "$channel_config_file"
        sed -i "s/^ManorRanchWorldID=.*/ManorRanchWorldID=$world_id/" "$channel_config_file"
        sed -i "s/^RaidBattleWorldID=.*/RaidBattleWorldID=$world_id/" "$channel_config_file"
        echo -e "${GREEN}   ✓ Channel-specific config updated${NC}"
    else
        echo -e "${YELLOW}   ! Config file $channel_config_file not found${NC}"
    fi
    
    # Add to database
    echo -e "${BLUE}>> Adding channel to database...${NC}"
    
    # Get real server IP from existing database for client connections
    local server_ip=$(get_server_ip)
    
    # Add to worlds table in shared FFAccount database
    echo -e "${BLUE}   - Adding to worlds table (IP: $server_ip)...${NC}"
    if PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFAccount" -c "
    INSERT INTO worlds (id, name, ip, port, online_user, maxnum_user, state, version, show_order)
    VALUES ($world_id, '$world_name', '$server_ip', $port, 0, 1000, 1, '015.001.01.16', $channel_num)
    ON CONFLICT (id) DO UPDATE SET 
        name = '$world_name',
        ip = '$server_ip',
        port = $port,
        show_order = $channel_num,
        state = 1;
    " 2>&1; then
        echo -e "${GREEN}   ✓ Successfully added to worlds table${NC}"
    else
        echo -e "${RED}   ✗ Failed to add to worlds table${NC}"
    fi
    
    # Add WorldServer to serverstatus table in shared FFDB1 database
    echo -e "${BLUE}   - Adding WorldServer to serverstatus (IP: $server_ip)...${NC}"
    if PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -c "
    INSERT INTO serverstatus (id, name, ext_address, ext_port, int_address, int_port, last_start_time, last_vip_mail_time)
    VALUES ($world_id, 'WorldServer', '$server_ip', $port, '127.0.0.1', $((port + 1)), 0, 0)
    ON CONFLICT (id) DO UPDATE SET 
        ext_address = '$server_ip',
        int_address = '127.0.0.1',
        ext_port = $port,
        int_port = $((port + 1)),
        name = 'WorldServer';
    " 2>&1; then
        echo -e "${GREEN}   ✓ Successfully added WorldServer to serverstatus${NC}"
    else
        echo -e "${RED}   ✗ Failed to add WorldServer to serverstatus${NC}"
    fi
    
    # Add ZoneServer to serverstatus table in shared FFDB1 database  
    echo -e "${BLUE}   - Adding ZoneServer to serverstatus (IP: $server_ip)...${NC}"
    if PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -c "
    INSERT INTO serverstatus (id, name, ext_address, ext_port, int_address, int_port, last_start_time, last_vip_mail_time)
    VALUES ($zone_id, 'ZoneServer', '$server_ip', $((port + 100)), '127.0.0.1', $((port + 101)), 0, 0)
    ON CONFLICT (id) DO UPDATE SET 
        ext_address = '$server_ip',
        int_address = '127.0.0.1',
        ext_port = $((port + 100)),
        int_port = $((port + 101)),
        name = 'ZoneServer';
    " 2>&1; then
        echo -e "${GREEN}   ✓ Successfully added ZoneServer to serverstatus${NC}"
    else
        echo -e "${RED}   ✗ Failed to add ZoneServer to serverstatus${NC}"
    fi
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}   ✓ Database tables updated successfully${NC}"
    else
        echo -e "${YELLOW}   Warning: Some database updates may have failed${NC}"
    fi
    
    # Add to configuration
    CHANNELS+=("$channel_name")
    CHANNEL_IDS+=("$world_id")
    CHANNEL_PORTS+=("$port")
    CHANNEL_ZONE_IDS+=("$zone_id")
    
    save_channel_config
    
    echo -e "${GREEN}
==================================================
        Channel Created Successfully!
        
        Instance: $selected_instance
        Channel: $channel_name
        World ID: $world_id
        Port: $port
        Zone ID: $zone_id
        Name: $world_name
        
        Use './start' to start all servers and channels
==================================================${NC}"
}

# Enhanced Channel Manager - Intelligent batch channel creation
create_channels_batch() {
    echo -e "${PURPLE}
==================================================
         Enhanced Channel Manager
    Intelligent Batch Channel Creation
==================================================${NC}"
    
    if [[ -z "$DB_PASSWORD" ]]; then
        echo -e "${RED}>> Database password not available. Cannot create channels.${NC}"
        return 1
    fi
    
    # Select server instance
    if [[ ${#SERVER_INSTANCES[@]} -eq 0 ]]; then
        echo -e "${RED}>> No server instances found.${NC}"
        return 1
    elif [[ ${#SERVER_INSTANCES[@]} -eq 1 ]]; then
        # Only one instance, use it
        for instance in "${!SERVER_INSTANCES[@]}"; do
            selected_instance="$instance"
            selected_path="${SERVER_INSTANCES[$instance]}"
            selected_db="${SERVER_DATABASES[$instance]}"
            break
        done
        echo -e "${GREEN}>> Using instance: $selected_instance${NC}"
    else
        # Multiple instances, let user choose
        echo -e "${BLUE}>> Available server instances:${NC}"
        local -a instance_list=()
        local counter=1
        for instance in "${!SERVER_INSTANCES[@]}"; do
            echo -e "${GREEN}   $counter. $instance (${SERVER_INSTANCES[$instance]})${NC}"
            instance_list+=("$instance")
            ((counter++))
        done
        
        read -p "Select server instance (1-${#instance_list[@]}): " choice
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#instance_list[@]} ]]; then
            echo -e "${RED}>> Invalid selection.${NC}"
            return 1
        fi
        
        selected_instance="${instance_list[$((choice-1))]}"
        selected_path="${SERVER_INSTANCES[$selected_instance]}"
        selected_db="${SERVER_DATABASES[$selected_instance]}"
    fi
    
    echo -e "${BLUE}>> Selected instance: $selected_instance${NC}"
    echo -e "${BLUE}>> Instance path: $selected_path${NC}"
    echo -e "${BLUE}>> Database: $selected_db${NC}"
    
    # Check existing channels
    echo -e "${BLUE}>> Analyzing existing channels...${NC}"
    local existing_channels=()
    local max_existing=0
    
    for channel_dir in "$selected_path"/Channel_*; do
        if [[ -d "$channel_dir" ]]; then
            local channel_name=$(basename "$channel_dir")
            local channel_num=$(echo "$channel_name" | sed 's/Channel_0*//')
            existing_channels+=("$channel_num")
            if [[ "$channel_num" -gt "$max_existing" ]]; then
                max_existing="$channel_num"
            fi
        fi
    done
    
    if [[ ${#existing_channels[@]} -gt 0 ]]; then
        echo -e "${GREEN}>> Found ${#existing_channels[@]} existing channels: ${existing_channels[*]}${NC}"
        echo -e "${BLUE}>> Highest channel number: $max_existing${NC}"
    else
        echo -e "${YELLOW}>> No existing channels found.${NC}"
    fi
    
    # Get desired total channel count
    echo -e "${CYAN}>> How many channels do you want in total?${NC}"
    read -p "Enter total channel count (1-50): " total_channels
    if [[ ! "$total_channels" =~ ^[0-9]+$ ]] || [[ "$total_channels" -lt 1 ]] || [[ "$total_channels" -gt 50 ]]; then
        echo -e "${RED}>> Invalid channel count. Must be between 1-50.${NC}"
        return 1
    fi
    
    # Smart analysis
    local channels_to_create=()
    local creation_count=0
    
    echo -e "${BLUE}>> Analyzing what needs to be created...${NC}"
    
    for ((i=1; i<=total_channels; i++)); do
        local channel_name="Channel_$(printf "%02d" $i)"
        local channel_path="$selected_path/$channel_name"
        
        if [[ ! -d "$channel_path" ]]; then
            channels_to_create+=("$i")
            ((creation_count++))
        fi
    done
    
    if [[ $creation_count -eq 0 ]]; then
        echo -e "${GREEN}>> All $total_channels channels already exist! Nothing to create.${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}>> Channels to create: ${channels_to_create[*]}${NC}"
    echo -e "${CYAN}>> Will create $creation_count new channels.${NC}"
    
    read -p "Continue with batch channel creation? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}>> Batch channel creation cancelled.${NC}"
        return 1
    fi
    
    # Create channels
    echo -e "${PURPLE}>> Starting batch channel creation...${NC}"
    local success_count=0
    local failed_channels=()
    
    for channel_num in "${channels_to_create[@]}"; do
        echo -e "${BLUE}>> Creating Channel $channel_num...${NC}"
        
        local channel_name="Channel_$(printf "%02d" $channel_num)"
        local channel_path="$selected_path/$channel_name"
        
        # Calculate channel parameters using instance-specific ID
        local instance_id=$(get_instance_id "$selected_instance")
        local params=($(calculate_channel_params "$channel_num" "$instance_id"))
        local world_id="${params[0]}"
        local port="${params[1]}"
        local zone_id="${params[2]}"
        local world_name="$BASE_WORLD_NAME-${selected_instance}-Ch$(printf "%02d" $channel_num)"
        
        # Create channel directory
        mkdir -p "$channel_path"
        
        # Copy required files and directories with proper structure
        echo -e "${BLUE}   Copying channel files and directories...${NC}"
        local copy_success=true
        
        # Copy WorldServer directory with all its contents (recommended approach)
        local world_server_copied=false
        if [[ -d "$selected_path/WorldServer" ]]; then
            if cp -r "$selected_path/WorldServer" "$channel_path/" 2>/dev/null; then
                echo -e "${GREEN}     ✓ WorldServer directory copied (including setup.ini, libs, and configs)${NC}"
                world_server_copied=true
            fi
        else
            # Fallback: try copying executable only (legacy mode)
            for ws_location in "$selected_path/WorldServer" "$selected_path/worldserver" "$selected_path/World_Server"; do
                if [[ -f "$ws_location" ]]; then
                    if cp "$ws_location" "$channel_path/WorldServer" 2>/dev/null; then
                        echo -e "${GREEN}     ✓ Copied $(basename "$ws_location") from $(dirname "$ws_location") → WorldServer${NC}"
                        world_server_copied=true
                        break
                    fi
                fi
            done
        fi
        
        # Copy ZoneServer directory with all its contents (recommended approach)
        local zone_server_copied=false
        if [[ -d "$selected_path/ZoneServer" ]]; then
            if cp -r "$selected_path/ZoneServer" "$channel_path/" 2>/dev/null; then
                echo -e "${GREEN}     ✓ ZoneServer directory copied (including setup.ini and GMCmd.ini)${NC}"
                zone_server_copied=true
            fi
        else
            # Fallback: try copying executable only (legacy mode)
            for zs_location in "$selected_path/ZoneServer" "$selected_path/zoneserver" "$selected_path/Zone_Server"; do
                if [[ -f "$zs_location" ]]; then
                    if cp "$zs_location" "$channel_path/ZoneServer" 2>/dev/null; then
                        echo -e "${GREEN}     ✓ Copied $(basename "$zs_location") from $(dirname "$zs_location") → ZoneServer${NC}"
                        zone_server_copied=true
                        break
                    fi
                fi
            done
        fi
        
        # Copy config files
        local config_copied=false
        if cp "$selected_path/"*.ini "$channel_path/" 2>/dev/null; then
            echo -e "${GREEN}     ✓ Copied configuration files${NC}"
            config_copied=true
        fi
        
        # Copy library files
        cp "$selected_path/"*.so* "$channel_path/" 2>/dev/null
        
        # Check if essential files were copied
        if [[ "$world_server_copied" == "true" && "$zone_server_copied" == "true" && "$config_copied" == "true" ]]; then
            
            # Create channel-specific setup.ini
            if [[ -f "$channel_path/setup.ini" ]]; then
                echo -e "${BLUE}   - Updating channel setup.ini...${NC}"
                
                # Ensure IP addresses are set to 127.0.0.1
                sed -i "s/^GameDBIP=.*/GameDBIP=127.0.0.1/" "$channel_path/setup.ini"
                sed -i "s/^AccountDBIP=.*/AccountDBIP=127.0.0.1/" "$channel_path/setup.ini"
                sed -i "s/^TicketServerIP=.*/TicketServerIP=127.0.0.1/" "$channel_path/setup.ini"
                sed -i "s/^BillingGatewayIP=.*/BillingGatewayIP=127.0.0.1/" "$channel_path/setup.ini"
                sed -i "s/^BillingGatewayPaymentIP=.*/BillingGatewayPaymentIP=127.0.0.1/" "$channel_path/setup.ini"
                sed -i "s/^BillingGatewayWorldIP=.*/BillingGatewayWorldIP=127.0.0.1/" "$channel_path/setup.ini"
                
                # World Server port configuration (each channel gets unique port)
                sed -i "s/^TicketServerPort=.*/TicketServerPort=$port/" "$channel_path/setup.ini"
                
                # World ID configurations for this channel
                sed -i "s/^PlayerRoomWorldID=.*/PlayerRoomWorldID=$world_id/" "$channel_path/setup.ini"
                sed -i "s/^CrossWorldID=.*/CrossWorldID=$world_id/" "$channel_path/setup.ini"
                sed -i "s/^TerritoryWorldID=.*/TerritoryWorldID=$world_id/" "$channel_path/setup.ini"
                sed -i "s/^ColosseumWorldID=.*/ColosseumWorldID=$world_id/" "$channel_path/setup.ini"
                sed -i "s/^FightZoneWroldID=.*/FightZoneWroldID=$world_id/" "$channel_path/setup.ini"
                
                # Keep shared database settings (no changes needed)
                # AccountDBName=FFAccount (unchanged)
                # GameDB=FFDB1 (unchanged)
            fi
            
            # Update WorldServer setup.ini for this channel
            if [[ -f "$channel_path/WorldServer/setup.ini" ]]; then
                sed -i "s/^WorldServerID=.*/WorldServerID=$world_id/" "$channel_path/WorldServer/setup.ini"
            fi
            
            # Update ZoneServer setup.ini for this channel
            if [[ -f "$channel_path/ZoneServer/setup.ini" ]]; then
                sed -i "s/^ZoneServerID=.*/ZoneServerID=$zone_id/" "$channel_path/ZoneServer/setup.ini"
                # Update ZoneServer ports (base port + 100 offset for zone server)
                sed -i "s/^GMToolPort=.*/GMToolPort=$((port + 100))/" "$channel_path/ZoneServer/setup.ini"
                sed -i "s/^CGIPort=.*/CGIPort=$((port + 200))/" "$channel_path/ZoneServer/setup.ini"
            fi
            
            # Update LoginServer setup.ini for this channel
            if [[ -f "$channel_path/LoginServer/setup.ini" ]]; then
                sed -i "s/^LoginServerPort=.*/LoginServerPort=$((port - 1000))/" "$channel_path/LoginServer/setup.ini"
            fi
            
            # Update TicketServer setup.ini for this channel
            if [[ -f "$channel_path/TicketServer/setup.ini" ]]; then
                sed -i "s/^TicketServerIP=.*/TicketServerIP=127.0.0.1/" "$channel_path/TicketServer/setup.ini"
                sed -i "s/^TicketServerPort=.*/TicketServerPort=$port/" "$channel_path/TicketServer/setup.ini"
            fi
            
            # Update GatewayServer setup.ini for this channel
            if [[ -f "$channel_path/GatewayServer/setup.ini" ]]; then
                sed -i "s/^AccountDBIP=.*/AccountDBIP=127.0.0.1/" "$channel_path/GatewayServer/setup.ini"
                sed -i "s/^HttpServerPort=.*/HttpServerPort=$((port + 300))/" "$channel_path/GatewayServer/setup.ini"
            fi
            
            # Update configXX.ini for this specific channel
            local channel_config_file="$instance_path/config$(printf "%02d" $channel_num).ini"
            if [[ -f "$channel_config_file" ]]; then
                sed -i "s/^CrossWorldID=.*/CrossWorldID=$world_id/" "$channel_config_file"
                sed -i "s/^TerritoryWorldID=.*/TerritoryWorldID=$world_id/" "$channel_config_file"
                sed -i "s/^ColosseumWorldID=.*/ColosseumWorldID=$world_id/" "$channel_config_file"
                sed -i "s/^WarCampWorldID=.*/WarCampWorldID=$world_id/" "$channel_config_file"
                sed -i "s/^FamilyWarWorldID=.*/FamilyWarWorldID=$world_id/" "$channel_config_file"
                sed -i "s/^ManorRanchWorldID=.*/ManorRanchWorldID=$world_id/" "$channel_config_file"
                sed -i "s/^RaidBattleWorldID=.*/RaidBattleWorldID=$world_id/" "$channel_config_file"
            fi
            
            # Add to database
            echo -e "${BLUE}   - Adding to database...${NC}"
            
            # Get real server IP from existing database for client connections
            local server_ip=$(get_server_ip)
            
            # Add to worlds table in shared FFAccount database
            if PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFAccount" -c "
            INSERT INTO worlds (id, name, ip, port, online_user, maxnum_user, state, version, show_order)
            VALUES ($world_id, '$world_name', '$server_ip', $port, 0, 1000, 1, '015.001.01.16', $channel_num)
            ON CONFLICT (id) DO UPDATE SET 
                name = '$world_name',
                ip = '$server_ip',
                port = $port,
                show_order = $channel_num,
                state = 1;
            " 2>&1; then
                echo -e "${GREEN}     ✓ Added to worlds table${NC}"
                db_success=true
            else
                echo -e "${RED}     ✗ Failed to add to worlds table${NC}"
                db_success=false
            fi
            
            # Add WorldServer to serverstatus table in shared FFDB1 database
            if PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -c "
            INSERT INTO serverstatus (id, name, ext_address, ext_port, int_address, int_port, last_start_time, last_vip_mail_time)
            VALUES ($world_id, 'WorldServer', '$server_ip', $port, '127.0.0.1', $((port + 1)), 0, 0)
            ON CONFLICT (id) DO UPDATE SET 
                ext_address = '$server_ip',
                int_address = '127.0.0.1',
                ext_port = $port,
                int_port = $((port + 1)),
                name = 'WorldServer';
            " 2>&1; then
                echo -e "${GREEN}     ✓ Added WorldServer to serverstatus${NC}"
            else
                echo -e "${RED}     ✗ Failed to add WorldServer to serverstatus${NC}"
                db_success=false
            fi
            
            # Add ZoneServer to serverstatus table in shared FFDB1 database  
            if PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -c "
            INSERT INTO serverstatus (id, name, ext_address, ext_port, int_address, int_port, last_start_time, last_vip_mail_time)
            VALUES ($zone_id, 'ZoneServer', '$server_ip', $((port + 100)), '127.0.0.1', $((port + 101)), 0, 0)
            ON CONFLICT (id) DO UPDATE SET 
                ext_address = '$server_ip',
                int_address = '127.0.0.1',
                ext_port = $((port + 100)),
                int_port = $((port + 101)),
                name = 'ZoneServer';
            " 2>&1; then
                echo -e "${GREEN}     ✓ Added ZoneServer to serverstatus${NC}"
            else
                echo -e "${RED}     ✗ Failed to add ZoneServer to serverstatus${NC}"
                db_success=false
            fi
            
            if [[ "$db_success" == "true" ]]; then
                echo -e "${GREEN}   ✓ Channel $channel_num created successfully${NC}"
                ((success_count++))
            else
                echo -e "${YELLOW}   ⚠ Channel $channel_num created but database update failed${NC}"
                failed_channels+=("$channel_num")
            fi
            
            # Add to configuration arrays even if DB failed
            CHANNELS+=("$channel_name")
            CHANNEL_IDS+=("$world_id")
            CHANNEL_PORTS+=("$port")
            CHANNEL_ZONE_IDS+=("$zone_id")
        else
            echo -e "${RED}   ✗ Failed to copy essential files for Channel $channel_num${NC}"
            if [[ "$world_server_copied" == "false" ]]; then
                echo -e "${RED}     Missing: WorldServer${NC}"
            fi
            if [[ "$zone_server_copied" == "false" ]]; then
                echo -e "${RED}     Missing: ZoneServer${NC}"
            fi
            if [[ "$config_copied" == "false" ]]; then
                echo -e "${RED}     Missing: Configuration files${NC}"
            fi
            failed_channels+=("$channel_num")
            # Remove the failed directory
            rm -rf "$channel_path" 2>/dev/null
        fi
    done
    
    # Save channel configuration
    if [[ $success_count -gt 0 ]]; then
        save_channel_config
        echo -e "${GREEN}>> Channel configuration saved to $MULTI_CHANNEL_CONFIG${NC}"
    fi
    
    # Results summary
    echo -e "${PURPLE}
==================================================
         Batch Channel Creation Results
==================================================${NC}"
    echo -e "${GREEN}>> Successfully created: $success_count channels${NC}"
    echo -e "${BLUE}>> Total channels now: $total_channels${NC}"
    
    if [[ ${#failed_channels[@]} -gt 0 ]]; then
        echo -e "${YELLOW}>> Issues with channels: ${failed_channels[*]}${NC}"
    fi
    
    echo -e "${CYAN}>> Use './start' to start all servers and channels${NC}"
    echo -e "${PURPLE}==================================================${NC}"
}

# List all instances and channels
list_instances() {
    echo -e "${BLUE}
==================================================
           Server Instances & Channels
==================================================${NC}"
    
    if [[ ${#SERVER_INSTANCES[@]} -eq 0 ]]; then
        echo -e "${YELLOW}>> No server instances found.${NC}"
        return 0
    fi
    
    for instance in "${!SERVER_INSTANCES[@]}"; do
        local instance_path="${SERVER_INSTANCES[$instance]}"
        local instance_db="${SERVER_DATABASES[$instance]}"
        
        echo -e "${GREEN}
📁 Instance: $instance${NC}"
        echo -e "${BLUE}   Path: $instance_path${NC}"
        echo -e "${BLUE}   Database: $instance_db${NC}"
        
        # Check if instance is running
        local running_servers=0
        for server_type in TicketServer GatewayServer LoginServer MissionServer WorldServer ZoneServer; do
            if pgrep -f "$instance_path/$server_type" > /dev/null 2>&1; then
                ((running_servers++))
            fi
        done
        
        if [[ $running_servers -gt 0 ]]; then
            echo -e "${GREEN}   Status: $running_servers servers running${NC}"
        else
            echo -e "${YELLOW}   Status: Stopped${NC}"
        fi
        
        # List channels
        local channel_count=0
        for channel_dir in "$instance_path"/Channel_*; do
            if [[ -d "$channel_dir" ]]; then
                local channel_name=$(basename "$channel_dir")
                echo -e "${CYAN}   📺 $channel_name${NC}"
                
                # Check channel status
                local channel_running=0
                for server_type in WorldServer ZoneServer; do
                    if pgrep -f "$channel_dir/$server_type" > /dev/null 2>&1; then
                        ((channel_running++))
                    fi
                done
                
                if [[ $channel_running -gt 0 ]]; then
                    echo -e "${GREEN}      Status: $channel_running servers running${NC}"
                else
                    echo -e "${YELLOW}      Status: Stopped${NC}"
                fi
                
                ((channel_count++))
            fi
        done
        
        echo -e "${BLUE}   Channels: $channel_count${NC}"
    done
    
    echo -e "${PURPLE}
==================================================
Total: ${#SERVER_INSTANCES[@]} instances found
==================================================${NC}"
}

# Remove server instance
remove_server_instance() {
    echo -e "${BLUE}
==================================================
         Remove Server Instance
==================================================${NC}"
    
    if [[ ${#SERVER_INSTANCES[@]} -eq 0 ]]; then
        echo -e "${YELLOW}>> No server instances found.${NC}"
        return 0
    fi
    
    # List instances
    echo -e "${BLUE}>> Available server instances:${NC}"
    local -a instance_list=()
    local counter=1
    for instance in "${!SERVER_INSTANCES[@]}"; do
        echo -e "${GREEN}   $counter. $instance (${SERVER_INSTANCES[$instance]})${NC}"
        instance_list+=("$instance")
        ((counter++))
    done
    
    read -p "Select instance to remove (1-${#instance_list[@]}): " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#instance_list[@]} ]]; then
        echo -e "${RED}>> Invalid selection.${NC}"
        return 1
    fi
    
    local selected_instance="${instance_list[$((choice-1))]}"
    local selected_path="${SERVER_INSTANCES[$selected_instance]}"
    local selected_db="${SERVER_DATABASES[$selected_instance]}"
    
    echo -e "${RED}
⚠️  WARNING: This will permanently delete:
   - Instance: $selected_instance
   - Path: $selected_path  
   - Database: $selected_db
   - All channels and data
${NC}"
    
    read -p "Type 'DELETE' to confirm removal: " confirm
    if [[ "$confirm" != "DELETE" ]]; then
        echo -e "${YELLOW}>> Removal cancelled.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}>> Removing server instance '$selected_instance'...${NC}"
    
    # Stop any running servers first
    for server_type in ZoneServer WorldServer MissionServer LoginServer GatewayServer TicketServer; do
        pkill -f "$selected_path/$server_type" 2>/dev/null
    done
    
    # Stop channel servers
    for channel_dir in "$selected_path"/Channel_*; do
        if [[ -d "$channel_dir" ]]; then
            pkill -f "$channel_dir/WorldServer" 2>/dev/null
            pkill -f "$channel_dir/ZoneServer" 2>/dev/null
        fi
    done
    
    # Remove directory
    if [[ -d "$selected_path" ]]; then
        rm -rf "$selected_path"
        echo -e "${GREEN}>> Directory removed: $selected_path${NC}"
    fi
    
    # Remove server entries from shared databases
    if [[ -n "$DB_PASSWORD" ]]; then
        echo -e "${BLUE}>> Removing server entries from shared databases...${NC}"
        
        # Calculate server ID range for this instance
        local instance_suffix="${selected_db#FFAccount_}"
        local server_id=0
        
        # Find server_id by checking existing instances
        local counter=0
        for existing_instance in "${!SERVER_INSTANCES[@]}"; do
            if [[ "$existing_instance" == "$selected_instance" ]]; then
                server_id=$counter
                break
            fi
            ((counter++))
        done
        
        local base_world_id=$((1010 + server_id * 100))
        local base_zone_id=$((1011 + server_id * 100))
        
        # Remove server status entries from shared FFDB1
        PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -c "
        DELETE FROM serverstatus WHERE id >= $base_world_id AND id < $((base_world_id + 100));
        " >/dev/null 2>&1
        echo -e "${GREEN}   ✓ Removed server status entries from FFDB1${NC}"
        
        # Remove world entries from shared FFAccount
        PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFAccount" -c "
        DELETE FROM worlds WHERE id >= $base_world_id AND id < $((base_world_id + 100));
        " >/dev/null 2>&1
        echo -e "${GREEN}   ✓ Removed world entries from FFAccount${NC}"
    fi
    
    echo -e "${GREEN}>> Server instance '$selected_instance' removed successfully.${NC}"
    
    # Re-detect instances
    detect_server_instances
}

# Remove channel
remove_channel() {
    echo -e "${BLUE}
==================================================
             Remove Channel
==================================================${NC}"
    
    # Find all channels across all instances
    local -a all_channels=()
    local -a channel_instances=()
    local -a channel_paths=()
    
    for instance in "${!SERVER_INSTANCES[@]}"; do
        local instance_path="${SERVER_INSTANCES[$instance]}"
        for channel_dir in "$instance_path"/Channel_*; do
            if [[ -d "$channel_dir" ]]; then
                local channel_name=$(basename "$channel_dir")
                all_channels+=("$channel_name")
                channel_instances+=("$instance")
                channel_paths+=("$channel_dir")
            fi
        done
    done
    
    if [[ ${#all_channels[@]} -eq 0 ]]; then
        echo -e "${YELLOW}>> No channels found.${NC}"
        return 0
    fi
    
    # List channels
    echo -e "${BLUE}>> Available channels:${NC}"
    for i in "${!all_channels[@]}"; do
        echo -e "${GREEN}   $((i+1)). ${all_channels[i]} (Instance: ${channel_instances[i]})${NC}"
    done
    
    read -p "Select channel to remove (1-${#all_channels[@]}): " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#all_channels[@]} ]]; then
        echo -e "${RED}>> Invalid selection.${NC}"
        return 1
    fi
    
    local idx=$((choice-1))
    local selected_channel="${all_channels[idx]}"
    local selected_instance="${channel_instances[idx]}"
    local selected_path="${channel_paths[idx]}"
    local selected_db="${SERVER_DATABASES[$selected_instance]}"
    
    echo -e "${RED}
⚠️  WARNING: This will permanently delete:
   - Channel: $selected_channel
   - Instance: $selected_instance
   - Path: $selected_path
${NC}"
    
    read -p "Type 'DELETE' to confirm removal: " confirm
    if [[ "$confirm" != "DELETE" ]]; then
        echo -e "${YELLOW}>> Removal cancelled.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}>> Removing channel '$selected_channel'...${NC}"
    
    # Stop channel servers
    pkill -f "$selected_path/WorldServer" 2>/dev/null
    pkill -f "$selected_path/ZoneServer" 2>/dev/null
    
    # Extract channel number for database cleanup
    if [[ "$selected_channel" =~ Channel_([0-9]+) ]]; then
        local channel_num="${BASH_REMATCH[1]}"
        local world_id=$((BASE_WORLD_ID + channel_num))
        local zone_id=$((BASE_ZONESERVER_ID + channel_num))
        
        # Remove from shared databases
        if [[ -n "$DB_PASSWORD" ]]; then
            echo -e "${BLUE}>> Removing database entries...${NC}"
            
            # Remove from worlds table in shared FFAccount database
            PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFAccount" -c "
            DELETE FROM worlds WHERE id = $world_id;
            " >/dev/null 2>&1
            echo -e "${GREEN}   ✓ Removed from worlds table${NC}"
            
            # Remove WorldServer from serverstatus table in shared FFDB1 database
            PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -c "
            DELETE FROM serverstatus WHERE id = $world_id AND name = 'WorldServer';
            " >/dev/null 2>&1
            echo -e "${GREEN}   ✓ Removed WorldServer from serverstatus${NC}"
            
            # Remove ZoneServer from serverstatus table in shared FFDB1 database
            PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFDB1" -c "
            DELETE FROM serverstatus WHERE id = $zone_id AND name = 'ZoneServer';
            " >/dev/null 2>&1
            echo -e "${GREEN}   ✓ Removed ZoneServer from serverstatus${NC}"
        fi
    fi
    
    # Remove directory
    if [[ -d "$selected_path" ]]; then
        rm -rf "$selected_path"
        echo -e "${GREEN}>> Directory removed: $selected_path${NC}"
    fi
    
    echo -e "${GREEN}>> Channel '$selected_channel' removed successfully.${NC}"
}

# Main menu
show_main_menu() {
    while true; do
        echo -e "${PURPLE}
==================================================
          AKF Enhanced Server Manager
==================================================
${GREEN}1.${NC} Create New Server Instance
${GREEN}2.${NC} Create Single Channel
${GREEN}3.${NC} Enhanced Channel Manager (Batch)
${GREEN}4.${NC} List All Instances & Channels
${GREEN}5.${NC} Remove Server Instance
${GREEN}6.${NC} Remove Channel
${GREEN}7.${NC} Test Database Connection
${GREEN}8.${NC} Refresh Detection
${GREEN}0.${NC} Exit
==================================================${NC}"
        
        read -p "Select option (0-8): " choice
        
        case "$choice" in
            1)
                create_server_instance
                ;;
            2)
                create_channel
                ;;
            3)
                create_channels_batch
                ;;
            4)
                list_instances
                ;;
            5)
                remove_server_instance
                ;;
            6)
                remove_channel
                ;;
            7)
                test_database_connection
                ;;
            8)
                echo -e "${BLUE}>> Refreshing detection...${NC}"
                detect_server_instances
                load_server_config
                load_channel_config
                ;;
            0)
                echo -e "${GREEN}>> Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}>> Invalid option. Please try again.${NC}"
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Main execution
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}>> This script must be run as root.${NC}"
        exit 1
    fi
    
    # Initialize
    initialize
    
    # Check if database password is available
    if [[ -z "$DB_PASSWORD" ]]; then
        echo -e "${YELLOW}>> Warning: Database password not auto-detected.${NC}"
        echo -e "${YELLOW}>> Some features may not work properly.${NC}"
        echo
    fi
    
    # Show main menu
    show_main_menu
}

# Run main function
main "$@"
