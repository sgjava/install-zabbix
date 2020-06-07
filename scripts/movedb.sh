#!/bin/sh
#
# Created on June 6, 2020
#
# @author: sgoldsmith
#
# Move MySQL database directory from default location to another location. This
# script assumes you ran install.sh already.
#
# Steven P. Goldsmith
# sgjava@gmail.com
#

# MySQL data destination directory
destdir="/tmp"

# stdout and stderr for commands logged
logfile="$PWD/movedb.log"
rm -f $logfile

# Simple logger
log(){
	timestamp=$(date +"%m-%d-%Y %k:%M:%S")
	echo "$timestamp $1"
	echo "$timestamp $1" >> $logfile 2>&1
}

# Shut down Zabbix
log "Stopping Zabbix Server..."
sudo -E service zabbix-server stop >> $logfile 2>&1
log "Stopping Zabbix Agent 2..."
sudo -E service zabbix-agent2 stop >> $logfile 2>&1
# Shut down MySQL
log "Stopping MySQL..."
sudo -E service mysql stop >> $logfile 2>&1

# Copy MySQL data directory
log "Copying MySQL data directory..."
sudo rsync -av /var/lib/mysql "$destdir" >> $logfile 2>&1
# Remove MySQL data directory
log "Removing MySQL data directory..."
sudo rm -rf /var/lib/mysql
# Change location of MySQL data directory
sudo -E sed -i "s|# datadir	= /var/lib/mysql|datadir	= $destdir/mysql|g" /etc/mysql/mysql.conf.d/mysqld.cnf >> $logfile 2>&1
# Start MySQL
log "Starting MySQL..."
sudo -E service mysql start >> $logfile 2>&1
# Start up Zabbix
log "Starting Zabbix Server..."
sudo -E service zabbix-server start >> $logfile 2>&1
log "Starting Zabbix Agent 2..."
sudo -E service zabbix-agent2 start >> $logfile 2>&1
