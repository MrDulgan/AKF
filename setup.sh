#!/bin/bash

echo "Setting up AKF Enhanced Server Manager..."

# Fix line endings for shell scripts
echo "Fixing line endings for shell scripts..."
dos2unix start stop akutools *.sh 2>/dev/null || {
    echo "dos2unix not found, using alternative method..."
    # Alternative method using sed
    for file in start stop akutools *.sh; do
        if [[ -f "$file" ]]; then
            sed -i 's/\r$//' "$file"
            echo "Fixed line endings for $file"
        fi
    done
}

# Set executable permissions
echo "Setting executable permissions..."
chmod +x start stop akutools *.sh

# Fix permissions for server executables if they exist
if [[ -d "hxsy" ]]; then
    echo "Setting permissions for server executables..."
    find hxsy/ -name "*Server" -type f -exec chmod +x {} \;
    find hxsy/ -name "akutools" -type f -exec chmod +x {} \;
fi

echo "Setup completed successfully!"
echo "You can now run ./server_manager.sh to start server management."