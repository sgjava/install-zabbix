#!/bin/bash
#
# Created July 2026
#
# @author: sgoldsmith
#
# Configures Zabbix Java Gateway post-compile: handles JVM symlinks,
# file permissions, systemd unit creation, and zabbix_server.conf wiring.
#

set -e

ZABBIX_CONF="/usr/local/etc/zabbix_server.conf"
ZABBIX_JAVA_DIR="/usr/local/sbin/zabbix_java"

echo "--------------------------------------------------"
echo "STEP 1: Verify Pre-Installed Java & Gateway Files"
echo "--------------------------------------------------"
if [ -f /etc/environment ]; then
    . /etc/environment
fi

if ! command -v java >/dev/null 2>&1; then
    echo "Error: Java binary not found in PATH. Please run install-java first."
    exit 1
fi

if [ ! -d "$ZABBIX_JAVA_DIR" ]; then
    echo "Error: $ZABBIX_JAVA_DIR does not exist. Ensure install.sh compiled Zabbix with --enable-java."
    exit 1
fi

JAVA_BIN=$(which java)
JAVA_HOME_RESOLVED=$(readlink -f "$JAVA_BIN" | sed 's|/bin/java||')

echo "Detected Architecture : $(uname -m)"
echo "Found Java Binary     : $JAVA_BIN"
echo "Resolved JAVA_HOME    : $JAVA_HOME_RESOLVED"

echo "--------------------------------------------------"
echo "STEP 2: Fix JVM Server Directory Structure"
echo "--------------------------------------------------"
# Locates libjvm.so dynamically and creates the 'server' symlink if missing (crucial for custom ARM builds)
LIBJVM_PATH=$(find "$JAVA_HOME_RESOLVED" -name "libjvm.so" | head -n 1)

if [ -n "$LIBJVM_PATH" ]; then
    LIB_DIR=$(dirname "$LIBJVM_PATH")
    JDK_LIB_BASE="$JAVA_HOME_RESOLVED/lib"
    
    if [ ! -d "$JDK_LIB_BASE/server" ]; then
        echo "Creating missing 'server' directory link pointing to $LIB_DIR..."
        sudo ln -sf "$LIB_DIR" "$JDK_LIB_BASE/server"
    fi
fi

# Ensure global binary symlink exists for system services
if [ ! -f /usr/bin/java ]; then
    sudo ln -sf "$JAVA_BIN" /usr/bin/java
fi

# Ensure zabbix user can traverse directory if Java lives under a user home directory
if [[ "$JAVA_HOME_RESOLVED" == /home/* ]]; then
    USER_DIR=$(echo "$JAVA_HOME_RESOLVED" | cut -d'/' -f1-3)
    sudo chmod +x "$USER_DIR" || true
    sudo chmod -R +rX "$JAVA_HOME_RESOLVED" || true
fi

echo "--------------------------------------------------"
echo "STEP 3: Configure Gateway Permissions & Executables"
echo "--------------------------------------------------"
# Ensure zabbix system user exists
if ! id -u zabbix >/dev/null 2>&1; then
    sudo useradd -r -s /bin/false zabbix
fi

# Set proper script ownership and permissions
sudo chown -R zabbix:zabbix "$ZABBIX_JAVA_DIR"
sudo chmod +x "$ZABBIX_JAVA_DIR"/*.sh

# Explicitly set JAVA path in settings.sh to global symlink
sudo sed -i 's|^#\? \?JAVA=.*|JAVA="/usr/bin/java"|' "$ZABBIX_JAVA_DIR/settings.sh"

echo "--------------------------------------------------"
echo "STEP 4: Deploy Systemd Unit"
echo "--------------------------------------------------"
cat <<EOT | sudo tee /etc/systemd/system/zabbix-java-gateway.service > /dev/null
[Unit]
Description=Zabbix Java Gateway
After=syslog.target network.target

[Service]
Type=forking
User=zabbix
Group=zabbix
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$JAVA_HOME_RESOLVED/bin"
Environment="JAVA_HOME=$JAVA_HOME_RESOLVED"
ExecStart=$ZABBIX_JAVA_DIR/startup.sh
ExecStop=$ZABBIX_JAVA_DIR/shutdown.sh
PIDFile=/tmp/zabbix_java.pid
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOT

sudo systemctl daemon-reload
sudo systemctl enable zabbix-java-gateway
sudo systemctl restart zabbix-java-gateway

echo "--------------------------------------------------"
echo "STEP 5: Configure Zabbix Server Interconnect"
echo "--------------------------------------------------"
if [ -f "$ZABBIX_CONF" ]; then
    echo "Updating $ZABBIX_CONF..."
    
    sudo sed -i 's/^[#[:space:]]*JavaGateway=.*/JavaGateway=127.0.0.1/' "$ZABBIX_CONF"
    sudo sed -i 's/^[#[:space:]]*JavaGatewayPort=.*/JavaGatewayPort=10052/' "$ZABBIX_CONF"
    sudo sed -i 's/^[#[:space:]]*StartJavaPollers=.*/StartJavaPollers=5/' "$ZABBIX_CONF"

    grep -q "^JavaGateway=" "$ZABBIX_CONF" || echo "JavaGateway=127.0.0.1" | sudo tee -a "$ZABBIX_CONF"
    grep -q "^JavaGatewayPort=" "$ZABBIX_CONF" || echo "JavaGatewayPort=10052" | sudo tee -a "$ZABBIX_CONF"
    grep -q "^StartJavaPollers=" "$ZABBIX_CONF" || echo "StartJavaPollers=5" | sudo tee -a "$ZABBIX_CONF"

    sudo systemctl restart zabbix-server || true
else
    echo "Warning: $ZABBIX_CONF not found. Update server directives manually if running server here."
fi

echo "--------------------------------------------------"
echo "STEP 6: Verification"
echo "--------------------------------------------------"
sleep 2
echo -n "Service Status: "
if systemctl is-active --quiet zabbix-java-gateway; then
    echo "ACTIVE (running)"
else
    echo "FAILED"
    sudo journalctl -u zabbix-java-gateway.service -n 20 --no-pager
    exit 1
fi

echo "Listening Ports:"
sudo ss -tulpn | grep 10052 || echo "Warning: Port 10052 is not active yet."

echo "--------------------------------------------------"
echo "Zabbix Java Gateway Setup Complete!"
echo "--------------------------------------------------"
