#!/bin/sh
#
# Created on June 7, 2020
#
# Updated for Ubuntu 26.04
#
# Install Zabbix Agent 2
#

# Zabbix Server URL
zabbixurl="https://cdn.zabbix.com/zabbix/sources/stable/7.4/zabbix-7.4.9.tar.gz"
zabbixarchive=$(basename "$zabbixurl")
srcdir="/usr/local/src"
zabbixconf="/usr/local/etc/zabbix_agent2.conf"
zabbixhost="192.168.1.69"
tmpdir="/tmp/zabbix-install"
logfile="$PWD/install-agent2.log"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root (sudo $0)"
    exit 1
fi

rm -f $logfile

log(){
	timestamp=$(date +"%m-%d-%Y %k:%M:%S")
	echo "$timestamp $1"
	echo "$timestamp $1" >> $logfile 2>&1
}

log "Removing temp dir $tmpdir"
rm -rf "$tmpdir" >> $logfile 2>&1
mkdir -p "$tmpdir" >> $logfile 2>&1

log "Downloading $zabbixarchive to $tmpdir"
wget -q --directory-prefix=$tmpdir "$zabbixurl" >> $logfile 2>&1
tar -xf "$tmpdir/$zabbixarchive" -C "$tmpdir" >> $logfile 2>&1
filename="${zabbixarchive%.tar.gz}"

mv "$tmpdir/$filename" "${srcdir}" >> $logfile 2>&1

log "Installing Zabbix Agent 2..."
if [ -f /etc/systemd/system/zabbix-agent2.service ]; then
	service zabbix-agent2 stop >> $logfile 2>&1
	log "Saving existing configuration to ${zabbixconf}.bak"
	mv "${zabbixconf}" "${zabbixconf}.bak"
else
	groupadd zabbix 2>/dev/null || true
	useradd -g zabbix -s /bin/bash zabbix 2>/dev/null || true
	apt update >> $logfile 2>&1
	# Updated to libpcre2-dev
	apt-get -y install build-essential pkg-config libpcre2-dev libz-dev golang-go >> $logfile 2>&1
fi

# Ensure go is in path
export PATH=$PATH:/usr/local/go/bin

cd "${srcdir}/${filename}" >> $logfile 2>&1
log "Patching source to work on 32 bit platforms..."
sed -i 's/strconv.Atoi(strings.TrimSpace(line\[:len(line)-2\]))/strconv.ParseInt(strings.TrimSpace(line[:len(line)-2]),10,64)/' src/go/plugins/proc/procfs_linux.go >> $logfile 2>&1

./configure --enable-agent2 --prefix=/usr/local >> $logfile 2>&1
make install >> $logfile 2>&1

sed -i "s|Server=127.0.0.1|Server=$zabbixhost|g" "$zabbixconf" >> $logfile 2>&1
sed -i "s|ServerActive=127.0.0.1|ServerActive=$zabbixhost|g" "$zabbixconf" >> $logfile 2>&1
sed -i "s|Hostname=|#Hostname=|g" "$zabbixconf" >> $logfile 2>&1

if [ ! -f /etc/systemd/system/zabbix-agent2.service ]; then
	log "Installing Zabbix Agent 2 Service..."
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
	systemctl enable zabbix-agent2 >> $logfile 2>&1
fi

log "Starting Zabbix Agent 2..."
systemctl start zabbix-agent2 >> $logfile 2>&1
rm -rf "$tmpdir"
