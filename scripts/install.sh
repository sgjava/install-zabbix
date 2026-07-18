#!/bin/sh
#
# Created on June 5, 2020
# Refactored for absolute structural stability and clean database compilation
# Updated for Ubuntu 26.04 compatibility (Swapped MySQL for MariaDB) and Zabbix 7.4.9
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

# Get architecture
arch=$(uname -m)

# Temp dir for downloads, etc.
tmpdir="$HOME/temp"

# stdout and stderr for commands logged
logfile="$PWD/install.log"
rm -f "$logfile"

# Simple logger
log(){
	timestamp=$(date +"%m-%d-%Y %k:%M:%S")
	echo "$timestamp $1"
	echo "$timestamp $1" >> "$logfile" 2>&1
}

if [ "$(id -u)" -ne 0 ]; then
	echo "This script must be run as root."
	exit 1
fi

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
CREATE USER IF NOT EXISTS 'zabbix'@'%' IDENTIFIED BY '${dbzabbix}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'%';
CREATE USER IF NOT EXISTS 'zbx_monitor'@'%' IDENTIFIED BY '${monzabbix}';
GRANT USAGE,REPLICATION CLIENT,PROCESS,SHOW DATABASES,SHOW VIEW ON *.* TO 'zbx_monitor'@'%';
FLUSH PRIVILEGES;
_EOF_

	# Update command tracker since root now explicitly enforces the updated password
	MYSQL_CMD="mysql -uroot -p${dbroot}"
else
	log "Existing populated environment discovered."
	# Stop existing services before upgrade build
	if [ -f /etc/systemd/system/zabbix-server.service ]; then
		log "Stopping existing zabbix-server service..."
		systemctl stop zabbix-server >> "$logfile" 2>&1
		log "Saving existing configuration to ${zabbixconf}.bak"
		cp "${zabbixconf}" "${zabbixconf}.bak"
	fi
	if [ -f /etc/systemd/system/zabbix-agent2.service ]; then
		log "Stopping existing zabbix-agent2 service..."
		systemctl stop zabbix-agent2 >> "$logfile" 2>&1
		log "Saving existing configuration to ${zabbixagentconf}.bak"
		cp "${zabbixagentconf}" "${zabbixagentconf}.bak"
	fi
fi

# Determine JDK URL based on Architecture
if [ "$arch" = "armv7l" ]; then
	jdkurl="https://cdn.azul.com/zulu-embedded/bin/zulu17.46.19-ca-jdk17.0.9-linux_aarch32hf.tar.gz"
	javahome=/usr/lib/jvm/jdk17
elif [ "$arch" = "aarch64" ]; then
	jdkurl="https://cdn.azul.com/zulu/bin/zulu21.44.17-ca-jdk21.0.8-linux_aarch64.tar.gz"
	javahome=/usr/lib/jvm/jdk21
elif [ "$arch" = "i586" ] || [ "$arch" = "i686" ]; then
	jdkurl="https://cdn.azul.com/zulu/bin/zulu17.46.19-ca-fx-jdk17.0.9-linux_i686.tar.gz"
	javahome=/usr/lib/jvm/jdk17
elif [ "$arch" = "x86_64" ]; then
	jdkurl="https://cdn.azul.com/zulu/bin/zulu21.44.17-ca-fx-jdk21.0.8-linux_x64.tar.gz"
	javahome=/usr/lib/jvm/jdk21
fi
export javahome
jdkarchive=$(basename "$jdkurl")

# Install Zulu Java JDK
log "Downloading $jdkarchive to $tmpdir"
wget -q --directory-prefix="$tmpdir" "$jdkurl" >> "$logfile" 2>&1
log "Extracting $jdkarchive to $tmpdir"
tar -xf "$tmpdir/$jdkarchive" -C "$tmpdir" >> "$logfile" 2>&1
log "Removing old $javahome"
rm -rf "$javahome" >> "$logfile" 2>&1

