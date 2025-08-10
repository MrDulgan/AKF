#!/bin/bash

# Enhanced Server Manager for AKF
# Combines multi-server and multi-channel management
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
    if [[ -f "$SETUP_INI" ]]; then
        DB_PASSWORD=$(grep "^AccountDBPW=" "$SETUP_INI" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$DB_PASSWORD" ]]; then
            echo -e "${GREEN}>> Database password auto-detected from setup.ini${NC}"
            return 0
        fi
    fi
    
    # Fallback: try to find from any instance
    for instance_dir in /root/hxsy*; do
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
    
    # Clear existing detection
    SERVER_INSTANCES=()
    SERVER_DATABASES=()
    
    # Default instance
    if [[ -d "$BASE_DIR/$BASE_NAME" && -f "$BASE_DIR/$BASE_NAME/TicketServer" ]]; then
        SERVER_INSTANCES["default"]="$BASE_DIR/$BASE_NAME"
        SERVER_DATABASES["default"]="FFAccount"
        echo -e "${GREEN}   • Found default instance: $BASE_DIR/$BASE_NAME${NC}"
    fi
    
    # Named instances (hxsy_*)
    for instance_dir in /root/hxsy_*; do
        if [[ -d "$instance_dir" && -f "$instance_dir/TicketServer" ]]; then
            local instance_name=$(basename "$instance_dir")
            SERVER_INSTANCES["$instance_name"]="$instance_dir"
            
            # Try to detect database name from setup.ini
            local db_name="FFAccount"
            if [[ -f "$instance_dir/setup.ini" ]]; then
                local detected_db=$(grep "^AccountDBName=" "$instance_dir/setup.ini" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [[ -n "$detected_db" ]]; then
                    db_name="$detected_db"
                fi
            fi
            
            SERVER_DATABASES["$instance_name"]="$db_name"
            echo -e "${GREEN}   • Found instance: $instance_name at $instance_dir (DB: $db_name)${NC}"
        fi
    done
    
    # Custom named instances
    for custom_dir in /root/*/; do
        local dir_name=$(basename "$custom_dir")
        if [[ "$dir_name" != "hxsy" && "$dir_name" != "hxsy_"* && "$dir_name" != "AKUTools" && "$dir_name" != "." && "$dir_name" != ".." ]]; then
            if [[ -f "$custom_dir/TicketServer" ]]; then
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

# Calculate channel parameters
calculate_channel_params() {
    local channel_num="$1"
    local world_id=$((BASE_WORLD_ID + channel_num))
    local port=$((BASE_PORT + channel_num))
    local zone_id=$((BASE_ZONESERVER_ID + channel_num))
    
    echo "$world_id $port $zone_id"
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
    if [[ ! -d "$BASE_DIR/$BASE_NAME" ]]; then
        echo -e "${RED}>> Base server not found at $BASE_DIR/$BASE_NAME${NC}"
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
    
    # Copy base server
    echo -e "${BLUE}>> Copying base server files...${NC}"
    if ! cp -r "$BASE_DIR/$BASE_NAME" "$server_path"; then
        echo -e "${RED}>> Failed to copy server files.${NC}"
        return 1
    fi
    
    # Create database
    echo -e "${BLUE}>> Creating database FFAccount_${server_name}...${NC}"
    PGPASSWORD="$DB_PASSWORD" createdb -U "$DB_USER" -h localhost "FFAccount_${server_name}" 2>/dev/null
    
    # Copy database structure
    echo -e "${BLUE}>> Copying database structure...${NC}"
    PGPASSWORD="$DB_PASSWORD" pg_dump -U "$DB_USER" -h localhost -s FFAccount | PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "FFAccount_${server_name}" >/dev/null 2>&1
    
    # Update configuration files
    echo -e "${BLUE}>> Updating configuration files...${NC}"
    
    # Update setup.ini
    if [[ -f "$server_path/setup.ini" ]]; then
        sed -i "s/^AccountDBName=.*/AccountDBName=FFAccount_${server_name}/" "$server_path/setup.ini"
        sed -i "s/^LoginServerPort=.*/LoginServerPort=${server_ports[0]}/" "$server_path/setup.ini"
        sed -i "s/^TicketServerPort=.*/TicketServerPort=${server_ports[1]}/" "$server_path/setup.ini"
        sed -i "s/^GatewayServerPort=.*/GatewayServerPort=${server_ports[2]}/" "$server_path/setup.ini"
    fi
    
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
      Database: FFAccount_${server_name}
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
    
    # Calculate channel parameters
    local params=($(calculate_channel_params "$channel_num"))
    local world_id="${params[0]}"
    local port="${params[1]}"
    local zone_id="${params[2]}"
    local world_name="$BASE_WORLD_NAME-Ch$(printf "%02d" $channel_num)"
    
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
    
    # Copy required files
    echo -e "${BLUE}>> Copying channel files...${NC}"
    cp "$selected_path/WorldServer" "$channel_path/" 2>/dev/null
    cp "$selected_path/ZoneServer" "$channel_path/" 2>/dev/null
    cp "$selected_path/"*.ini "$channel_path/" 2>/dev/null
    cp "$selected_path/"*.so* "$channel_path/" 2>/dev/null
    
    # Create channel-specific setup.ini
    if [[ -f "$channel_path/setup.ini" ]]; then
        sed -i "s/^WorldServerPort=.*/WorldServerPort=$port/" "$channel_path/setup.ini"
        sed -i "s/^ZoneServerID=.*/ZoneServerID=$zone_id/" "$channel_path/setup.ini"
        
        # Add channel-specific database name if different
        if [[ "$selected_db" != "FFAccount" ]]; then
            sed -i "s/^AccountDBName=.*/AccountDBName=$selected_db/" "$channel_path/setup.ini"
        fi
    fi
    
    # Add to database
    echo -e "${BLUE}>> Adding channel to database...${NC}"
    PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "$selected_db" -c "
    INSERT INTO worlds (world_id, world_name, world_ip, world_port, world_max_user, world_order) 
    VALUES ($world_id, '$world_name', '127.0.0.1', $port, 1000, $channel_num)
    ON CONFLICT (world_id) DO UPDATE SET 
        world_name = '$world_name',
        world_port = $port,
        world_order = $channel_num;
    " >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}>> Database updated successfully.${NC}"
    else
        echo -e "${YELLOW}>> Warning: Database update may have failed.${NC}"
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
    
    # Remove database
    if [[ -n "$DB_PASSWORD" && "$selected_db" != "FFAccount" ]]; then
        PGPASSWORD="$DB_PASSWORD" dropdb -U "$DB_USER" -h localhost "$selected_db" 2>/dev/null
        echo -e "${GREEN}>> Database removed: $selected_db${NC}"
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
        
        # Remove from database
        if [[ -n "$DB_PASSWORD" ]]; then
            PGPASSWORD="$DB_PASSWORD" psql -U "$DB_USER" -h localhost -d "$selected_db" -c "
            DELETE FROM worlds WHERE world_id = $world_id;
            " >/dev/null 2>&1
            echo -e "${GREEN}>> Database entry removed.${NC}"
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
${GREEN}2.${NC} Create New Channel
${GREEN}3.${NC} List All Instances & Channels
${GREEN}4.${NC} Remove Server Instance
${GREEN}5.${NC} Remove Channel
${GREEN}6.${NC} Refresh Detection
${GREEN}0.${NC} Exit
==================================================${NC}"
        
        read -p "Select option (0-6): " choice
        
        case "$choice" in
            1)
                create_server_instance
                ;;
            2)
                create_channel
                ;;
            3)
                list_instances
                ;;
            4)
                remove_server_instance
                ;;
            5)
                remove_channel
                ;;
            6)
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
