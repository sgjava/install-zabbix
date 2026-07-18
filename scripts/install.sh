#!/bin/sh
#
# Created on June 5, 2020
# Refactored for absolute structural stability and clean database compilation
# Updated for Ubuntu 26.04 compatibility and verified PHP Front End deployment
#
# @author: sgoldsmith
#

# MySQL root password
dbroot="rootZaq!2wsx"
dbzabbix="zabbixZaq!2wsx"
monzabbix="monzabbixZaq!2wsx"

# Zabbix Server URL
zabbixurl="https://cdn.zabbix.com/zabbix/sources/stable/7.4/zabbix-7.4.9.tar.gz"
zabbixarchive=$(basename "$zabbixurl")
srcdir="/usr/local/src"
phptz="America/New_York"
zabbixconf="/usr/local/etc/zabbix_server.conf"
zabbixagentconf="/usr/local/etc/zabbix_agent2.conf"
tmpdir="$HOME/temp"
logfile="$PWD/install.log"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

rm -f "$logfile"

log(){
	timestamp=$(date +"%m-%d-%Y %k:%M:%S")
	echo "$timestamp $1"
	echo "$timestamp $1" >> "$logfile" 2>&1
}

log "Removing temp dir $tmpdir"
rm -rf "$tmpdir" >> "$logfile" 2>&1
mkdir -p "$tmpdir" >> "$logfile" 2>&1

# Source global environment
if [ -f /etc/environment ]; then
	log "Sourcing global environments..."
	. /etc/environment
fi

MYSQL_CMD="mysql -uroot -p${dbroot}"
if ! mysql -uroot -p"${dbroot}" -e "SELECT 1;" >/dev/null 2>&1; then
	MYSQL_CMD="mysql -uroot"
fi

db_populated=$( $MYSQL_CMD -sse "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='zabbix' AND TABLE_NAME='dbversion';" 2>/dev/null )

if [ "$db_populated" != "1" ]; then
	log "Performing pristine database installation sequence..."
	apt-get -y update >> "$logfile" 2>&1
	apt-get -y install mysql-server mysql-client >> "$logfile" 2>&1
	
	$MYSQL_CMD <<_EOF_ >> "$logfile" 2>&1
SET GLOBAL log_bin_trust_function_creators = 1;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${dbroot}';
DROP DATABASE IF EXISTS zabbix;
CREATE DATABASE zabbix CHARACTER SET UTF8 COLLATE UTF8_BIN;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${dbzabbix}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
CREATE USER IF NOT EXISTS 'zbx_monitor'@'localhost' IDENTIFIED BY '${monzabbix}';
GRANT USAGE,REPLICATION CLIENT,PROCESS,SHOW DATABASES,SHOW VIEW ON *.* TO 'zbx_monitor'@'localhost';
FLUSH PRIVILEGES;
_EOF_
else
	log "Existing populated environment discovered."
fi

# Download/Extract
log "Downloading $zabbixarchive to $tmpdir"
wget -q --directory-prefix="$tmpdir" "$zabbixurl" >> "$logfile" 2>&1
tar -xf "$tmpdir/$zabbixarchive" -C "$tmpdir" >> "$logfile" 2>&1
filename="${zabbixarchive%.tar.gz}"

rm -rf "${srcdir}/${filename}"
mv "$tmpdir/$filename" "${srcdir}" >> "$logfile" 2>&1

if [ "$db_populated" != "1" ]; then
	cd "${srcdir}/${filename}/database/mysql" >> "$logfile" 2>&1
	(echo "SET GLOBAL innodb_strict_mode = OFF; SET SESSION innodb_strict_mode = OFF;"; cat schema.sql) | $MYSQL_CMD zabbix >> "$logfile" 2>&1
	$MYSQL_CMD zabbix < images.sql >> "$logfile" 2>&1
	$MYSQL_CMD zabbix < data.sql >> "$logfile" 2>&1
	$MYSQL_CMD -e "SET GLOBAL log_bin_trust_function_creators = 0; SET GLOBAL innodb_strict_mode = ON;" >> "$logfile" 2>&1

	log "Installing Webserver, PHP, and Framework libraries..."
	# Ubuntu 26.04 clean package set (no libpcre3-dev)
	apt-get -y install fping apache2 php libapache2-mod-php php-cli php-mysql php-mbstring php-gd php-xml php-bcmath php-ldap plocate build-essential libmysqlclient-dev libssl-dev libsnmp-dev libevent-dev pkg-config golang-go libopenipmi-dev libcurl4-openssl-dev libxml2-dev libssh2-1-dev libpcre2-dev php-curl libgnutls28-dev >> "$logfile" 2>&1
	
	# Locate php.ini dynamically and adjust configurations safely
	phpini=$(locate php.ini 2>&1 | grep "apache2" | head -n 1)
	if [ -z "$phpini" ] || [ ! -f "$phpini" ]; then
		phpini="/etc/php/$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'/)/apache2/php.ini"
	fi

	log "Updating PHP settings in $phpini"
	sed -i 's/max_execution_time = 30/max_execution_time = 300/g' "$phpini" >> "$logfile" 2>&1
	sed -i 's/memory_limit = 128M/memory_limit = 256M/g' "$phpini" >> "$logfile" 2>&1
	sed -i 's/post_max_size = 8M/post_max_size = 32M/g' "$phpini" >> "$logfile" 2>&1
	sed -i 's/max_input_time = 60/max_input_time = 300/g' "$phpini" >> "$logfile" 2>&1
	sed -i "s|;date.timezone =|date.timezone = $phptz|g" "$phpini" >> "$logfile" 2>&1
	
	systemctl restart apache2 >> "$logfile" 2>&1

	# Handle Zabbix system user setup
	if ! getent group zabbix >/dev/null; then
		addgroup --system --quiet zabbix >> "$logfile" 2>&1
	fi
	if ! getent passwd zabbix >/dev/null; then
		adduser --quiet --system --disabled-login --ingroup zabbix --home /var/lib/zabbix --no-create-home zabbix >> "$logfile" 2>&1
	fi
	mkdir -m u=rwx,g=rwx,o= -p /var/lib/zabbix >> "$logfile" 2>&1
	chown zabbix:zabbix /var/lib/zabbix >> "$logfile" 2>&1
