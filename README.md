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
- Multi-server architecture support

## 🎮 Server Management

### Essential Commands
```bash
# Start server
/root/hxsy/start

# Stop server  
/root/hxsy/stop

# Monitor server (real-time dashboard)
/root/hxsy/monitor.sh

# Create backup
/root/hxsy/backup.sh

# Restore from backup
/root/hxsy/restore.sh

# Create game accounts
./account_creator.sh
```

### Systemd Commands (if installed)
```bash
systemctl start|stop|restart aurakingdom
systemctl status aurakingdom
```

## 📁 Directory Structure

```
/root/hxsy/
├── start              # Server startup script
├── stop               # Server shutdown script  
├── monitor.sh         # Real-time monitoring dashboard
├── backup.sh          # Automated backup tool
├── restore.sh         # Restore from backup tool
├── setup.ini          # Database configuration
├── Logs/              # Log files and backups
├── TicketServer/      # Game server components
├── GatewayServer/     
├── LoginServer/       
├── MissionServer/     
├── WorldServer/       
└── ZoneServer/        
```

## ⚙️ Configuration

- **Database**: PostgreSQL 13 with auto-generated secure passwords
- **Ports**: 5567, 5568, 6543, 7654, 7777, 7878, 10021, 10022
- **Default Install Path**: `/root/hxsy`

## 🔨 Development

Created with ❤️ by **Dulgan**

---

*For detailed feature documentation and troubleshooting, check the installation logs at `/tmp/ak_installer.log`*
