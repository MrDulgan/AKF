## Full installation script for Aura Kingdom (Ubuntu, Debian and CentOS)
```sh
cd /root && curl -o fullinstaller.sh https://raw.githubusercontent.com/MrDulgan/AKF/main/fullinstaller.sh && chmod +x fullinstaller.sh
```
- Recognises the operating system and acts accordingly.
- Lists IP addresses for you to choose from.
- Checks your kernel version and updates it accordingly.
- Installs the required packages.
- Checks the PostgreSQL version and performs a dynamic and flexible installation.
- Makes the necessary firewall settings.
- Automatically downloads server files.
- Extracts the downloaded server files and installs them correctly.
- Creates the required databases and makes the necessary customisations.
- Allows you to create an Admin (GM) account at the end of the installation.

You can run the script repeatedly, you don't need to do anything, even if the server is installed on your VPS, the script will detect it and handle the installation.

The whole script including start and stop is coded by Dulgan.
