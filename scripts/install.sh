#!/usr/bin/sh
#
# Created on June 5, 2020
# Refactored for absolute structural stability and clean database compilation
# Updated for Ubuntu 26.04 compatibility (Swapped MySQL for MariaDB)
#
# @author: sgoldsmith
#

# MariaDB/MySQL root password
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

# MariaDB client binary fallback structure
MYSQL_CMD="mysql -uroot -p${dbroot}"
if ! mysql -uroot -p"${dbroot}" -e "SELECT 1;" >/dev/null 2>&1; then
	MYSQL_CMD="mysql -uroot"
fi

db_populated=$( $MYSQL_CMD -sse "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='zabbix' AND TABLE_NAME='dbversion';" 2>/dev/null )

if [ "$db_populated" != "1" ]; then
	log "Performing pristine database installation sequence..."
	apt-get -y update >> "$logfile" 2>&1
	# Ubuntu 26.04 package tracking for modern RDBMS engines
	apt-get -y install mariadb-server mariadb-client >> "$logfile" 2>&1
	
	# Start database engine to process structural setups
	systemctl start mariadb >> "$logfile" 2>&1
	systemctl enable mariadb >> "$logfile" 2>&1

	# MariaDB uses unix_socket for root by default; altering root password and building Zabbix users
	$MYSQL_CMD <<_EOF_ >> "$logfile" 2>&1
SET GLOBAL log_bin_trust_function_creators = 1;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${dbroot}';
DROP DATABASE IF EXISTS zabbix;
CREATE DATABASE zabbix CHARACTER SET UTF8 COLLATE UTF8_BIN;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${dbzabbix}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
_EOF_

	# Update command tracker since root now explicitly enforces the updated password
	MYSQL_CMD="mysql -uroot -p${dbroot}"
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
	# Swapped libmysqlclient-dev to libmariadb-dev for Ubuntu 26.04 engine links
	apt-get -y install fping apache2 php libapache2-mod-php php-cli php-mysql php-mbstring php-gd php-xml php-bcmath php-ldap plocate build-essential libmariadb-dev libssl-dev libsnmp-dev libevent-dev pkg-config golang-go libopenipmi-dev libcurl4-openssl-dev libxml2-dev libssh2-1-dev libpcre2-dev php-curl libgnutls28-dev >> "$logfile" 2>&1
	
	# Basic PHP ini adjustment
	sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php/*/apache2/php.ini
	systemctl restart apache2
fi	

cd "${srcdir}/${filename}" >> "$logfile" 2>&1
sed -i 's/strconv.Atoi(strings.TrimSpace(line\[:len(line)-2\]))/strconv.ParseInt(strings.TrimSpace(line[:len(line)-2]),10,64)/' src/go/plugins/proc/procfs_linux.go
sed -i '/MYSQL_OPT_RECONNECT/d' src/libs/zbxdb/db.c

log "Running Zabbix configure and build..."
./configure --enable-server --enable-agent --enable-agent2 --enable-ipv6 --with-mysql --with-openssl --with-net-snmp --with-openipmi --with-libcurl --with-libxml2 --with-ssh2 --with-ldap --enable-java --prefix=/usr/local >> "$logfile" 2>&1
make install >> "$logfile" 2>&1

# Configure Zabbix config files if freshly built
if [ -f "$zabbixconf" ]; then
	sed -i "s/# DBPassword=/DBPassword=${dbzabbix}/g" "$zabbixconf"
fi

# Ensure zabbix system user exists before starting systemd units
if ! id "zabbix" >/dev/null 2>&1; then
	log "Creating system user zabbix..."
	useradd -r -s /bin/false zabbix
fi

# Setup units (Point targeting to mariadb service wrapper dependencies)
cat <<EOT > /etc/systemd/system/zabbix-server.service
[Unit]
Description=Zabbix Server
After=syslog.target network.target mariadb.service
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
systemctl enable zabbix-server zabbix-agent2
systemctl restart zabbix-server zabbix-agent2

log "Zabbix Framework setup finalized."