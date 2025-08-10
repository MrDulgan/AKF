# 🎮 Aura Kingdom Server Framework (AKF)

A comprehensive, automated installer and management suite for Aura Kingdom private servers. Designed for seamless deployment on Debian/CentOS systems with professional-grade features.

## 🚀 Quick Start

```bash
cd /root && curl -o fullinstaller.sh https://raw.githubusercontent.com/MrDulgan/AKF/main/fullinstaller.sh && chmod +x fullinstaller.sh && ./fullinstaller.sh
```

## 📋 System Requirements

- **OS**: Debian 11 (recommended), Ubuntu, or CentOS
- **RAM**: Minimum 4GB
- **Storage**: At least 1GB free space
- **Kernel**: 5.x recommended (6.x+ may have compatibility issues)

## ⚡ Key Features

### 🔧 **Full Automation**
- Interactive IP selection and configuration
- PostgreSQL 13 auto-installation and setup
- Secure password generation
- Firewall configuration (UFW/Firewalld)

### 🛡️ **Security & Reliability**
- Enhanced admin account validation (secure passwords, reserved names check)
- Advanced PostgreSQL security configuration
- Automated backup and error recovery
- Comprehensive logging system
- GRUB configuration for binary compatibility
- Input validation and sanity checks
- Download verification and retry mechanisms

### 📊 **Server Management**
- Real-time resource monitoring (CPU/RAM)
- Process crash detection and alerting
- Graceful server shutdown/startup
- Systemd service integration (optional)

### 🎯 **Game Features**
- Admin account creation with full privileges
- Database management and IP updates
- Binary patching for optimal performance
- **Multi-server architecture support with shared database**
- **Real multi-server instances (same PostgreSQL, different ports)**
- **Multi-channel support (multiple channels per server)**

## 🎮 Server Management

### Essential Commands
```bash
# Start base server
/root/hxsy/start

# Stop base server  
/root/hxsy/stop

# Monitor server (real-time dashboard)
/root/hxsy/monitor.sh

# Create backup
/root/hxsy/backup.sh

# Restore from backup
/root/hxsy/restore.sh

# Create game accounts
./account_creator.sh

# Multi-server management
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

### Systemd Commands (if installed)
```bash
systemctl start|stop|restart aurakingdom
systemctl status aurakingdom
```

## 📁 Directory Structure

```
/root/hxsy/                    # Base server instance
├── start                      # Server startup script
├── stop                       # Server shutdown script  
├── monitor.sh                 # Real-time monitoring dashboard
├── backup.sh                  # Automated backup tool
├── restore.sh                 # Restore from backup tool
├── setup.ini                  # Database configuration
├── config.ini                 # Game features configuration
├── config00.ini - config09.ini  # Additional configurations
├── Logs/                      # Log files and backups
├── TicketServer/              # Game server components
├── GatewayServer/             
├── LoginServer/               
├── MissionServer/             
├── WorldServer/               
└── ZoneServer/                

/root/hxsy-pvp/                # Additional PVP server instance
├── [same structure as base]   # Same files with different ports
├── Different ports:           # LoginServer: 6643, TicketServer: 7877
└── Same database access       # Uses same PostgreSQL instance

/root/hxsy-pve/                # Additional PVE server instance  
├── [same structure as base]   # Same files with different ports
├── Different ports:           # LoginServer: 6743, TicketServer: 7977
└── Same database access       # Uses same PostgreSQL instance
```

## ⚙️ Configuration

- **Database**: PostgreSQL 13 with auto-generated secure passwords
- **Base Server Ports**: LoginServer:6543, TicketServer:7777, GatewayServer:7878
- **Multi-Server Ports**: Each additional server uses +100 port offset
- **Multi-Channel Ports**: Each channel uses +1 port offset (5567, 5568, 5569...)
- **Default Install Path**: `/root/hxsy` (base), `/root/hxsy-{name}` (additional)
- **Shared Database**: All servers use same PostgreSQL instance (FFAccount, FFDB1, FFMember)
- **World IDs**: Each server gets unique WorldServerID and ZoneServerID
- **Channel System**: Base=Aurora-Ch01, Additional=Aurora-Ch02, Aurora-Ch03...

## 🔨 Development

Created with ❤️ by **Dulgan**

---

*For detailed feature documentation and troubleshooting, check the installation logs at `/tmp/ak_installer.log`*
