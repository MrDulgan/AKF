# 🎮 Aura Kingdom Server Framework (AKF)

A comprehensive, automated installer and management suite for Aura Kingdom private servers. Designed for seamless deployment on multiple Linux distributions with professional-grade features and advanced management tools.

## 🚀 Quick Start

```bash
cd /root && curl -o fullinstaller.sh https://raw.githubusercontent.com/MrDulgan/AKF/main/fullinstaller.sh && chmod +x fullinstaller.sh && ./fullinstaller.sh
```

## 📋 System Requirements

- **OS**: Debian 11 (recommended), Ubuntu, CentOS/RHEL, or compatible Linux
- **RAM**: Minimum 4GB (8GB+ recommended for multi-server)
- **Storage**: At least 2GB free space
- **Kernel**: 5.x recommended (6.x+ supported with compatibility optimizations)
- **Architecture**: x86_64 (ARM64 experimental support)

## ⚡ Key Features

### 🔧 **Enhanced Automation**
- Interactive IP selection and configuration
- PostgreSQL 13 auto-installation and setup
- Secure password generation with complexity validation
- **SSH server configuration** (optional PuTTY/remote access)
- Firewall configuration (UFW/Firewalld)
- **Multi-distribution support** with compatibility libraries

### 🛡️ **Advanced Security & Reliability**
- Enhanced admin account validation (secure passwords, reserved names check)
- Advanced PostgreSQL security configuration
- **Kernel parameter optimization** for game servers
- **System limits configuration** (file descriptors, processes)
- **Legacy compatibility libraries** for binary execution
- **CPU architecture detection** and optimization
- Automated backup and error recovery
- Comprehensive logging system
- **Intelligent GRUB configuration** for vsyscall support
- Input validation and sanity checks
- Download verification and retry mechanisms

### 📊 **Professional Server Management**
- **AKUTools Management Suite** - Centralized control panel
- **Enhanced monitoring** with multi-server/instance support
- **Non-blocking server startup** - terminal stays free after launch
- Real-time resource monitoring (CPU/RAM/Network)
- Process crash detection and alerting
- Graceful server shutdown/startup
- Systemd service integration (optional)
- **Multi-instance management** - Switch between server setups

### 🎯 **Advanced Game Features**
- Admin account creation with full privileges
- Database management and IP updates
- Binary patching for optimal performance
- **Multi-server architecture support with shared database**
- **Real multi-server instances (same PostgreSQL, different ports)**
- **Multi-channel support (multiple channels per server)**
- **Cross-distribution compatibility** optimizations

## 🎮 Server Management

### 🚀 **Quick Launch Commands**
```bash
# Start server (optimized - non-blocking)
/root/hxsy/start

# Stop server
/root/hxsy/stop

# Enhanced monitoring with multi-server support
/root/hxsy/monitor.sh

# Access centralized management suite
/root/hxsy/akutools
```

### 🛠️ **AKUTools Management Suite** (`/root/AKUTools/`)

The centralized management interface providing professional-grade server administration:

```bash
# Launch AKUTools interface
/root/hxsy/akutools

# Direct tool access
/root/AKUTools/monitor.sh           # Enhanced multi-server monitoring
/root/AKUTools/backup.sh            # Advanced backup system
/root/AKUTools/restore.sh           # Intelligent restore system
/root/AKUTools/account_creator.sh   # Game account management
/root/AKUTools/multi_server_manager.sh   # Multi-server orchestration
/root/AKUTools/multi_channel_manager.sh  # Multi-channel management
```

### 📊 **Enhanced Monitoring Features**
- **Multi-instance support** - Manage multiple server installations
- **Real-time switching** between server instances (`[i]` key)
- **Quick instance access** (number keys 1-9)
- **Integrated AKUTools** access (`[a]` key)
- **Multi-server manager** access (`[m]` key)
- **Advanced process monitoring** with crash detection
- **Resource usage tracking** (CPU, RAM, Network)
- **Log file integration** and error detection

