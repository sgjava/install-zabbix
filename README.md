![Title](images/title.png)

Install Zabbix is s set of scripts to install Zabbix 5.x from source on Ubuntu
20.04 and probably other Debian derived distributions. You can of course use
various methods to install Zabbix Server, but this method gives you the ultimate
flexibility. In addition, there are no deb packages for ARM based platforms hence
building from source is the only method. The scripts allow:
* Install and secure MySQL server
* Import Zabbix data into MySQL
* Install Java 11 JDK for the Java gateway
* Install Zabbix Server
* Instal Zabbix Agent 2
* Create systemd services for both Zabbix Server and Agent
* Move MySQL data directory (optional)
* Install Zabbix Agent 2 on clients (optional)

## Download project
* `cd ~/`
* `git clone --depth 1 https://github.com/sgjava/install-zabbix.git`

## Install script
This assumes a fresh OS install. You should try the scripts out on a VM to play
with configuration prior to doing final install.
* `cd ~/install-zabbix`
* Change configuration values as needed
* `./install.sh`
* Check log file for errors
* Navigate to http://host/zabbix
* Get DB password from script and finalize front end configuration
* Login using Admin/zabbix

## Move DB script
This assumes you ran install.sh above. It's handy to move the MySQL data directory
to a NFS share if you are running Zabbix Server off an SD card for instance.
* `cd ~/install-zabbix`
* Change configuration values as needed
* `./movedb.sh`
* Check log file for errors

## Install Agent 2 script
Install Zabbix Agent 2 script on client. Make sure to change configuration to point to
you Zabbix server before running. You can always configure manually should you forget. 
* `cd ~/install-zabbix`
* Change configuration values as needed
* `./install-agent2.sh`
* Check log file for errors
