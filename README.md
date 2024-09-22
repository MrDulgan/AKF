## How to Use the AK Server Installer Script

To install and set up the AK Server using the installer script, follow these simple steps:

- **Connect to Your Server:** Use SSH to connect to your server, either using an SSH client or your terminal.

- **Run the Installer Command:** Once connected, execute the following command in your server’s terminal:

```sh
cd /root && curl -o fullinstaller.sh https://raw.githubusercontent.com/MrDulgan/AKF/main/fullinstaller.sh && chmod +x fullinstaller.sh && ./fullinstaller.sh
```

## AK Installer Features :

- **Interactive Installer:** The script starts with a welcoming message and interacts with the user by asking for input (e.g., IP selection) during the installation process.

- **Supports Debian and CentOS:** Automatically detects if the system is running Debian or CentOS, and adjusts package management and installation commands accordingly.

- Automatic Locale Configuration: It installs the appropriate packages (locales for Debian, glibc-langpack-en for CentOS) and generates required locales (en_US.UTF-8, POSIX, etc.) based on the detected operating system, ensuring compatibility and proper locale configuration.

- **Kernel Version Compatibility Warning:** Notifies users if the kernel version is 6.x or higher, recommending downgrading to 5.x for better compatibility with the server binaries.

- **PostgreSQL Management:** Checks if PostgreSQL is installed and manages the installation of version 13. It can remove existing versions and install the correct one if needed.

- **Password Security:** Generates a secure random password for the PostgreSQL user and ensures proper security configurations.

- **Firewall Configuration:** Automatically configures firewall rules for necessary ports, supporting both UFW and Firewalld, depending on the system.

- **Directory Handling:** If the installation directory already exists, the script offers options to either delete it or rename it and proceed with the installation.

- **Server File Download and Extraction:** Downloads server files from a specified URL, unpacks them, and sets proper file permissions.

- **Database Setup:** Automatically creates necessary databases, imports SQL backups, and applies updates such as IP address adjustments in the database.

- **File Patching:** Patches specific server binaries and configuration files, including replacing placeholder values with actual server IPs and database credentials.

- **GRUB Configuration for Compatibility:** Configures the GRUB bootloader to enable vsyscall emulation, which is required for certain server binaries to function properly.

- **Admin Account Creation:** The script prompts the user to create an admin account for managing the server, ensuring that the admin account has the highest privileges.

- **Start and Stop Scripts:** Downloads and configures start and stop scripts for easily managing the server once it is set up.

- **Comprehensive Error Handling:** At each step, if an error occurs, the script provides clear error messages, allowing users to diagnose and resolve issues effectively.

- **Final Installation Summary:** Once the installation is complete, the script provides a summary of important details, including the server IP, PostgreSQL version, database credentials, and paths to start the server.



## Start Script Features :

- **Directory Management:** Ensures that the Logs/Startup directory exists. If it doesn’t, the script automatically creates it and logs the creation process.

- **Comprehensive Logging:** Creates a startup_logs file within the Logs/Startup directory to record all actions and outputs during the server startup process.

- **Graceful Shutdown of Servers:** Silently stops any currently running server instances (LoginServer, GatewayServer, etc.) before starting new ones to avoid conflicts.

- **CTRL+C Handling:** Includes a trap function that listens for CTRL+C interrupts. If triggered, it stops all servers gracefully using the stop script before exiting.

- **Server Startup Process:** Starts multiple servers (TicketServer, GatewayServer, LoginServer, MissionServer, WorldServer, ZoneServer) one by one, logging success or failure for each, and checks if the server process is running after startup.

- **Port Handling:** Supports passing a specific port for servers that require it, such as the TicketServer which starts on port 7777.

- **Process Management:** Tracks the process IDs (PIDs) of each running server to monitor their status continuously and handle crashes.

- **Resource Usage Monitoring:** Displays the uptime, CPU, and RAM usage in real-time once all servers are started, giving users insight into the server’s performance.

- **Crash Detection:** Actively monitors if any server crashes during operation, notifying the user via the console and logging the event in the startup log.

- **Real-time Uptime Display:** Continuously updates the terminal with the server's running time (in days, hours, minutes, seconds) and system resource usage (CPU and RAM).



## Stop Script Features:

- **Log Directory Management:** Ensures the Logs directory exists within the installation path. If it doesn’t, the script creates it to store logs safely.

- **System Log Clearance:** Clears a list of key system log files (syslog, wtmp, secure, etc.), ensuring old logs are removed to free up space and maintain a clean logging environment.

- **Old Server Log Cleanup:** Automatically finds and deletes all logs in the Logs directory except for the Startup folder, helping to keep the directory organized by removing unnecessary files.

- **Server Log Archiving:** Moves server logs into the Logs directory, renaming them with the current date to ensure easy tracking of old logs for later analysis.

- **Graceful Server Shutdown:** Stops all servers (ZoneServer, WorldServer, MissionServer, LoginServer, GatewayServer, TicketServer) in reverse order, ensuring that they are properly shut down and preventing any conflicts.

- **Success and Error Notifications:** Provides clear color-coded messages indicating whether each server was successfully stopped or if it was already inactive, ensuring full transparency in the shutdown process.

- **Comprehensive Log Management:** After shutting down servers, the script moves all server logs into the Logs directory, ensuring that no logs are lost and they are stored for future reference.

The whole script including start and stop is coded by **Dulgan**.