### 🎯 **Multi-Server Management**
```bash
# Create additional server instances
./multi_server_manager.sh create pvp_server    # Create PVP server
./multi_server_manager.sh create pve_server    # Create PVE server  
./multi_server_manager.sh list                 # List all servers
./multi_server_manager.sh start pvp_server     # Start specific server
./multi_server_manager.sh stop pve_server      # Stop specific server
./multi_server_manager.sh monitor              # Monitor all servers

# Multi-channel management (same server, multiple channels)
./multi_channel_manager.sh create 1            # Create Ch02 (channel 2)
./multi_channel_manager.sh create 2            # Create Ch03 (channel 3)
./multi_channel_manager.sh list                # List all channels
./multi_channel_manager.sh remove Ch02         # Remove channel 2
./multi_channel_manager.sh info                # Show database info
```

### 🔧 **System Administration**
### 🔧 **System Administration**
```bash
# SSH Configuration (if enabled during installation)
ssh root@YOUR_SERVER_IP              # Remote access via SSH
# PuTTY Settings: Host: YOUR_IP, Port: 22, Connection Type: SSH

# Legacy backup/restore (also available as shortcuts)
/root/hxsy/backup.sh                 # Quick backup
/root/hxsy/restore.sh                # Quick restore
/root/hxsy/account_creator.sh        # Quick account creation

# System optimization verification
cat /etc/sysctl.d/99-gameserver-optimization.conf    # Kernel parameters
cat /etc/security/limits.conf                        # System limits
```

### ⚙️ **Systemd Integration** (optional)
```bash
systemctl start|stop|restart aurakingdom
systemctl status aurakingdom
systemctl enable aurakingdom          # Auto-start on boot
```

## 🏗️ **Installation Features**

### 🔍 **Compatibility Optimizations**
- **Multi-distribution support**: Debian, Ubuntu, CentOS, RHEL
- **Kernel compatibility**: Automatic detection and optimization
- **Legacy library installation**: 32-bit compatibility for older binaries
- **Architecture detection**: x86_64 optimized, ARM64 experimental
- **Binary dependency verification**: Dynamic loader and library checks

### 🛡️ **Security Enhancements**
- **SSH server configuration**: Optional remote access setup
- **Firewall integration**: UFW/Firewalld automatic configuration
- **PostgreSQL hardening**: Secure default configuration
- **Input validation**: Protection against malicious input
- **Password complexity**: Enforced strong password policies

### ⚡ **Performance Optimizations**
- **Kernel parameter tuning**: Network and memory optimizations
- **System limits configuration**: Process and file descriptor limits
- **GRUB configuration**: vsyscall=emulate for binary compatibility
- **Resource monitoring**: Built-in performance tracking

## 📁 Directory Structure

```
/root/hxsy/                    # Primary server instance
├── start                      # Optimized startup script (non-blocking)
├── stop                       # Server shutdown script
├── monitor.sh                 # Enhanced monitoring (multi-server support)
├── akutools                   # AKUTools launcher script
├── backup.sh → /root/AKUTools/backup.sh     # Symlink to AKUTools
├── restore.sh → /root/AKUTools/restore.sh   # Symlink to AKUTools  
├── account_creator.sh → /root/AKUTools/account_creator.sh # Symlink
├── setup.ini                  # Database configuration
├── config.ini                 # Game features configuration
├── config00.ini - config09.ini  # Additional configurations
├── .server_pids               # Runtime PID information
├── Logs/                      # Log files and backups
├── TicketServer/              # Game server components
├── GatewayServer/             
├── LoginServer/               
├── MissionServer/             
├── WorldServer/               
└── ZoneServer/                

/root/AKUTools/                # Centralized Management Suite
├── monitor.sh                 # Enhanced multi-server monitoring
├── backup.sh                  # Advanced backup system
├── restore.sh                 # Intelligent restore system
├── account_creator.sh         # Game account management
├── multi_server_manager.sh    # Multi-server orchestration
├── multi_channel_manager.sh   # Multi-channel management
└── server_*.conf              # Server instance configurations

/root/hxsy-pvp/                # Additional PVP server instance
├── [same structure as base]   # Same files with different ports
├── Different ports:           # LoginServer: 6643, TicketServer: 7877
└── Same database access       # Uses same PostgreSQL instance

/root/hxsy-pve/                # Additional PVE server instance  
├── [same structure as base]   # Same files with different ports
├── Different ports:           # LoginServer: 6743, TicketServer: 7977
└── Same database access       # Uses same PostgreSQL instance

/etc/sysctl.d/
└── 99-gameserver-optimization.conf  # Kernel optimizations

/etc/security/
└── limits.conf                # Updated with game server limits
```

