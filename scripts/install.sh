#!/bin/sh
#
# Created on June 5, 2020
#
# @author: sgoldsmith
#
# Install dependencies, mysql, Zabbix Server 6.2.x and Zabbix Agent 2 on Ubuntu
# 22.05. This may work on other versions and Debian like distributions.
#
# Change variables below to suit your needs.
#
# Steven P. Goldsmith
# sgjava@gmail.com
#

# MySQL root password
dbroot="rootZaq!2wsx"

# Zabbix user MySQL password
dbzabbix="zabbixZaq!2wsx"

# MySQL database monitoring user
monzabbix="monzabbixZaq!2wsx"

# Zabbix Server URL
zabbixurl="https://cdn.zabbix.com/zabbix/sources/stable/6.2/zabbix-6.2.7.tar.gz"

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

# Get architecture
arch=$(uname -m)

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

if [ ! -f /etc/systemd/system/zabbix-server.service  ]; then
	log "Installing MySQL..."
	sudo -E apt-get -y update >> $logfile 2>&1
	sudo -E apt-get -y install mysql-server mysql-client >> $logfile 2>&1
	# Secure MySQL, create zabbix DB, zabbix user and zbx_monitor user.
	sudo -E mysql --user=root <<_EOF_
SET GLOBAL log_bin_trust_function_creators = 1;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${dbroot}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE DATABASE zabbix CHARACTER SET UTF8 COLLATE UTF8_BIN;
CREATE USER 'zabbix'@'%' IDENTIFIED BY '${dbzabbix}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'%';
CREATE USER 'zbx_monitor'@'%' IDENTIFIED BY '${monzabbix}';
GRANT USAGE,REPLICATION CLIENT,PROCESS,SHOW DATABASES,SHOW VIEW ON *.* TO 'zbx_monitor'@'%';
FLUSH PRIVILEGES;
_EOF_

else
	# Stop existing service
	sudo -E service zabbix-server stop >> $logfile 2>&1
	log "Saving existing configuration to ${zabbixconf}.bak"
	sudo -E mv "${zabbixconf}" "${zabbixconf}.bak"
	# Stop existing service
	sudo -E service zabbix-agent2 stop >> $logfile 2>&1
	log "Saving existing configuration to ${zabbixagentconf}.bak"
	sudo -E mv "${zabbixagentconf}" "${zabbixagentconf}.bak"
fi
#Default JDK
javahome=/usr/lib/jvm/jdk17
# ARM 32
if [ "$arch" = "armv7l" ]; then
    jdkurl="https://cdn.azul.com/zulu-embedded/bin/zulu17.36.19-ca-jdk17.0.4.1-linux_aarch32hf.tar.gz"
# ARM 64
elif [ "$arch" = "aarch64" ]; then
	jdkurl="https://cdn.azul.com/zulu/bin/zulu17.36.17-ca-jdk17.0.4.1-linux_aarch64.tar.gz"
# X86_32
elif [ "$arch" = "i586" ] || [ "$arch" = "i686" ]; then
	jdkurl="https://cdn.azul.com/zulu/bin/zulu17.36.19-ca-jdk17.0.4.1-linux_i686.tar.gz"
# X86_64	
elif [ "$arch" = "x86_64" ]; then
    jdkurl="https://cdn.azul.com/zulu/bin/zulu17.36.17-ca-jdk17.0.4.1-linux_x64.tar.gz"
fi
export javahome
# Just JDK archive name
jdkarchive=$(basename "$jdkurl")

# Install Zulu Java JDK
log "Downloading $jdkarchive to $tmpdir"
wget -q --directory-prefix=$tmpdir "$jdkurl" >> $logfile 2>&1
log "Extracting $jdkarchive to $tmpdir"
tar -xf "$tmpdir/$jdkarchive" -C "$tmpdir" >> $logfile 2>&1
log "Removing $javahome"
sudo -E rm -rf "$javahome" >> $logfile 2>&1
# Remove .gz
filename="${jdkarchive%.*}"
# Remove .tar
filename="${filename%.*}"
sudo mkdir -p /usr/lib/jvm >> $logfile 2>&1
log "Moving $tmpdir/$filename to $javahome"
sudo -E mv "$tmpdir/$filename" "$javahome" >> $logfile 2>&1
sudo -E update-alternatives --install "/usr/bin/java" "java" "$javahome/bin/java" 1 >> $logfile 2>&1
sudo -E update-alternatives --install "/usr/bin/javac" "javac" "$javahome/bin/javac" 1 >> $logfile 2>&1
sudo -E update-alternatives --install "/usr/bin/jar" "jar" "$javahome/bin/jar" 1 >> $logfile 2>&1
sudo -E update-alternatives --install "/usr/bin/javadoc" "javadoc" "$javahome/bin/javadoc" 1 >> $logfile 2>&1
# See if JAVA_HOME exists and if not add it to /etc/environment
if grep -q "JAVA_HOME" /etc/environment; then
    log "JAVA_HOME already exists, deleting"
    sudo sed -i '/JAVA_HOME/d' /etc/environment	
fi
# Add JAVA_HOME to /etc/environment
log "Adding JAVA_HOME to /etc/environment"
sudo -E sh -c 'echo "JAVA_HOME=$javahome" >> /etc/environment'
. /etc/environment
log "JAVA_HOME = $JAVA_HOME"

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