filename="${jdkarchive%.tar.gz}"
mkdir -p /usr/lib/jvm >> "$logfile" 2>&1
log "Moving $tmpdir/$filename to $javahome"
mv "$tmpdir/$filename" "$javahome" >> "$logfile" 2>&1

update-alternatives --install "/usr/bin/java" "java" "$javahome/bin/java" 1 >> "$logfile" 2>&1
update-alternatives --install "/usr/bin/javac" "javac" "$javahome/bin/javac" 1 >> "$logfile" 2>&1
update-alternatives --install "/usr/bin/jar" "jar" "$javahome/bin/jar" 1 >> "$logfile" 2>&1
update-alternatives --install "/usr/bin/javadoc" "javadoc" "$javahome/bin/javadoc" 1 >> "$logfile" 2>&1

if grep -q "JAVA_HOME" /etc/environment; then
	log "JAVA_HOME already exists, deleting old entry"
	sed -i '/JAVA_HOME/d' /etc/environment	
fi
log "Adding JAVA_HOME to /etc/environment"
sh -c "echo 'JAVA_HOME=$javahome' >> /etc/environment"
. /etc/environment
log "JAVA_HOME = $JAVA_HOME"

# Download/Extract Zabbix source
log "Downloading $zabbixarchive to $tmpdir"
wget -q --directory-prefix="$tmpdir" "$zabbixurl" >> "$logfile" 2>&1
log "Extracting $zabbixarchive to $tmpdir"
tar -xf "$tmpdir/$zabbixarchive" -C "$tmpdir" >> "$logfile" 2>&1
filename="${zabbixarchive%.tar.gz}"

rm -rf "${srcdir}/${filename}"
mv "$tmpdir/$filename" "${srcdir}" >> "$logfile" 2>&1

if [ "$db_populated" != "1" ]; then
	log "Importing Zabbix schema and core datasets..."
	cd "${srcdir}/${filename}/database/mysql" >> "$logfile" 2>&1
	(echo "SET GLOBAL innodb_strict_mode = OFF; SET SESSION innodb_strict_mode = OFF;"; cat schema.sql) | $MYSQL_CMD zabbix >> "$logfile" 2>&1
	$MYSQL_CMD zabbix < images.sql >> "$logfile" 2>&1
	$MYSQL_CMD zabbix < data.sql >> "$logfile" 2>&1
	$MYSQL_CMD -e "SET GLOBAL log_bin_trust_function_creators = 0; SET GLOBAL innodb_strict_mode = ON;" >> "$logfile" 2>&1

	log "Installing Webserver, PHP, and Framework libraries..."
	# Swapped libmysqlclient-dev to libmariadb-dev for Ubuntu 26.04 engine links
	apt-get -y install fping apache2 php libapache2-mod-php php-cli php-mysql php-mbstring php-gd php-xml php-bcmath php-ldap plocate build-essential libmariadb-dev libssl-dev libsnmp-dev libevent-dev pkg-config golang-go libopenipmi-dev libcurl4-openssl-dev libxml2-dev libssh2-1-dev libpcre2-dev php-curl libgnutls28-dev >> "$logfile" 2>&1
	
	# Update PHP settings
	updatedb >> "$logfile" 2>&1
	phpini=$(locate php.ini 2>&1 | head -n 1)
	if [ -f "$phpini" ]; then
		sed -i 's/max_execution_time = 30/max_execution_time = 300/g' "$phpini" >> "$logfile" 2>&1
		sed -i 's/memory_limit = 128M/memory_limit = 256M/g' "$phpini" >> "$logfile" 2>&1
		sed -i 's/post_max_size = 8M/post_max_size = 32M/g' "$phpini" >> "$logfile" 2>&1
		sed -i 's/max_input_time = 60/max_input_time = 300/g' "$phpini" >> "$logfile" 2>&1
		sed -i "s|;date.timezone =|date.timezone = $phptz|g" "$phpini" >> "$logfile" 2>&1
	fi
	systemctl restart apache2 >> "$logfile" 2>&1
