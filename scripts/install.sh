#!/bin/sh
#
# Created on June 5, 2020
# Refactored for absolute structural stability and clean database compilation
#
# @author: sgoldsmith
#

# MySQL root password
dbroot="rootZaq!2wsx"

# Zabbix user MySQL password
dbzabbix="zabbixZaq!2wsx"

# MySQL database monitoring user
monzabbix="monzabbixZaq!2wsx"

# Zabbix Server URL
zabbixurl="https://cdn.zabbix.com/zabbix/sources/stable/7.4/zabbix-7.4.9.tar.gz"

# Just Zabbix server archive name
zabbixarchive=$(basename "$zabbixurl")

# Where to put Zabbix source
srcdir="/usr/local/src"

# PHP timezone
phptz="America/New_York"

# Zabbix server configuration
zabbixconf="/usr/local/etc/zabbix_server.conf"

#Zabbix agent configuration
zabbixagentconf="/usr/local/etc/zabbix_agent2.conf"

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

# Source global environment to grab SDKMAN-managed JAVA_HOME
if [ -f /etc/environment ]; then
	log "Sourcing global environments..."
	. /etc/environment
fi

if [ -z "$JAVA_HOME" ]; then
	log "WARNING: JAVA_HOME is not set. Ensure SDKMAN paths are verified."
fi

# Determine if the database layout is FULLY populated by verifying the dbversion table specifically
db_populated=$(sudo mysql -uroot -sse "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='zabbix' AND TABLE_NAME='dbversion';" 2>/dev/null)

if [ "$db_populated" != "1" ]; then
	log "Database unpopulated or incomplete. Performing pristine database installation sequence..."
	log "Installing MySQL..."
	sudo -E apt-get -y update >> $logfile 2>&1
	sudo -E apt-get -y install mysql-server mysql-client >> $logfile 2>&1
	
	# Unconditionally purge any leftover half-baked schemas to ensure schema.sql doesn't throw Error 1050
	sudo -E mysql --user=root <<_EOF_
SET GLOBAL log_bin_trust_function_creators = 1;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${dbroot}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DROP DATABASE IF EXISTS zabbix;
CREATE DATABASE zabbix CHARACTER SET UTF8 COLLATE UTF8_BIN;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${dbzabbix}';
CREATE USER IF NOT EXISTS 'zabbix'@'%' IDENTIFIED BY '${dbzabbix}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'%';
CREATE USER IF NOT EXISTS 'zbx_monitor'@'%' IDENTIFIED BY '${monzabbix}';
GRANT USAGE,REPLICATION CLIENT,PROCESS,SHOW DATABASES,SHOW VIEW ON *.* TO 'zbx_monitor'@'%';
FLUSH PRIVILEGES;
_EOF_

else
	log "Existing populated environment discovered. Preparing system upgrade sequence..."
	sudo -E systemctl stop zabbix-server >> $logfile 2>&1
	sudo -E systemctl stop zabbix-agent2 >> $logfile 2>&1
	
	if [ -f "$zabbixconf" ]; then
		log "Saving existing configuration to ${zabbixconf}.bak"
		sudo -E mv "${zabbixconf}" "${zabbixconf}.bak"
	fi
	if [ -f "$zabbixagentconf" ]; then
		log "Saving existing configuration to ${zabbixagentconf}.bak"
		sudo -E mv "${zabbixagentconf}" "${zabbixagentconf}.bak"
	fi
fi

# Download Zabbix source
log "Downloading $zabbixarchive to $tmpdir"
wget -q --directory-prefix=$tmpdir "$zabbixurl" >> $logfile 2>&1
log "Extracting $zabbixarchive to $tmpdir"
tar -xf "$tmpdir/$zabbixarchive" -C "$tmpdir" >> $logfile 2>&1

filename="${zabbixarchive%.*}"
filename="${filename%.*}"

# Clean target source path completely to avoid messy file nests on retries
sudo rm -rf "${srcdir}/${filename}"
sudo -E mv "$tmpdir/$filename" "${srcdir}" >> $logfile 2>&1

