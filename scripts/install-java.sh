#!/bin/bash
#
# Created on May 24, 2026
# Modified July 2026
#
# @author: sgoldsmith
#
# Install dependencies and JDK 25 exclusively.
# Local SDKMAN setup with global environment execution flags.
#

set -e

ARCH=$(uname -m)
SDKMAN_DIR="$HOME/.sdkman"
JAVA_TMP="$HOME/.java_tmp"

echo "--------------------------------------------------"
echo "STEP 1: System Prep & Tmp Dir"
echo "--------------------------------------------------"
sudo apt update && sudo apt install -y curl zip unzip wget xz-utils git build-essential
mkdir -p "$JAVA_TMP"
chmod 777 "$JAVA_TMP"

echo "--------------------------------------------------"
echo "STEP 2: SDKMAN Setup"
echo "--------------------------------------------------"
export SDKMAN_DIR="$HOME/.sdkman"
if [[ ! -d "$SDKMAN_DIR" ]]; then
    curl -s "https://get.sdkman.io" | bash || true
fi
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

echo "--------------------------------------------------"
echo "STEP 3: JDK Installation"
echo "--------------------------------------------------"
case $ARCH in
    armv7l|armv8l)
        JDK_DIR="$SDKMAN_DIR/candidates/java/25-arm32-local"
        if [ ! -d "$JDK_DIR" ]; then
            wget -q -O /tmp/jdk25.tar.xz "https://builds.shipilev.net/openjdk-jdk25/openjdk-jdk25-linux-arm32-hflt-server.tar.xz"
            mkdir -p "$JDK_DIR"
            tar -xJf /tmp/jdk25.tar.xz -C "$JDK_DIR" --strip-components=1
            sdk install java 25-arm32-local "$JDK_DIR"
        fi
        sdk default java 25-arm32-local
        ;;
    *)
        sdk install java 25-zulu || true
        sdk default java 25-zulu
        ;;
esac

echo "--------------------------------------------------"
echo "STEP 4: Global Environment Persistence"
echo "--------------------------------------------------"
update_env_var() {
    local var_name=$1
    local var_value=$2
    if grep -q "^${var_name}=" /etc/environment; then
        sudo sed -i "s|^${var_name}=.*|${var_name}=\"${var_value}\"|" /etc/environment
    else
        echo "${var_name}=\"${var_value}\"" | sudo tee -a /etc/environment
    fi
}

# Target runtime home
JAVA_P="$SDKMAN_DIR/candidates/java/current"

update_env_var "JAVA_HOME" "$JAVA_P"
update_env_var "JAVA_OPTS" "-Djava.io.tmpdir=$JAVA_TMP"

# Simple path structure keeping standard system binaries and our SDKMAN compiler
NEW_PATH="$JAVA_P/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
update_env_var "PATH" "$NEW_PATH"

echo "--------------------------------------------------"
echo "STEP 5: Comprehensive Verification"
echo "--------------------------------------------------"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

printf "Java:      " && java -version 2>&1 | head -n 1

echo "--------------------------------------------------"
echo "Setup Complete! Please run: source /etc/environment"
echo "--------------------------------------------------"