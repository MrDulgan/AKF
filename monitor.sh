#!/bin/bash

# AK Server Monitoring Script
# Developer: Dulgan

RED='\e[0;31m'
GREEN='\e[1;32m'
BLUE='\e[0;36m'
YELLOW='\e[1;33m'
PURPLE='\e[0;35m'
NC='\e[0m'

INSTALL_DIR="/root/hxsy"
SERVERS=("TicketServer" "GatewayServer" "LoginServer" "MissionServer" "WorldServer" "ZoneServer")
REFRESH_INTERVAL=5

get_server_status() {
    local server="$1"
    if pgrep -f "$server" > /dev/null; then
        echo -e "${GREEN}RUNNING${NC}"
    else
        echo -e "${RED}STOPPED${NC}"
    fi
}

get_server_pid() {
    local server="$1"
    local pid=$(pgrep -f "$server" | head -n1)
    if [[ -n "$pid" ]]; then
        echo "$pid"
    else
        echo "N/A"
    fi
}

get_server_memory() {
    local server="$1"
    local pid=$(pgrep -f "$server" | head -n1)
    if [[ -n "$pid" ]] && [[ -d "/proc/$pid" ]]; then
        local mem_kb=$(cat /proc/$pid/status 2>/dev/null | grep VmRSS | awk '{print $2}')
        if [[ -n "$mem_kb" ]]; then
            echo "$((mem_kb / 1024)) MB"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

get_server_cpu() {
    local server="$1"
    local pid=$(pgrep -f "$server" | head -n1)
    if [[ -n "$pid" ]] && [[ -d "/proc/$pid" ]]; then
        local cpu=$(ps -p "$pid" -o pcpu= 2>/dev/null | xargs)
        if [[ -n "$cpu" ]]; then
            echo "${cpu}%"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

get_server_uptime() {
    local server="$1"
    local pid=$(pgrep -f "$server" | head -n1)
    if [[ -n "$pid" ]] && [[ -d "/proc/$pid" ]]; then
        local start_time=$(stat -c %Y /proc/$pid 2>/dev/null)
        if [[ -n "$start_time" ]]; then
            local current_time=$(date +%s)
            local uptime_seconds=$((current_time - start_time))
            local days=$((uptime_seconds / 86400))
            local hours=$(((uptime_seconds % 86400) / 3600))
            local minutes=$(((uptime_seconds % 3600) / 60))
            
            if [[ $days -gt 0 ]]; then
                echo "${days}d ${hours}h ${minutes}m"
            elif [[ $hours -gt 0 ]]; then
                echo "${hours}h ${minutes}m"
            else
                echo "${minutes}m"
            fi
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

get_system_info() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    local mem_info=$(free | grep Mem)
    local mem_total=$(echo "$mem_info" | awk '{printf "%.1f", $2/1024/1024}')
    local mem_used=$(echo "$mem_info" | awk '{printf "%.1f", $3/1024/1024}')
    local mem_percent=$(echo "$mem_info" | awk '{printf "%.1f", ($3/$2)*100}')
    local disk_usage=$(df -h "$INSTALL_DIR" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    echo "CPU: ${cpu_usage}% | Memory: ${mem_used}GB/${mem_total}GB (${mem_percent}%) | Disk: ${disk_usage}% | Load: ${load_avg}"
}

check_database_connection() {
    local config_path="$INSTALL_DIR/setup.ini"
    if [[ -f "$config_path" ]]; then
        local db_pass=$(grep "^AccountDBPW=" "$config_path" | head -n 1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$db_pass" ]]; then
            if PGPASSWORD="$db_pass" psql -U postgres -h localhost -d FFAccount -c "SELECT 1;" &>/dev/null; then
                echo -e "${GREEN}CONNECTED${NC}"
            else
                echo -e "${RED}FAILED${NC}"
            fi
        else
            echo -e "${YELLOW}NO_CONFIG${NC}"
        fi
    else
        echo -e "${YELLOW}NO_CONFIG${NC}"
    fi
}

get_port_status() {
    local port="$1"
    if ss -tuln | grep ":$port " > /dev/null 2>&1; then
        echo -e "${GREEN}OPEN${NC}"
    else
        echo -e "${RED}CLOSED${NC}"
    fi
}

display_header() {
    clear
    echo -e "${BLUE}
==================================================
           AK Server Monitor
           Developer: Dulgan
           $(date '+%Y-%m-%d %H:%M:%S')
==================================================${NC}"
}

display_server_status() {
    echo -e "\n${YELLOW}🎮 Server Status:${NC}"
    printf "%-15s %-10s %-8s %-8s %-10s %-12s\n" "Server" "Status" "PID" "CPU" "Memory" "Uptime"
    echo "-------------------------------------------------------------------------"
    
    for server in "${SERVERS[@]}"; do
        local status=$(get_server_status "$server")
        local pid=$(get_server_pid "$server")
        local cpu=$(get_server_cpu "$server")
        local memory=$(get_server_memory "$server")
        local uptime=$(get_server_uptime "$server")
        
        printf "%-15s %-18s %-8s %-8s %-10s %-12s\n" "$server" "$status" "$pid" "$cpu" "$memory" "$uptime"
    done
}

display_system_status() {
    echo -e "\n${YELLOW}💻 System Status:${NC}"
    echo -e "$(get_system_info)"
}

display_network_status() {
    echo -e "\n${YELLOW}🌐 Network Status:${NC}"
    local ports=("5567" "5568" "6543" "7654" "7777" "7878" "10021" "10022")
    
    printf "%-8s %-10s    " "Port" "Status"
    for i in "${!ports[@]}"; do
        if [[ $((i % 4)) -eq 0 ]] && [[ $i -gt 0 ]]; then
            printf "\n%-8s %-10s    " "" ""
        fi
        printf "%-8s %-10s    " "${ports[$i]}" "$(get_port_status "${ports[$i]}")"
    done
    echo ""
}

display_database_status() {
    echo -e "\n${YELLOW}🗄️  Database Status:${NC}"
    echo -e "PostgreSQL Connection: $(check_database_connection)"
}

display_log_info() {
    echo -e "\n${YELLOW}📝 Recent Logs:${NC}"
    if [[ -d "$INSTALL_DIR/Logs" ]]; then
        local log_count=$(find "$INSTALL_DIR/Logs" -name "*.log*" 2>/dev/null | wc -l)
        local log_size=$(du -sh "$INSTALL_DIR/Logs" 2>/dev/null | cut -f1)
        echo -e "Log files: $log_count | Total size: $log_size"
        
        # Show last few error lines if any
        local recent_errors=$(find "$INSTALL_DIR/Logs" -name "*.log*" -type f -exec grep -l "ERROR\|FATAL\|error\|fatal" {} \; 2>/dev/null | wc -l)
        if [[ $recent_errors -gt 0 ]]; then
            echo -e "${RED}⚠️  Found $recent_errors log files with errors${NC}"
        fi
    else
        echo -e "No log directory found"
    fi
}

display_controls() {
    echo -e "\n${PURPLE}🎛️  Controls:${NC}"
    echo -e "  [q] Quit    [r] Restart Servers    [s] Stop Servers    [b] Backup    [l] View Logs"
}

handle_input() {
    read -t 1 -n 1 key
    case $key in
        q|Q)
            echo -e "\n${GREEN}Monitoring stopped.${NC}"
            exit 0
            ;;
        r|R)
            echo -e "\n${BLUE}Restarting servers...${NC}"
            "$INSTALL_DIR/stop" && sleep 3 && "$INSTALL_DIR/start" &
            ;;
        s|S)
            echo -e "\n${BLUE}Stopping servers...${NC}"
            "$INSTALL_DIR/stop" &
            ;;
        b|B)
            echo -e "\n${BLUE}Creating backup...${NC}"
            if [[ -f "$(dirname "$0")/backup.sh" ]]; then
                "$(dirname "$0")/backup.sh" &
            else
                echo -e "${RED}Backup script not found${NC}"
            fi
            ;;
        l|L)
            echo -e "\n${BLUE}Opening log viewer...${NC}"
            if [[ -d "$INSTALL_DIR/Logs" ]]; then
                find "$INSTALL_DIR/Logs" -name "*.log*" -type f | head -5 | xargs tail -f &
            fi
            ;;
    esac
}

# Main monitoring loop
echo -e "${GREEN}Starting AK Server Monitor...${NC}"
echo -e "${BLUE}Press 'q' to quit, 'r' to restart servers, 's' to stop servers${NC}"
sleep 2

while true; do
    display_header
    display_server_status
    display_system_status
    display_network_status
    display_database_status
    display_log_info
    display_controls
    
    handle_input
    sleep $REFRESH_INTERVAL
done