fi	

cd "${srcdir}/${filename}" >> "$logfile" 2>&1

# Patch source to fix "plugins/proc/procfs_linux.go:248:6: constant 1099511627776 overflows int" on 32 bit systems
log "Patching procfs_linux.go to work on 32 bit platforms..."
sed -i 's/strconv.Atoi(strings.TrimSpace(line\[:len(line)-2\]))/strconv.ParseInt(strings.TrimSpace(line[:len(line)-2]),10,64)/' src/go/plugins/proc/procfs_linux.go

# Patch db.c to prevent spamming log and fix modern MariaDB compile errors...
log "Patching db.c to prevent spamming log..."
sed -i '/MYSQL_OPT_RECONNECT/d' src/libs/zbxdbhigh/db.c
sed -i '/Cannot set MySQL reconnect option/d' src/libs/zbxdbhigh/db.c

log "Running Zabbix configure and build..."
./configure --enable-server --enable-agent --enable-agent2 --enable-ipv6 --with-mysql --with-openssl --with-net-snmp --with-openipmi --with-libcurl --with-libxml2 --with-ssh2 --with-ldap --enable-java --prefix=/usr/local >> "$logfile" 2>&1
make install >> "$logfile" 2>&1

# Configure SUID rules for fping execution requirements
chmod ug+s /usr/bin/fping
chmod ug+s /usr/bin/fping6

# Configure Zabbix configuration components
if [ -f "$zabbixconf" ]; then
	sed -i "s/# DBPassword=/DBPassword=${dbzabbix}/g" "$zabbixconf" >> "$logfile" 2>&1
	sed -i "s|# FpingLocation=/usr/sbin/fping|FpingLocation=/usr/bin/fping|g" "$zabbixconf" >> "$logfile" 2>&1
	sed -i "s|# Fping6Location=/usr/sbin/fping6|Fping6Location=/usr/bin/fping6|g" "$zabbixconf" >> "$logfile" 2>&1
	sed -i "s/# StartPingers=1/StartPingers=10/g" "$zabbixconf" >> "$logfile" 2>&1
fi

# Ensure zabbix system group and user exists
if ! getent group zabbix >/dev/null 2>&1; then
	addgroup --system --quiet zabbix >> "$logfile" 2>&1
fi
if ! id "zabbix" >/dev/null 2>&1; then
	log "Creating system user zabbix..."
	useradd -r -s /bin/false -g zabbix -d /var/lib/zabbix Zabbix >> "$logfile" 2>&1
	mkdir -m u=rwx,g=rwx,o= -p /var/lib/zabbix >> "$logfile" 2>&1
	chown zabbix:zabbix /var/lib/zabbix >> "$logfile" 2>&1
fi

# Setup pristine systemd targets pointing directly to MariaDB dependency nodes
cat <<EOT > /etc/systemd/system/zabbix-server.service
[Unit]
Description=Zabbix Server
After=syslog.target network.target mariadb.service
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

cat <<EOT > /etc/systemd/system/zabbix-agent2.service
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

if [ "$db_populated" != "1" ]; then
	log "Installing Zabbix PHP Front End..."
	rm - Harris /var/www/html/zabbix
	mv "${srcdir}/${filename}/ui" /var/www/html/zabbix >> "$logfile" 2>&1
	chown -R www-data:www-data /var/www/html/zabbix >> "$logfile" 2>&1
fi

systemctl daemon-reload
systemctl enable zabbix-server zabbix-agent2
systemctl restart zabbix-server zabbix-agent2

# Cleanup active assets layout environment
log "Removing temp dir $tmpdir"
rm -rf "$tmpdir" >> "$logfile" 2>&1

log "Zabbix Framework setup finalized."