## ⚙️ Enhanced Configuration

### 🗄️ **Database Configuration**
- **Database**: PostgreSQL 13 with auto-generated secure passwords
- **Security**: Enhanced authentication and connection limits
- **Shared Access**: All server instances use same PostgreSQL database
- **Tables**: FFAccount, FFDB1, FFMember with optimized schema

### 🌐 **Network Configuration**
- **Base Server Ports**: LoginServer:6543, TicketServer:7777, GatewayServer:7878
- **Multi-Server Ports**: Each additional server uses +100 port offset
- **Multi-Channel Ports**: Each channel uses +1 port offset (5567, 5568, 5569...)
- **SSH Access**: Optional SSH server on port 22 for remote management
- **Firewall**: Automatic UFW/Firewalld configuration

### 📂 **Installation Paths**
- **Default Install Path**: `/root/hxsy` (primary server)
- **Additional Servers**: `/root/hxsy-{name}` pattern
- **Management Tools**: `/root/AKUTools/` (centralized)
- **Logs**: Individual server log directories with rotation

### 🎮 **Game Server Configuration**
- **World IDs**: Each server gets unique WorldServerID and ZoneServerID  
- **Channel System**: Base=Aurora-Ch01, Additional=Aurora-Ch02, Aurora-Ch03...
- **Binary Compatibility**: vsyscall=emulate kernel parameter
- **Performance**: Optimized kernel parameters and system limits

### � **System Optimization**
- **Kernel Parameters**: Network, memory, and process optimizations
- **File Descriptors**: Increased limits for server processes
- **Memory Management**: Swappiness and cache pressure tuning
- **Legacy Support**: 32-bit compatibility libraries for older binaries

## 🎯 **Post-Installation Management**

### 📊 **Monitoring & Maintenance**
- **Real-time monitoring**: Enhanced dashboard with multi-server support
- **Automated backups**: Scheduled and on-demand backup system
- **Log management**: Automatic rotation and error detection
- **Health checks**: Process monitoring and crash detection
- **Performance tracking**: Resource usage and optimization suggestions

### 🔐 **Security Features**
- **SSH hardening**: Secure remote access configuration
- **Database security**: PostgreSQL access control and authentication
- **Firewall management**: Automatic rule configuration
- **Password policies**: Enforced complexity requirements
- **Access logging**: Comprehensive audit trail

### 🚀 **Scalability Options**
- **Multi-server deployment**: Multiple server instances with shared database
- **Channel expansion**: Additional channels per server
- **Load balancing**: Distribute players across instances
- **Resource monitoring**: Scale based on usage patterns

## 🔨 Development & Support

### 👨‍💻 **Developer Information**
Created with ❤️ by **Dulgan**

### 📝 **Version History**
- **v3.0+**: AKUTools Suite, Enhanced monitoring, Multi-distribution support
- **v2.x**: Multi-server/channel support, Advanced security
- **v1.x**: Basic automation, PostgreSQL integration

### 🐛 **Troubleshooting**
- **Installation logs**: `/tmp/ak_installer.log`
- **Server logs**: Individual server log directories
- **System logs**: `/var/log/` for system-level issues
- **GRUB issues**: Manual configuration guide in installation output

### 🤝 **Contributing**
- Report issues via GitHub Issues
- Submit pull requests for improvements
- Share configuration optimizations
- Help test on different distributions

---

---

*For detailed installation process, troubleshooting guides, and advanced configuration options, check the comprehensive logs and documentation generated during installation.*
