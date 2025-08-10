#!/bin/bash

# Enhanced Security Functions for AK Installer
# Developer: Dulgan

# Enhanced input validation
validate_username() {
    local username="$1"
    
    # Check length (3-16 characters)
    if [[ ${#username} -lt 3 ]] || [[ ${#username} -gt 16 ]]; then
        return 1
    fi
    
    # Check character set (only lowercase letters and numbers)
    if [[ ! "$username" =~ ^[a-z0-9]+$ ]]; then
        return 1
    fi
    
    # Check for reserved usernames
    local reserved=("admin" "root" "postgres" "system" "guest" "user" "test")
    for reserved_name in "${reserved[@]}"; do
        if [[ "$username" == "$reserved_name" ]]; then
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
    
    if [[ $complexity_score -lt 3 ]]; then
        echo "Password must contain at least 3 of: lowercase, uppercase, digit, special character"
        return 1
    fi
    
    return 0
}

# Secure file permissions
set_secure_permissions() {
    local file="$1"
    local permissions="$2"
    local owner="$3"
    
    if [[ -f "$file" ]]; then
        chmod "$permissions" "$file" || error_exit "Failed to set permissions on $file"
        if [[ -n "$owner" ]]; then
            chown "$owner" "$file" || error_exit "Failed to set owner on $file"
        fi
        log_message "Set secure permissions $permissions on $file"
    fi
}

# Enhanced PostgreSQL security
secure_postgresql_advanced() {
    echo -e "${BLUE}>> Applying advanced PostgreSQL security...${NC}"
    
    # Set secure postgresql.conf parameters
    local pg_conf
    if [ "$OS" = 'Debian' ] || [ "$OS" = 'Ubuntu' ]; then
        pg_conf="/etc/postgresql/$DB_VERSION/main/postgresql.conf"
    elif [ "$OS" = 'CentOS' ]; then
        pg_conf="/var/lib/pgsql/$DB_VERSION/data/postgresql.conf"
    fi
    
    # Backup original config
    sudo cp "$pg_conf" "$pg_conf.backup" || error_exit "Failed to backup PostgreSQL config"
    
    # Apply security settings
    sudo tee -a "$pg_conf" > /dev/null <<EOF

# AK Installer Security Settings
log_connections = on
log_disconnections = on
log_checkpoints = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
log_statement = 'mod'
log_min_duration_statement = 1000
shared_preload_libraries = 'pg_stat_statements'
max_connections = 50
password_encryption = 'md5'
EOF
    
    echo -e "${GREEN}>> Advanced PostgreSQL security applied${NC}"
    log_message "Advanced PostgreSQL security configured"
}

# Network security checks
check_network_security() {
    echo -e "${BLUE}>> Checking network security...${NC}"
    
    # Check for open ports that shouldn't be open
    local dangerous_ports=("22" "3389" "23" "21" "25" "53" "80" "443")
    for port in "${dangerous_ports[@]}"; do
        if ss -tuln | grep ":$port " > /dev/null 2>&1; then
            echo -e "${YELLOW}[WARNING] Port $port is open - ensure this is intentional${NC}"
            log_message "Warning: Port $port is open"
        fi
    done
    
    # Check SSH configuration if present
    if [[ -f "/etc/ssh/sshd_config" ]]; then
        if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config; then
            echo -e "${YELLOW}[WARNING] SSH root login is enabled - consider disabling${NC}"
            log_message "Warning: SSH root login enabled"
        fi
        
        if ! grep -q "Protocol 2" /etc/ssh/sshd_config; then
            echo -e "${YELLOW}[WARNING] SSH protocol version not explicitly set to 2${NC}"
            log_message "Warning: SSH protocol not set to 2"
        fi
    fi
    
    echo -e "${GREEN}>> Network security check completed${NC}"
    log_message "Network security check completed"
}

# File integrity verification
verify_file_integrity() {
    local file="$1"
    local expected_hash="$2"
    
    if [[ -f "$file" ]]; then
        local actual_hash=$(sha256sum "$file" | cut -d' ' -f1)
        if [[ "$actual_hash" == "$expected_hash" ]]; then
            echo -e "${GREEN}>> File integrity verified: $(basename "$file")${NC}"
            return 0
        else
            echo -e "${RED}[WARNING] File integrity mismatch: $(basename "$file")${NC}"
            log_message "Warning: File integrity mismatch for $file"
            return 1
        fi
    else
        echo -e "${RED}[ERROR] File not found for verification: $file${NC}"
        return 1
    fi
}

# Secure cleanup
secure_cleanup() {
    echo -e "${BLUE}>> Performing secure cleanup...${NC}"
    
    # Secure delete temporary files
    local temp_files=("/tmp/ak_installer.log" "/root/hxsy.zip")
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            # Overwrite with random data before deletion
            dd if=/dev/urandom of="$file" bs=1M count=1 2>/dev/null || true
            rm -f "$file"
            log_message "Securely deleted $file"
        fi
    done
    
    # Clear bash history of sensitive commands
    history -c
    
    echo -e "${GREEN}>> Secure cleanup completed${NC}"
    log_message "Secure cleanup completed"
}

# Enhanced admin account creation with security
create_admin_account_secure() {
    echo -e "\n${BLUE}>> Creating Secure Admin Account...${NC}"
    
    local username=""
    local password=""
    local password_confirm=""
    
    # Username validation loop
    while true; do
        read -p "Admin Username: " username
        if validate_username "$username"; then
            # Check if username already exists
            cd /tmp
            if sudo -H -u "$DB_USER" psql -tAc "SELECT 1 FROM tb_user WHERE mid = '$username';" FFMember 2>/dev/null | grep -q "1"; then
                echo -e "${RED}[ERROR] Username already exists. Please choose another.${NC}"
                continue
            fi
            break
        else
            echo -e "${RED}[ERROR] Invalid username. Must be 3-16 characters, lowercase letters and numbers only.${NC}"
        fi
    done
    
    # Password validation loop
    while true; do
        read -s -p "Admin Password: " password
        echo ""
        
        local validation_result
        validation_result=$(validate_password "$password")
        
        if [[ $? -eq 0 ]]; then
            read -s -p "Confirm Password: " password_confirm
            echo ""
            
            if [[ "$password" == "$password_confirm" ]]; then
                break
            else
                echo -e "${RED}[ERROR] Passwords do not match.${NC}"
            fi
        else
            echo -e "${RED}[ERROR] $validation_result${NC}"
        fi
    done
    
    # Create account with enhanced security
    echo -e "${BLUE}>> Creating admin account with enhanced security...${NC}"
    local admin_pwd_hash=$(echo -n "$password" | sha256sum | cut -d' ' -f1)
    local admin_pwd_md5=$(echo -n "$password" | md5sum | cut -d' ' -f1)
    
    cd /tmp
    sudo -H -u "$DB_USER" psql -q -d "FFMember" -c "INSERT INTO tb_user (mid, password, pwd, pvalues) VALUES ('$username', '$password', '$admin_pwd_md5', 999999);" >/dev/null || error_exit "Failed to create admin account in FFMember."
    
    local user_id
    user_id=$(sudo -H -u "$DB_USER" psql -At -d "FFMember" -c "SELECT idnum FROM tb_user WHERE mid = '$username';")
    
    sudo -H -u "$DB_USER" psql -q -d "FFAccount" -c "INSERT INTO accounts (id, username, password) VALUES ('$user_id', '$username', '$password');" >/dev/null || error_exit "Failed to create admin account in FFAccount."
    
    sudo -H -u "$DB_USER" psql -q -d "FFAccount" -c "INSERT INTO gm_tool_accounts (id, account_name, password, privilege) VALUES ('$user_id', '$username', '$password', 5);" >/dev/null || error_exit "Failed to create entry in gm_tool_accounts."
    
    # Log account creation (without sensitive data)
    log_message "Secure admin account '$username' created with ID $user_id"
    
    STATUS[admin_creation_success]=true
    echo -e "${GREEN}>> Secure admin account '$username' created successfully.${NC}"
    
    # Clear password variables
    unset password password_confirm admin_pwd_hash admin_pwd_md5
}

# System hardening
apply_system_hardening() {
    echo -e "${BLUE}>> Applying system hardening...${NC}"
    
    # Disable unnecessary services
    local services_to_disable=("telnet" "rsh" "rlogin" "vsftpd" "apache2" "httpd")
    for service in "${services_to_disable[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${BLUE}   - Disabling $service...${NC}"
            sudo systemctl stop "$service" 2>/dev/null
            sudo systemctl disable "$service" 2>/dev/null
            log_message "Disabled service: $service"
        fi
    done
    
    # Set secure kernel parameters
    if [[ -f "/etc/sysctl.conf" ]]; then
        echo -e "${BLUE}   - Configuring kernel security parameters...${NC}"
        sudo tee -a /etc/sysctl.conf > /dev/null <<EOF

# AK Installer Security Settings
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
kernel.exec-shield = 1
kernel.randomize_va_space = 2
EOF
        sudo sysctl -p > /dev/null 2>&1
        log_message "Applied kernel security parameters"
    fi
    
    echo -e "${GREEN}>> System hardening completed${NC}"
    log_message "System hardening applied"
}
