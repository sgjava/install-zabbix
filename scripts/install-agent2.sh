#!/bin/sh
#
# Created on June 7, 2020
#
# @author: sgoldsmith
#
# Install Zabbix Agent 2 on Ubuntu 20.04. This may work on other versions and
# Debian like distributions. Change variables below to suit your needs.
#
# Steven P. Goldsmith
# sgjava@gmail.com
#

# Zabbix Server URL
zabbixurl="https://cdn.zabbix.com/zabbix/sources/stable/5.0/zabbix-5.0.1.tar.gz"

# Just Zabbix server archive name
zabbixarchive=$(basename "$zabbixurl")

# Where to put Zabbix source
srcdir="/usr/local/src"

# Zabbix agent configuration
zabbixconf="/usr/local/etc/zabbix_agent2.conf"

# Zabbix host
zabbixhost="192.168.1.69"

# Temp dir for downloads, etc.
tmpdir="$HOME/temp"

# stdout and stderr for commands logged
logfile="$PWD/install.log"
rm -f $logfile

# Simple logger
log(){
	timestamp=$(date +"%m-%d-%Y %k:%M:%S")
	echo "$timestamp $1"
	echo "$timestamp $1" >> $logfile 2>&1
}

log "Removing temp dir $tmpdir"
rm -rf "$tmpdir" >> $logfile 2>&1
mkdir -p "$tmpdir" >> $logfile 2>&1

# Download Zabbix source
log "Downloading $zabbixarchive to $tmpdir"
wget -q --directory-prefix=$tmpdir "$zabbixurl" >> $logfile 2>&1
log "Extracting $zabbixarchive to $tmpdir"
tar -xf "$tmpdir/$zabbixarchive" -C "$tmpdir" >> $logfile 2>&1
# Remove .gz
filename="${zabbixarchive%.*}"
# Remove .tar
filename="${filename%.*}"
sudo -E mv "$tmpdir/$filename" "${srcdir}" >> $logfile 2>&1

# Install Zabbix Agent 2
log "Installing Zabbix Agent 2..."
sudo -E groupadd zabbix >> $logfile 2>&1
sudo -E useradd -g zabbix -s /bin/bash zabbix >> $logfile 2>&1
sudo -E apt-get -y install build-essential pkg-config libpcre3-dev libz-dev golang >> $logfile 2>&1
cd "${srcdir}/${filename}" >> $logfile 2>&1
# Cnange configuration options here
sudo -E ./configure --enable-agent2 --prefix=/usr/local >> $logfile 2>&1
sudo -E make install >> $logfile 2>&1
# Configure Zabbix agent 2
sudo -E sed -i "s/Server=127.0.0.1/Server=$zabbixhost/g" "$zabbixconf" >> $logfile 2>&1
sudo -E sed -i "s/ServerActive=127.0.0.1/ServerActive=$zabbixhost/g" "$zabbixconf" >> $logfile 2>&1

# Install Zabbix agent 2 service
log "Installing Zabbix Agent 2 Service..."
sudo tee -a /etc/systemd/system/zabbix-agent2.service > /dev/null <<EOT
[Unit]
Description=Zabbix Agent 2
After=syslog.target network.target
 
[Service]
Type=simple
User=zabbix
ExecStart=/usr/local/sbin/zabbix_agent2 -c /usr/local/etc/zabbix_agent2.conf
RemainAfterExit=yes
PIDFile=/tmp/zabbix_agent2.pid
 
[Install]
WantedBy=multi-user.target
EOT
sudo -E systemctl enable zabbix-agent2 >> $logfile 2>&1

# Start up Zabbix Agent 2
log "Starting Zabbix Agent 2..."
sudo -E service zabbix-agent2 start >> $logfile 2>&1
log "Removing temp dir $tmpdir"
rm -rf "$tmpdir" >> $logfile 2>&1