else
	# Existing installation fallback cleanup for UI replacement
	log "Cleaning up old front end files..."
	rm -rf /var/www/html/zabbix
fi	

cd "${srcdir}/${filename}" >> "$logfile" 2>&1
sed -i 's/strconv.Atoi(strings.TrimSpace(line\[:len(line)-2\]))/strconv.ParseInt(strings.TrimSpace(line[:len(line)-2]),10,64)/' src/go/plugins/proc/procfs_linux.go >> "$logfile" 2>&1

# Apply db.c patch safely checking paths dynamically
if [ -f src/libs/zbxdbhigh/db.c ]; then
	sed -i '/MYSQL_OPT_RECONNECT/d' src/libs/zbxdbhigh/db.c >> "$logfile" 2>&1
elif [ -f src/libs/zbxdb/db.c ]; then
	sed -i '/MYSQL_OPT_RECONNECT/d' src/libs/zbxdb/db.c >> "$logfile" 2>&1
fi

log "Running Zabbix configure and build..."
./configure --enable-server --enable-agent --enable-agent2 --enable-ipv6 --with-mysql --with-openssl --with-net-snmp --with-openipmi --with-libcurl --with-libxml2 --with-ssh2 --with-ldap --enable-java --prefix=/usr/local >> "$logfile" 2>&1
make install >> "$logfile" 2>&1

# Post-build Zabbix daemon configurations
chmod ug+s /usr/bin/fping >> "$logfile" 2>&1
chmod ug+s /usr/bin/fping6 >> "$logfile" 2>&1
if [ -f "$zabbixconf" ]; then
	sed -i "s/# DBPassword=/DBPassword=$dbzabbix/g" "$zabbixconf" >> "$logfile" 2>&1
	sed -i "s|# FpingLocation=/usr/sbin/fping|FpingLocation=/usr/bin/fping|g" "$zabbixconf" >> "$logfile" 2>&1
	sed -i "s|# Fping6Location=/usr/sbin/fping6|Fping6Location=/usr/bin/fping6|g" "$zabbixconf" >> "$logfile" 2>&1
	sed -i "s/# StartPingers=1/StartPingers=10/g" "$zabbixconf" >> "$logfile" 2>&1
fi

# Deploying Zabbix Front End UI
log "Installing Zabbix PHP Front End..."
mkdir -p /var/www/html/zabbix >> "$logfile" 2>&1
cp -r "${srcdir}/${filename}/ui/"* /var/www/html/zabbix/ >> "$logfile" 2>&1
chown -R www-data:www-data /var/www/html/zabbix >> "$logfile" 2>&1

# Setup units
cat <<EOT > /etc/systemd/system/zabbix-server.service
[Unit]
Description=Zabbix Server
After=syslog.target network.target mysql.service

[Service]
Type=simple
User=zabbix
ExecStart=/usr/local/sbin/zabbix_server
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOT

cat <<EOT > /etc/systemd/system/zabbix-agent2.service
[Unit]
Description=Zabbix Agent 2
After=syslog.target network.target

[Service]
Type=simple
User=zabbix
ExecStart=/usr/local/sbin/zabbix_agent2 -c /usr/local/etc/zabbix_agent2.conf
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl enable zabbix-server zabbix-agent2 >> "$logfile" 2>&1
systemctl restart zabbix-server zabbix-agent2 >> "$logfile" 2>&1

log "Removing temp dir $tmpdir"
rm -rf "$tmpdir" >> "$logfile" 2>&1

log "Zabbix Framework setup finalized."