if [ ! -f /etc/systemd/system/zabbix-server.service  ]; then
	# Import Zabbix data
	log "Importing Zabbix data..."
	cd "${srcdir}/${filename}/database/mysql" >> $logfile 2>&1
	sudo -E mysql -u zabbix -p zabbix --password=$dbzabbix < schema.sql >> $logfile 2>&1
	sudo -E mysql -u zabbix -p zabbix --password=$dbzabbix < images.sql >> $logfile 2>&1
	sudo -E mysql -u zabbix -p zabbix --password=$dbzabbix < data.sql >> $logfile 2>&1
	# Insert macro values to monitor 'Zabbix server' MySQL DB (just add 'Template DB MySQL by Zabbix agent 2')
	sudo -E mysql --user=root <<_EOF_
SET GLOBAL log_bin_trust_function_creators = 0;
_EOF_

	# Install webserver
	log "Installing Apache and PHP..."
	sudo -E apt-get -y install fping apache2 php libapache2-mod-php php-cli php-mysql php-mbstring php-gd php-xml php-bcmath php-ldap mlocate >> $logfile 2>&1
	sudo -E updatedb >> $logfile 2>&1
	# Get php.ini file location
	phpini=$(locate php.ini 2>&1 | head -n 1)
	# Update settings in php.ini
	sudo -E sed -i 's/max_execution_time = 30/max_execution_time = 300/g' "$phpini" >> $logfile 2>&1
	sudo -E sed -i 's/memory_limit = 128M/memory_limit = 256M/g' "$phpini" >> $logfile 2>&1
	sudo -E sed -i 's/post_max_size = 8M/post_max_size = 32M/g' "$phpini" >> $logfile 2>&1
	sudo -E sed -i 's/max_input_time = 60/max_input_time = 300/g' "$phpini" >> $logfile 2>&1
	sudo -E sed -i "s|;date.timezone =|date.timezone = $phptz|g" "$phpini" >> $logfile 2>&1
	sudo -E service apache2 restart >> $logfile 2>&1

	# Use latest golang
	log "Adding Go repository..."
	sudo -E add-apt-repository ppa:longsleep/golang-backports -y >> $logfile 2>&1
	sudo -E apt update >> $logfile 2>&1
	# Install Zabbix
	log "Installing Zabbix Server..."
	# Create group and user
	sudo -E addgroup --system --quiet zabbix >> $logfile 2>&1
	sudo -E adduser --quiet --system --disabled-login --ingroup zabbix --home /var/lib/zabbix --no-create-home zabbix >> $logfile 2>&1
	# Create user home
	sudo -E mkdir -m u=rwx,g=rwx,o= -p /var/lib/zabbix >> $logfile 2>&1
	sudo -E chown zabbix:zabbix /var/lib/zabbix >> $logfile 2>&1
	sudo -E apt-get -y install build-essential libmysqlclient-dev libssl-dev libsnmp-dev libevent-dev pkg-config golang-go >> $logfile 2>&1
	sudo -E apt-get -y install libopenipmi-dev libcurl4-openssl-dev libxml2-dev libssh2-1-dev libpcre3-dev >> $logfile 2>&1
	sudo -E apt-get -y install libldap2-dev libiksemel-dev libcurl4-openssl-dev libgnutls28-dev >> $logfile 2>&1
fi	
cd "${srcdir}/${filename}" >> $logfile 2>&1
# Patch source to fix "plugins/proc/procfs_linux.go:248:6: constant 1099511627776 overflows int" on 32 bit systems
log "Patching source to work on 32 bit platforms..."
sed -i 's/strconv.Atoi(strings.TrimSpace(line\[:len(line)-2\]))/strconv.ParseInt(strings.TrimSpace(line[:len(line)-2]),10,64)/' src/go/plugins/proc/procfs_linux.go >> $logfile 2>&1
# Cnange configuration options here
sudo -E ./configure --enable-server --enable-agent2 --enable-ipv6 --with-mysql --with-openssl --with-net-snmp --with-openipmi --with-libcurl --with-libxml2 --with-ssh2 --with-ldap --enable-java --prefix=/usr/local >> $logfile 2>&1
sudo -E make install >> $logfile 2>&1
# Configure Zabbix server
sudo -E chmod ug+s /usr/bin/fping
sudo -E chmod ug+s /usr/bin/fping6
sudo -E sed -i "s/# DBPassword=/DBPassword=$dbzabbix/g" "$zabbixconf" >> $logfile 2>&1
sudo -E sed -i "s|# FpingLocation=/usr/sbin/fping|FpingLocation=/usr/bin/fping|g" "$zabbixconf" >> $logfile 2>&1
sudo -E sed -i "s|# Fping6Location=/usr/sbin/fping6|Fping6Location=/usr/bin/fping6|g" "$zabbixconf" >> $logfile 2>&1
sudo -E sed -i "s/# StartPingers=1/StartPingers=10/g" "$zabbixconf" >> $logfile 2>&1

# Install Zabbix server service
if [ ! -f /etc/systemd/system/zabbix-server.service  ]; then
	log "Installing Zabbix Server Service..."
	sudo tee -a /etc/systemd/system/zabbix-server.service > /dev/null <<EOT
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
else
	# Remove front end	
	sudo -E rm -rf /var/www/html/zabbix
fi
# Installing Zabbix front end
log "Installing Zabbix PHP Front End..."
cd "${srcdir}/${filename}" >> $logfile 2>&1
sudo -E mv "${srcdir}/${filename}/ui" /var/www/html/zabbix >> $logfile 2>&1
sudo -E chown -R www-data:www-data /var/www/html/zabbix >> $logfile 2>&1
# Start up Zabbix
log "Starting Zabbix Server..."
sudo -E service zabbix-server start >> $logfile 2>&1
log "Starting Zabbix Agent 2..."
sudo -E service zabbix-agent2 start >> $logfile 2>&1
log "Removing temp dir $tmpdir"
rm -rf "$tmpdir" >> $logfile 2>&1