if [ "$db_populated" != "1" ]; then
	log "Importing fresh Zabbix structural database schema..."
	cd "${srcdir}/${filename}/database/mysql" >> $logfile 2>&1
	
	# Explicit root bypass to ensure socket tracking limits don't drop packet streams
	sudo mysql -uroot zabbix < schema.sql >> $logfile 2>&1
	sudo mysql -uroot zabbix < images.sql >> $logfile 2>&1
	sudo mysql -uroot zabbix < data.sql >> $logfile 2>&1
	
	# Secure functions block right after import completes successfully
	sudo mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;" >> $logfile 2>&1

	# Install dependencies
	log "Installing Webserver and PHP extensions..."
	sudo -E apt-get -y install fping apache2 php libapache2-mod-php php-cli php-mysql php-mbstring php-gd php-xml php-bcmath php-ldap plocate >> $logfile 2>&1
	sudo -E updatedb >> $logfile 2>&1
	
	phpini=$(locate php.ini 2>&1 | head -n 1)
	sudo -E sed -i 's/max_execution_time = 30/max_execution_time = 300/g' "$phpini" >> $logfile 2>&1
	sudo -E sed -i 's/memory_limit = 128M/memory_limit = 256M/g' "$phpini" >> $logfile 2>&1
	sudo -E sed -i 's/post_max_size = 8M/post_max_size = 32M/g' "$phpini" >> $logfile 2>&1
	sudo -E sed -i 's/max_input_time = 60/max_input_time = 300/g' "$phpini" >> $logfile 2>&1
	sudo -E sed -i "s|;date.timezone =|date.timezone = $phptz|g" "$phpini" >> $logfile 2>&1
	sudo -E systemctl restart apache2 >> $logfile 2>&1

	log "Adding Go backports repository..."
	sudo -E add-apt-repository ppa:longsleep/golang-backports -y >> $logfile 2>&1
	sudo -E apt-get update >> $logfile 2>&1
	
	log "Installing compilation framework libraries..."
	if ! id "zabbix" >/dev/null 2>&1; then
		sudo -E addgroup --system --quiet zabbix >> $logfile 2>&1
		sudo -E adduser --quiet --system --disabled-login --ingroup zabbix --home /var/lib/zabbix --no-create-home zabbix >> $logfile 2>&1
	fi
	sudo -E mkdir -m u=rwx,g=rwx,o= -p /var/lib/zabbix >> $logfile 2>&1
	sudo -E chown zabbix:zabbix /var/lib/zabbix >> $logfile 2>&1
	sudo -E apt-get -y install build-essential libmysqlclient-dev libssl-dev libsnmp-dev libevent-dev pkg-config golang-go >> $logfile 2>&1
	sudo -E apt-get -y install libopenipmi-dev libcurl4-openssl-dev libxml2-dev libssh2-1-dev libpcre2-dev libpcre3-dev >> $logfile 2>&1
	sudo -E apt-get -y install libldap2-dev php-curl libgnutls28-dev >> $logfile 2>&1
fi	

cd "${srcdir}/${filename}" >> $logfile 2>&1

log "Applying platform source patches..."
sed -i 's/strconv.Atoi(strings.TrimSpace(line\[:len(line)-2\]))/strconv.ParseInt(strings.TrimSpace(line[:len(line)-2]),10,64)/' src/go/plugins/proc/procfs_linux.go >> $logfile 2>&1
sed -i '/MYSQL_OPT_RECONNECT/d' src/libs/zbxdb/db.c >> $logfile 2>&1
sed -i '/Cannot set MySQL reconnect option/d' src/libs/zbxdb/db.c >> $logfile 2>&1

# Provide explicitly isolated configuration execution environments passing native compiler hooks
export JAVA_HOME
log "Running Zabbix configure..."
sudo -E PATH="$JAVA_HOME/bin:$PATH" ./configure --enable-server --enable-agent --enable-agent2 --enable-ipv6 --with-mysql --with-openssl --with-net-snmp --with-openipmi --with-libcurl --with-libxml2 --with-ssh2 --with-ldap --enable-java --prefix=/usr/local >> $logfile 2>&1

log "Running Zabbix compilation and install..."
sudo -E PATH="$JAVA_HOME/bin:$PATH" make install >> $logfile 2>&1

# Apply system rules
sudo -E chmod ug+s /usr/bin/fping
sudo -E chmod ug+s /usr/bin/fping6
sudo -E sed -i "s/# DBPassword=/DBPassword=$dbzabbix/g" "$zabbixconf" >> $logfile 2>&1
sudo -E sed -i "s|# FpingLocation=/usr/sbin/fping|FpingLocation=/usr/bin/fping|g" "$zabbixconf" >> $logfile 2>&1
sudo -E sed -i "s|# Fping6Location=/usr/sbin/fping6|Fping6Location=/usr/bin/fping6|g" "$zabbixconf" >> $logfile 2>&1
sudo -E sed -i "s/# StartPingers=1/StartPingers=10/g" "$zabbixconf" >> $logfile 2>&1

# Install Systemd service units
if [ ! -f /etc/systemd/system/zabbix-server.service ]; then
	log "Configuring Zabbix Server systemd unit..."
	sudo tee /etc/systemd/system/zabbix-server.service > /dev/null <<EOT
[Unit]
Description=Zabbix Server
After=syslog.target network.target mysql.service
 
[Service]
Type=simple
User=zabbix
ExecStart=/usr/local/sbin/zabbix_server
ExecReload=/usr/local/sbin/zabbix_server -R config_cache_reload
RemainAfterExit=yes
PIDFile=/tmp/zabbix_server.pid
 
[Install]
WantedBy=multi-user.target
EOT

	sudo -E systemctl enable zabbix-server >> $logfile 2>&1

	log "Configuring Zabbix Agent 2 systemd unit..."
	sudo tee /etc/systemd/system/zabbix-agent2.service > /dev/null <<EOT
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
fi

# Ensure web placement target directory path is entirely pristine
sudo -E rm -rf /var/www/html/zabbix

log "Deploying Zabbix PHP Web Front End UI..."
sudo -E mv "${srcdir}/${filename}/ui" /var/www/html/zabbix >> $logfile 2>&1
sudo -E chown -R www-data:www-data /var/www/html/zabbix >> $logfile 2>&1

log "Spawning Zabbix Services..."
sudo systemctl daemon-reload >> $logfile 2>&1
sudo systemctl restart zabbix-server >> $logfile 2>&1
sudo systemctl restart zabbix-agent2 >> $logfile 2>&1

log "Zabbix Framework setup execution finalized cleanly."
